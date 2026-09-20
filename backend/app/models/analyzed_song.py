import uuid
from datetime import datetime, timezone
from sqlalchemy import Column, String, DateTime, Text, Float
from app.core.database import Base

class AnalyzedSong(Base):
    __tablename__ = "analyzed_songs"

    id = Column(String(36), primary_key=True, default=lambda: str(uuid.uuid4()))
    filename = Column(String(255), nullable=False)
    audio_url = Column(String(1024), nullable=True)
    estimated_key = Column(String(50), default="N/A")
    duration = Column(Float, default=0.0)
    timeline_json = Column(Text, default="[]")
    created_at = Column(DateTime, default=lambda: datetime.now(timezone.utc))
