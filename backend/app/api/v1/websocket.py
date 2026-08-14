import json

from fastapi import APIRouter, WebSocket, WebSocketDisconnect

from app.services.realtime_service import realtime_service


router = APIRouter()


@router.websocket("/ws")
async def websocket_endpoint(websocket: WebSocket):
    await realtime_service.connect(websocket)
    try:
        while True:
            data = await websocket.receive_text()
            try:
                payload = json.loads(data)
            except json.JSONDecodeError:
                continue

            if payload.get("type") == "PING":
                await websocket.send_json({"type": "PONG"})
    except WebSocketDisconnect:
        realtime_service.disconnect(websocket)
    except Exception:
        realtime_service.disconnect(websocket)
