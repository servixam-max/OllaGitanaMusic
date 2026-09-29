"""
Utilidades compartidas para deduplicar resultados de catálogos musicales.

Los proveedores externos (LRCLIB, Deezer, iTunes) devuelven la misma canción
varias veces con pequeñas diferencias de formato: mayúsculas, acentos, sufijos
de versión ("(Remastered 2011)", "[Live]", "(feat. X)") y créditos de artista
distintos para la misma grabación ("Devito, Breshvica" / "Devito feat. Breshvica").
Sin unificar, las listas de la app muestran la misma canción repetida.
"""
import re
import unicodedata
from typing import Optional

# Separadores de colaboración en créditos de artista
_ARTIST_SPLIT_RE = re.compile(
    r"(?i)\s*(?:&|,|/|\+|;|\bfeat\b|\bfeaturing\b|\bwith\b|\bcon\b|\by\b|\band\b)\s*"
)


def normalize_key(text: Optional[str]) -> str:
    """
    Clave de comparación tolerante:
    - minúsculas, sin acentos/diacríticos
    - sin sufijos entre paréntesis/corchetes: (Remastered 2011), [Live], (feat. X)
    - sin puntuación sobrante
    """
    if not text:
        return ""
    value = unicodedata.normalize("NFKD", str(text))
    value = "".join(ch for ch in value if not unicodedata.combining(ch))
    value = value.lower()
    value = re.sub(r"[\(\[\{][^\)\]\}]*[\)\]\}]", " ", value)
    value = re.sub(r"[^a-z0-9]+", " ", value)
    return value.strip()


def primary_artist(artist_raw: Optional[str]) -> str:
    """
    Artista principal de un crédito en bruto: corta colaboraciones
    ('Devito feat. Breshvica' -> 'devito'). Se calcula ANTES de normalizar,
    porque la normalización elimina los separadores ('&', ',').
    """
    if not artist_raw:
        return ""
    head = _ARTIST_SPLIT_RE.split(str(artist_raw))[0]
    return normalize_key(head)


def dedupe_items(items, title_field: str, artist_field: str, rank=None, fill_fields=None):
    """
    Elimina duplicados conservando el mejor elemento de cada canción.

    Dos elementos se consideran la misma canción si coinciden título y artista,
    o si coinciden título y artista principal (casos 'Artista' vs 'Artista & Invitado').

    rank(item) -> tuple: prefieren la variante con mejor puntuación (p.ej. la que
    tiene karaoke). El primero de la lista gana en empates.

    fill_fields: nombres de campo que se completan desde el duplicado cuando el
    elemento conservado los tiene vacíos (p.ej. carátula que solo traía un
    proveedor). Así no se pierde información al colapsar resultados.
    """
    merged = []
    seen = {}

    for item in items:
        title_key = normalize_key(item.get(title_field))
        if not title_key:
            continue
        artist_key = normalize_key(item.get(artist_field))
        primary_key = primary_artist(item.get(artist_field))

        key = (title_key, artist_key)
        primary = (title_key, primary_key)

        index = seen.get(key)
        if index is None:
            index = seen.get(primary)

        if index is None:
            seen[key] = len(merged)
            seen.setdefault(primary, len(merged))
            merged.append(item)
            continue

        current = merged[index]

        # Completar huecos del elemento conservado con datos del duplicado
        if fill_fields:
            for field in fill_fields:
                if not current.get(field) and item.get(field):
                    current[field] = item[field]

        # Sustituir si la variante nueva es mejor (p.ej. tiene karaoke)
        if rank is not None and rank(item) > rank(current):
            replacement = dict(item)
            if fill_fields:
                for field in fill_fields:
                    if not replacement.get(field) and current.get(field):
                        replacement[field] = current[field]
            merged[index] = replacement

    return merged
