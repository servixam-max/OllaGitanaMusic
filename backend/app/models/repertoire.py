from datetime import datetime, timezone
from typing import List, Optional
from sqlalchemy import Column, Integer, String, DateTime, ForeignKey, Text, Float, Boolean
from sqlalchemy.orm import relationship
from app.core.database import Base

class SongProposal(Base):
    __tablename__ = "song_proposals"

    id = Column(Integer, primary_key=True, index=True)
    title = Column(String(255), nullable=False, index=True)
    artist = Column(String(255), nullable=False, index=True)
    album = Column(String(255), nullable=True)
    cover_url = Column(String(1024), nullable=True)
    preview_url = Column(String(1024), nullable=True)
    spotify_id = Column(String(100), nullable=True)
    status = Column(String(50), default="propuesta", index=True)  # propuesta, para_ensayar, en_repertorio, descartada
    proposed_by = Column(String(100), default="Anónimo")
    notes = Column(Text, nullable=True)
    created_at = Column(DateTime, default=lambda: datetime.now(timezone.utc))

    votes = relationship("SongVote", back_populates="song", cascade="all, delete-orphan", lazy="selectin")

    @property
    def yes_votes(self) -> int:
        """Número de músicos que han votado SÍ (les gusta)."""
        return sum(1 for v in self.votes if v.liked is True)

    @property
    def no_votes(self) -> int:
        """Número de músicos que han votado NO (no les gusta)."""
        return sum(1 for v in self.votes if v.liked is False)

    @property
    def total_votes(self) -> int:
        return len(self.votes) if self.votes else 0

    # Mantenemos average_rating por retrocompatibilidad (no se usa en el nuevo sistema)
    @property
    def average_rating(self) -> float:
        return 0.0

class SongVote(Base):
    __tablename__ = "song_votes"

    id = Column(Integer, primary_key=True, index=True)
    song_id = Column(Integer, ForeignKey("song_proposals.id", ondelete="CASCADE"), nullable=False)
    user_name = Column(String(100), nullable=False)
    liked = Column(Boolean, nullable=True)  # True = Sí me gusta, False = No me gusta
    # rating se mantiene como alias para retrocompatibilidad de la columna SQLite
    rating = Column(Integer, nullable=True)
    created_at = Column(DateTime, default=lambda: datetime.now(timezone.utc))

    song = relationship("SongProposal", back_populates="votes")
