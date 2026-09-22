import aiofiles
import httpx
from typing import List, Optional
from pydantic import BaseModel, Field
from fastapi import APIRouter, Depends, HTTPException, Query, BackgroundTasks
from fastapi.responses import FileResponse, RedirectResponse
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, desc
from sqlalchemy.orm import selectinload

from app.core.config import settings
from app.core.database import get_db
from app.core.security import require_api_token
from app.models.repertoire import SongProposal, SongVote
from app.services.spotify_service import SpotifyService
from app.services.ws_manager import ws_manager

router = APIRouter(prefix="/repertoire", tags=["Repertoire & Collaboration"])

# Schemas Pydantic
class SongCreateSchema(BaseModel):
    title: str = Field(..., examples=["Entre dos aguas"])
    artist: str = Field(..., examples=["Paco de Lucía"])
    album: Optional[str] = None
    cover_url: Optional[str] = None
    preview_url: Optional[str] = None
    spotify_id: Optional[str] = None
    proposed_by: str = Field(default="Miembro Olla Gitana")
    notes: Optional[str] = None

class StatusUpdateSchema(BaseModel):
    status: str = Field(..., pattern="^(propuesta|para_ensayar|en_repertorio|descartada)$")

class VoteCreateSchema(BaseModel):
    user_name: str = Field(..., examples=["Carlos (Guitarra)"])
    liked: bool = Field(..., description="True = me gusta (Sí), False = no me gusta (No)")

def format_song(song: SongProposal) -> dict:
    preview = f"/api/v1/repertoire/songs/{song.id}/preview" if (song.preview_url or song.spotify_id) else None
    return {
        "id": song.id,
        "title": song.title,
        "artist": song.artist,
        "album": song.album,
        "cover_url": song.cover_url,
        "preview_url": preview,
        "spotify_id": song.spotify_id,
        "status": song.status,
        "proposed_by": song.proposed_by,
        "notes": song.notes,
        "yes_votes": song.yes_votes,
        "no_votes": song.no_votes,
        "total_votes": song.total_votes,
        # Retrocompatibilidad
        "average_rating": 0.0,
        "votes": [
            {"id": v.id, "user_name": v.user_name, "liked": v.liked}
            for v in song.votes
        ],
        "created_at": song.created_at.isoformat()
    }

async def cache_preview_task(song_id: int, spotify_id: Optional[str], title: str, artist: str, direct_url: Optional[str]):
    """Descarga en background el snippet de 30s de la canción para tenerlo en disco para siempre."""
    preview_file = settings.previews_dir / f"{song_id}.mp3"
    if preview_file.exists() and preview_file.stat().st_size > 1000:
        return

    url = direct_url or await SpotifyService.get_fresh_preview_url(spotify_id, title, artist)
    if url:
        try:
            async with httpx.AsyncClient(timeout=15.0, follow_redirects=True) as client:
                resp = await client.get(url)
                if resp.status_code == 200 and len(resp.content) > 1000:
                    async with aiofiles.open(preview_file, "wb") as f:
                        await f.write(resp.content)
                    print(f"[Repertoire] Preview cacheado con éxito en disco para song_id={song_id}")
        except Exception as e:
            print(f"[Repertoire] Error cacheando preview para {song_id}: {e}")

@router.get("/spotify/search")
async def search_spotify(query: str = Query(..., description="Búsqueda en catálogo de Spotify/Deezer/iTunes")):
    """
    Busca temas para autocompletar carátula y reproducir preview de 30s.
    """
    results = await SpotifyService.search_tracks(query)
    return {"results": results, "count": len(results)}

@router.get("/songs")
async def get_songs(
    status: Optional[str] = Query(None, description="Filtrar por estado"),
    db: AsyncSession = Depends(get_db)
):
    """
    Obtiene la lista de temas propuestos, ordenados por puntuación media y fecha.
    """
    query = select(SongProposal).options(selectinload(SongProposal.votes))
    if status:
        query = query.filter(SongProposal.status == status)
    
    result = await db.execute(query)
    songs = result.scalars().all()
    
    # Ordenar por consenso: más votos SÍ y menos votos NO primero
    sorted_songs = sorted(
        songs,
        key=lambda s: (s.yes_votes - s.no_votes, s.yes_votes),
        reverse=True,
    )
    return [format_song(s) for s in sorted_songs]

@router.get("/songs/{song_id}/preview")
@router.head("/songs/{song_id}/preview")
async def get_song_preview(song_id: int, db: AsyncSession = Depends(get_db)):
    """
    Sirve el snippet de 30s de la canción.
    Si ya está cacheado localmente en backend/data/previews/{song_id}.mp3, lo devuelve directamente.
    Si no, obtiene una URL fresca, lo descarga y almacena en disco para siempre, y lo sirve.
    """
    preview_file = settings.previews_dir / f"{song_id}.mp3"
    
    # 1. Si ya existe en caché local
    if preview_file.exists() and preview_file.stat().st_size > 1000:
        return FileResponse(
            path=preview_file,
            media_type="audio/mpeg",
            filename=f"preview_{song_id}.mp3"
        )
    
    # 2. Buscar datos de la canción en DB
    song = await db.get(SongProposal, song_id)
    if not song:
        raise HTTPException(status_code=404, detail="Canción no encontrada")
    
    fresh_url = await SpotifyService.get_fresh_preview_url(
        spotify_id=song.spotify_id,
        title=song.title,
        artist=song.artist
    )
    
    if not fresh_url:
        raise HTTPException(status_code=404, detail="No hay preview de audio disponible para este tema")
    
    # 3. Descargar y guardar en disco
    try:
        async with httpx.AsyncClient(timeout=15.0, follow_redirects=True) as client:
            resp = await client.get(fresh_url)
            if resp.status_code == 200 and len(resp.content) > 1000:
                async with aiofiles.open(preview_file, "wb") as f:
                    await f.write(resp.content)
                
                return FileResponse(
                    path=preview_file,
                    media_type="audio/mpeg",
                    filename=f"preview_{song_id}.mp3"
                )
    except Exception as e:
        print(f"[Repertoire] Error descargando preview para {song_id}: {e}")
    
    # Si la descarga falló pero tenemos fresh_url, redirigir
    return RedirectResponse(url=fresh_url)

@router.post("/songs")
async def create_song_proposal(
    payload: SongCreateSchema,
    background_tasks: BackgroundTasks,
    db: AsyncSession = Depends(get_db),
    _: None = Depends(require_api_token),
):
    """
    Propone una nueva canción para el repertorio de Olla Gitana.
    """
    song = SongProposal(
        title=payload.title,
        artist=payload.artist,
        album=payload.album,
        cover_url=payload.cover_url,
        preview_url=payload.preview_url,
        spotify_id=payload.spotify_id,
        proposed_by=payload.proposed_by,
        notes=payload.notes,
        status="propuesta"
    )
    db.add(song)
    await db.commit()
    await db.refresh(song)

    # Iniciar descarga y almacenamiento en background para que el snippet no caduque jamás
    background_tasks.add_task(
        cache_preview_task,
        song.id,
        song.spotify_id,
        song.title,
        song.artist,
        payload.preview_url
    )

    data = format_song(song)
    await ws_manager.broadcast_repertoire_event("song_added", data)
    return data

@router.patch("/songs/{song_id}/status")
async def update_song_status(
    song_id: int,
    payload: StatusUpdateSchema,
    db: AsyncSession = Depends(get_db),
    _: None = Depends(require_api_token),
):
    """
    Actualiza el estado de un tema ("propuesta", "para_ensayar", "en_repertorio", "descartada").
    """
    song = await db.get(SongProposal, song_id, options=[selectinload(SongProposal.votes)])
    if not song:
        raise HTTPException(status_code=404, detail="Canción no encontrada")

    song.status = payload.status
    await db.commit()
    await db.refresh(song)

    data = format_song(song)
    await ws_manager.broadcast_repertoire_event("status_changed", data)
    return data

@router.post("/songs/{song_id}/vote")
async def vote_song(
    song_id: int,
    payload: VoteCreateSchema,
    db: AsyncSession = Depends(get_db),
    _: None = Depends(require_api_token),
):
    """
    Registra o actualiza el voto (Sí/No) de un integrante para una canción.
    Cada músico puede votar una sola vez; votar de nuevo actualiza su voto previo.
    """
    song = await db.get(SongProposal, song_id, options=[selectinload(SongProposal.votes)])
    if not song:
        raise HTTPException(status_code=404, detail="Canción no encontrada")

    # Verificar si el usuario ya votó para actualizar su voto
    vote = None
    for v in song.votes:
        if v.user_name.lower() == payload.user_name.lower():
            vote = v
            break

    if vote:
        vote.liked = payload.liked
        # Compatibilidad con bases de datos antiguas donde 'rating' era NOT NULL
        vote.rating = 5 if payload.liked else 1
    else:
        vote = SongVote(
            song_id=song_id,
            user_name=payload.user_name,
            liked=payload.liked,
            # Compatibilidad con bases de datos antiguas donde 'rating' era NOT NULL
            rating=5 if payload.liked else 1,
        )
        db.add(vote)

    await db.commit()
    await db.refresh(song)

    data = format_song(song)
    await ws_manager.broadcast_repertoire_event("vote_updated", data)
    return data

@router.delete("/songs/{song_id}")
async def delete_song(
    song_id: int,
    db: AsyncSession = Depends(get_db),
    _: None = Depends(require_api_token),
):
    """
    Elimina una propuesta del repertorio.
    """
    song = await db.get(SongProposal, song_id)
    if not song:
        raise HTTPException(status_code=404, detail="Canción no encontrada")

    # Eliminar preview en disco si existe
    preview_file = settings.previews_dir / f"{song_id}.mp3"
    try:
        preview_file.unlink(missing_ok=True)
    except Exception:
        pass

    await db.delete(song)
    await db.commit()

    await ws_manager.broadcast_repertoire_event("song_deleted", {"id": song_id})
    return {"message": "Canción eliminada exitosamente", "id": song_id}
