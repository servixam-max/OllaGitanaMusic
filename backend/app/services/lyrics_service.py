import re
from typing import Dict, Any, List, Optional
import httpx

LRCLIB_BASE_URL = "https://lrclib.net/api"
HEADERS = {"User-Agent": "OllaGitanaMusic/1.0 (https://github.com/servixam-max/OllaGitanaMusic)"}

# Etiquetas de metadatos LRC que no son letra
LRC_META_TAGS = {
    "ar", "ti", "al", "by", "offset", "re", "ve", "length",
    "au", "ly", "la", "encoding", "tool", "id", "artist", "title",
}

# [mm:ss.xx] o [mm:ss] o [mm:ss:xx]; admite varias marcas por línea
LRC_TIME_PATTERN = re.compile(r"\[(\d{1,3}):(\d{1,2})(?:[.:](\d{1,3}))?\]")


class LyricsService:
    @staticmethod
    def parse_lrc_synced_lyrics(lrc_text: Optional[str]) -> List[Dict[str, Any]]:
        """
        Parsea letra en formato LRC de forma tolerante:
        - Soporta [mm:ss.xx], [mm:ss] y varias marcas de tiempo por línea.
        - Aplica el desplazamiento global [offset:±ms] si existe.
        - Descarta líneas de metadatos [ar:...], [ti:...] y líneas vacías.
        Devuelve una lista ordenada por tiempo en milisegundos.
        """
        if not lrc_text:
            return []

        # Desplazamiento global opcional [offset:+250] / [offset:-500]
        offset_ms = 0
        offset_match = re.search(r"\[offset:\s*([+-]?\d+)\s*\]", lrc_text, re.IGNORECASE)
        if offset_match:
            try:
                offset_ms = int(offset_match.group(1))
            except ValueError:
                offset_ms = 0

        parsed: List[Dict[str, Any]] = []
        for raw_line in lrc_text.splitlines():
            line = raw_line.strip()
            if not line:
                continue

            # Ignorar líneas que son solo metadatos
            meta_match = re.match(r"^\[([a-zA-Z#]+):(.*)\]$", line)
            if meta_match and meta_match.group(1).lower() in LRC_META_TAGS:
                continue

            marks = list(LRC_TIME_PATTERN.finditer(line))
            if not marks:
                continue

            # El texto es lo que queda tras la última marca de tiempo
            text = line[marks[-1].end():].strip()

            for mark in marks:
                minutes = int(mark.group(1))
                seconds = int(mark.group(2))
                fraction = mark.group(3) or "0"
                # Normalizar fracción a milisegundos (1, 2 o 3 dígitos)
                if len(fraction) == 1:
                    millis = int(fraction) * 100
                elif len(fraction) == 2:
                    millis = int(fraction) * 10
                else:
                    millis = int(fraction[:3])

                time_ms = minutes * 60 * 1000 + seconds * 1000 + millis + offset_ms
                if time_ms < 0:
                    time_ms = 0

                parsed.append({"time_ms": time_ms, "text": text})

        # Ordenar por tiempo y eliminar duplicados exactos (misma marca repetida)
        parsed.sort(key=lambda item: item["time_ms"])
        deduped: List[Dict[str, Any]] = []
        seen = set()
        for item in parsed:
            key = (item["time_ms"], item["text"])
            if key in seen:
                continue
            seen.add(key)
            deduped.append(item)
        return deduped

    @staticmethod
    def _has_synced_lyrics(item: Dict[str, Any]) -> bool:
        return bool(item.get("syncedLyrics"))

    @classmethod
    def _format_lrclib_item(cls, item: Dict[str, Any]) -> Dict[str, Any]:
        """Normaliza un elemento de LRCLIB (de /get o /search) al formato de la app."""
        return {
            "id": item.get("id"),
            "track_name": item.get("trackName") or "Sin título",
            "artist_name": item.get("artistName") or "Desconocido",
            "album_name": item.get("albumName"),
            "duration": item.get("duration"),
            "plain_lyrics": item.get("plainLyrics"),
            "synced_lyrics": item.get("syncedLyrics"),
            "lines": cls.parse_lrc_synced_lyrics(item.get("syncedLyrics")),
            "has_synced": cls._has_synced_lyrics(item),
            "source": "LRCLIB",
        }

    @classmethod
    async def _search_lrclib(cls, query: str) -> List[Dict[str, Any]]:
        """Busca en LRCLIB y formatea los resultados."""
        params = {"q": query}
        async with httpx.AsyncClient(timeout=8.0) as client:
            response = await client.get(f"{LRCLIB_BASE_URL}/search", params=params, headers=HEADERS)
            if response.status_code != 200:
                return []
            results = response.json()

        formatted = []
        for item in results:
            if not item.get("trackName"):
                continue
            formatted.append(cls._format_lrclib_item(item))
        return formatted

    @classmethod
    async def get_lyrics(cls, track_name: str, artist_name: str) -> Optional[Dict[str, Any]]:
        """
        Obtiene la letra exacta de una canción por título y artista.

        Estrategia:
        1. LRCLIB /get (match exacto): es la vía que devuelve letra SINCRONIZADA.
        2. LRCLIB /search filtrado por título+artista y ordenado priorizando las
           versiones con LRC sincronizado (esto arregla los casos en que /get
           falla por ligeras diferencias en el nombre).
        3. Fallback a Lyrics.ovh (solo texto plano).
        """
        # 1. Match exacto en LRCLIB
        params = {"track_name": track_name, "artist_name": artist_name}
        async with httpx.AsyncClient(timeout=8.0) as client:
            try:
                response = await client.get(f"{LRCLIB_BASE_URL}/get", params=params, headers=HEADERS)
                if response.status_code == 200:
                    data = response.json()
                    return cls._format_lrclib_item(data)
            except Exception as e:
                print(f"[LyricsService] LRCLIB no disponible: {e}")

        # 2. Búsqueda flexible: encontrar la mejor versión con letra sincronizada
        try:
            candidates = await cls._search_lrclib(f"{track_name} {artist_name}")
            if candidates:
                track_lower = track_name.lower().strip()
                artist_lower = artist_name.lower().strip()

                def score(item: Dict[str, Any]) -> tuple:
                    item_track = (item.get("track_name") or "").lower()
                    item_artist = (item.get("artist_name") or "").lower()
                    # Prioridad: tiene LRC > coincide título > coincide artista > tiene letra
                    return (
                        1 if item.get("has_synced") else 0,
                        1 if track_lower and track_lower in item_track else 0,
                        1 if artist_lower and artist_lower in item_artist else 0,
                        1 if item.get("plain_lyrics") else 0,
                    )

                best = max(candidates, key=score)
                if best.get("has_synced") or best.get("plain_lyrics"):
                    return best
        except Exception as e:
            print(f"[LyricsService] Búsqueda flexible de letra falló: {e}")

        # 3. Fallback a Lyrics.ovh (texto plano)
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
                            "has_synced": False,
                            "source": "Lyrics.ovh"
                        }
        except Exception as e:
            print(f"[LyricsService] Fallback Lyrics.ovh error: {e}")

        return None

    @classmethod
    async def search_lyrics(cls, query: str) -> List[Dict[str, Any]]:
        """
        Busca canciones y letras en LRCLIB.
        Ordena los resultados priorizando los que tienen letra sincronizada (karaoke),
        que son los que enganchan bien con la música.
        """
        try:
            formatted = await cls._search_lrclib(query)
            if formatted:
                # Primero los sincronizados y con letra disponible; luego por longitud de título
                formatted.sort(
                    key=lambda item: (
                        1 if item.get("has_synced") else 0,
                        1 if item.get("plain_lyrics") else 0,
                        -(item.get("duration") or 0),
                    ),
                    reverse=True,
                )
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
                            "has_synced": False,
                            "source": "Deezer Suggestions"
                        })
                    return results
        except Exception:
            pass

        return []
