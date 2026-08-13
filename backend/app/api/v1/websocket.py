from fastapi import APIRouter, WebSocket, WebSocketDisconnect
from app.services.realtime_service import realtime_service

router = APIRouter()

@router.websocket("/ws")
async def websocket_endpoint(websocket: WebSocket):
    await realtime_service.connect(websocket) # Chấp nhận kết nối và đăng ký client realtime
    try:
        while True:
            # Giữ kết nối WebSocket luôn mở và chờ dữ liệu từ client
            data = await websocket.receive_text()
    except WebSocketDisconnect:
        realtime_service.disconnect(websocket) # Xóa client khi kết nối bị ngắt
