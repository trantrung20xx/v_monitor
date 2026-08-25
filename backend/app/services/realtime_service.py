import asyncio

from fastapi import WebSocket

from app.core.config import settings


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
        connections = list(self.active_connections)
        if not connections:
            return

        # Gửi đồng thời để một socket chậm không làm tăng độ trễ tuyến tính cho
        # tất cả socket phía sau. Timeout giới hạn thời gian giữ worker MQTT.
        delivered = await asyncio.gather(
            *(self._send(connection, message) for connection in connections)
        )
        for connection, succeeded in zip(connections, delivered):
            if not succeeded:
                self.disconnect(connection)

    async def _send(self, connection: WebSocket, message: dict) -> bool:
        try:
            await asyncio.wait_for(
                connection.send_json(message),
                timeout=settings.realtime_send_timeout_seconds,
            )
            return True
        except Exception:
            return False


realtime_service = RealtimeService()
