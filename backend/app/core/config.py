import os
from pathlib import Path
from pydantic_settings import BaseSettings

class Settings(BaseSettings):
    PROJECT_NAME: str = "Olla Gitana Music Backend"
    VERSION: str = "1.0.8"
    PORT: int = 8000
    DATA_DIR: str = os.getenv("DATA_DIR", "./data")
    DATABASE_URL: str = os.getenv("DATABASE_URL", "sqlite+aiosqlite:///./data/olla_gitana.db")
    
    # Spotify API (Opcional pero recomendado para previews y carátulas)
    SPOTIFY_CLIENT_ID: str = os.getenv("SPOTIFY_CLIENT_ID", "")
    SPOTIFY_CLIENT_SECRET: str = os.getenv("SPOTIFY_CLIENT_SECRET", "")

    @property
    def upload_dir(self) -> Path:
        path = Path(self.DATA_DIR) / "uploads"
        path.mkdir(parents=True, exist_ok=True)
        return path

    @property
    def stems_dir(self) -> Path:
        path = Path(self.DATA_DIR) / "stems"
        path.mkdir(parents=True, exist_ok=True)
        return path

    model_config = {"env_file": ".env", "extra": "ignore"}

settings = Settings()
