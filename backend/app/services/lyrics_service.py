import re
from typing import Dict, Any, List, Optional
import httpx

LRCLIB_BASE_URL = "https://lrclib.net/api"

class LyricsService:
    @staticmethod
    def parse_lrc_synced_lyrics(lrc_text: Optional[str]) -> List[Dict[str, Any]]:
        """
        Parsea letra en formato LRC [mm:ss.xx] texto en una lista estructurada con tiempos en milisegundos.
        """
        if not lrc_text:
            return []
        
        parsed = []
        pattern = re.compile(r"\[(\d+):(\d+(?:\.\d+)?)\](.*)")
        for line in lrc_text.splitlines():
            line = line.strip()
            match = pattern.match(line)
            if match:
                minutes = int(match.group(1))
                seconds = float(match.group(2))
                time_ms = int((minutes * 60 + seconds) * 1000)
                text = match.group(3).strip()
                parsed.append({"time_ms": time_ms, "text": text})
        return parsed

    @classmethod
    async def get_lyrics(cls, track_name: str, artist_name: str) -> Optional[Dict[str, Any]]:
        """
        Obtiene la letra exacta desde LRCLIB dado el título y artista.
        """
        params = {
            "track_name": track_name,
            "artist_name": artist_name
        }
        async with httpx.AsyncClient(timeout=10.0) as client:
            try:
                response = await client.get(f"{LRCLIB_BASE_URL}/get", params=params)
                if response.status_code == 200:
                    data = response.json()
                    return {
                        "id": data.get("id"),
                        "track_name": data.get("trackName"),
                        "artist_name": data.get("artistName"),
                        "album_name": data.get("albumName"),
                        "duration": data.get("duration"),
                        "plain_lyrics": data.get("plainLyrics"),
                        "synced_lyrics": data.get("syncedLyrics"),
                        "lines": cls.parse_lrc_synced_lyrics(data.get("syncedLyrics"))
                    }
                return None
            except Exception as e:
                print(f"[LyricsService] Error al obtener letra: {e}")
                return None

    @classmethod
    async def search_lyrics(cls, query: str) -> List[Dict[str, Any]]:
        """
        Busca canciones y letras en LRCLIB por término general.
        """
        params = {"q": query}
        async with httpx.AsyncClient(timeout=10.0) as client:
            try:
                response = await client.get(f"{LRCLIB_BASE_URL}/search", params=params)
                if response.status_code == 200:
                    results = response.json()
                    formatted = []
                    for item in results:
                        formatted.append({
                            "id": item.get("id"),
                            "track_name": item.get("trackName"),
                            "artist_name": item.get("artistName"),
                            "album_name": item.get("albumName"),
                            "duration": item.get("duration"),
                            "plain_lyrics": item.get("plainLyrics"),
                            "synced_lyrics": item.get("syncedLyrics"),
                            "lines": cls.parse_lrc_synced_lyrics(item.get("syncedLyrics"))
                        })
                    return formatted
                return []
            except Exception as e:
                print(f"[LyricsService] Error al buscar letras: {e}")
                return []
