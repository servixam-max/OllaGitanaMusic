import base64
import time
from typing import List, Dict, Any, Optional
import httpx
from app.core.config import settings

class SpotifyService:
    """
    Servicio universal de búsqueda musical.
    Prioriza Spotify si existen credenciales y recurre de forma transparente a
    Deezer e iTunes Search API para garantizar carátulas HD y previews de 30s reales
    sin necesidad de configurar claves ni cuentas de desarrollador.
    """
    _access_token: Optional[str] = None
    _token_expires_at: float = 0.0

    @classmethod
    async def _get_spotify_token(cls) -> Optional[str]:
        if not settings.SPOTIFY_CLIENT_ID or not settings.SPOTIFY_CLIENT_SECRET:
            return None

        if cls._access_token and time.time() < cls._token_expires_at - 60:
            return cls._access_token

        auth_str = f"{settings.SPOTIFY_CLIENT_ID}:{settings.SPOTIFY_CLIENT_SECRET}"
        b64_auth = base64.b64encode(auth_str.encode()).decode()

        headers = {
            "Authorization": f"Basic {b64_auth}",
            "Content-Type": "application/x-www-form-urlencoded"
        }
        data = {"grant_type": "client_credentials"}

        async with httpx.AsyncClient(timeout=10.0) as client:
            try:
                resp = await client.post("https://accounts.spotify.com/api/token", headers=headers, data=data)
                if resp.status_code == 200:
                    payload = resp.json()
                    cls._access_token = payload.get("access_token")
                    expires_in = payload.get("expires_in", 3600)
                    cls._token_expires_at = time.time() + expires_in
                    return cls._access_token
            except Exception as e:
                print(f"[MusicService] Error autenticando en Spotify: {e}")
        return None

    @classmethod
    async def search_tracks(cls, query: str, limit: int = 15) -> List[Dict[str, Any]]:
        # 1. Intentar Spotify si hay credenciales
        token = await cls._get_spotify_token()
        if token:
            spotify_results = await cls._search_spotify(query, token, limit)
            if spotify_results:
                return spotify_results

        # 2. Fallback primario: Deezer API (Pública, sin keys, carátulas HD y previews de 30s en MP3)
        deezer_results = await cls._search_deezer(query, limit)
        if deezer_results:
            return deezer_results

        # 3. Fallback secundario: iTunes Search API (Pública, sin keys)
        return await cls._search_itunes(query, limit)

    @classmethod
    async def _search_spotify(cls, query: str, token: str, limit: int) -> List[Dict[str, Any]]:
        headers = {"Authorization": f"Bearer {token}"}
        params = {"q": query, "type": "track", "limit": limit}

        async with httpx.AsyncClient(timeout=10.0) as client:
            try:
                resp = await client.get("https://api.spotify.com/v1/search", headers=headers, params=params)
                if resp.status_code == 200:
                    data = resp.json()
                    tracks = []
                    for item in data.get("tracks", {}).get("items", []):
                        images = item.get("album", {}).get("images", [])
                        cover_url = images[0]["url"] if images else None
                        artists = ", ".join(a["name"] for a in item.get("artists", []))
                        tracks.append({
                            "spotify_id": item.get("id"),
                            "title": item.get("name"),
                            "artist": artists,
                            "album": item.get("album", {}).get("name"),
                            "cover_url": cover_url,
                            "preview_url": item.get("preview_url"),
                            "duration_ms": item.get("duration_ms", 0),
                            "source": "Spotify"
                        })
                    return tracks
            except Exception as e:
                print(f"[MusicService] Error en Spotify search: {e}")
        return []

    @classmethod
    async def _search_deezer(cls, query: str, limit: int) -> List[Dict[str, Any]]:
        url = "https://api.deezer.com/search"
        params = {"q": query, "limit": limit}

        async with httpx.AsyncClient(timeout=10.0) as client:
            try:
                resp = await client.get(url, params=params)
                if resp.status_code == 200:
                    data = resp.json().get("data", [])
                    results = []
                    for item in data:
                        album = item.get("album", {})
                        artist = item.get("artist", {})
                        results.append({
                            "spotify_id": f"deezer_{item.get('id')}",
                            "title": item.get("title"),
                            "artist": artist.get("name", "Desconocido"),
                            "album": album.get("title"),
                            "cover_url": album.get("cover_xl") or album.get("cover_big") or album.get("cover_medium"),
                            "preview_url": item.get("preview"),  # Snippet 30s MP3 real
                            "duration_ms": item.get("duration", 0) * 1000,
                            "source": "Deezer"
                        })
                    return results
            except Exception as e:
                print(f"[MusicService] Error buscando en Deezer: {e}")
        return []

    @classmethod
    async def _search_itunes(cls, query: str, limit: int) -> List[Dict[str, Any]]:
        url = "https://itunes.apple.com/search"
        params = {"term": query, "entity": "song", "limit": limit}

        async with httpx.AsyncClient(timeout=10.0) as client:
            try:
                resp = await client.get(url, params=params)
                if resp.status_code == 200:
                    data = resp.json().get("results", [])
                    results = []
                    for item in data:
                        cover = item.get("artworkUrl100", "")
                        # Obtener carátula en alta resolución 600x600
                        if cover:
                            cover = cover.replace("100x100bb.jpg", "600x600bb.jpg")
                        results.append({
                            "spotify_id": f"itunes_{item.get('trackId')}",
                            "title": item.get("trackName"),
                            "artist": item.get("artistName"),
                            "album": item.get("collectionName"),
                            "cover_url": cover,
                            "preview_url": item.get("previewUrl"),
                            "duration_ms": item.get("trackTimeMillis", 0),
                            "source": "iTunes"
                        })
                    return results
            except Exception as e:
                print(f"[MusicService] Error buscando en iTunes: {e}")
        return []
