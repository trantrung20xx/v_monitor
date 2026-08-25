# Quản lý danh sách WebSocket frontend và phát cùng một bản tin cho mọi kết nối.
# Socket lỗi hoặc quá chậm bị loại riêng để không chặn pipeline MQTT và người dùng khác.
import asyncio

from fastapi import WebSocket

from app.core.config import settings


class RealtimeService:
    # Registry WebSocket trong bộ nhớ và cơ chế broadcast không lưu hàng đợi.

    def __init__(self):
        # Danh sách chỉ sống trong tiến trình hiện tại; frontend phải tải lại REST sau
        # reconnect vì WebSocket không được dùng làm nguồn dữ liệu bền vững.
        self.active_connections: list[WebSocket] = []

    async def connect(self, websocket: WebSocket, *, already_accepted: bool = False):
        # Accept nếu cần và thêm socket một lần vào registry.
        # Endpoint đã accept để đọc AUTH truyền `already_accepted=True` nhằm tránh accept hai lần.
        if not already_accepted:
            await websocket.accept()
        # Kiểm tra membership ngăn cùng socket nhận một event nhiều lần.
        if websocket not in self.active_connections:
            self.active_connections.append(websocket)

    def disconnect(self, websocket: WebSocket):
        # Loại socket đã đóng; gọi lặp lại vẫn an toàn.
        if websocket in self.active_connections:
            self.active_connections.remove(websocket)

    async def broadcast_telemetry(self, message: dict):
        # Gửi đồng thời một event cho snapshot các kết nối đang hoạt động.
        # Snapshot tách khỏi list gốc vì các kết nối lỗi có thể bị xóa sau gather.
        connections = list(self.active_connections)
        # Không tạo coroutine/gather khi chưa có frontend kết nối.
        if not connections:
            return

        # Gửi đồng thời để một socket chậm không làm tăng độ trễ tuyến tính cho
        # tất cả socket phía sau. Timeout giới hạn thời gian giữ worker MQTT.
        delivered = await asyncio.gather(
            *(self._send(connection, message) for connection in connections)
        )
        # Kết quả giữ cùng thứ tự với connections nên zip ánh xạ đúng từng socket.
        for connection, succeeded in zip(connections, delivered):
            # Socket lỗi hoặc quá timeout bị loại để các lần broadcast sau không lặp lỗi.
            if not succeeded:
                self.disconnect(connection)

    async def _send(self, connection: WebSocket, message: dict) -> bool:
        # Giới hạn thời gian gửi và trả kết quả để caller loại socket lỗi/chậm.
        try:
            # send_json chịu trách nhiệm serialize dict thành frame JSON; timeout bao
            # toàn bộ thời gian chờ socket ghi dữ liệu.
            await asyncio.wait_for(
                connection.send_json(message),
                timeout=settings.realtime_send_timeout_seconds,
            )
            return True
        except Exception:
            # Không phát exception của một client lên pipeline MQTT; False báo caller dọn socket.
            return False


# Singleton dùng chung cho MQTT, presence, settings và endpoint WebSocket.
realtime_service = RealtimeService()
