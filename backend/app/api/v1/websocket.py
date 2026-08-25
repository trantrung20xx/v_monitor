# Kênh realtime của frontend: xác thực bằng bản tin AUTH đầu tiên, sau đó giữ
# kết nối để nhận DEVICE_UPDATE/DEVICE_EVENT và phản hồi heartbeat PING bằng PONG.
import asyncio
import json

from fastapi import APIRouter, HTTPException, WebSocket, WebSocketDisconnect

from app.api.auth_dependencies import authenticate_websocket_token
from app.core.config import settings
from app.services.realtime_service import realtime_service


router = APIRouter()


@router.websocket("/ws")
async def websocket_endpoint(websocket: WebSocket):
    # WebSocket phải được accept trước khi nhận AUTH hoặc gửi mã đóng riêng 4401.
    # Socket chỉ được thêm vào registry broadcast sau khi xác thực hoàn tất.
    await websocket.accept()
    token: str | None = None
    try:
        # Nhánh AUTH chỉ tồn tại khi cấu hình backend yêu cầu đăng nhập.
        if settings.auth_required:
            # Khóa đăng nhập được gửi trong bản tin đầu tiên thay vì query URL để
            # JWT lâu dài không xuất hiện trong access log của reverse proxy.
            try:
                # Giới hạn 10 giây tránh kết nối mở nhưng không gửi AUTH chiếm tài nguyên.
                raw_auth = await asyncio.wait_for(
                    websocket.receive_text(),
                    timeout=10,
                )
                auth_payload = json.loads(raw_auth)
                # Frame đầu phải là object AUTH; các loại frame khác không được xử lý trước xác thực.
                if not isinstance(auth_payload, dict) or auth_payload.get("type") != "AUTH":
                    raise ValueError("Bản tin xác thực WebSocket không hợp lệ")
                token_value = auth_payload.get("access_token")
                # Chỉ chấp nhận token dạng chuỗi và loại khoảng trắng do quá trình lưu/đọc.
                token = token_value.strip() if isinstance(token_value, str) else None
                await authenticate_websocket_token(token)
            except (asyncio.TimeoutError, json.JSONDecodeError, ValueError, HTTPException):
                # Mã 4401 là mã đóng ứng dụng quy ước cho lỗi xác thực WebSocket.
                await websocket.close(code=4401)
                return
            # Chỉ báo AUTH_OK sau khi chữ ký, tài khoản active và token_version đều hợp lệ.
            await websocket.send_json({"type": "AUTH_OK"})

        # Từ thời điểm này socket mới được nhận các event nghiệp vụ broadcast.
        await realtime_service.connect(websocket, already_accepted=True)
        while True:
            # Chiều client → server hiện chỉ dùng cho heartbeat. Dữ liệu thiết bị
            # luôn đi qua MQTT/REST, không được nhập qua kết nối frontend này.
            data = await websocket.receive_text()
            try:
                payload = json.loads(data)
            except json.JSONDecodeError:
                # Frame không phải JSON không ảnh hưởng kết nối và không được phát lại.
                continue
            # Các loại message chưa hỗ trợ được bỏ qua; chỉ PING tạo phản hồi PONG.
            if payload.get("type") == "PING":
                # Heartbeat đồng thời xác thực lại token_version. Kết nối trên máy
                # cũ bị đóng ở nhịp kế tiếp sau khi mật khẩu hoặc quyền thay đổi.
                if settings.auth_required:
                    try:
                        await authenticate_websocket_token(token)
                    except HTTPException:
                        # Token đã bị thu hồi trong lúc socket mở nên kết nối phải kết thúc ngay.
                        await websocket.close(code=4401)
                        return
                # PONG xác nhận cả kết nối vật lý và phiên đăng nhập vẫn còn sử dụng được.
                await websocket.send_json({"type": "PONG"})
    except WebSocketDisconnect:
        # Ngắt mạng hoặc đóng tab là vòng đời bình thường, không ghi thành lỗi server.
        pass
    finally:
        # Gỡ registry ở mọi nhánh để broadcast sau đó không tiếp tục gửi vào socket cũ.
        realtime_service.disconnect(websocket)
