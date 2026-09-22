from typing import AsyncGenerator
from sqlalchemy import text
from sqlalchemy.ext.asyncio import AsyncSession, create_async_engine, async_sessionmaker
from sqlalchemy.orm import declarative_base
from app.core.config import settings

engine = create_async_engine(
    settings.DATABASE_URL,
    echo=False,
    future=True,
    connect_args={"check_same_thread": False} if "sqlite" in settings.DATABASE_URL else {}
)

AsyncSessionLocal = async_sessionmaker(
    bind=engine,
    class_=AsyncSession,
    expire_on_commit=False,
    autocommit=False,
    autoflush=False
)

Base = declarative_base()

# Migraciones ligeras para bases de datos SQLite ya existentes.
# Formato: tabla -> {columna: definición SQL}
LIGHTWEIGHT_MIGRATIONS = {
    "stem_tasks": {
        "preset": "VARCHAR(50)",
    },
    "song_votes": {
        "liked": "BOOLEAN",  # v1.2.2: sistema de votos Sí/No binario
    },
}


async def _apply_lightweight_migrations(conn):
    """Añade columnas nuevas a bases de datos existentes sin perder datos."""
    if "sqlite" not in settings.DATABASE_URL:
        return
    for table, columns in LIGHTWEIGHT_MIGRATIONS.items():
        try:
            result = await conn.execute(text(f"PRAGMA table_info({table})"))
            existing = {row[1] for row in result.fetchall()}
            if not existing:
                continue
            for column, definition in columns.items():
                if column not in existing:
                    await conn.execute(text(f"ALTER TABLE {table} ADD COLUMN {column} {definition}"))
                    print(f"[DB] Columna añadida: {table}.{column}")
        except Exception as e:
            print(f"[DB] Aviso en migración de {table}: {e}")


async def get_db() -> AsyncGenerator[AsyncSession, None]:
    async with AsyncSessionLocal() as session:
        try:
            yield session
        finally:
            await session.close()

async def init_db():
    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.create_all)
        await _apply_lightweight_migrations(conn)
