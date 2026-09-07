"""Phát lại sự kiện đã commit, không giữ kết nối DB khi đợi WebSocket."""
import asyncio
from datetime import datetime, timedelta, timezone
import logging
import uuid

from sqlalchemy import delete, select, update

from app.core.config import settings
from app.core.database import AsyncSessionLocal
from app.models.realtime_outbox import RealtimeOutbox
from app.services.realtime_service import realtime_service

logger = logging.getLogger(__name__)


def stage_device_events(db, events):
    """Gọi trước commit nghiệp vụ; rollback cũng hủy thông báo tương ứng."""
    # Chuẩn bị thông báo trong cùng giao dịch đang ghi GPS hoặc trạng thái thiết bị.
    # Hàm chỉ thêm vào session; TrackingService/PresenceService mới quyết định lưu:
    # - commit: dữ liệu thiết bị và thông báo cùng được lưu vào DB;
    # - rollback: cả thay đổi dữ liệu và thông báo đều bị hủy.
    # Khi gửi lại, vẫn dùng ID sự kiện cũ để giao diện bỏ qua sự kiện đã nhận.
    for event in events:
        if event.id is None:
            event.id = uuid.uuid4()
        db.add(RealtimeOutbox(payload={
            "type": "DEVICE_EVENT",
            "event": {
                "id": str(event.id), "device_id": str(event.device_id),
                "event_type": event.event_type, "occurred_at": event.occurred_at.isoformat(),
                "source": event.source, "description": event.description,
            },
        }))


class RealtimeOutboxService:
    def __init__(self):
        self._task = None
        self._stop = asyncio.Event()

    async def dispatch_once(self) -> int:
        # Bước 1: tạo mã riêng cho lượt gửi này để biết nó đang phụ trách dòng nào.
        token = uuid.uuid4()
        now = datetime.now(timezone.utc)
        lease = timedelta(seconds=settings.realtime_send_timeout_seconds * 3 + 10)
        # Bước 2: tạm giữ các dòng trong một khoảng thời gian, gọi là lease.
        # Ví dụ với cấu hình mặc định: nhận lúc 10:00:00 -> giữ tới 10:00:25.
        # Trước mốc đó, lượt khác bỏ qua các dòng này. Nếu chương trình dừng đột ngột,
        # dữ liệu vẫn còn trong DB; bộ phát chạy lại được nhận chúng từ 10:00:25.
        # 25 giây được tính từ timeout gửi: 3 * 5 + 10, không phải thời gian retry 2s.
        async with AsyncSessionLocal() as db:
            # Chọn tối đa 250 dòng đã tới giờ gửi (theo cấu hình realtime_batch_size).
            # SKIP LOCKED: gặp dòng đang được giao dịch khác giữ thì bỏ qua để lấy dòng
            # khác. Việc chọn dòng và gắn mã lượt gửi nằm trong cùng giao dịch DB.
            ids = select(RealtimeOutbox.id).where(RealtimeOutbox.available_at <= now).order_by(
                RealtimeOutbox.created_at, RealtimeOutbox.id
            ).limit(settings.realtime_batch_size).with_for_update(skip_locked=True)
            result = await db.execute(update(RealtimeOutbox).where(RealtimeOutbox.id.in_(ids)).values(
                claim_token=token, available_at=now + lease
            ).returning(RealtimeOutbox.id, RealtimeOutbox.payload, RealtimeOutbox.created_at))
            rows = sorted(result.all(), key=lambda row: (row.created_at, str(row.id)))
            await db.commit()
        # Bước 3: đóng session, trả kết nối DB về kho kết nối dùng chung rồi mới gửi.
        # Dù WebSocket chậm, lượt gửi này cũng không giữ kết nối DB trong lúc chờ.
        if not rows:
            return 0
        delivered = await realtime_service.deliver_events([row.payload for row in rows])
        async with AsyncSessionLocal() as db:
            # Bước 4: mở session mới để ghi kết quả, chỉ tác động dòng còn mang mã
            # của lượt này. Nếu lượt B đã nhận lại dòng sau khi lượt A hết hạn giữ,
            # lượt A hoàn tất muộn cũng không được sửa/xóa dòng đang thuộc lượt B.
            owned = RealtimeOutbox.claim_token == token
            if delivered:
                # Bộ gửi cho phép hoàn tất: xóa bản thông báo chờ gửi trong outbox.
                # Lịch sử sự kiện (device_events) và lịch sử GPS vẫn được giữ lại.
                # Không có client cũng được coi là hoàn tất; xem deliver_events().
                await db.execute(delete(RealtimeOutbox).where(owned))
            else:
                # Có socket gửi lỗi hoặc đã hết thời gian chờ: giữ nội dung thông báo,
                # bỏ mã lượt gửi và hẹn lần thử tiếp theo (mặc định sau 2 giây).
                # Ví dụ lỗi lúc 10:00:03 -> được thử lại từ 10:00:05.
                # Mỗi lần lỗi đều hẹn như vậy; hiện chưa giới hạn số lần thử.
                # Nếu client A đã nhận nhưng B lỗi, A có thể nhận lại cùng ID sự kiện.
                await db.execute(update(RealtimeOutbox).where(owned).values(
                    claim_token=None,
                    available_at=datetime.now(timezone.utc) + timedelta(seconds=settings.realtime_outbox_retry_seconds),
                ))
            await db.commit()
        return len(rows)

    async def _run(self):
        # Vòng gửi chạy nền, tách khỏi worker đang ghi GPS:
        # - vừa xử lý một lô: kiểm tra lô tiếp theo ngay;
        # - chưa có dòng tới giờ gửi hoặc gặp lỗi: chờ mặc định 0,25s rồi kiểm tra lại.
        # Lưu ý: nếu lỗi xảy ra trước khi ghi được lịch thử lại, dòng có thể vẫn đang
        # bị giữ tới hết lease. Khi đó phải chờ hết hạn giữ, không chỉ chờ 2 giây.
        while not self._stop.is_set():
            try:
                count = await self.dispatch_once()
                if count and not self._stop.is_set():
                    continue
            except Exception:
                logger.exception("Không thể phát outbox realtime; sẽ thử lại")
            try:
                await asyncio.wait_for(self._stop.wait(), settings.realtime_outbox_poll_seconds)
            except asyncio.TimeoutError:
                pass

    async def start(self):
        if self._task and not self._task.done():
            return
        self._stop.clear()
        self._task = asyncio.create_task(self._run(), name="realtime-outbox")

    async def stop(self):
        self._stop.set()
        if self._task:
            self._task.cancel()
            await asyncio.gather(self._task, return_exceptions=True)
            self._task = None


realtime_outbox_service = RealtimeOutboxService()
