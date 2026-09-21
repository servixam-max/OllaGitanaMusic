import asyncio
import uuid
from pathlib import Path
from typing import Dict, Optional

from app.core.config import settings
from app.core.database import AsyncSessionLocal
from app.models.stem_task import StemTask
from app.services.demucs_service import DemucsService, get_preset
from app.services.ws_manager import ws_manager


class StemQueue:
    """
    Cola de separación con un único worker.

    Demucs es intensivo en CPU/GPU y memoria: ejecutar varias separaciones a la vez
    en un mismo servidor degrada la calidad y puede agotar la memoria (M4/16 GB).
    Esta cola garantiza una tarea activa, informa de la posición de espera y
    recupera tareas huérfanas tras un reinicio del servidor.
    """

    def __init__(self):
        self._queue: asyncio.Queue = asyncio.Queue()
        self._worker: Optional[asyncio.Task] = None
        self._queued_ids: list[str] = []
        self._current_task_id: Optional[str] = None
        self._loop: Optional[asyncio.AbstractEventLoop] = None

    @property
    def current_task_id(self) -> Optional[str]:
        return self._current_task_id

    def queued_position(self, task_id: str) -> Optional[int]:
        try:
            return self._queued_ids.index(task_id) + 1
        except ValueError:
            return None

    def start(self):
        """Arranca el worker y recupera tareas pendientes/interrumpidas."""
        if self._worker and not self._worker.done():
            return
        self._loop = asyncio.get_running_loop()
        self._worker = self._loop.create_task(self._run())
        self._loop.create_task(self._recover_orphans())

    async def _recover_orphans(self):
        """Marca como interrumpidas las tareas que quedaron a medias tras un reinicio."""
        async with AsyncSessionLocal() as session:
            from sqlalchemy import select
            result = await session.execute(
                select(StemTask).where(StemTask.status.in_(["processing", "queued"]))
            )
            orphans = result.scalars().all()
            if not orphans:
                return
            for task in orphans:
                # Si los archivos de pistas ya existen y están completos, la damos por terminada.
                stems_dir = settings.stems_dir / task.id
                has_stems = stems_dir.exists() and any(stems_dir.rglob("*.mp3")) or any(stems_dir.rglob("*.wav"))
                if has_stems:
                    task.status = "interrupted"
                    task.error_message = "El servidor se reinició durante la separación. Puedes reintentar y reutilizará lo ya procesado."
                else:
                    task.status = "interrupted"
                    task.error_message = "El servidor se reinició durante la separación. Reintenta la separación."
                task.progress = 0
            await session.commit()
            print(f"[StemQueue] {len(orphans)} tarea(s) marcadas como interrumpidas tras el reinicio")

    def enqueue(self, task_id: str, preset: Optional[str] = None) -> int:
        """Encola una tarea. Devuelve la posición en la cola (1 = siguiente)."""
        if task_id in self._queued_ids or task_id == self._current_task_id:
            pos = self.queued_position(task_id)
            return pos if pos is not None else 1
        self._queued_ids.append(task_id)
        self._queue.put_nowait((task_id, preset))
        return self.queued_position(task_id) or 1

    async def _run(self):
        while True:
            task_id, preset = await self._queue.get()
            try:
                if task_id in self._queued_ids:
                    self._queued_ids.remove(task_id)
                self._current_task_id = task_id
                await self._process(task_id, preset)
            except Exception as e:
                print(f"[StemQueue] Error procesando tarea {task_id}: {e}")
            finally:
                self._current_task_id = None
                self._queue.task_done()

    async def _process(self, task_id: str, preset: Optional[str]):
        async with AsyncSessionLocal() as session:
            task = await session.get(StemTask, task_id)
            if not task:
                return
            input_candidates = list(settings.upload_dir.glob(f"{task_id}.*"))
            if not input_candidates:
                task.status = "failed"
                task.error_message = "Archivo original no encontrado en el servidor"
                await session.commit()
                await ws_manager.broadcast_task_progress(task_id, {
                    "task_id": task_id, "status": "failed", "progress": 0,
                    "stems": {}, "error": task.error_message,
                })
                return
            input_path = input_candidates[0]

        preset_key, _ = get_preset(preset)
        async with AsyncSessionLocal() as session:
            task = await session.get(StemTask, task_id)
            if task:
                task.preset = preset_key
                await session.commit()

        await DemucsService.process_audio(task_id, input_path, preset_key)


stem_queue = StemQueue()
