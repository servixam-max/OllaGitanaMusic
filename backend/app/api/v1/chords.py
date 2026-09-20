from typing import Optional
from pathlib import Path
import json
import aiofiles
import uuid
from fastapi import APIRouter, Query, UploadFile, File, Form, HTTPException, Depends
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, desc

from app.core.config import settings
from app.core.database import get_db
from app.models.stem_task import StemTask
from app.models.analyzed_song import AnalyzedSong
from app.services.chord_service import ChordService

router = APIRouter(prefix="/chords", tags=["Chords"])

@router.get("/search")
async def search_chords(query: str = Query(..., description="Canción o artista a buscar")):
    """
    Busca tablaturas y cifrados de acordes en repositorios públicos (Songsterr).
    """
    results = await ChordService.search_chords(query)
    return {"results": results, "count": len(results)}

@router.get("/history")
async def get_chord_history(db: AsyncSession = Depends(get_db)):
    """
    Obtiene el listado de canciones analizadas armónicamente para recuperarlas sin volver a procesar.
    """
    query = select(AnalyzedSong).order_by(desc(AnalyzedSong.created_at)).limit(30)
    result = await db.execute(query)
    songs = result.scalars().all()
    return [
        {
            "id": s.id,
            "filename": s.filename,
            "audio_url": s.audio_url,
            "estimated_key": s.estimated_key,
            "duration": s.duration,
            "timeline": json.loads(s.timeline_json) if s.timeline_json else [],
            "created_at": s.created_at.isoformat() if s.created_at else None
        }
        for s in songs
    ]

@router.delete("/history/{id}")
async def delete_chord_analysis(id: str, db: AsyncSession = Depends(get_db)):
    """
    Elimina una canción analizada de la biblioteca.
    """
    song = await db.get(AnalyzedSong, id)
    if not song:
        raise HTTPException(status_code=404, detail="Análisis no encontrado")

    if song.audio_url and "chord_" in song.audio_url:
        filename = song.audio_url.split("/")[-1]
        target_file = settings.upload_dir / filename
        if target_file.exists():
            try:
                target_file.unlink(missing_ok=True)
            except Exception:
                pass

    await db.delete(song)
    await db.commit()
    return {"message": "Canción analizada eliminada correctamente"}

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
    original_name = "Audio Analizado"

    if task_id:
        task = await db.get(StemTask, task_id)
        if not task:
            raise HTTPException(status_code=404, detail="Tarea de audio no encontrada")
        candidates = list(settings.upload_dir.glob(f"{task_id}.*"))
        if not candidates:
            raise HTTPException(status_code=404, detail="Archivo de audio original no encontrado en el servidor")
        audio_path = candidates[0]
        original_name = task.original_filename
    elif file:
        if not file.filename.lower().endswith((".mp3", ".wav", ".flac", ".ogg", ".m4a")):
            raise HTTPException(status_code=400, detail="Formato de audio no compatible")
        
        tmp_id = str(uuid.uuid4())
        ext = file.filename.split(".")[-1]
        audio_path = settings.upload_dir / f"chord_{tmp_id}.{ext}"
        original_name = file.filename
        
        async with aiofiles.open(audio_path, "wb") as out_file:
            while chunk := await file.read(1024 * 1024):
                await out_file.write(chunk)
    else:
        raise HTTPException(status_code=400, detail="Debe proporcionar un archivo de audio o un task_id existente")

    analysis = ChordService.extract_chords_from_audio(audio_path)

    # Persistir en la base de datos para historial y reproductor sincronizado
    audio_url = f"/static/uploads/{audio_path.name}"
    analyzed = AnalyzedSong(
        filename=original_name,
        audio_url=audio_url,
        estimated_key=analysis.get("estimated_key", "N/A"),
        duration=analysis.get("duration", 0.0),
        timeline_json=json.dumps(analysis.get("timeline", []))
    )
    db.add(analyzed)
    await db.commit()
    await db.refresh(analyzed)

    analysis["id"] = analyzed.id
    analysis["filename"] = analyzed.filename
    analysis["audio_url"] = analyzed.audio_url
    return analysis
