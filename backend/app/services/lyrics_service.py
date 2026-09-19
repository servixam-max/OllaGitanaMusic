import re
from typing import Dict, Any, List, Optional
import httpx

LRCLIB_BASE_URL = "https://lrclib.net/api"
HEADERS = {"User-Agent": "OllaGitanaMusic/1.0 (https://github.com/servixam-max/OllaGitanaMusic)"}

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
        Obtiene la letra exacta desde LRCLIB con fallback automático a Lyrics.ovh.
        """
        # 1. Intentar LRCLIB
        params = {
            "track_name": track_name,
            "artist_name": artist_name
        }
        async with httpx.AsyncClient(timeout=8.0) as client:
            try:
                response = await client.get(f"{LRCLIB_BASE_URL}/get", params=params, headers=HEADERS)
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
                        "lines": cls.parse_lrc_synced_lyrics(data.get("syncedLyrics")),
                        "source": "LRCLIB"
                    }
            except Exception as e:
                print(f"[LyricsService] LRCLIB no disponible: {e}")

        # 2. Fallback a Lyrics.ovh
        try:
            async with httpx.AsyncClient(timeout=8.0) as client:
                ovh_url = f"https://api.lyrics.ovh/v1/{artist_name}/{track_name}"
                resp = await client.get(ovh_url)
                if resp.status_code == 200:
                    data = resp.json()
                    plain = data.get("lyrics", "").strip()
                    if plain:
                        return {
                            "id": "ovh_1",
                            "track_name": track_name,
                            "artist_name": artist_name,
                            "album_name": "",
                            "duration": None,
                            "plain_lyrics": plain,
                            "synced_lyrics": None,
                            "lines": [],
                            "source": "Lyrics.ovh"
                        }
        except Exception as e:
            print(f"[LyricsService] Fallback Lyrics.ovh error: {e}")

        return None

    @classmethod
    async def search_lyrics(cls, query: str) -> List[Dict[str, Any]]:
        """
        Busca canciones y letras en LRCLIB con fallback de sugerencias vía Deezer.
        """
        params = {"q": query}
        async with httpx.AsyncClient(timeout=8.0) as client:
            try:
                response = await client.get(f"{LRCLIB_BASE_URL}/search", params=params, headers=HEADERS)
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
                            "lines": cls.parse_lrc_synced_lyrics(item.get("syncedLyrics")),
                            "source": "LRCLIB"
                        })
                    if formatted:
                        return formatted
            except Exception as e:
                print(f"[LyricsService] Error al buscar en LRCLIB: {e}")

        # Si LRCLIB está saturado (503) o no devuelve resultados, buscamos títulos en Deezer
        try:
            async with httpx.AsyncClient(timeout=6.0) as client:
                resp = await client.get("https://api.deezer.com/search", params={"q": query, "limit": 10})
                if resp.status_code == 200:
                    data = resp.json().get("data", [])
                    results = []
                    for item in data:
                        results.append({
                            "id": f"dz_{item.get('id')}",
                            "track_name": item.get("title"),
                            "artist_name": item.get("artist", {}).get("name", "Desconocido"),
                            "album_name": item.get("album", {}).get("title"),
                            "duration": item.get("duration"),
                            "plain_lyrics": None,
                            "synced_lyrics": None,
                            "lines": [],
                            "source": "Deezer Suggestions"
                        })
                    return results
        except Exception:
            pass

        return []
