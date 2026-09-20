import asyncio
import json
import os
import re
import shutil
import sys
from pathlib import Path
from typing import Dict, Optional

from app.core.config import settings
from app.core.database import AsyncSessionLocal
from app.models.stem_task import StemTask
from app.services.ws_manager import ws_manager

class DemucsService:
    @classmethod
    async def process_audio(cls, task_id: str, input_path: Path, model_name: str = "htdemucs"):
        """
        Ejecuta la separación de pistas con Demucs en segundo plano con aceleración
        por hardware (Metal / MPS en Apple Silicon o CUDA) y progreso real en vivo vía WebSocket.
        """
        output_base_dir = settings.stems_dir / task_id
        output_base_dir.mkdir(parents=True, exist_ok=True)

        async def update_status(status: str, progress: int, stems: Optional[Dict[str, str]] = None, error: Optional[str] = None):
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
            
            # Notificar inmediatamente a la app por WebSocket
            await ws_manager.broadcast_task_progress(task_id, {
                "task_id": task_id,
                "status": status,
                "progress": progress,
                "stems": stems or {},
                "error": error
            })

        try:
            await update_status("processing", 5)
            
            # Detectar si demucs está disponible en el entorno de Python
            has_demucs = False
            try:
                import demucs
                has_demucs = True
            except ImportError:
                has_demucs = shutil.which("demucs") is not None

            if has_demucs:
                # Detectar aceleración por hardware
                device = "cpu"
                try:
                    import torch
                    if torch.backends.mps.is_available() and torch.backends.mps.is_built():
                        device = "mps"
                        print(f"[DemucsService] Usando aceleración Apple Silicon Metal (MPS) para tarea {task_id}")
                    elif torch.cuda.is_available():
                        device = "cuda"
                        print(f"[DemucsService] Usando aceleración NVIDIA CUDA para tarea {task_id}")
                except Exception as e:
                    print(f"[DemucsService] Detección de aceleración: {e}, usando CPU")

                cmd = [
                    sys.executable, "-m", "demucs.separate",
                    "-n", model_name,
                    "-d", device,
                    "--mp3",
                    "--mp3-bitrate", "192",
                    "-o", str(output_base_dir),
                    str(input_path)
                ]

                env = os.environ.copy()
                env["PYTORCH_ENABLE_MPS_FALLBACK"] = "1"

                process = await asyncio.create_subprocess_exec(
                    *cmd,
                    stdout=asyncio.subprocess.PIPE,
                    stderr=asyncio.subprocess.PIPE,
                    env=env
                )

                last_progress = 5
                err_output = []
                pct_regex = re.compile(r'(\d+)%')

                # Lectura en tiempo real de stderr para capturar el avance exacto de Demucs (tqdm)
                async def read_stderr():
                    nonlocal last_progress
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
                            # Mapear de 5% a 95%
                            scaled_pct = int(5 + (raw_pct * 0.90))
                            if scaled_pct > last_progress:
                                last_progress = scaled_pct
                                await update_status("processing", scaled_pct)

                        if len(buffer) > 2048:
                            buffer = buffer[-512:]

                async def read_stdout():
                    while True:
                        line = await process.stdout.readline()
                        if not line:
                            break

                await asyncio.gather(read_stderr(), read_stdout(), process.wait())

                if process.returncode != 0:
                    err_msg = "".join(err_output) if err_output else "Error desconocido al ejecutar Demucs"
                    print(f"[DemucsService] Error ejecutando Demucs: {err_msg[:500]}")
                    await update_status("failed", 0, error=err_msg[:500])
                    return
            else:
                # Fallback con filtros de frecuencia por ffmpeg
                print("[DemucsService] Generando pistas filtradas con ffmpeg...")
                model_dir = output_base_dir / model_name / input_path.stem
                model_dir.mkdir(parents=True, exist_ok=True)
                
                filters = {
                    "vocals": "bandpass=f=1500:width_type=h:w=2000",
                    "drums": "highpass=f=40,lowpass=f=6000",
                    "bass": "lowpass=f=250",
                    "other": "highpass=f=800",
                }
                if "6s" in model_name:
                    filters["guitar"] = "bandpass=f=1200:width_type=h:w=1800"
                    filters["piano"] = "bandpass=f=800:width_type=h:w=1200"

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
                            stderr=asyncio.subprocess.DEVNULL
                        )
                        await proc.wait()
                    curr_p += step_pct
                    await update_status("processing", min(curr_p, 90))

            # Buscar las pistas generadas en la carpeta de salida (mp3 o wav)
            stems_dict = {}
            track_stem_dir = output_base_dir / model_name / input_path.stem
            
            if track_stem_dir.exists():
                for file in track_stem_dir.glob("*.mp3"):
                    stems_dict[file.stem] = f"/static/stems/{task_id}/{model_name}/{input_path.stem}/{file.name}"
                for file in track_stem_dir.glob("*.wav"):
                    if file.stem not in stems_dict:
                        stems_dict[file.stem] = f"/static/stems/{task_id}/{model_name}/{input_path.stem}/{file.name}"
            else:
                for file in output_base_dir.rglob("*.mp3"):
                    rel_path = file.relative_to(settings.stems_dir)
                    stems_dict[file.stem] = f"/static/stems/{rel_path}"
                for file in output_base_dir.rglob("*.wav"):
                    if file.stem not in stems_dict:
                        rel_path = file.relative_to(settings.stems_dir)
                        stems_dict[file.stem] = f"/static/stems/{rel_path}"

            await update_status("completed", 100, stems=stems_dict)
            print(f"[DemucsService] Separación completada con éxito para tarea {task_id}: {stems_dict}")

        except Exception as e:
            print(f"[DemucsService] Excepción procesando audio: {e}")
            await update_status("failed", 0, error=str(e))
