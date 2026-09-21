import uuid
from datetime import datetime, timezone
from sqlalchemy import Column, String, Integer, DateTime, Text
from app.core.database import Base

class StemTask(Base):
    __tablename__ = "stem_tasks"

    id = Column(String(36), primary_key=True, default=lambda: str(uuid.uuid4()))
    original_filename = Column(String(255), nullable=False)
    collection_name = Column(String(255), nullable=True)  # Grupo/Colección de la canción
    status = Column(String(50), default="pending")  # pending, processing, completed, failed
    progress = Column(Integer, default=0)  # 0 a 100
    stems_json = Column(Text, nullable=True)  # JSON string con URLs de cada pista
    error_message = Column(Text, nullable=True)
    created_at = Column(DateTime, default=lambda: datetime.now(timezone.utc))
