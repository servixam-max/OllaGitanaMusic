from fastapi import APIRouter, WebSocket, WebSocketDisconnect
from app.services.ws_manager import ws_manager

router = APIRouter(tags=["WebSockets"])

@router.websocket("/ws/tasks/{task_id}")
async def websocket_task_progress(websocket: WebSocket, task_id: str):
    """
    Canal WebSocket para recibir el porcentaje de progreso (0% a 100%) del aislamiento de stems.
    """
    await ws_manager.connect_task(task_id, websocket)
    try:
        while True:
            # Mantener la conexión abierta escuchando posibles pings del cliente
            await websocket.receive_text()
    except WebSocketDisconnect:
        ws_manager.disconnect_task(task_id, websocket)

@router.websocket("/ws/repertoire")
async def websocket_repertoire(websocket: WebSocket):
    """
    Canal WebSocket para sincronización en vivo de la sala de ensayo (nuevos temas, votos, cambios de estado).
    """
    await ws_manager.connect_general(websocket)
    try:
        while True:
            await websocket.receive_text()
    except WebSocketDisconnect:
        ws_manager.disconnect_general(websocket)
