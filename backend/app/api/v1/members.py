from typing import List, Optional
from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select

from app.core.database import get_db
from app.models.member import BandMember

router = APIRouter(prefix="/members", tags=["Band Members"])

DEFAULT_MEMBERS = [
    {"name": "Champi", "role": "Voz / Guitarra", "avatar_color": "#E5A93C"},
    {"name": "Rubén", "role": "Músico", "avatar_color": "#FF7A00"},
    {"name": "Mario", "role": "Músico", "avatar_color": "#00E676"},
    {"name": "Miguel", "role": "Músico", "avatar_color": "#00B0FF"},
]

class MemberCreate(BaseModel):
    name: str
    role: Optional[str] = "Músico"
    avatar_color: Optional[str] = "#E5A93C"

@router.get("")
async def get_band_members(db: AsyncSession = Depends(get_db)):
    """
    Obtiene la lista de músicos de Olla Gitana.
    Si la base de datos está vacía, la inicializa con los miembros fundadores.
    """
    query = select(BandMember).order_by(BandMember.created_at)
    result = await db.execute(query)
    members = result.scalars().all()

    if not members:
        # Sembrar miembros por defecto
        for m_data in DEFAULT_MEMBERS:
            new_m = BandMember(
                name=m_data["name"],
                role=m_data["role"],
                avatar_color=m_data["avatar_color"]
            )
            db.add(new_m)
        await db.commit()
        
        result = await db.execute(query)
        members = result.scalars().all()

    return [
        {
            "id": m.id,
            "name": m.name,
            "role": m.role,
            "avatar_color": m.avatar_color,
            "created_at": m.created_at.isoformat() if m.created_at else None
        }
        for m in members
    ]

@router.post("")
async def add_band_member(payload: MemberCreate, db: AsyncSession = Depends(get_db)):
    """
    Registra un nuevo miembro en la banda si no existe ya.
    """
    clean_name = payload.name.strip()
    if not clean_name:
        raise HTTPException(status_code=400, detail="El nombre del músico no puede estar vacío")

    query = select(BandMember).where(BandMember.name.ilike(clean_name))
    result = await db.execute(query)
    existing = result.scalar_one_or_none()
    if existing:
        return {
            "id": existing.id,
            "name": existing.name,
            "role": existing.role,
            "avatar_color": existing.avatar_color,
            "message": "El músico ya estaba registrado"
        }

    member = BandMember(
        name=clean_name,
        role=payload.role or "Músico",
        avatar_color=payload.avatar_color or "#E5A93C"
    )
    db.add(member)
    await db.commit()
    await db.refresh(member)

    return {
        "id": member.id,
        "name": member.name,
        "role": member.role,
        "avatar_color": member.avatar_color,
        "message": "Músico añadido correctamente"
    }

@router.delete("/{name}")
async def delete_band_member(name: str, db: AsyncSession = Depends(get_db)):
    """
    Elimina un miembro de la banda por nombre.
    """
    query = select(BandMember).where(BandMember.name.ilike(name.strip()))
    result = await db.execute(query)
    member = result.scalar_one_or_none()
    if not member:
        raise HTTPException(status_code=404, detail="Músico no encontrado")

    await db.delete(member)
    await db.commit()
    return {"message": f"Músico {member.name} eliminado"}
