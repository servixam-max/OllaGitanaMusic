import uuid
from datetime import datetime, timezone
from sqlalchemy import Column, String, DateTime, Text
from app.core.database import Base

class BandEvent(Base):
    __tablename__ = "band_events"

    id = Column(String(36), primary_key=True, default=lambda: str(uuid.uuid4()))
    name = Column(String(255), nullable=False)
    event_date = Column(String(100), nullable=False)
    location = Column(String(255), nullable=True)
    notes = Column(Text, nullable=True)
    setlist_json = Column(Text, default="[]")
    created_at = Column(DateTime, default=lambda: datetime.now(timezone.utc))
