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

        # 2. Votar la canción
        vote_payload = {
            "user_name": "Manuel (Cajón)",
            "rating": 5
        }
        res_vote = await client.post(f"/api/v1/repertoire/songs/{song_id}/vote", json=vote_payload)
        assert res_vote.status_code == 200
        voted = res_vote.json()
        assert voted["average_rating"] == 5.0
        assert voted["total_votes"] == 1

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

@pytest.mark.asyncio
async def test_stems_tasks_list():
    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        response = await client.get("/api/v1/stems/tasks")
        assert response.status_code == 200
        assert isinstance(response.json(), list)
