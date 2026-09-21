from fastapi import Header, HTTPException
from app.core.config import settings


async def require_api_token(x_api_token: str = Header(default="")):
    """
    Protege las operaciones de escritura cuando el servidor está expuesto a Internet
    (túnel Tailscale / Cloudflare). Si no se configura API_TOKEN en el backend, el
    servidor queda abierto (modo red local de ensayo).
    """
    if not settings.API_TOKEN:
        return
    if x_api_token != settings.API_TOKEN:
        raise HTTPException(status_code=401, detail="Token de API inválido o ausente")
