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
from app.core.security import require_api_token
from app.models.stem_task import StemTask
from app.models.analyzed_song import AnalyzedSong
from app.services.chord_service import ChordService

router = APIRouter(prefix="/chords", tags=["Chords"])


def _song_payload(song: AnalyzedSong, include_timeline: bool = True) -> dict:
    """Payload de una canción analizada con su estado de tono (bajado/subido)."""
    payload = {
        "id": song.id,
        "filename": song.filename,
        "audio_url": song.audio_url,
        "estimated_key": song.estimated_key,
        "duration": song.duration,
        "transpose_semitones": song.transpose_semitones or 0,
        "transposed_audio_url": song.transposed_audio_url,
        "play_url": song.transposed_audio_url or song.audio_url,
        "created_at": song.created_at.isoformat() if song.created_at else None,
    }
    if include_timeline:
        timeline = json.loads(song.timeline_json) if song.timeline_json else []
        payload["timeline"] = timeline
        unique: list = []
        for seg in timeline:
            chord = seg.get("chord")
            if chord and chord not in unique:
                unique.append(chord)
        payload["unique_chords"] = unique
    return payload


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
    return [_song_payload(s) for s in songs]


@router.delete("/history/{id}")
async def delete_chord_analysis(
    id: str,
    db: AsyncSession = Depends(get_db),
    _: None = Depends(require_api_token),
):
    """
    Elimina una canción analizada de la biblioteca (incluida su versión transpuesta).
    """
    song = await db.get(AnalyzedSong, id)
    if not song:
        raise HTTPException(status_code=404, detail="Análisis no encontrado")

    for url_field in (song.transposed_audio_url, song.audio_url):
        if url_field and ("chord_" in url_field or "chord_t" in url_field):
            filename = url_field.split("/")[-1]
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
    db: AsyncSession = Depends(get_db),
    _: None = Depends(require_api_token),
):
    """
    Extrae la tonalidad y la secuencia temporal de acordes mediante análisis armónico con librosa.
    Motor v2: corrección de afinación, vocabulario diatónico y cifrado simplificado (segmentos >= 1 s).
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

    if analysis.get("error"):
        # No persistir análisis fallidos ni inventar resultados
        return {
            "error": analysis.get("error"),
            "timeline": [],
            "estimated_key": "N/A",
            "duration": analysis.get("duration", 0.0),
        }

    # Persistir en la base de datos para historial y reproductor sincronizado
    audio_url = f"/static/uploads/{audio_path.name}"
    analyzed = AnalyzedSong(
        filename=original_name,
        audio_url=audio_url,
        estimated_key=analysis.get("estimated_key", "N/A"),
        duration=analysis.get("duration", 0.0),
        timeline_json=json.dumps(analysis.get("timeline", [])),
    )
    db.add(analyzed)
    await db.commit()
    await db.refresh(analyzed)

    analysis["id"] = analyzed.id
    analysis["filename"] = analyzed.filename
    analysis["audio_url"] = analyzed.audio_url
    # La versión que suena es siempre la original al analizar (sin transponer)
    analysis["transpose_semitones"] = 0
    analysis["transposed_audio_url"] = None
    analysis["play_url"] = analyzed.audio_url
    return analysis


@router.post("/reanalyze/{id}")
async def reanalyze_song(
    id: str,
    db: AsyncSession = Depends(get_db),
    _: None = Depends(require_api_token),
):
    """
    Re-analiza con el motor actual una canción antigua de la biblioteca
    (útil para canciones guardadas con el detector v1: cifrado simplificado v2).
    """
    song = await db.get(AnalyzedSong, id)
    if not song:
        raise HTTPException(status_code=404, detail="Análisis no encontrado")

    source_url = song.transposed_audio_url or song.audio_url
    if not source_url:
        raise HTTPException(status_code=400, detail="Esta canción no tiene audio asociado")
    source_path = settings.upload_dir / source_url.split("/")[-1]
    if not source_path.exists():
        raise HTTPException(status_code=404, detail="El archivo de audio ya no está en el servidor")

    # Re-analizar SIEMPRE sobre el audio original (la transposición no cambia las posiciones)
    original_path = settings.upload_dir / song.audio_url.split("/")[-1]
    analysis = ChordService.extract_chords_from_audio(original_path if original_path.exists() else source_path)
    if analysis.get("error"):
        raise HTTPException(status_code=500, detail=f"No se pudo re-analizar: {analysis['error']}")

    song.estimated_key = analysis.get("estimated_key", "N/A")
    song.duration = analysis.get("duration", song.duration)
    song.timeline_json = json.dumps(analysis.get("timeline", []))
    await db.commit()
    await db.refresh(song)

    return {
        **_song_payload(song),
        "tempo": analysis.get("tempo"),
        "engine": analysis.get("engine"),
        "tuning_offset": analysis.get("tuning_offset"),
        "play_url": song.transposed_audio_url or song.audio_url,
    }


@router.post("/transpose/{id}")
async def transpose_analysis(
    id: str,
    semitones: int = Query(..., ge=-6, le=6, description="Semitonos a bajar (negativo) o subir (positivo)"),
    db: AsyncSession = Depends(get_db),
    _: None = Depends(require_api_token),
):
    """
    Opción "bajar el tono": transpone a otra tonalidad una canción YA analizada,
    sin cambiar su duración ni su tempo. El cifrado NO se modifica (sigue siendo
    tocable con las mismas posiciones); si se quiere cifrado en la nueva tonalidad,
    el cliente lo transporta sumando los mismos semitonos.
    """
    song = await db.get(AnalyzedSong, id)
    if not song:
        raise HTTPException(status_code=404, detail="Análisis no encontrado")

    source_url = song.audio_url
    if not source_url:
        raise HTTPException(status_code=400, detail="Esta canción no tiene audio asociado")

    source_filename = source_url.split("/")[-1]
    source_path = settings.upload_dir / source_filename
    if not source_path.exists():
        raise HTTPException(status_code=404, detail="El archivo de audio original ya no está en el servidor")

    if semitones == 0:
        # Volver al original: se descarta la versión transpuesta
        if song.transposed_audio_url:
            old = settings.upload_dir / song.transposed_audio_url.split("/")[-1]
            try:
                old.unlink(missing_ok=True)
            except Exception:
                pass
        song.transpose_semitones = 0
        song.transposed_audio_url = None
        await db.commit()
        await db.refresh(song)
        return {**_song_payload(song), "play_url": song.audio_url}

    out_name = f"chord_t{semitones:+d}_{source_path.stem}.mp3"
    out_path = settings.upload_dir / out_name

    try:
        await ChordService.transpose_audio_file(source_path, semitones, out_path)
    except Exception as e:
        print(f"[Chords] Error transponiendo: {e}")
        raise HTTPException(status_code=500, detail=f"No se pudo cambiar el tono: {e}")

    song.transpose_semitones = semitones
    # Limpiar la versión transpuesta anterior si ya no se usa
    if song.transposed_audio_url and song.transposed_audio_url != f"/static/uploads/{out_name}":
        old = settings.upload_dir / song.transposed_audio_url.split("/")[-1]
        try:
            old.unlink(missing_ok=True)
        except Exception:
            pass
    song.transposed_audio_url = f"/static/uploads/{out_name}"
    await db.commit()
    await db.refresh(song)

    return {**_song_payload(song), "play_url": song.transposed_audio_url}
