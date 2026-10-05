import uuid
from datetime import datetime, timezone
from sqlalchemy import Column, String, DateTime, Text, Float, Integer
from app.core.database import Base

class AnalyzedSong(Base):
    __tablename__ = "analyzed_songs"

    id = Column(String(36), primary_key=True, default=lambda: str(uuid.uuid4()))
    filename = Column(String(255), nullable=False)
    audio_url = Column(String(1024), nullable=True)  # audio ORIGINAL subido (fuente del análisis)
    estimated_key = Column(String(50), default="N/A")
    duration = Column(Float, default=0.0)
    timeline_json = Column(Text, default="[]")  # línea temporal ORIGINAL detectada
    # Bajar/subir tono de una canción ya analizada (0 = original)
    transpose_semitones = Column(Integer, default=0)
    transposed_audio_url = Column(String(1024), nullable=True)  # versión transpuesta lista para reproducir
    created_at = Column(DateTime, default=lambda: datetime.now(timezone.utc))
