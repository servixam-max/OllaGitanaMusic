from typing import Optional
from pathlib import Path
import aiofiles
import uuid
from fastapi import APIRouter, Query, UploadFile, File, Form, HTTPException, Depends
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.config import settings
from app.core.database import get_db
from app.models.stem_task import StemTask
from app.services.chord_service import ChordService

router = APIRouter(prefix="/chords", tags=["Chords"])

@router.get("/search")
async def search_chords(query: str = Query(..., description="Canción o artista a buscar")):
    """
    Busca tablaturas y cifrados de acordes en repositorios públicos (Songsterr).
    """
    results = await ChordService.search_chords(query)
    return {"results": results, "count": len(results)}

@router.post("/extract")
async def extract_chords(
    file: Optional[UploadFile] = File(None),
    task_id: Optional[str] = Form(None),
    db: AsyncSession = Depends(get_db)
):
    """
    Extrae la tonalidad y secuencia temporal de acordes mediante análisis armónico con librosa.
    Puede recibir un archivo nuevo o el task_id de un audio ya subido.
    """
    audio_path: Optional[Path] = None

    if task_id:
        task = await db.get(StemTask, task_id)
        if not task:
            raise HTTPException(status_code=404, detail="Tarea de audio no encontrada")
        # Buscar el archivo original subido
        candidates = list(settings.upload_dir.glob(f"{task_id}.*"))
        if not candidates:
            raise HTTPException(status_code=404, detail="Archivo de audio original no encontrado en el servidor")
        audio_path = candidates[0]
    elif file:
        if not file.filename.lower().endswith((".mp3", ".wav", ".flac", ".ogg", ".m4a")):
            raise HTTPException(status_code=400, detail="Formato de audio no compatible")
        
        tmp_id = str(uuid.uuid4())
        ext = file.filename.split(".")[-1]
        audio_path = settings.upload_dir / f"chord_{tmp_id}.{ext}"
        
        async with aiofiles.open(audio_path, "wb") as out_file:
            while chunk := await file.read(1024 * 1024):
                await out_file.write(chunk)
    else:
        raise HTTPException(status_code=400, detail="Debe proporcionar un archivo de audio o un task_id existente")

    analysis = ChordService.extract_chords_from_audio(audio_path)
    return analysis
