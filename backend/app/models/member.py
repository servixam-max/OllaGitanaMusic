import uuid
from datetime import datetime, timezone
from sqlalchemy import Column, String, DateTime
from app.core.database import Base

class BandMember(Base):
    __tablename__ = "band_members"

    id = Column(String(36), primary_key=True, default=lambda: str(uuid.uuid4()))
    name = Column(String(100), unique=True, nullable=False)
    role = Column(String(100), nullable=True, default="Músico")
    avatar_color = Column(String(20), nullable=True, default="#E5A93C")
    created_at = Column(DateTime, default=lambda: datetime.now(timezone.utc))
