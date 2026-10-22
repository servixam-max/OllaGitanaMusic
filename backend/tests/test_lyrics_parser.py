"""Parser LRC: los marcadores de tiempo sin texto no son versos.

LRCLIB suele cerrar la letra con una marca tipo ``[03:06.99]`` sin letra. Si se
devuelve, el karaoke de la app resalta un recuadro vacío al final de la canción.
"""

from app.services.lyrics_service import LyricsService

LRC = """[ar:Estopa]
[ti:Tu calorro]
[00:04.09]Fui a la orilla del río
[00:05.89]Y vi que estabas muy sola
[00:08.12][00:09.12]Vi que te habías dormido
[03:06.99]
"""


def test_marcador_final_vacio_se_descarta():
    lines = LyricsService.parse_lrc_synced_lyrics(LRC)

    assert [line["time_ms"] for line in lines] == [4090, 5890, 8120, 9120]
    assert all(line["text"].strip() for line in lines)


def test_linea_con_solo_espacios_tampoco_es_verso():
    lrc = "[00:01.00]\n[00:02.00]   \n[00:03.00]Hola\n"
    lines = LyricsService.parse_lrc_synced_lyrics(lrc)

    assert [line["text"] for line in lines] == ["Hola"]


def test_letra_sin_sincronizar_devuelve_lista_vacia():
    assert LyricsService.parse_lrc_synced_lyrics(None) == []
    assert LyricsService.parse_lrc_synced_lyrics("") == []
