import pytest
import pytest_asyncio
from httpx import AsyncClient, ASGITransport
from app.main import app
from app.core.database import init_db

@pytest.fixture(scope="session")
def anyio_backend():
    return "asyncio"

@pytest_asyncio.fixture(autouse=True)
async def prepare_database():
    await init_db()
    yield

@pytest.mark.asyncio
async def test_root_endpoint():
    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        response = await client.get("/")
        assert response.status_code == 200
        data = response.json()
        assert data["status"] == "online"
        assert "Olla Gitana" in data["app"]

@pytest.mark.asyncio
async def test_repertoire_workflow():
    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        # 1. Crear propuesta
        song_payload = {
            "title": "Entre dos aguas",
            "artist": "Paco de Lucía",
            "album": "Fuente y caudal",
            "proposed_by": "Carlos (Guitarra)",
            "notes": "Rumba flamenca imprescindible"
        }
        res_create = await client.post("/api/v1/repertoire/songs", json=song_payload)
        assert res_create.status_code == 200
        created = res_create.json()
        assert created["title"] == "Entre dos aguas"
        song_id = created["id"]

        # 2. Votar la canción (nuevo sistema Sí/No)
        vote_payload = {
            "user_name": "Manuel (Cajón)",
            "liked": True
        }
        res_vote = await client.post(f"/api/v1/repertoire/songs/{song_id}/vote", json=vote_payload)
        assert res_vote.status_code == 200
        voted = res_vote.json()
        assert voted["yes_votes"] == 1
        assert voted["no_votes"] == 0
        assert voted["total_votes"] == 1
        assert voted["votes"][0]["liked"] is True

        # 3. Cambiar estado a "para_ensayar"
        status_payload = {"status": "para_ensayar"}
        res_status = await client.patch(f"/api/v1/repertoire/songs/{song_id}/status", json=status_payload)
        assert res_status.status_code == 200
        assert res_status.json()["status"] == "para_ensayar"

        # 4. Listar canciones y verificar filtrado
        res_list = await client.get("/api/v1/repertoire/songs?status=para_ensayar")
        assert res_list.status_code == 200
        songs = res_list.json()
        assert any(s["id"] == song_id for s in songs)

        # 5. Eliminar canción
        res_del = await client.delete(f"/api/v1/repertoire/songs/{song_id}")
        assert res_del.status_code == 200

@pytest.mark.asyncio
async def test_lyrics_search_endpoint():
    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        response = await client.get("/api/v1/lyrics/search?q=flamenco")
        assert response.status_code == 200
        data = response.json()
        assert "results" in data


def test_lyrics_dedupe_removes_repeated_entries():
    """LRCLIB devuelve varias subidas de la misma canción: debe quedar una sola."""
    from app.services.lyrics_service import LyricsService

    items = [
        {"track_name": "Tu Calorro", "artist_name": "Estopa", "has_synced": False, "plain_lyrics": "x"},
        {"track_name": "Tu Calorro", "artist_name": "Estopa", "has_synced": True, "plain_lyrics": "x"},
        {"track_name": "tu calorro", "artist_name": "Estopa", "has_synced": False, "plain_lyrics": "x"},
        {"track_name": "Tu Calorro", "artist_name": "La Hungara", "has_synced": False, "plain_lyrics": "y"},
    ]
    deduped = LyricsService.dedupe_results(items)

    assert len(deduped) == 2
    # Gana la variante con karaoke (LRC sincronizado)
    estopa = [d for d in deduped if d["artist_name"] == "Estopa"][0]
    assert estopa["has_synced"] is True
    # La versión de otro artista es una canción distinta y se conserva
    assert any(d["artist_name"] == "La Hungara" for d in deduped)


def test_lyrics_dedupe_ignores_version_suffixes():
    """'Cancion (Remastered 2011)' y 'Cancion' son la misma entrada para la app."""
    from app.services.lyrics_service import LyricsService

    items = [
        {"track_name": "Volando Voy", "artist_name": "Camarón", "has_synced": True, "plain_lyrics": None},
        {"track_name": "Volando Voy (Remastered 2011)", "artist_name": "Camarón", "has_synced": False, "plain_lyrics": "z"},
    ]
    assert len(LyricsService.dedupe_results(items)) == 1


def test_lyrics_dedupe_collapses_artist_credit_variants():
    """Mismos colaboradores escritos distinto son una sola canción."""
    from app.services.lyrics_service import LyricsService

    items = [
        {"track_name": "Tu Tu Tu", "artist_name": "Devito, Breshvica", "has_synced": True, "plain_lyrics": None},
        {"track_name": "Tu Tu Tu", "artist_name": "Devito feat. Breshvica", "has_synced": True, "plain_lyrics": None},
        {"track_name": "Tu Tu Tu", "artist_name": "Devito", "has_synced": True, "plain_lyrics": None},
        {"track_name": "TU TU TU", "artist_name": "ORTYNXHAN", "has_synced": False, "plain_lyrics": "otro"},
    ]
    deduped = LyricsService.dedupe_results(items)

    # Las tres primeras son la misma grabación; la de ORTYNXHAN es otra canción
    assert len(deduped) == 2
    assert {d["artist_name"] for d in deduped} == {"Devito, Breshvica", "ORTYNXHAN"}


def test_music_search_merges_providers_without_duplicates():
    """Deezer + iTunes: la misma canción no debe aparecer dos veces."""
    from app.services.spotify_service import SpotifyService

    deezer = [
        {"title": "Con La Luna Llena", "artist": "Los Chunguitos", "preview_url": "http://a", "cover_url": None},
        {"title": "Me quedo contigo", "artist": "Los Chunguitos", "preview_url": "http://b", "cover_url": "c"},
    ]
    itunes = [
        {"title": "Con La Luna Llena", "artist": "Los Chunguitos & Melendi", "preview_url": None, "cover_url": "cover2"},
        {"title": "Me Quedo Contigo", "artist": "Los Rebujitos", "preview_url": "http://d", "cover_url": "e"},
    ]
    merged = SpotifyService._merge_unique(deezer, itunes)

    titles = [m["title"].lower() for m in merged]
    # 'Con La Luna Llena' se colapsa (mismo artista principal: Los Chunguitos)
    assert titles.count("con la luna llena") == 1
    # 'Me quedo contigo' de Los Rebujitos es OTRO artista: se conserva como resultado propio
    assert titles.count("me quedo contigo") == 2
    chunguitos = [m for m in merged if m["title"].lower() == "me quedo contigo" and m["artist"] == "Los Chunguitos"]
    assert len(chunguitos) == 1
    # No se pierde la carátula que solo traía el segundo proveedor
    luna = [m for m in merged if m["title"] == "Con La Luna Llena"][0]
    assert luna["cover_url"] == "cover2"

@pytest.mark.asyncio
async def test_stems_tasks_list():
    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        response = await client.get("/api/v1/stems/tasks")
        assert response.status_code == 200
        assert isinstance(response.json(), list)

@pytest.mark.asyncio
async def test_events_workflow():
    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        # 1. Crear evento con setlist
        event_payload = {
            "name": "Concierto Chiringuito El Sol",
            "event_date": "2026-10-24T21:00:00",
            "location": "Málaga",
            "notes": "Prueba de sonido 19:30",
            "setlist": [
                {"id": 1, "title": "Entre dos aguas", "artist": "Paco de Lucía"},
                {"id": 2, "title": "Volando voy", "artist": "Camarón de la Isla"}
            ]
        }
        res_create = await client.post("/api/v1/events", json=event_payload)
        assert res_create.status_code == 200
        created = res_create.json()
        assert created["name"] == "Concierto Chiringuito El Sol"
        assert len(created["setlist"]) == 2
        event_id = created["id"]

        # 2. Listar eventos
        res_list = await client.get("/api/v1/events")
        assert res_list.status_code == 200
        events = res_list.json()
        assert any(e["id"] == event_id for e in events)

        # 3. Actualizar evento
        res_update = await client.put(f"/api/v1/events/{event_id}", json={"location": "Torremolinos"})
        assert res_update.status_code == 200
        assert res_update.json()["location"] == "Torremolinos"

        # 4. Eliminar evento
        res_delete = await client.delete(f"/api/v1/events/{event_id}")
        assert res_delete.status_code == 200


@pytest.mark.asyncio
async def test_stems_presets_endpoint():
    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        response = await client.get("/api/v1/stems/presets")
        assert response.status_code == 200
        data = response.json()
        assert "presets" in data
        assert data["default"] == "hybrid"
        keys = {p["key"] for p in data["presets"]}
        assert {"fast", "balanced", "max", "six", "hybrid", "karaoke"}.issubset(keys)


@pytest.mark.asyncio
async def test_stems_upload_rejects_bad_extension():
    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        files = {"file": ("documento.pdf", b"%PDF-1.4 fake", "application/pdf")}
        response = await client.post("/api/v1/stems/upload", files=files, data={"preset": "fast"})
        assert response.status_code == 400


@pytest.mark.asyncio
async def test_stem_task_retry_not_found():
    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        response = await client.post("/api/v1/stems/tasks/no-existe/retry")
        assert response.status_code == 404


@pytest.mark.asyncio
async def test_events_ordered_by_event_date():
    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        # Crear eventos temporales de prueba
        res_late = await client.post("/api/v1/events", json={
            "name": "Evento Tardío QA", "event_date": "2099-12-31T23:00:00"
        })
        res_early = await client.post("/api/v1/events", json={
            "name": "Evento Temprano QA", "event_date": "2030-01-01T20:00:00"
        })
        late_id = res_late.json()["id"]
        early_id = res_early.json()["id"]

        try:
            res = await client.get("/api/v1/events")
            assert res.status_code == 200
            events = res.json()
            dates = [e["event_date"] for e in events]
            assert dates == sorted(dates)
        finally:
            # Limpiar SIEMPRE los eventos de prueba para no ensuciar datos reales
            await client.delete(f"/api/v1/events/{late_id}")
            await client.delete(f"/api/v1/events/{early_id}")
