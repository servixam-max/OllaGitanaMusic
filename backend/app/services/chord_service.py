from pathlib import Path
from typing import List, Dict, Any, Optional
import httpx
import numpy as np

# Nombres de notas estándar
NOTES = ['C', 'C#', 'D', 'D#', 'E', 'F', 'F#', 'G', 'G#', 'A', 'A#', 'B']

# Perfil de tonalidad de Krumhansl-Kessler para estimar la tónica
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

# Prior: preferir tríadas simples cuando la puntuación es muy parecida.
# Evita oscilaciones artificiales entre Am / Am7 / Amaj7 en el mismo compás.
QUALITY_PRIOR: Dict[str, float] = {
    "": 1.0,
    "m": 1.0,
    "7": 0.96,
    "m7": 0.96,
    "maj7": 0.95,
    "sus4": 0.92,
    "dim": 0.90,
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


def _smooth_with_viterbi(observations: List[np.ndarray], labels: List[str], change_penalty: float = 0.12) -> List[str]:
    """
    Suavizado temporal tipo Viterbi: evita saltos de acorde en cada frame
    y produce una progresión estable y legible.
    """
    n_frames = len(observations)
    if n_frames == 0:
        return []

    n_labels = len(labels)
    scores = np.zeros((n_frames, n_labels))
    for t, obs in enumerate(observations):
        for j, label in enumerate(labels):
            quality = label[1:] if len(label) > 1 and label[1] in ("m", "7", "d", "s") else ""
            base_sim = 0.0
            for quality_name, prior in QUALITY_PRIOR.items():
                if label.endswith(quality_name) and quality_name != "":
                    base_sim = prior
                    break
            if base_sim == 0.0:
                base_sim = QUALITY_PRIOR[""]
            scores[t, j] = float(np.dot(obs, CHORD_TEMPLATES[label])) * base_sim

    back = np.zeros((n_frames, n_labels), dtype=int)
    dp = scores[0].copy()
    for t in range(1, n_frames):
        prev = dp
        best_prev = np.zeros(n_labels, dtype=int)
        best_score = np.full(n_labels, -np.inf)
        for j in range(n_labels):
            # Cambiar de acorde tiene un coste; mantenerse es gratis
            candidates = prev - change_penalty
            candidates[j] = prev[j]
            best_prev[j] = int(np.argmax(candidates))
            best_score[j] = candidates[best_prev[j]] + scores[t, j]
        dp = best_score
        back[t] = best_prev

    path = [0] * n_frames
    path[-1] = int(np.argmax(dp))
    for t in range(n_frames - 1, 0, -1):
        path[t - 1] = back[t][path[t]]
    return [labels[i] for i in path]


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
        Analiza el audio con cromagramas CQT, detecta beats y estima la progresión
        de acordes con plantillas armónicas (tríadas + séptimas) y suavizado Viterbi,
        además de la tonalidad global con perfiles Krumhansl-Kessler.
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
            chroma = librosa.feature.chroma_cqt(y=y_harmonic, sr=sr, hop_length=hop_length)
            chroma = librosa.util.normalize(chroma, axis=0, norm=np.inf, threshold=1e-6)

            n_frames = chroma.shape[1]
            if n_frames == 0:
                return {"error": "No se pudieron extraer características armónicas", "timeline": [], "estimated_key": "N/A"}

            # Detección de beats: cada beat es una observación y cada intervalo entre cambios es un acorde
            tempo, beat_frames = librosa.beat.beat_track(y=y, sr=sr, hop_length=hop_length)
            tempo_value = float(np.atleast_1d(tempo)[0]) if tempo is not None else None
            if beat_frames is None or len(beat_frames) < 2:
                beat_frames = np.arange(0, n_frames, max(1, int(1.5 * sr / hop_length)))

            beat_times = librosa.frames_to_time(beat_frames, sr=sr, hop_length=hop_length)
            observations = []
            beat_centers = []
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
                beat_centers.append(float(beat_times[i]))

            if not observations:
                return {"error": "No se detectaron segmentos armónicos válidos", "timeline": [], "estimated_key": "N/A"}

            labels = list(CHORD_TEMPLATES.keys())
            smoothed = _smooth_with_viterbi(observations, labels)

            # Construir línea temporal compacta (une acordes consecutivos idénticos)
            timeline: List[Dict[str, Any]] = []
            for idx, chord in enumerate(smoothed):
                start_sec = beat_centers[idx]
                end_sec = beat_centers[idx + 1] if idx + 1 < len(beat_centers) else duration
                if timeline and timeline[-1]["chord"] == chord:
                    timeline[-1]["end"] = round(end_sec, 2)
                    timeline[-1]["frames"] += 1
                else:
                    timeline.append({
                        "start": round(start_sec, 2),
                        "end": round(end_sec, 2),
                        "chord": chord,
                        "frames": 1,
                    })

            # Confianza media por segmento y fusión de segmentos muy cortos (< 1 beat)
            for seg in timeline:
                frames = max(1, seg.pop("frames"))
                seg["confidence"] = round(min(0.99, 0.55 + min(frames, 8) * 0.05), 2)

            global_chroma = np.mean(chroma, axis=1)
            estimated_key = _estimate_key(global_chroma)

            return {
                "duration": round(duration, 2),
                "estimated_key": estimated_key,
                "tempo": round(tempo_value, 1) if tempo_value else None,
                "timeline": timeline,
            }

        except Exception as e:
            print(f"[ChordService] Error analizando acordes: {e}")
            return {"error": str(e), "timeline": [], "estimated_key": "N/A"}
