from contextlib import asynccontextmanager
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles

from app.core.config import settings
from app.core.database import init_db
from app.api.v1.lyrics import router as lyrics_router
from app.api.v1.stems import router as stems_router
from app.api.v1.chords import router as chords_router
from app.api.v1.repertoire import router as repertoire_router
from app.api.v1.ws import router as ws_router

@asynccontextmanager
async def lifespan(app: FastAPI):
    # Inicialización de base de datos y directorios de almacenamiento
    await init_db()
    settings.upload_dir.mkdir(parents=True, exist_ok=True)
    settings.stems_dir.mkdir(parents=True, exist_ok=True)
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

# Registrar routers de la API v1
app.include_router(lyrics_router, prefix="/api/v1")
app.include_router(stems_router, prefix="/api/v1")
app.include_router(chords_router, prefix="/api/v1")
app.include_router(repertoire_router, prefix="/api/v1")
app.include_router(ws_router)

@app.get("/")
async def root():
    return {
        "status": "online",
        "app": settings.PROJECT_NAME,
        "version": settings.VERSION,
        "endpoints": {
            "docs": "/docs",
            "lyrics": "/api/v1/lyrics",
            "stems": "/api/v1/stems",
            "chords": "/api/v1/chords",
            "repertoire": "/api/v1/repertoire",
            "websockets": ["/ws/tasks/{task_id}", "/ws/repertoire"]
        }
    }
