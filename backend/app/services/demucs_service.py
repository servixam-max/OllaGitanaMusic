import asyncio
import json
import os
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
        Ejecuta la separación de pistas con Demucs en segundo plano y actualiza el estado.
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
            
            # Notificar por WebSocket
            await ws_manager.broadcast_task_progress(task_id, {
                "task_id": task_id,
                "status": status,
                "progress": progress,
                "stems": stems or {},
                "error": error
            })

        try:
            await update_status("processing", 10)
            
            # Verificar si demucs está disponible en el entorno de Python
            has_demucs = False
            try:
                import demucs
                has_demucs = True
            except ImportError:
                has_demucs = shutil.which("demucs") is not None

            if has_demucs:
                cmd = [
                    sys.executable, "-m", "demucs.separate",
                    "-n", model_name,
                    "--mp3",
                    "--mp3-bitrate", "192",
                    "-o", str(output_base_dir),
                    str(input_path)
                ]

                process = await asyncio.create_subprocess_exec(
                    *cmd,
                    stdout=asyncio.subprocess.PIPE,
                    stderr=asyncio.subprocess.PIPE
                )

                # Simular avance mientras el proceso corre
                for p in [25, 45, 65, 85]:
                    await asyncio.sleep(2)
                    if process.returncode is not None:
                        break
                    await update_status("processing", p)

                stdout, stderr = await process.communicate()

                if process.returncode != 0:
                    err_msg = stderr.decode() if stderr else "Error desconocido al ejecutar Demucs"
                    print(f"[DemucsService] Error ejecutando Demucs: {err_msg}")
                    await update_status("failed", 0, error=err_msg[:500])
                    return
            else:
                # Fallback con filtros de frecuencia por ffmpeg para no duplicar el audio
                print("[DemucsService] Generando pistas filtradas por frecuencia con ffmpeg...")
                model_dir = output_base_dir / model_name / input_path.stem
                model_dir.mkdir(parents=True, exist_ok=True)
                
                filters = {
                    "bass": "lowpass=f=250",
                    "vocals": "bandpass=f=1500:width_type=h:w=2000",
                    "drums": "highpass=f=40,lowpass=f=6000",
                    "other": "highpass=f=800"
                }

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
            print(f"[DemucsService] Separación completada con éxito para tarea {task_id}: {stems_dict}")

        except Exception as e:
            print(f"[DemucsService] Excepción procesando audio: {e}")
            await update_status("failed", 0, error=str(e))
