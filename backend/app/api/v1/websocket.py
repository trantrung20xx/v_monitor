from fastapi import APIRouter, WebSocket, WebSocketDisconnect
from app.services.realtime_service import realtime_service

router = APIRouter()

@router.websocket("/ws")
async def websocket_endpoint(websocket: WebSocket):
    await realtime_service.connect(websocket)
    try:
        while True:
            # We just keep connection open, optionally receive ping/pong
            data = await websocket.receive_text()
    except WebSocketDisconnect:
        realtime_service.disconnect(websocket)
