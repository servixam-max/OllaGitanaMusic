import base64
import time
from typing import List, Dict, Any, Optional
import httpx
from app.core.config import settings

class SpotifyService:
    _access_token: Optional[str] = None
    _token_expires_at: float = 0.0

    @classmethod
    async def _get_access_token(cls) -> Optional[str]:
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
                else:
                    print(f"[SpotifyService] Error obteniendo token: {resp.status_code} {resp.text}")
                    return None
            except Exception as e:
                print(f"[SpotifyService] Excepción al autenticar en Spotify: {e}")
                return None

    @classmethod
    async def search_tracks(cls, query: str, limit: int = 15) -> List[Dict[str, Any]]:
        """
        Busca temas en Spotify y devuelve título, artista, carátula y URL del preview de 30 segundos.
        """
        token = await cls._get_access_token()
        if not token:
            # Modo fallback si no hay credenciales de Spotify configuradas
            return [
                {
                    "spotify_id": f"demo_{i}",
                    "title": f"Tema '{query}' #{i+1}",
                    "artist": "Olla Gitana",
                    "album": "Ensayo Directo",
                    "cover_url": "https://images.unsplash.com/photo-1511671782779-c97d3d27a1d4?w=500&q=80",
                    "preview_url": "https://www.soundhelix.com/examples/mp3/SoundHelix-Song-1.mp3",
                    "duration_ms": 180000,
                    "is_demo": True
                }
                for i in range(3)
            ]

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
                            "is_demo": False
                        })
                    return tracks
                return []
            except Exception as e:
                print(f"[SpotifyService] Error buscando canciones en Spotify: {e}")
                return []
