import asyncio
import json
import os
import re
import shutil
import sys
from pathlib import Path
from typing import Dict, List, Optional, Tuple

from app.core.config import settings
from app.core.database import AsyncSessionLocal
from app.models.stem_task import StemTask
from app.services.ws_manager import ws_manager

# Pistas estándar que puede devolver Demucs
SIX_STEM_NAMES = ["vocals", "drums", "bass", "guitar", "piano", "other"]
FOUR_STEM_NAMES = ["vocals", "drums", "bass", "other"]
KARAOKE_STEM_NAMES = ["vocals", "instrumental"]

# Presets de calidad disponibles para la app.
# - htdemucs_ft es el modelo fine-tuned: máxima calidad en voz/batería/bajo/otros (4 pistas).
# - htdemucs_6s añade guitarra y piano, con menor definición general.
# - hybrid = htdemucs_ft (4 pistas) + htdemucs_6s (añade guitarra/piano) -> máxima calidad en las 6.
PRESETS: Dict[str, Dict[str, object]] = {
    "fast": {
        "label": "Rápida",
        "model": "htdemucs",
        "shifts": 0,
        "overlap": 0.25,
        "format": "mp3",
        "bitrate": "320",
        "description": "4 pistas, la más rápida. Ideal para ensayar ya mismo.",
    },
    "balanced": {
        "label": "Equilibrada",
        "model": "htdemucs_ft",
        "shifts": 1,
        "overlap": 0.5,
        "format": "mp3",
        "bitrate": "320",
        "description": "4 pistas de alta calidad (voz/batería/bajo/otros).",
    },
    "max": {
        "label": "Máxima",
        "model": "htdemucs_ft",
        "shifts": 4,
        "overlap": 0.75,
        "format": "wav",
        "bitrate": None,
        "description": "4 pistas en WAV 24-bit para loops y búsqueda con precisión de muestra.",
    },
    "six": {
        "label": "6 pistas",
        "model": "htdemucs_6s",
        "shifts": 1,
        "overlap": 0.5,
        "format": "mp3",
        "bitrate": "320",
        "description": "Separa también guitarra y piano (menor definición general).",
    },
    "hybrid": {
        "label": "Híbrida (recomendada)",
        "model": "hybrid",
        "shifts": 1,
        "overlap": 0.5,
        "format": "mp3",
        "bitrate": "320",
        "description": "Voz/batería/bajo/otros con el modelo fine-tuned + guitarra y piano del modelo 6s. La mejor calidad global.",
    },
    "karaoke": {
        "label": "Karaoke",
        "model": "htdemucs_ft",
        "shifts": 1,
        "overlap": 0.5,
        "format": "mp3",
        "bitrate": "320",
        "two_stems": "vocals",
        "description": "Solo voz e instrumental. Perfecta para cantar o tocar encima del tema.",
    },
}

DEFAULT_PRESET = "hybrid"


def get_preset(name: Optional[str]) -> Tuple[str, Dict[str, object]]:
    """Devuelve el preset validado (con fallback al preset por defecto)."""
    key = (name or DEFAULT_PRESET).strip().lower()
    if key not in PRESETS:
        key = DEFAULT_PRESET
    return key, PRESETS[key]


class DemucsService:
    """Separación de pistas con Demucs (MPS/CUDA/CPU) y progreso en vivo vía WebSocket."""

    @classmethod
    async def update_status(
        cls,
        task_id: str,
        status: str,
        progress: int,
        stems: Optional[Dict[str, str]] = None,
        error: Optional[str] = None,
    ):
        """Actualiza la tarea en base de datos y notifica por WebSocket."""
        async with AsyncSessionLocal() as session:
            task = await session.get(StemTask, task_id)
            if task:
                task.status = status
                task.progress = progress
                if stems is not None:
                    task.stems_json = json.dumps(stems)
                if error is not None:
                    task.error_message = error
                await session.commit()

        await ws_manager.broadcast_task_progress(task_id, {
            "task_id": task_id,
            "status": status,
            "progress": progress,
            "stems": stems or {},
            "error": error,
        })

    @classmethod
    def _python_exe(cls) -> str:
        venv_python = Path(__file__).resolve().parents[3] / ".venv" / "bin" / "python"
        if venv_python.exists():
            return str(venv_python)
        return sys.executable

    @classmethod
    async def _has_demucs(cls, python_exe: str) -> bool:
        try:
            check_proc = await asyncio.create_subprocess_exec(
                python_exe, "-c", "import demucs",
                stdout=asyncio.subprocess.DEVNULL,
                stderr=asyncio.subprocess.DEVNULL,
            )
            await check_proc.wait()
            return check_proc.returncode == 0
        except Exception:
            return shutil.which("demucs") is not None

    @classmethod
    async def _detect_device(cls, python_exe: str) -> str:
        """Detecta aceleración por hardware: MPS en Apple Silicon, CUDA en NVIDIA."""
        try:
            dev_proc = await asyncio.create_subprocess_exec(
                python_exe, "-c",
                "import torch; print('mps' if torch.backends.mps.is_available() and torch.backends.mps.is_built() else ('cuda' if torch.cuda.is_available() else 'cpu'))",
                stdout=asyncio.subprocess.PIPE,
                stderr=asyncio.subprocess.DEVNULL,
            )
            stdout, _ = await dev_proc.communicate()
            detected = stdout.decode().strip()
            if detected in ("mps", "cuda"):
                return detected
        except Exception:
            pass
        return "cpu"

    @classmethod
    async def _run_demucs(
        cls,
        task_id: str,
        input_path: Path,
        model: str,
        output_base_dir: Path,
        preset: Dict[str, object],
        two_stems: Optional[str] = None,
        progress_from: int = 5,
        progress_to: int = 95,
    ) -> Tuple[bool, str]:
        """Ejecuta una pasada de Demucs con progreso real parseado del tqdm de stderr."""
        python_exe = cls._python_exe()
        device = await cls._detect_device(python_exe)

        out_format = str(preset.get("format", "mp3"))
        cmd: List[str] = [
            python_exe, "-m", "demucs.separate",
            "-n", model,
            "-d", device,
            "--overlap", str(preset.get("overlap", 0.5)),
            "--clip-mode", "rescale",
        ]

        shifts = int(preset.get("shifts", 1) or 0)
        if shifts > 0:
            cmd += ["--shifts", str(shifts)]

        if two_stems:
            cmd += ["--two-stems", two_stems]

        if out_format == "wav":
            cmd += ["--int24"]
        else:
            cmd += ["--mp3", "--mp3-bitrate", str(preset.get("bitrate", "320"))]

        cmd += ["-o", str(output_base_dir), str(input_path)]

        env = os.environ.copy()
        env["PYTORCH_ENABLE_MPS_FALLBACK"] = "1"

        print(f"[DemucsService] Ejecutando: {' '.join(cmd)}")
        process = await asyncio.create_subprocess_exec(
            *cmd,
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.PIPE,
            env=env,
        )

        state = {"progress": progress_from}
        err_output: List[str] = []
        pct_regex = re.compile(r"(\d+)%")
        span = max(1, progress_to - progress_from)

        async def read_stderr():
            buffer = ""
            while True:
                chunk = await process.stderr.read(256)
                if not chunk:
                    break
                text = chunk.decode("utf-8", errors="replace")
                err_output.append(text)
                buffer += text

                matches = pct_regex.findall(buffer)
                if matches:
                    raw_pct = int(matches[-1])
                    scaled = int(progress_from + (raw_pct / 100.0) * span)
                    if scaled > state["progress"]:
                        state["progress"] = scaled
                        await cls.update_status(task_id, "processing", scaled)

                if len(buffer) > 2048:
                    buffer = buffer[-512:]

        async def read_stdout():
            while True:
                line = await process.stdout.readline()
                if not line:
                    break

        await asyncio.gather(read_stderr(), read_stdout(), process.wait())

        if process.returncode != 0:
            err_msg = "".join(err_output)[-800:] or "Error desconocido al ejecutar Demucs"
            return False, err_msg
        return True, ""

    @classmethod
    def _collect_stems(cls, model_dir: Path, task_id: str, model_name: str, input_stem: str) -> Dict[str, str]:
        """Recoge los archivos de pistas generados y los publica con URL estática."""
        stems_dict: Dict[str, str] = {}
        track_dir = model_dir / model_name / input_stem
        search_root = track_dir if track_dir.exists() else model_dir

        for pattern in ("*.mp3", "*.wav"):
            for file in sorted(search_root.rglob(pattern)):
                # Demucs nombra la pista instrumental "no_vocals" en modo karaoke
                name = "instrumental" if file.stem == "no_vocals" else file.stem
                if name in stems_dict:
                    continue
                rel = file.relative_to(settings.stems_dir)
                stems_dict[name] = f"/static/stems/{rel.as_posix()}"
        return stems_dict

    @classmethod
    async def _ffmpeg_fallback(
        cls, task_id: str, input_path: Path, output_base_dir: Path, model_name: str
    ) -> Dict[str, str]:
        """Fallback con filtros de frecuencia cuando Demucs no está disponible."""
        model_dir = output_base_dir / model_name / input_path.stem
        model_dir.mkdir(parents=True, exist_ok=True)

        filters = {
            "vocals": "bandpass=f=1500:width_type=h:w=2000",
            "drums": "highpass=f=40,lowpass=f=6000",
            "bass": "lowpass=f=250",
            "guitar": "bandpass=f=1200:width_type=h:w=1800",
            "piano": "bandpass=f=800:width_type=h:w=1200",
            "other": "highpass=f=800",
        }

        step_pct = 80 // len(filters)
        curr_p = 10
        for stem_name, audio_filter in filters.items():
            out_file = model_dir / f"{stem_name}.mp3"
            if not out_file.exists():
                proc = await asyncio.create_subprocess_exec(
                    "ffmpeg", "-y", "-i", str(input_path),
                    "-af", audio_filter,
                    "-b:a", "192k",
                    str(out_file),
                    stdout=asyncio.subprocess.DEVNULL,
                    stderr=asyncio.subprocess.DEVNULL,
                )
                await proc.wait()
            curr_p += step_pct
            await cls.update_status(task_id, "processing", min(curr_p, 90))

        return cls._collect_stems(output_base_dir, task_id, model_name, input_path.stem)

    @classmethod
    async def _probe_duration(cls, python_exe: str, path: Path) -> Optional[float]:
        """Duración exacta (segundos) de un archivo de audio."""
        try:
            proc = await asyncio.create_subprocess_exec(
                python_exe, "-c",
                (
                    "import soundfile as sf, sys;"
                    "info = sf.info(sys.argv[1]);"
                    "print(info.frames / info.samplerate)"
                ),
                str(path),
                stdout=asyncio.subprocess.PIPE,
                stderr=asyncio.subprocess.DEVNULL,
            )
            stdout, _ = await proc.communicate()
            return float(stdout.decode().strip())
        except Exception:
            return None

    @classmethod
    async def process_audio(cls, task_id: str, input_path: Path, preset_name: Optional[str] = None):
        """
        Separa las pistas de una canción usando el preset de calidad indicado.
        Soporta salida de 4/6 pistas, karaoke y modo híbrido (ft + 6s).
        """
        preset_key, preset = get_preset(preset_name)
        model = str(preset["model"])
        two_stems = preset.get("two_stems")

        output_base_dir = settings.stems_dir / task_id
        output_base_dir.mkdir(parents=True, exist_ok=True)

        async def fail(message: str):
            await cls.update_status(task_id, "failed", 0, error=message[:800])

        try:
            await cls.update_status(task_id, "processing", 5)

            python_exe = cls._python_exe()
            if not await cls._has_demucs(python_exe):
                print("[DemucsService] Demucs no disponible, usando filtros ffmpeg como fallback...")
                stems_dict = await cls._ffmpeg_fallback(task_id, input_path, output_base_dir, "ffmpeg_fallback")
                if stems_dict:
                    await cls.update_status(task_id, "completed", 100, stems=stems_dict)
                else:
                    await fail("No se pudieron generar pistas con el fallback ffmpeg")
                return

            hybrid = model == "hybrid"
            if hybrid:
                # Primero htdemucs_ft (4 pistas de máxima calidad): 5% -> 60%
                ok, err = await cls._run_demucs(
                    task_id, input_path, "htdemucs_ft", output_base_dir, preset,
                    progress_from=5, progress_to=60,
                )
                if not ok:
                    await fail(err)
                    return

                # Después htdemucs_6s (guitarra/piano/other): 60% -> 95%.
                # No lanzamos el modelo si la pista de guitarra ya existe de una ejecución previa.
                guitar_path = output_base_dir / "htdemucs_6s" / input_path.stem / "guitar.mp3"
                if not guitar_path.exists():
                    six_preset = dict(preset)
                    six_preset["model"] = "htdemucs_6s"
                    ok, err = await cls._run_demucs(
                        task_id, input_path, "htdemucs_6s", output_base_dir, six_preset,
                        progress_from=60, progress_to=95,
                    )
                    if not ok:
                        await fail(err)
                        return
            else:
                ok, err = await cls._run_demucs(
                    task_id, input_path, model, output_base_dir, preset,
                    two_stems=str(two_stems) if two_stems else None,
                    progress_from=5, progress_to=95,
                )
                if not ok:
                    await fail(err)
                    return

            # Recolectar todas las pistas (en híbrido las 4 stems de ft y guitar/piano de 6s)
            stems_dict: Dict[str, str] = {}
            for search_model in ("htdemucs_ft", "htdemucs_6s", "htdemucs"):
                found = cls._collect_stems(output_base_dir, task_id, search_model, input_path.stem)
                for name, url in found.items():
                    stems_dict.setdefault(name, url)
            stems_dict = {k: v for k, v in stems_dict.items() if k in SIX_STEM_NAMES + KARAOKE_STEM_NAMES}

            if not stems_dict:
                await fail("No se encontraron pistas de salida en el directorio esperado")
                return

            # Validación de duración: todas las pistas deben durar lo mismo (sincronía perfecta)
            durations = []
            for name, url in stems_dict.items():
                file_path = settings.stems_dir / Path(url.replace("/static/stems/", "", 1))
                dur = await cls._probe_duration(python_exe, file_path)
                if dur is not None:
                    durations.append((name, dur))
            if len(durations) > 1:
                max_dur = max(d for _, d in durations)
                min_dur = min(d for _, d in durations)
                if max_dur - min_dur > 0.5:
                    print(f"[DemucsService] Aviso: desfase de duración de {max_dur - min_dur:.2f}s entre pistas")

            await cls.update_status(task_id, "completed", 100, stems=stems_dict)
            print(f"[DemucsService] Separación completada ({preset_key}) para tarea {task_id}: {list(stems_dict.keys())}")

        except Exception as e:
            print(f"[DemucsService] Excepción procesando audio: {e}")
            await fail(str(e))
