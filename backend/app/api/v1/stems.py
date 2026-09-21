import json
import uuid
import aiofiles
from fastapi import APIRouter, UploadFile, File, Form, Depends, HTTPException, Request
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, desc
from pydantic import BaseModel
from typing import Optional

from app.core.config import settings
from app.core.database import get_db
from app.core.security import require_api_token
from app.models.stem_task import StemTask
from app.services.demucs_service import PRESETS, DEFAULT_PRESET, get_preset
from app.services.stem_queue import stem_queue

router = APIRouter(prefix="/stems", tags=["Stems Separator"])

ALLOWED_EXTENSIONS = (".mp3", ".wav", ".flac", ".ogg", ".m4a")


@router.get("/presets")
async def list_presets():
    """Lista los presets de calidad disponibles para la separación de pistas."""
    return {
        "default": DEFAULT_PRESET,
        "presets": [
            {
                "key": key,
                "label": preset["label"],
                "description": preset["description"],
                "model": preset["model"],
                "format": preset["format"],
                "shifts": preset["shifts"],
                "overlap": preset["overlap"],
            }
            for key, preset in PRESETS.items()
        ],
    }


@router.post("/upload")
async def upload_audio_for_stems(
    file: UploadFile = File(...),
    collection_name: str = Form(""),
    preset: str = Form(""),
    db: AsyncSession = Depends(get_db),
    _: None = Depends(require_api_token),
):
    """
    Sube un archivo de audio y lo encola para separación de pistas.
    La separación se ejecuta de una en una (cola con worker único) para no degradar la calidad.
    """
    if not file.filename.lower().endswith(ALLOWED_EXTENSIONS):
        raise HTTPException(status_code=400, detail="Formato no soportado. Formatos válidos: MP3, WAV, FLAC, OGG, M4A")

    preset_key, _preset = get_preset(preset)

    # Comprobar espacio libre en disco antes de aceptar el archivo (mínimo 2 GB)
    try:
        import shutil as _shutil
        free_bytes = _shutil.disk_usage(settings.upload_dir).free
        if free_bytes < 2 * 1024 * 1024 * 1024:
            raise HTTPException(status_code=507, detail="Espacio insuficiente en el servidor (menos de 2 GB libres)")
    except HTTPException:
        raise
    except Exception:
        pass

    task_id = str(uuid.uuid4())
    ext = file.filename.split(".")[-1]
    input_filename = f"{task_id}.{ext}"
    input_path = settings.upload_dir / input_filename

    # Guardar archivo en disco con límite de tamaño (600 MB)
    max_bytes = 600 * 1024 * 1024
    written = 0
    async with aiofiles.open(input_path, "wb") as out_file:
        while chunk := await file.read(1024 * 1024):
            written += len(chunk)
            if written > max_bytes:
                await out_file.close()
                input_path.unlink(missing_ok=True)
                raise HTTPException(status_code=413, detail="Archivo demasiado grande (máximo 600 MB)")
            await out_file.write(chunk)

    task = StemTask(
        id=task_id,
        original_filename=file.filename,
        collection_name=collection_name.strip() if collection_name and collection_name.strip() else None,
        status="queued",
        progress=0,
        preset=preset_key,
    )
    db.add(task)
    await db.commit()

    position = stem_queue.enqueue(task_id, preset_key)

    return {
        "task_id": task_id,
        "filename": file.filename,
        "collection_name": task.collection_name,
        "preset": preset_key,
        "status": "queued",
        "queue_position": position,
        "message": "Archivo recibido. Separación en cola." if position > 1 else "Archivo recibido. Separación iniciada.",
        "ws_url": f"/ws/tasks/{task_id}",
    }


@router.post("/tasks/{task_id}/retry")
async def retry_stem_task(
    task_id: str,
    db: AsyncSession = Depends(get_db),
    _: None = Depends(require_api_token),
):
    """
    Reintenta una separación fallida o interrumpida reutilizando el audio ya subido.
    """
    task = await db.get(StemTask, task_id)
    if not task:
        raise HTTPException(status_code=404, detail="Tarea no encontrada")

    if task.status in ("processing", "queued"):
        raise HTTPException(status_code=409, detail="La tarea ya está en proceso")

    if not list(settings.upload_dir.glob(f"{task_id}.*")):
        raise HTTPException(status_code=404, detail="El audio original ya no está disponible en el servidor")

    task.status = "queued"
    task.progress = 0
    task.error_message = None
    await db.commit()

    position = stem_queue.enqueue(task_id, task.preset)
    return {"task_id": task_id, "status": "queued", "queue_position": position}


@router.get("/tasks/{task_id}")
async def get_stem_task(task_id: str, db: AsyncSession = Depends(get_db)):
    """
    Consulta el estado y los enlaces de streaming de una tarea de separación de stems.
    """
    task = await db.get(StemTask, task_id)
    if not task:
        raise HTTPException(status_code=404, detail="Tarea no encontrada")

    stems = json.loads(task.stems_json) if task.stems_json else {}

    response = {
        "task_id": task.id,
        "filename": task.original_filename,
        "collection_name": task.collection_name,
        "preset": task.preset,
        "status": task.status,
        "progress": task.progress,
        "stems": stems,
        "error": task.error_message,
        "created_at": task.created_at.isoformat(),
    }
    if task.status == "queued":
        response["queue_position"] = stem_queue.queued_position(task_id)
    return response


@router.get("/tasks")
async def list_stem_tasks(limit: int = 50, db: AsyncSession = Depends(get_db)):
    """
    Lista las tareas de separación de pistas, ordenadas por fecha reciente.
    """
    query = select(StemTask).order_by(desc(StemTask.created_at)).limit(limit)
    result = await db.execute(query)
    tasks = result.scalars().all()

    return [
        {
            "id": t.id,
            "task_id": t.id,
            "filename": t.original_filename,
            "collection_name": t.collection_name,
            "preset": t.preset,
            "status": t.status,
            "progress": t.progress,
            "queue_position": stem_queue.queued_position(t.id) if t.status == "queued" else None,
            "stems": json.loads(t.stems_json) if t.stems_json else {},
            "error": t.error_message,
            "created_at": t.created_at.isoformat(),
        }
        for t in tasks
    ]


class CollectionUpdate(BaseModel):
    collection_name: Optional[str] = None


@router.patch("/tasks/{task_id}/collection")
async def update_task_collection(
    task_id: str,
    body: CollectionUpdate,
    db: AsyncSession = Depends(get_db),
    _: None = Depends(require_api_token),
):
    """
    Asigna o cambia la colección/grupo de una canción.
    """
    task = await db.get(StemTask, task_id)
    if not task:
        raise HTTPException(status_code=404, detail="Tarea no encontrada")

    task.collection_name = body.collection_name.strip() if body.collection_name and body.collection_name.strip() else None
    await db.commit()

    return {"task_id": task_id, "collection_name": task.collection_name}


@router.get("/collections")
async def list_collections(db: AsyncSession = Depends(get_db)):
    """
    Devuelve la lista de nombres de colecciones distintos que tienen canciones completadas.
    """
    query = select(StemTask.collection_name).where(
        StemTask.collection_name != None,
        StemTask.status == "completed"
    ).distinct()
    result = await db.execute(query)
    names = [r[0] for r in result.fetchall() if r[0]]
    return {"collections": sorted(names)}


@router.delete("/tasks/{task_id}")
async def delete_stem_task(
    task_id: str,
    db: AsyncSession = Depends(get_db),
    _: None = Depends(require_api_token),
):
    """
    Elimina una tarea de separación de pistas y borra sus archivos asociados de disco.
    """
    task = await db.get(StemTask, task_id)
    if not task:
        raise HTTPException(status_code=404, detail="Tarea no encontrada")

    stems_folder = settings.stems_dir / task_id
    if stems_folder.exists():
        import shutil
        shutil.rmtree(stems_folder, ignore_errors=True)

    for upload_file in settings.upload_dir.glob(f"{task_id}.*"):
        try:
            upload_file.unlink(missing_ok=True)
        except Exception:
            pass

    await db.delete(task)
    await db.commit()

    return {"message": "Canción y pistas eliminadas correctamente"}
