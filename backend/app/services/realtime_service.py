from fastapi import WebSocket
from typing import List, Dict

# Dịch vụ thời gian thực (Real-time) quản lý các kết nối WebSockets.
# Đảm nhiệm việc đẩy (push/broadcast) dữ liệu mới nhất từ Backend xuống tất cả các Client (Flutter App) đang trực tuyến.
class RealtimeService:
    def __init__(self):
        # Danh sách lưu trữ tất cả các kết nối (socket) hiện đang mở
        self.active_connections: List[WebSocket] = []

    async def connect(self, websocket: WebSocket):
        """
        Chấp nhận một kết nối WebSocket mới từ Client và thêm vào danh sách theo dõi.
        """
        await websocket.accept()
        self.active_connections.append(websocket)

    def disconnect(self, websocket: WebSocket):
        """
        Xóa kết nối khỏi danh sách khi Client chủ động ngắt kết nối hoặc gặp lỗi.
        """
        if websocket in self.active_connections:
            self.active_connections.remove(websocket)

    async def broadcast_telemetry(self, message: dict):
        """
        Gửi dữ liệu (dạng JSON) tới toàn bộ các Client đang trực tuyến.
        Nếu có Client nào gặp sự cố (ví dụ: mất mạng giữa chừng), hệ thống sẽ tự động ngắt kết nối đó.
        """
        for connection in self.active_connections:
            try:
                await connection.send_json(message)
            except Exception:
                self.disconnect(connection)

# Khởi tạo đối tượng Singleton dùng chung trên toàn hệ thống
realtime_service = RealtimeService()
