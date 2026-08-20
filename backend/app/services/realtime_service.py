from fastapi import WebSocket


class RealtimeService:
    def __init__(self):
        self.active_connections: list[WebSocket] = []

    async def connect(self, websocket: WebSocket, *, already_accepted: bool = False):
        if not already_accepted:
            await websocket.accept()
        if websocket not in self.active_connections:
            self.active_connections.append(websocket)

    def disconnect(self, websocket: WebSocket):
        if websocket in self.active_connections:
            self.active_connections.remove(websocket)

    async def broadcast_telemetry(self, message: dict):
        stale_connections: list[WebSocket] = []
        for connection in list(self.active_connections):
            try:
                await connection.send_json(message)
            except Exception:
                stale_connections.append(connection)

        for connection in stale_connections:
            self.disconnect(connection)


realtime_service = RealtimeService()
