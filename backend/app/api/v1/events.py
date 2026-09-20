import json
from typing import List, Optional
from pydantic import BaseModel, Field
from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, desc

from app.core.database import get_db
from app.models.event import BandEvent

router = APIRouter(prefix="/events", tags=["Events & Setlists"])

class SetlistItemSchema(BaseModel):
    id: Optional[int] = None
    title: str
    artist: str
    notes: Optional[str] = None

class EventCreateSchema(BaseModel):
    name: str = Field(..., examples=["Concierto Chiringuito El Sol"])
    event_date: str = Field(..., examples=["2026-10-24T21:00:00"])
    location: Optional[str] = Field(None, examples=["Málaga"])
    notes: Optional[str] = Field(None, examples=["Prueba de sonido 19:30"])
    setlist: List[SetlistItemSchema] = Field(default_factory=list)

class EventUpdateSchema(BaseModel):
    name: Optional[str] = None
    event_date: Optional[str] = None
    location: Optional[str] = None
    notes: Optional[str] = None
    setlist: Optional[List[SetlistItemSchema]] = None

def format_event(event: BandEvent) -> dict:
    try:
        setlist = json.loads(event.setlist_json) if event.setlist_json else []
    except Exception:
        setlist = []
    return {
        "id": event.id,
        "name": event.name,
        "event_date": event.event_date,
        "location": event.location,
        "notes": event.notes,
        "setlist": setlist,
        "created_at": event.created_at.isoformat() if event.created_at else None
    }

@router.get("")
async def list_events(db: AsyncSession = Depends(get_db)):
    """
    Lista todos los eventos de la banda ordenados por fecha de creación o celebración.
    """
    query = select(BandEvent).order_by(desc(BandEvent.created_at))
    result = await db.execute(query)
    events = result.scalars().all()
    return [format_event(e) for e in events]

@router.post("")
async def create_event(payload: EventCreateSchema, db: AsyncSession = Depends(get_db)):
    """
    Crea un nuevo evento con su setlist inicial.
    """
    setlist_json = json.dumps([item.model_dump() for item in payload.setlist])
    event = BandEvent(
        name=payload.name,
        event_date=payload.event_date,
        location=payload.location,
        notes=payload.notes,
        setlist_json=setlist_json
    )
    db.add(event)
    await db.commit()
    await db.refresh(event)
    return format_event(event)

@router.get("/{event_id}")
async def get_event(event_id: str, db: AsyncSession = Depends(get_db)):
    event = await db.get(BandEvent, event_id)
    if not event:
        raise HTTPException(status_code=404, detail="Evento no encontrado")
    return format_event(event)

@router.put("/{event_id}")
async def update_event(event_id: str, payload: EventUpdateSchema, db: AsyncSession = Depends(get_db)):
    event = await db.get(BandEvent, event_id)
    if not event:
        raise HTTPException(status_code=404, detail="Evento no encontrado")
    
    if payload.name is not None:
        event.name = payload.name
    if payload.event_date is not None:
        event.event_date = payload.event_date
    if payload.location is not None:
        event.location = payload.location
    if payload.notes is not None:
        event.notes = payload.notes
    if payload.setlist is not None:
        event.setlist_json = json.dumps([item.model_dump() for item in payload.setlist])

    await db.commit()
    await db.refresh(event)
    return format_event(event)

@router.delete("/{event_id}")
async def delete_event(event_id: str, db: AsyncSession = Depends(get_db)):
    event = await db.get(BandEvent, event_id)
    if not event:
        raise HTTPException(status_code=404, detail="Evento no encontrado")
    
    await db.delete(event)
    await db.commit()
    return {"message": "Evento eliminado correctamente"}
