"""Detección de acordes v2 (motor simplificado y estable).

Cambios clave respecto a v1:
- Corrección de afinación de la grabación (estimate_tuning + pitch_shift) antes del análisis.
- Estimación de tonalidad global y vocabulario diatónico ponderado por función armónica:
  la progresión se restringe a los acordes que realmente pertenecen a la tonalidad,
  eliminando el ruido de maj7/dim/sus4 espurios.
- Sesgo de bajo (chroma de graves) para acertar la fundamental cuando hay inversiones.
- Suavizado Viterbi con coste de cambio + gamma (penaliza confusiones marginales).
- Simplificación final: segmentos de menos de 1 segundo se fusionan con su vecino
  armónicamente más cercano y las tensiones se pliegan a su tríada base
  (maj7 -> mayor, m7 -> menor, sus4 -> tríada), para que el cifrado quede como
  el de una hoja de papel ("si la canción tiene cuatro acordes, salen cuatro").
"""
from pathlib import Path
from typing import List, Dict, Any, Optional, Tuple
import shutil
import subprocess

import httpx
import numpy as np

# Nombres de notas estándar
NOTES = ['C', 'C#', 'D', 'D#', 'E', 'F', 'F#', 'G', 'G#', 'A', 'A#', 'B']

# Perfiles de tonalidad de Krumhansl-Kessler para estimar la tónica
MAJOR_PROFILE = np.array([6.35, 2.23, 3.48, 2.33, 4.38, 4.09, 2.52, 5.19, 2.39, 3.66, 2.29, 2.88])
MINOR_PROFILE = np.array([6.33, 2.68, 3.52, 5.38, 2.60, 3.53, 2.54, 4.75, 3.98, 2.69, 3.34, 3.17])

# Familias de acordes: intervalos (en semitonos) que componen cada calidad
CHORD_INTERVALS: Dict[str, List[int]] = {
    "": [0, 4, 7],              # Mayor
    "m": [0, 3, 7],             # Menor
    "7": [0, 4, 7, 10],         # Séptima dominante
    "maj7": [0, 4, 7, 11],      # Séptima mayor
    "m7": [0, 3, 7, 10],        # Séptima menor
    "dim": [0, 3, 6],           # Disminuido
    "sus4": [0, 5, 7],          # Suspendido en cuarta
}

# Peso de la fundamental, la tercera y la quinta al comparar plantillas
DEGREE_WEIGHTS = [1.0, 0.9, 0.8, 0.6]

# Plegado de tensiones para el cifrado simplificado final.
# El 7 dominante SÍ se conserva (es un color armónico real y útil en el cifrado).
FOLD_MAP: Dict[str, str] = {
    "maj7": "",
    "m7": "m",
    "sus4": "",
    "sus2": "",
    "add9": "",
    "6": "",
    "dim7": "dim",
}

# Longitud mínima de un segmento en la línea temporal simplificada ("un segundo o nada")
MIN_SEGMENT_SECONDS = 1.0

# Parámetros de suavizado validados contra grabaciones reales
VITERBI_GAMMA = 4.0          # afila la decisión: pequeñas diferencias de similitud no cambian el acorde
VITERBI_CHANGE_PENALTY = 0.10
BASS_WEIGHT = 0.5            # peso del croma de graves al puntuar la fundamental
TUNING_CORRECTION_THRESHOLD = 0.15  # semitonos de desviación media para corregir afinación

# Pesos por función armónica: grado -> {calidad -> peso}.
# Menor: i, ii°, III, iv, v/V, VI, VII (natural y armónica)
_FUNCTION_MINOR: Dict[int, Dict[str, float]] = {
    0: {"m": 1.0, "7": 0.85, "m7": 0.8},
    2: {"dim": 0.7, "m": 0.8},
    3: {"": 1.0, "maj7": 0.85},
    5: {"m": 1.0, "": 0.75},
    7: {"m": 0.9, "7": 1.0, "": 0.85},
    8: {"": 0.95, "maj7": 0.8},
    10: {"": 1.0, "7": 0.85},
    4: {"m": 0.6, "7": 0.5},
    9: {"": 0.5, "m": 0.5},
    11: {"": 0.45, "7": 0.5},
    1: {"dim": 0.5, "": 0.45},
    6: {"dim": 0.5},
}

# Mayor: I, ii, iii, IV, V, vi + préstamos frecuentes (bVII, bIII, bVI del modo mixto)
_FUNCTION_MAJOR: Dict[int, Dict[str, float]] = {
    0: {"": 1.0, "7": 0.9, "maj7": 0.85},
    2: {"m": 1.0, "m7": 0.75, "7": 0.8},
    4: {"m": 1.0, "7": 0.65},
    5: {"": 1.0, "maj7": 0.8, "m": 0.7},
    7: {"": 1.0, "7": 1.0, "sus4": 0.8, "m": 0.45},
    9: {"m": 1.0, "m7": 0.75, "": 0.5},
    10: {"": 0.8, "7": 0.75},
    3: {"": 0.8, "7": 0.75},
    11: {"dim": 0.85, "m": 0.55},
    8: {"m": 0.7, "": 0.75},
    1: {"": 0.4},
    6: {"dim": 0.7, "": 0.7, "maj7": 0.65},
}

# Calidades de reserva para variantes no listadas explícitamente
_QUALITY_FALLBACK: Dict[str, Tuple[str, float]] = {
    "m7": ("m", 0.85),
    "maj7": ("", 0.85),
    "7": ("", 0.9),
    "sus4": ("", 0.9),
    "dim": ("", 0.6),
    "m": ("", 0.6),
    "": ("m", 0.6),
}


def build_chord_templates() -> Dict[str, np.ndarray]:
    """Construye plantillas normalizadas de cromagrama para todos los acordes soportados."""
    templates: Dict[str, np.ndarray] = {}
    for i, note in enumerate(NOTES):
        for quality, intervals in CHORD_INTERVALS.items():
            chroma = np.zeros(12)
            for degree_idx, interval in enumerate(intervals):
                weight = DEGREE_WEIGHTS[degree_idx] if degree_idx < len(DEGREE_WEIGHTS) else 0.5
                chroma[(i + interval) % 12] = weight
            norm = np.linalg.norm(chroma)
            if norm > 0:
                chroma = chroma / norm
            templates[f"{note}{quality}"] = chroma
    return templates


CHORD_TEMPLATES = build_chord_templates()


# ---------------------------------------------------------------- utilidades puras

def chord_root(chord: str) -> str:
    """Devuelve la raíz de un acorde ('A#m7' -> 'A#', 'C' -> 'C')."""
    if not chord:
        return "C"
    if len(chord) > 1 and chord[1] == '#':
        return chord[:2]
    return chord[:1]


def chord_quality(chord: str) -> str:
    """Devuelve la calidad de un acorde ('A#m7' -> 'm7', 'C' -> '')."""
    return chord[len(chord_root(chord)):]


def fold_tension(chord: str) -> str:
    """Pliega tensiones a la tríada base (Gm7 -> Gm, Cmaj7 -> C). El 7 dominante se conserva."""
    root = chord_root(chord)
    quality = chord_quality(chord)
    new_quality = FOLD_MAP.get(quality, quality)
    return f"{root}{new_quality}"


def key_function_weight(chord: str, key: str) -> float:
    """Peso funcional de un acorde dentro de una tonalidad (0..1)."""
    root = chord_root(chord)
    quality = chord_quality(chord)
    if root not in NOTES or not key:
        return 0.5
    key_root = chord_root(key)
    minor = key.endswith("m")
    if key_root not in NOTES:
        return 0.5
    degree = (NOTES.index(root) - NOTES.index(key_root)) % 12
    table = _FUNCTION_MINOR if minor else _FUNCTION_MAJOR
    degree_map = table.get(degree, {})
    if quality in degree_map:
        return degree_map[quality]
    fallback_quality, fallback_weight = _QUALITY_FALLBACK.get(quality, ("", 0.6))
    return degree_map.get(fallback_quality, fallback_weight)


def diatonic_vocabulary(key: str) -> Tuple[List[str], List[float]]:
    """Acordes candidatos de una tonalidad (con su peso) que existen como plantilla."""
    if not key or chord_root(key) not in NOTES:
        return list(CHORD_TEMPLATES.keys()), [1.0] * len(CHORD_TEMPLATES)
    key_root = chord_root(key)
    minor = key.endswith("m")
    table = _FUNCTION_MINOR if minor else _FUNCTION_MAJOR
    labels: List[str] = []
    weights: List[float] = []
    for degree, quality_map in table.items():
        for quality, weight in quality_map.items():
            label = f"{NOTES[(NOTES.index(key_root) + degree) % 12]}{quality}"
            if label in CHORD_TEMPLATES and label not in labels:
                labels.append(label)
                weights.append(weight)
    if not labels:
        return list(CHORD_TEMPLATES.keys()), [1.0] * len(CHORD_TEMPLATES)
    return labels, weights


def simplify_timeline(
    timeline: List[Dict[str, Any]],
    min_duration: float = MIN_SEGMENT_SECONDS,
) -> List[Dict[str, Any]]:
    """
    Fusiona los segmentos más cortos que `min_duration` con el vecino armónicamente
    más cercano (y, en empate, el más largo), re-fusiona segmentos idénticos
    adyacentes y devuelve un cifrado compacto y legible.
    """
    simplified = [dict(seg) for seg in timeline]
    guard = 0
    while guard < 2000:
        guard += 1
        shortest_index: Optional[int] = None
        shortest_duration = min_duration
        for i, seg in enumerate(simplified):
            duration = seg["end"] - seg["start"]
            if duration < shortest_duration and len(simplified) > 1:
                shortest_duration = duration
                shortest_index = i
        if shortest_index is None:
            break

        i = shortest_index
        left = simplified[i - 1] if i > 0 else None
        right = simplified[i + 1] if i + 1 < len(simplified) else None

        def similarity(a: str, b: str) -> float:
            ta, tb = CHORD_TEMPLATES.get(a), CHORD_TEMPLATES.get(b)
            if ta is not None and tb is not None:
                return float(np.dot(ta, tb))
            return 0.8 if a == b else -1.0

        if left is not None and right is not None:
            left_score = similarity(left["chord"], simplified[i]["chord"]) + 0.04 * (left["end"] - left["start"])
            right_score = similarity(right["chord"], simplified[i]["chord"]) + 0.04 * (right["end"] - right["start"])
            target = i - 1 if left_score >= right_score else i + 1
        elif left is not None:
            target = i - 1
        else:
            target = i + 1

        if target == i - 1:
            simplified[i - 1]["end"] = simplified[i]["end"]
        else:
            simplified[i + 1]["start"] = simplified[i]["start"]
        simplified.pop(i)

        j = 0
        while j < len(simplified) - 1:
            if simplified[j]["chord"] == simplified[j + 1]["chord"]:
                simplified[j]["end"] = simplified[j + 1]["end"]
                simplified.pop(j + 1)
            else:
                j += 1
    return simplified


def _estimate_key(global_chroma: np.ndarray) -> str:
    """Estima tonalidad correlacionando el perfil cromático global con Krumhansl-Kessler."""
    if global_chroma.sum() <= 0:
        return "N/A"
    global_chroma = global_chroma / (np.linalg.norm(global_chroma) or 1.0)

    best_score = -np.inf
    best_key = "N/A"
    for i, note in enumerate(NOTES):
        for mode_name, profile in (("", MAJOR_PROFILE), ("m", MINOR_PROFILE)):
            rotated = np.roll(profile, i)
            rotated = rotated / np.linalg.norm(rotated)
            score = float(np.dot(global_chroma, rotated))
            if score > best_score:
                best_score = score
                best_key = f"{note}{mode_name}"
    return best_key


def _viterbi_path(
    observations: List[np.ndarray],
    labels: List[str],
    weights: Optional[List[float]] = None,
    bass_observations: Optional[List[np.ndarray]] = None,
    gamma: float = VITERBI_GAMMA,
    change_penalty: float = VITERBI_CHANGE_PENALTY,
    bass_weight: float = BASS_WEIGHT,
) -> List[str]:
    """
    Suavizado temporal Viterbi: la progresión resultante es estable (sin saltos por
    frame), los acordes fuera de la tonalidad quedan penalizados por `weights` y la
    fundamental se refuerza con el croma de graves.
    """
    n_frames = len(observations)
    if n_frames == 0:
        return []

    n_labels = len(labels)
    roots = [NOTES.index(chord_root(label)) if chord_root(label) in NOTES else 0 for label in labels]

    scores = np.zeros((n_frames, n_labels))
    for t, obs in enumerate(observations):
        bass = bass_observations[t] if (bass_observations is not None and bass_weight > 0) else None
        for j, label in enumerate(labels):
            base = float(np.dot(obs, CHORD_TEMPLATES[label])) ** gamma
            if weights is not None:
                base *= weights[j]
            if bass is not None:
                base *= (1.0 - bass_weight + 2.0 * bass_weight * float(bass[roots[j]]))
            scores[t, j] = base

    back = np.zeros((n_frames, n_labels), dtype=int)
    dp = scores[0].copy()
    for t in range(1, n_frames):
        for j in range(n_labels):
            candidates = dp - change_penalty
            candidates[j] = dp[j]
            best_prev = int(np.argmax(candidates))
            back[t, j] = best_prev
            dp[j] = candidates[best_prev] + scores[t, j]

    path = [0] * n_frames
    path[-1] = int(np.argmax(dp))
    for t in range(n_frames - 1, 0, -1):
        path[t - 1] = back[t][path[t]]
    return [labels[i] for i in path]


def _build_timeline(smoothed: List[str], centers: List[float], duration: float) -> List[Dict[str, Any]]:
    """Une acordes consecutivos idénticos en segmentos con inicio/fin."""
    timeline: List[Dict[str, Any]] = []
    for idx, chord in enumerate(smoothed):
        start_sec = centers[idx]
        end_sec = centers[idx + 1] if idx + 1 < len(centers) else duration
        if timeline and timeline[-1]["chord"] == chord:
            timeline[-1]["end"] = round(end_sec, 2)
        else:
            timeline.append({
                "start": round(start_sec, 2),
                "end": round(end_sec, 2),
                "chord": chord,
            })
    return timeline


def _attach_confidences(
    timeline: List[Dict[str, Any]],
    observations: List[np.ndarray],
    centers: List[float],
    duration: float,
) -> None:
    """Confianza real por segmento: similitud media entre el croma de sus beats y su plantilla."""
    beat_index = 0
    for seg in timeline:
        dots: List[float] = []
        while beat_index < len(centers):
            center = centers[beat_index]
            if center < seg["start"] - 1e-6:
                beat_index += 1
                continue
            if center >= seg["end"] - 1e-6 and seg is not timeline[-1]:
                break
            if center >= duration:
                break
            template = CHORD_TEMPLATES.get(seg["chord"])
            if template is not None:
                dots.append(float(np.dot(observations[beat_index], template)))
            beat_index += 1
        seg["confidence"] = round(min(0.99, max(0.3, sum(dots) / len(dots))), 2) if dots else 0.5


def _transpose_audio_sync(src: Path, semitones: int, out_path: Path) -> Path:
    """
    Cambia el tono de un audio SIN alterar su duración ni su tempo:
    asetrate (+/- semitonos) seguido de atempo (compensa la velocidad).
    """
    ffmpeg = shutil.which("ffmpeg") or "/opt/homebrew/bin/ffmpeg"
    if not Path(ffmpeg).exists():
        raise RuntimeError("ffmpeg no está disponible en el servidor")

    try:
        import soundfile as sf
        source_rate = int(sf.info(str(src)).samplerate) or 44100
    except Exception:
        source_rate = 44100

    factor = 2.0 ** (semitones / 12.0)
    new_rate = int(round(source_rate * factor))
    tempo = 1.0 / factor
    # Cadena simple y compatible con cualquier build de ffmpeg (sin soxr, que no
    # está compilado en todos): resample -> desafina -> resample -> recompensa tempo.
    filter_chain = (
        f"aresample={source_rate},"
        f"asetrate={new_rate},"
        f"atempo={tempo:.6f}"
    )
    out_path.parent.mkdir(parents=True, exist_ok=True)
    result = subprocess.run(
        [ffmpeg, "-y", "-hide_banner", "-loglevel", "error",
         "-i", str(src), "-af", filter_chain, "-q:a", "2", str(out_path)],
        capture_output=True, text=True, timeout=300,
    )
    if result.returncode != 0 or not out_path.exists():
        raise RuntimeError(f"ffmpeg falló al transponer: {result.stderr[-400:]}")
    return out_path


class ChordService:
    @classmethod
    async def search_chords(cls, query: str) -> List[Dict[str, Any]]:
        """
        Busca canciones y acordes en fuentes abiertas (Songsterr API).
        """
        url = "https://www.songsterr.com/api/songs"
        params = {"pattern": query}
        headers = {"User-Agent": "OllaGitanaMusic/1.0"}
        async with httpx.AsyncClient(timeout=10.0) as client:
            try:
                resp = await client.get(url, params=params, headers=headers)
                if resp.status_code == 200:
                    data = resp.json()
                    results = []
                    for item in data[:15]:
                        artist = item.get("artist", "Desconocido")
                        title = item.get("title", "Sin título")
                        song_id = item.get("songId")
                        results.append({
                            "source": "Songsterr",
                            "id": song_id,
                            "title": title,
                            "artist": artist,
                            "url": f"https://www.songsterr.com/a/wa/song?id={song_id}",
                            "has_chords": item.get("hasChords", True)
                        })
                    return results
                return []
            except Exception as e:
                print(f"[ChordService] Error al buscar en Songsterr: {e}")
                return []

    @classmethod
    def extract_chords_from_audio(cls, audio_path: Path, hop_length: int = 2048) -> Dict[str, Any]:
        """
        Analiza el audio y devuelve un cifrado simplificado y estable:
        corrección de afinación, tonalidad global, vocabulario diatónico ponderado,
        suavizado Viterbi, segmentos de al menos 1 segundo y acordes de la canción
        listos para mostrar.
        """
        try:
            import librosa
        except ImportError:
            return {"error": "librosa no está instalado en el servidor", "timeline": [], "estimated_key": "N/A"}

        try:
            y, sr = librosa.load(str(audio_path), sr=22050, mono=True)
            if y.size == 0:
                return {"error": "El archivo de audio está vacío", "timeline": [], "estimated_key": "N/A"}

            duration = float(librosa.get_duration(y=y, sr=sr))

            # Armonía sin percusión para mejorar los cromagramas
            y_harmonic = librosa.effects.harmonic(y, margin=3.0)

            # Corrección de afinación: si la grabación está desafinada (cintas, directos),
            # se desplaza a tono estándar para que las plantillas casen.
            tuning_offset = float(librosa.estimate_tuning(y=y_harmonic, sr=sr))
            if abs(tuning_offset) >= TUNING_CORRECTION_THRESHOLD:
                y_harmonic = librosa.effects.pitch_shift(
                    y=y_harmonic, sr=sr, n_steps=-float(np.clip(tuning_offset, -1.0, 1.0)),
                )
                tuning_offset_used = float(np.clip(tuning_offset, -1.0, 1.0))
            else:
                tuning_offset_used = 0.0

            chroma = librosa.feature.chroma_cqt(y=y_harmonic, sr=sr, hop_length=hop_length)
            chroma = librosa.util.normalize(chroma, axis=0, norm=np.inf, threshold=1e-6)

            n_frames = chroma.shape[1]
            if n_frames == 0:
                return {"error": "No se pudieron extraer características armónicas", "timeline": [], "estimated_key": "N/A"}

            # Croma de graves: refuerza la fundamental real de cada acorde (bajo)
            try:
                from scipy.signal import butter, sosfilt
                sos = butter(4, 180 / (sr / 2.0), "low", output="sos")
                y_bass = sosfilt(sos, y_harmonic)
            except Exception:
                y_bass = y_harmonic
            chroma_bass = librosa.feature.chroma_cqt(
                y=y_bass, sr=sr, hop_length=hop_length,
                fmin=librosa.note_to_hz("C1"), n_octaves=4,
            )
            chroma_bass = librosa.util.normalize(chroma_bass, axis=0, norm=np.inf, threshold=1e-6)

            # Detección de beats: cada beat es una observación y cada intervalo entre cambios es un acorde
            tempo, beat_frames = librosa.beat.beat_track(y=y, sr=sr, hop_length=hop_length)
            tempo_value = float(np.atleast_1d(tempo)[0]) if tempo is not None else None
            if beat_frames is None or len(beat_frames) < 2:
                beat_frames = np.arange(0, n_frames, max(1, int(1.5 * sr / hop_length)))

            beat_times = librosa.frames_to_time(beat_frames, sr=sr, hop_length=hop_length)
            observations: List[np.ndarray] = []
            bass_observations: List[np.ndarray] = []
            beat_centers: List[float] = []
            for i, frame in enumerate(beat_frames):
                start = int(frame)
                end = int(beat_frames[i + 1]) if i + 1 < len(beat_frames) else n_frames
                if end <= start:
                    continue
                segment = chroma[:, start:end]
                if segment.shape[1] == 0:
                    continue
                mean_chroma = np.mean(segment, axis=1)
                norm = np.linalg.norm(mean_chroma)
                if norm <= 0:
                    continue
                observations.append(mean_chroma / norm)
                if start < chroma_bass.shape[1]:
                    bass_segment = chroma_bass[:, start:min(end, chroma_bass.shape[1])]
                    if bass_segment.shape[1] > 0:
                        bass_mean = np.mean(bass_segment, axis=1)
                        bass_sum = float(bass_mean.sum())
                        bass_observations.append(bass_mean / bass_sum if bass_sum > 0 else bass_mean)
                    else:
                        bass_observations.append(np.zeros(12))
                else:
                    bass_observations.append(np.zeros(12))
                beat_centers.append(float(beat_times[i]))

            if not observations:
                return {"error": "No se detectaron segmentos armónicos válidos", "timeline": [], "estimated_key": "N/A"}

            # Tonalidad global -> vocabulario diatónico ponderado
            global_chroma = np.mean(chroma, axis=1)
            estimated_key = _estimate_key(global_chroma)
            labels, weights = diatonic_vocabulary(estimated_key)

            smoothed = _viterbi_path(observations, labels, weights=weights, bass_observations=bass_observations)

            # Línea temporal compacta + simplificación ("un segundo o nada") + plegado de tensiones
            timeline = _build_timeline(smoothed, beat_centers, duration)
            timeline = simplify_timeline(timeline, MIN_SEGMENT_SECONDS)
            for seg in timeline:
                seg["chord"] = fold_tension(seg["chord"])

            merged: List[Dict[str, Any]] = []
            for seg in timeline:
                if merged and merged[-1]["chord"] == seg["chord"]:
                    merged[-1]["end"] = seg["end"]
                else:
                    merged.append(seg)
            timeline = merged

            _attach_confidences(timeline, observations, beat_centers, duration)

            # Acordes de la canción, en orden de aparición
            unique_chords: List[str] = []
            for seg in timeline:
                if seg["chord"] not in unique_chords:
                    unique_chords.append(seg["chord"])

            return {
                "duration": round(duration, 2),
                "estimated_key": estimated_key,
                "tempo": round(tempo_value, 1) if tempo_value else None,
                "timeline": timeline,
                "unique_chords": unique_chords,
                "tuning_offset": round(tuning_offset_used, 2),
                "engine": "v2",
            }

        except Exception as e:
            print(f"[ChordService] Error analizando acordes: {e}")
            return {"error": str(e), "timeline": [], "estimated_key": "N/A"}

    @classmethod
    async def transpose_audio_file(cls, src: Path, semitones: int, out_path: Path) -> Path:
        """Cambia el tono del audio (async, ejecuta ffmpeg en un hilo aparte)."""
        import asyncio
        return await asyncio.to_thread(_transpose_audio_sync, src, semitones, out_path)
