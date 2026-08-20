import asyncio
import json

from fastapi import APIRouter, HTTPException, WebSocket, WebSocketDisconnect

from app.api.auth_dependencies import authenticate_websocket_token
from app.core.config import settings
from app.services.realtime_service import realtime_service


router = APIRouter()


@router.websocket("/ws")
async def websocket_endpoint(websocket: WebSocket):
    await websocket.accept()
    token: str | None = None
    try:
        if settings.auth_required:
            # Khóa đăng nhập được gửi trong bản tin đầu tiên thay vì query URL để
            # JWT lâu dài không xuất hiện trong access log của reverse proxy.
            try:
                raw_auth = await asyncio.wait_for(
                    websocket.receive_text(),
                    timeout=10,
                )
                auth_payload = json.loads(raw_auth)
                if not isinstance(auth_payload, dict) or auth_payload.get("type") != "AUTH":
                    raise ValueError("Bản tin xác thực WebSocket không hợp lệ")
                token_value = auth_payload.get("access_token")
                token = token_value.strip() if isinstance(token_value, str) else None
                await authenticate_websocket_token(token)
            except (asyncio.TimeoutError, json.JSONDecodeError, ValueError, HTTPException):
                await websocket.close(code=4401)
                return
            await websocket.send_json({"type": "AUTH_OK"})

        await realtime_service.connect(websocket, already_accepted=True)
        while True:
            data = await websocket.receive_text()
            try:
                payload = json.loads(data)
            except json.JSONDecodeError:
                continue
            if payload.get("type") == "PING":
                # Heartbeat đồng thời xác thực lại token_version. Kết nối trên máy
                # cũ bị đóng ở nhịp kế tiếp sau khi mật khẩu hoặc quyền thay đổi.
                if settings.auth_required:
                    try:
                        await authenticate_websocket_token(token)
                    except HTTPException:
                        await websocket.close(code=4401)
                        return
                await websocket.send_json({"type": "PONG"})
    except WebSocketDisconnect:
        pass
    finally:
        realtime_service.disconnect(websocket)
