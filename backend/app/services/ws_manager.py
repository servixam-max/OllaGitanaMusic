import json
from typing import Dict, List, Any
from fastapi import WebSocket

class WebSocketManager:
    def __init__(self):
        # Mapeo de task_id a lista de WebSockets escuchando esa tarea
        self.task_connections: Dict[str, List[WebSocket]] = {}
        # Conexiones generales (para la sala de ensayo/votaciones)
        self.general_connections: List[WebSocket] = []

    async def connect_task(self, task_id: str, websocket: WebSocket):
        await websocket.accept()
        if task_id not in self.task_connections:
            self.task_connections[task_id] = []
        self.task_connections[task_id].append(websocket)

    def disconnect_task(self, task_id: str, websocket: WebSocket):
        if task_id in self.task_connections:
            if websocket in self.task_connections[task_id]:
                self.task_connections[task_id].remove(websocket)
            if not self.task_connections[task_id]:
                del self.task_connections[task_id]

    async def broadcast_task_progress(self, task_id: str, data: Dict[str, Any]):
        if task_id in self.task_connections:
            message = json.dumps(data)
            disconnected = []
            for ws in self.task_connections[task_id]:
                try:
                    await ws.send_text(message)
                except Exception:
                    disconnected.append(ws)
            for ws in disconnected:
                self.disconnect_task(task_id, ws)

    async def connect_general(self, websocket: WebSocket):
        await websocket.accept()
        self.general_connections.append(websocket)

    def disconnect_general(self, websocket: WebSocket):
        if websocket in self.general_connections:
            self.general_connections.remove(websocket)

    async def broadcast_repertoire_event(self, event_type: str, payload: Any):
        message = json.dumps({"event": event_type, "data": payload})
        disconnected = []
        for ws in self.general_connections:
            try:
                await ws.send_text(message)
            except Exception:
                disconnected.append(ws)
        for ws in disconnected:
            self.disconnect_general(ws)

ws_manager = WebSocketManager()
