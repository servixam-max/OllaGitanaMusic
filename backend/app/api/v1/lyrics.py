from typing import Optional
from fastapi import APIRouter, HTTPException, Query
from app.services.lyrics_service import LyricsService

router = APIRouter(prefix="/lyrics", tags=["Lyrics"])

@router.get("/get")
async def get_lyrics(
    track_name: str = Query(..., description="Título de la canción"),
    artist_name: str = Query(..., description="Nombre del artista")
):
    lyrics = await LyricsService.get_lyrics(track_name=track_name, artist_name=artist_name)
    if not lyrics:
        raise HTTPException(status_code=404, detail="Letra no encontrada en LRCLIB")
    return lyrics

@router.get("/search")
async def search_lyrics(q: str = Query(..., description="Búsqueda por título o artista")):
    results = await LyricsService.search_lyrics(query=q)
    return {"results": results, "count": len(results)}
