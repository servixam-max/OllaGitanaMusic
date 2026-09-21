import asyncio
from contextlib import asynccontextmanager
import io
import logging
from pathlib import Path
import shutil
import tarfile
import httpx
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import RedirectResponse
from fastapi.staticfiles import StaticFiles

from app.core.config import settings
from app.core.database import init_db
from app.api.v1.lyrics import router as lyrics_router
from app.api.v1.stems import router as stems_router
from app.api.v1.chords import router as chords_router
from app.api.v1.repertoire import router as repertoire_router
from app.api.v1.events import router as events_router
from app.api.v1.members import router as members_router
from app.api.v1.ws import router as ws_router
from app.services.stem_queue import stem_queue

logger = logging.getLogger("uvicorn")

WEB_DIR = Path(__file__).resolve().parent.parent / "web"
WEB_DIR.mkdir(parents=True, exist_ok=True)

# Crear archivo placeholder inicial si WEB_DIR está vacío
placeholder_file = WEB_DIR / "index.html"
if not placeholder_file.exists():
    placeholder_file.write_text(
        """<!DOCTYPE html>
<html lang="es">
<head>
  <meta charset="UTF-8">
  <title>Olla Gitana Music</title>
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <style>
    body { background-color: #121214; color: #E5A93C; font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif; display: flex; flex-direction: column; align-items: center; justify-content: center; height: 100vh; margin: 0; text-align: center; }
    .spinner { width: 50px; height: 50px; border: 4px solid rgba(229,169,60,0.2); border-top-color: #E5A93C; border-radius: 50%; animation: spin 1s infinite linear; margin-bottom: 20px; }
    @keyframes spin { 0% { transform: rotate(0deg); } 100% { transform: rotate(360deg); } }
  </style>
</head>
<body>
  <div class="spinner"></div>
  <h2>Olla Gitana Music</h2>
  <p style="color: #A0A0A5; max-width: 320px; font-size: 14px; line-height: 1.5;">Sincronizando la sala de ensayo con el servidor... La versión Web PWA para iOS estará disponible en breves instantes. Por favor, recarga esta página en unos segundos.</p>
</body>
</html>
""",
        encoding="utf-8"
    )

async def sync_web_app(force: bool = False):
    """Descarga e instala automáticamente la última versión de la Web PWA desde GitHub Releases."""
    try:
        url = "https://api.github.com/repos/servixam-max/OllaGitanaMusic/releases/latest"
        headers = {
            "User-Agent": "OllaGitanaMusic-Backend/1.0",
            "Accept": "application/vnd.github.v3+json",
        }
        async with httpx.AsyncClient(timeout=45.0, follow_redirects=True) as client:
            resp = await client.get(url, headers=headers)
            if resp.status_code != 200:
                logger.warning(f"[WebSync] No se pudo consultar GitHub Releases: HTTP {resp.status_code}")
                return {"status": "error", "message": f"HTTP {resp.status_code}"}
            
            data = resp.json()
            tag = data.get("tag_name", "")
            version_file = WEB_DIR / "version.txt"
            
            if not force and version_file.exists():
                current_tag = version_file.read_text(encoding="utf-8").strip()
                if current_tag == tag and (WEB_DIR / "flutter_bootstrap.js").exists():
                    logger.info(f"[WebSync] Web PWA ya está al día ({tag})")
                    return {"status": "up_to_date", "version": tag}
            
            # Buscar asset olla-gitana-web.tar.gz
            web_asset = None
            for asset in data.get("assets", []):
                name = asset.get("name", "").lower()
                if "web" in name and name.endswith(".tar.gz"):
                    web_asset = asset
                    break
            
            if not web_asset:
                logger.info(f"[WebSync] No se encontró asset olla-gitana-web.tar.gz en release {tag}")
                return {"status": "not_found", "message": f"No web asset in release {tag}"}
            
            download_url = web_asset.get("browser_download_url")
            logger.info(f"[WebSync] Descargando Web PWA {tag} desde {download_url}...")
            
            dl_resp = await client.get(download_url)
            if dl_resp.status_code != 200:
                logger.error(f"[WebSync] Error descargando asset: HTTP {dl_resp.status_code}")
                return {"status": "error", "message": f"Download failed HTTP {dl_resp.status_code}"}
            
            # Extraer tar.gz en un directorio temporal y reemplazar
            temp_dir = WEB_DIR.parent / "web_temp"
            if temp_dir.exists():
                shutil.rmtree(temp_dir)
            temp_dir.mkdir(parents=True, exist_ok=True)
            
            with tarfile.open(fileobj=io.BytesIO(dl_resp.content), mode="r:gz") as tar:
                tar.extractall(path=temp_dir)
            
            # Copiar contenido de temp_dir a WEB_DIR
            for item in temp_dir.iterdir():
                dest = WEB_DIR / item.name
                if dest.is_dir():
                    shutil.rmtree(dest, ignore_errors=True)
                elif dest.is_file():
                    dest.unlink()
                shutil.move(str(item), str(dest))
            
            shutil.rmtree(temp_dir, ignore_errors=True)
            version_file.write_text(tag, encoding="utf-8")
            logger.info(f"[WebSync] Web PWA instalada y actualizada a {tag} con éxito")
            return {"status": "updated", "version": tag}
    except Exception as e:
        logger.error(f"[WebSync] Error sincronizando Web PWA: {e}")
        return {"status": "error", "message": str(e)}

@asynccontextmanager
async def lifespan(app: FastAPI):
    # Inicialización de base de datos y directorios de almacenamiento
    await init_db()
    settings.upload_dir.mkdir(parents=True, exist_ok=True)
    settings.stems_dir.mkdir(parents=True, exist_ok=True)
    settings.previews_dir.mkdir(parents=True, exist_ok=True)
    # Iniciar comprobación y sincronización de la versión web en segundo plano
    asyncio.create_task(sync_web_app())
    # Arrancar la cola de separación de pistas (worker único) y recuperar tareas huérfanas
    stem_queue.start()
    yield

app = FastAPI(
    title=settings.PROJECT_NAME,
    version=settings.VERSION,
    description="API Backend para Olla Gitana Music - Separación de stems, acordes, letras y repertorio colaborativo",
    lifespan=lifespan
)

# Configuración de CORS permisivo para desarrollo móvil y red local
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Montar directorios estáticos con soporte nativo de Range Requests (HTTP 206) para streaming de audio
app.mount("/static/stems", StaticFiles(directory=str(settings.stems_dir)), name="stems")
app.mount("/static/uploads", StaticFiles(directory=str(settings.upload_dir)), name="uploads")
app.mount("/static/previews", StaticFiles(directory=str(settings.previews_dir)), name="previews")

# Redirección amigable para asegurar la barra final en la Web PWA
@app.get("/app")
async def redirect_web_app():
    return RedirectResponse(url="/olla/app/", status_code=308)

# Montar la aplicación Web PWA (Flutter Web para iOS y navegadores)
app.mount("/app", StaticFiles(directory=str(WEB_DIR), html=True), name="web_app")

# Registrar routers de la API v1
app.include_router(lyrics_router, prefix="/api/v1")
app.include_router(stems_router, prefix="/api/v1")
app.include_router(chords_router, prefix="/api/v1")
app.include_router(repertoire_router, prefix="/api/v1")
app.include_router(events_router, prefix="/api/v1")
app.include_router(members_router, prefix="/api/v1")
app.include_router(ws_router)

@app.post("/api/v1/admin/sync-web")
@app.get("/api/v1/admin/sync-web")
async def trigger_sync_web():
    result = await sync_web_app(force=True)
    return result

@app.get("/")
async def root():
    return {
        "status": "online",
        "app": settings.PROJECT_NAME,
        "version": settings.VERSION,
        "endpoints": {
            "web_app": "/app/",
            "docs": "/docs",
            "lyrics": "/api/v1/lyrics",
            "stems": "/api/v1/stems",
            "chords": "/api/v1/chords",
            "repertoire": "/api/v1/repertoire",
            "events": "/api/v1/events",
            "websockets": ["/ws/tasks/{task_id}", "/ws/repertoire"]
        }
    }
