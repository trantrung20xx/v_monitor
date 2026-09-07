"""Gộp snapshot và gửi bằng task riêng; luồng ghi DB không đợi socket."""
import asyncio
from collections import OrderedDict
from dataclasses import dataclass
import json
import logging
import uuid

from fastapi import WebSocket
from sqlalchemy import select
from sqlalchemy.orm import selectinload

from app.core.config import settings
from app.core.database import AsyncSessionLocal
from app.models.device import Device
from app.schemas.device import DeviceResponse
from app.services.device_service import DeviceService

logger = logging.getLogger(__name__)


@dataclass
class _Delivery:
    # Một phần tử hàng chờ chứa một nhóm thông báo, gọi là lô.
    # Client mới nhận lô dưới dạng một bản tin gộp; client cũ nhận từng bản tin riêng.
    # completed trả kết quả gửi phía server. True chưa chứng minh trình duyệt đã
    # xử lý hoặc hiển thị dữ liệu; muốn lấy bù sau mất kết nối, client phải gọi REST.
    frames: tuple[str, ...]
    completed: asyncio.Future | None = None


class RealtimeService:
    def __init__(self):
        self.active_connections: list[WebSocket] = []
        self._queues: dict[WebSocket, asyncio.Queue] = {}
        self._senders: dict[WebSocket, asyncio.Task] = {}
        self._batch_connections: set[WebSocket] = set()
        self._closing: set[asyncio.Task] = set()
        self._dirty: OrderedDict[uuid.UUID, None] = OrderedDict()
        self._resync_required = False
        self._task: asyncio.Task | None = None
        self._stop = asyncio.Event()

    async def connect(self, websocket: WebSocket, *, already_accepted: bool = False, supports_batches: bool = False):
        if not already_accepted:
            await websocket.accept()
        if websocket in self._queues:
            return
        self.active_connections.append(websocket)
        # Client A có hàng chờ và tác vụ gửi A; client B có hàng chờ và tác vụ gửi B.
        # A gửi chậm thì B vẫn gửi tiếp. Mỗi hàng chờ chứa tối đa 32 lô theo mặc định,
        # ngoài ra có thể có một lô đã lấy ra và đang gửi.
        # Hàng chờ này nằm trong RAM, mất khi chương trình dừng. Thông báo cần phục hồi
        # được giữ riêng trong bảng outbox của PostgreSQL cho tới khi được phép dọn.
        queue = asyncio.Queue(maxsize=settings.realtime_client_queue_size)
        self._queues[websocket] = queue
        self.set_batch_support(websocket, supports_batches)
        self._senders[websocket] = asyncio.create_task(self._send_loop(websocket, queue))

    def set_batch_support(self, websocket: WebSocket, enabled: bool):
        if enabled and websocket in self._queues:
            self._batch_connections.add(websocket)
        else:
            self._batch_connections.discard(websocket)

    def disconnect(self, websocket: WebSocket):
        self._batch_connections.discard(websocket)
        if websocket in self.active_connections:
            self.active_connections.remove(websocket)
        queue = self._queues.pop(websocket, None)
        task = self._senders.pop(websocket, None)
        if task and task is not asyncio.current_task():
            task.cancel()
        if queue:
            # Socket đã ngắt: lấy hết lô còn chờ ra và báo gửi thất bại.
            # Nhờ đó bộ phát outbox biết rằng nó cần giữ thông báo để thử lại.
            while not queue.empty():
                delivery = queue.get_nowait()
                self._finish(delivery, False)
                queue.task_done()

    @staticmethod
    def _finish(delivery: _Delivery, success: bool):
        if delivery.completed is not None and not delivery.completed.done():
            delivery.completed.set_result(success)

    def _evict(self, websocket: WebSocket):
        # Ngừng gửi cho client chậm/lỗi: bỏ khỏi danh sách, hủy tác vụ và dọn hàng chờ.
        # Việc đóng kết nối chạy nền vì thao tác đóng cũng có thể phải đợi mạng.
        self.disconnect(websocket)
        task = asyncio.create_task(self._close_socket(websocket))
        self._closing.add(task)
        task.add_done_callback(self._closing.discard)

    async def _close_socket(self, websocket: WebSocket):
        # Gửi mã 1013 để báo client thử kết nối lại sau. Chỉ chờ đóng trong thời gian
        # cấu hình cho phép; kết nối bị treo không được làm tác vụ này đợi mãi.
        # Khi kết nối lại, client mới tải trạng thái/lịch sử còn thiếu qua REST.
        try:
            await asyncio.wait_for(websocket.close(code=1013), settings.realtime_send_timeout_seconds)
        except Exception:
            pass

    async def _send_loop(self, websocket: WebSocket, queue: asyncio.Queue):
        while True:
            delivery = await queue.get()
            try:
                # Bắt đầu đếm timeout khi lấy lô ra gửi, không tính thời gian xếp hàng.
                # Ví dụ mặc định: A bắt đầu lúc giây 0 thì hạn là giây 5; B bắt đầu
                # lúc giây 2 thì hạn là giây 7. Hai client cùng dùng mức 5s trong cấu
                # hình nhưng đếm riêng. Client cũ phải gửi hết mọi bản tin của lô
                # trong 5s này, không được thêm 5s cho mỗi bản tin.
                await asyncio.wait_for(self._send_frames(websocket, delivery.frames), settings.realtime_send_timeout_seconds)
                self._finish(delivery, True)
            except asyncio.CancelledError:
                self._finish(delivery, False)
                raise
            except Exception:
                # Gửi lỗi hoặc quá hạn: báo thất bại và ngắt riêng client này.
                # Các client khác có tác vụ gửi riêng nên vẫn tiếp tục.
                self._finish(delivery, False)
                self._evict(websocket)
                return
            finally:
                queue.task_done()

    @staticmethod
    async def _send_frames(websocket, frames):
        for frame in frames:
            await websocket.send_text(frame)

    def _enqueue(self, message: dict, *, acknowledge: bool = False) -> list[asyncio.Future]:
        # Chuyển dữ liệu thành chuỗi JSON dùng chung cho các client cùng định dạng.
        # Nếu có client cũ, tạo thêm bộ bản tin riêng tương thích với client cũ.
        encode = lambda item: json.dumps(item, ensure_ascii=False, separators=(",", ":"))
        encoded = (encode(message),)
        legacy = None
        completions = []
        for connection, queue in list(self._queues.items()):
            completed = asyncio.get_running_loop().create_future() if acknowledge else None
            frames = encoded
            if connection not in self._batch_connections:
                if legacy is None:
                    if message.get("type") == "DEVICE_UPDATES":
                        legacy = tuple(encode({"type": "DEVICE_UPDATE", "device": d}) for d in message["devices"])
                    elif message.get("type") == "REALTIME_BATCH":
                        legacy = tuple(encode(item) for item in message["messages"])
                    else:
                        legacy = encoded
                frames = legacy
            delivery = _Delivery(frames, completed)
            if completed is not None:
                completions.append(completed)
            try:
                # Đặt lô vào hàng chờ rồi trả về ngay; tác vụ gửi sẽ lấy ra sau.
                # put_nowait không chờ có chỗ trống và cũng không chờ mạng gửi xong.
                queue.put_nowait(delivery)
            except asyncio.QueueFull:
                # Hàng chờ đầy nghĩa là client chưa theo kịp: báo thất bại và ngắt
                # client đó, thay vì tiếp tục tích lũy lô trong RAM. Nếu là sự kiện
                # outbox, thông báo trong DB vẫn còn để bộ phát quyết định gửi lại.
                self._finish(delivery, False)
                self._evict(connection)
        return completions

    async def broadcast_telemetry(self, message: dict):
        # API cũ hoàn tất ngay sau enqueue, không chờ mạng.
        if message.get("type") == "DEVICE_UPDATE":
            self.notify_device(message["device"]["id"])
        else:
            if message.get("type") == "DEVICE_DELETED":
                self._dirty.pop(uuid.UUID(str(message["device_id"])), None)
            self._enqueue(message)

    def notify_device(self, device_id: uuid.UUID | str):
        if not self.active_connections:
            return
        device_id = uuid.UUID(str(device_id))
        if device_id in self._dirty:
            return
        if len(self._dirty) >= settings.realtime_pending_device_limit:
            self._resync_required = True
            return
        self._dirty[device_id] = None

    async def deliver_events(self, messages: list[dict]) -> bool:
        # Đưa cùng lô sự kiện vào hàng chờ của các client và đợi kết quả gửi.
        # Chỉ tác vụ phát outbox đợi ở đây; worker ghi GPS tiếp tục làm việc của nó.
        # Các client gửi đồng thời: có 10 client không có nghĩa là chờ 10 * 5 giây.
        completions = self._enqueue({"type": "REALTIME_BATCH", "messages": messages}, acknowledge=True)
        if not completions:
            # Không có client để gửi: cho phép dọn thông báo trong outbox.
            # Sự kiện và GPS vẫn lưu trong DB để client kết nối sau tải bằng REST.
            return True
        try:
            # Bộ phát chỉ chờ tối đa 2 * timeout gửi, mặc định 10s cho cả lượt này.
            # Khác với 5s trong _send_loop, 10s có tính cả thời gian chờ trong queue.
            # Tất cả báo True -> hoàn tất. Có False hoặc hết 10s -> giữ để thử lại.
            # Chờ quá hạn ở đây không tự ngắt socket; _send_loop/queue đầy xử lý việc
            # ngắt. Một số client có thể đã nhận, nên lần thử sau có thể gửi trùng ID.
            return all(await asyncio.wait_for(
                asyncio.gather(*completions), settings.realtime_send_timeout_seconds * 2
            ))
        except asyncio.TimeoutError:
            return False

    async def flush_devices(self):
        if not self.active_connections:
            self._dirty.clear()
            self._resync_required = False
            return
        if self._resync_required:
            self._resync_required = False
            self._enqueue({"type": "RESYNC_REQUIRED"})
        ids = []
        while self._dirty and len(ids) < settings.realtime_batch_size:
            ids.append(self._dirty.popitem(last=False)[0])
        if not ids:
            return
        try:
            async with AsyncSessionLocal() as db:
                result = await db.execute(
                    select(Device).options(selectinload(Device.latest_state)).where(Device.id.in_(ids))
                )
                devices = [
                    DeviceResponse.model_validate(DeviceService._format_device(d)).model_dump(mode="json")
                    for d in result.scalars()
                ]
            # Session đóng trước khi đưa snapshot vào hàng chờ socket.
            if devices:
                self._enqueue({"type": "DEVICE_UPDATES", "devices": devices})
        except Exception:
            for device_id in ids:
                self.notify_device(device_id)
            raise

    async def _run(self):
        while not self._stop.is_set():
            try:
                remaining = len(self._dirty)
                while remaining > 0 and not self._stop.is_set():
                    await self.flush_devices()
                    remaining -= settings.realtime_batch_size
                if self._resync_required:
                    await self.flush_devices()
            except Exception:
                logger.exception("Không thể tạo snapshot realtime; sẽ thử lại")
            try:
                await asyncio.wait_for(self._stop.wait(), settings.realtime_flush_interval_seconds)
            except asyncio.TimeoutError:
                pass

    async def start(self):
        if self._task and not self._task.done():
            return
        self._stop.clear()
        self._task = asyncio.create_task(self._run(), name="realtime-snapshots")

    async def stop(self):
        self._stop.set()
        if self._task:
            self._task.cancel()
            await asyncio.gather(self._task, return_exceptions=True)
            self._task = None
        senders = list(self._senders.values())
        for connection in list(self.active_connections):
            self._evict(connection)
        await asyncio.gather(*senders, *list(self._closing), return_exceptions=True)
        self._dirty.clear()


realtime_service = RealtimeService()
