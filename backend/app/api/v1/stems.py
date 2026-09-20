import asyncio
import json
import uuid
import aiofiles
from typing import List, Optional
from fastapi import APIRouter, UploadFile, File, Form, Depends, HTTPException, BackgroundTasks
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, desc

from app.core.config import settings
from app.core.database import get_db
from app.models.stem_task import StemTask
from app.services.demucs_service import DemucsService

router = APIRouter(prefix="/stems", tags=["Stems Separator"])

@router.post("/upload")
async def upload_audio_for_stems(
    background_tasks: BackgroundTasks,
    file: UploadFile = File(...),
    model: str = Form("htdemucs"),  # "htdemucs" o "htdemucs_6s"
    db: AsyncSession = Depends(get_db)
):
    """
    Sube un archivo de audio (MP3, WAV, etc.) y lanza la separación de pistas con Demucs en segundo plano.
    """
    if not file.filename.lower().endswith((".mp3", ".wav", ".flac", ".ogg", ".m4a")):
        raise HTTPException(status_code=400, detail="Formato no soportado. Formatos válidos: MP3, WAV, FLAC, OGG, M4A")

    task_id = str(uuid.uuid4())
    ext = file.filename.split(".")[-1]
    input_filename = f"{task_id}.{ext}"
    input_path = settings.upload_dir / input_filename

    # Guardar archivo en disco
    async with aiofiles.open(input_path, "wb") as out_file:
        while chunk := await file.read(1024 * 1024):  # 1MB por chunk
            await out_file.write(chunk)

    # Crear registro en la base de datos
    task = StemTask(
        id=task_id,
        original_filename=file.filename,
        status="pending",
        progress=0
    )
    db.add(task)
    await db.commit()

    # Lanzar la separación en segundo plano
    background_tasks.add_task(DemucsService.process_audio, task_id, input_path, model)

    return {
        "task_id": task_id,
        "filename": file.filename,
        "status": "pending",
        "message": "Archivo recibido. Separación de pistas iniciada.",
        "ws_url": f"/ws/tasks/{task_id}"
    }

@router.get("/tasks/{task_id}")
async def get_stem_task(task_id: str, db: AsyncSession = Depends(get_db)):
    """
    Consulta el estado y los enlaces de streaming de una tarea de separación de stems.
    """
    task = await db.get(StemTask, task_id)
    if not task:
        raise HTTPException(status_code=404, detail="Tarea no encontrada")

    stems = json.loads(task.stems_json) if task.stems_json else {}

    return {
        "task_id": task.id,
        "filename": task.original_filename,
        "status": task.status,
        "progress": task.progress,
        "stems": stems,
        "error": task.error_message,
        "created_at": task.created_at.isoformat()
    }

@router.get("/tasks")
async def list_stem_tasks(limit: int = 20, db: AsyncSession = Depends(get_db)):
    """
    Lista las tareas recientes de separación de pistas.
    """
    query = select(StemTask).order_by(desc(StemTask.created_at)).limit(limit)
    result = await db.execute(query)
    tasks = result.scalars().all()

    return [
        {
            "task_id": t.id,
            "filename": t.original_filename,
            "status": t.status,
            "progress": t.progress,
            "stems": json.loads(t.stems_json) if t.stems_json else {},
            "created_at": t.created_at.isoformat()
        }
        for t in tasks
    ]

@router.delete("/tasks/{task_id}")
async def delete_stem_task(task_id: str, db: AsyncSession = Depends(get_db)):
    """
    Elimina una tarea de separación de pistas y borra sus archivos asociados de disco.
    """
    task = await db.get(StemTask, task_id)
    if not task:
        raise HTTPException(status_code=404, detail="Tarea no encontrada")

    # Borrar archivos de stems
    stems_folder = settings.stems_dir / task_id
    if stems_folder.exists():
        import shutil
        shutil.rmtree(stems_folder, ignore_errors=True)

    # Borrar archivo subido original
    for upload_file in settings.upload_dir.glob(f"{task_id}.*"):
        try:
            upload_file.unlink(missing_ok=True)
        except Exception:
            pass

    await db.delete(task)
    await db.commit()

    return {"message": "Canción y pistas eliminadas correctamente"}
