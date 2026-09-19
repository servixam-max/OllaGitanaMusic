from typing import List, Optional
from pydantic import BaseModel, Field
from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, desc
from sqlalchemy.orm import selectinload

from app.core.database import get_db
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
    rating: int = Field(..., ge=1, le=5)

def format_song(song: SongProposal) -> dict:
    return {
        "id": song.id,
        "title": song.title,
        "artist": song.artist,
        "album": song.album,
        "cover_url": song.cover_url,
        "preview_url": song.preview_url,
        "spotify_id": song.spotify_id,
        "status": song.status,
        "proposed_by": song.proposed_by,
        "notes": song.notes,
        "average_rating": round(song.average_rating, 2),
        "total_votes": song.total_votes,
        "votes": [
            {"id": v.id, "user_name": v.user_name, "rating": v.rating}
            for v in song.votes
        ],
        "created_at": song.created_at.isoformat()
    }

@router.get("/spotify/search")
async def search_spotify(query: str = Query(..., description="Búsqueda en catálogo de Spotify")):
    """
    Busca temas en Spotify para autocompletar carátula y reproducir preview de 30s.
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
    
    # Ordenar por valoración media descendente
    sorted_songs = sorted(songs, key=lambda s: (s.average_rating, s.total_votes), reverse=True)
    return [format_song(s) for s in sorted_songs]

@router.post("/songs")
async def create_song_proposal(payload: SongCreateSchema, db: AsyncSession = Depends(get_db)):
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

    data = format_song(song)
    await ws_manager.broadcast_repertoire_event("song_added", data)
    return data

@router.patch("/songs/{song_id}/status")
async def update_song_status(
    song_id: int,
    payload: StatusUpdateSchema,
    db: AsyncSession = Depends(get_db)
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
    db: AsyncSession = Depends(get_db)
):
    """
    Emite o actualiza el voto de un integrante para una canción (1 a 5 estrellas).
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
        vote.rating = payload.rating
    else:
        vote = SongVote(song_id=song_id, user_name=payload.user_name, rating=payload.rating)
        db.add(vote)

    await db.commit()
    await db.refresh(song)

    data = format_song(song)
    await ws_manager.broadcast_repertoire_event("vote_updated", data)
    return data

@router.delete("/songs/{song_id}")
async def delete_song(song_id: int, db: AsyncSession = Depends(get_db)):
    """
    Elimina una propuesta del repertorio.
    """
    song = await db.get(SongProposal, song_id)
    if not song:
        raise HTTPException(status_code=404, detail="Canción no encontrada")

    await db.delete(song)
    await db.commit()

    await ws_manager.broadcast_repertoire_event("song_deleted", {"id": song_id})
    return {"message": "Canción eliminada exitosamente", "id": song_id}
