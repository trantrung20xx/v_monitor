# Đọc/cập nhật cấu hình vận hành singleton, cache trong bộ nhớ và phát thay đổi realtime.
# Mọi cập nhật khóa bản ghi, ghi audit log rồi mới làm mới cache để tránh trạng thái lệch.
import asyncio
import uuid
from dataclasses import asdict, dataclass
from datetime import datetime, timezone

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.config import settings
from app.core.database import AsyncSessionLocal
from app.models.audit_log import AuditLog
from app.models.system_setting import SystemSetting
from app.models.user_account import UserAccount
from app.schemas.system_settings import SystemSettingsUpdate


# Bảng chỉ có một dòng cố định; audit dùng UUID quy ước vì entity này không có UUID riêng.
SYSTEM_SETTINGS_ROW_ID = 1
SYSTEM_SETTINGS_AUDIT_ID = uuid.UUID("00000000-0000-0000-0000-000000000001")


@dataclass(frozen=True)
class RuntimeSystemSettings:
    # Snapshot bất biến chỉ chứa ba giá trị được đọc thường xuyên trong pipeline:
    # timeout xác định offline, ngưỡng tốc độ xác định di chuyển và khoảng đứt hành trình.
    offline_timeout_seconds: int
    movement_threshold_mps: float
    default_gap_threshold_seconds: int

    @classmethod
    def from_model(cls, model: SystemSetting) -> "RuntimeSystemSettings":
        # Tách snapshot khỏi ORM session để worker dùng an toàn sau khi session đóng.
        return cls(
            offline_timeout_seconds=model.offline_timeout_seconds,
            movement_threshold_mps=model.movement_threshold_mps,
            default_gap_threshold_seconds=model.default_gap_threshold_seconds,
        )


class SystemSettingsService:
    """Đọc cấu hình dùng chung và giữ cache nhỏ cho luồng telemetry tần suất cao."""

    def __init__(self) -> None:
        # Cache giảm truy vấn database trên mỗi gói MQTT; lock bảo vệ lần khởi tạo và
        # cập nhật để các coroutine không quan sát nửa trạng thái cũ, nửa trạng thái mới.
        self._cached: RuntimeSystemSettings | None = None
        self._cache_lock = asyncio.Lock()

    @staticmethod
    def _default_model() -> SystemSetting:
        # Các biến môi trường cũ tiếp tục làm giá trị dự phòng nếu dòng singleton
        # bị thiếu, nhờ đó deployment hiện hữu không đổi hành vi ngoài ý muốn.
        return SystemSetting(
            id=SYSTEM_SETTINGS_ROW_ID,
            offline_timeout_seconds=settings.device_offline_timeout_seconds,
            movement_threshold_mps=0.5,
            default_gap_threshold_seconds=settings.tracking_gap_threshold_seconds,
        )

    async def _get_or_create(
        self,
        db: AsyncSession,
        *,
        for_update: bool = False,
    ) -> SystemSetting:
        # for_update chỉ dùng khi sửa để khóa dòng singleton cho tới lúc commit.
        query = select(SystemSetting).where(
            SystemSetting.id == SYSTEM_SETTINGS_ROW_ID
        )
        # SELECT FOR UPDATE chỉ dùng trong luồng ghi để giữ singleton ổn định tới commit.
        if for_update:
            query = query.with_for_update()
        result = await db.execute(query)
        model = result.scalar_one_or_none()
        # Fast path trả dòng đã tồn tại mà không phát sinh thao tác ghi.
        if model is not None:
            return model

        # Database mới hoặc migration thiếu dữ liệu được tự bổ sung từ cấu hình an toàn.
        model = self._default_model()
        db.add(model)
        # Commit tại đây vì caller cần một dòng thật trước khi có thể khóa/cập nhật.
        await db.commit()
        await db.refresh(model)
        return model

    async def get_settings(self, db: AsyncSession) -> SystemSetting:
        # Trả model ORM cho API quản trị, đồng thời làm nóng cache runtime.
        # Tuần tự hóa lần khởi tạo hiếm hoi để hai request đầu tiên không cùng
        # chèn dòng singleton khi database bị thiếu dòng cấu hình.
        async with self._cache_lock:
            model = await self._get_or_create(db)
            self._cached = RuntimeSystemSettings.from_model(model)
            return model

    async def get_runtime_settings(self) -> RuntimeSystemSettings:
        # Fast path không khóa khi cache đã có; chỉ mở session riêng ở lần đọc đầu.
        cached = self._cached
        # Snapshot frozen có thể trả trực tiếp cho nhiều coroutine đọc đồng thời.
        if cached is not None:
            return cached

        async with self._cache_lock:
            # Kiểm tra lần hai sau khi lấy lock vì coroutine khác có thể vừa nạp cache.
            if self._cached is not None:
                return self._cached
            # Session nội bộ chỉ dùng ở lần cache miss và tự đóng sau khi snapshot được tách.
            async with AsyncSessionLocal() as db:
                model = await self._get_or_create(db)
                self._cached = RuntimeSystemSettings.from_model(model)
                return self._cached

    async def update_settings(
        self,
        db: AsyncSession,
        settings_in: SystemSettingsUpdate,
        *,
        actor: UserAccount,
    ) -> SystemSetting:
        # old/new snapshot giúp audit thể hiện đúng thay đổi nghiệp vụ và không chứa
        # thuộc tính nội bộ của SQLAlchemy.
        async with self._cache_lock:
            # Khóa cả cache và dòng database để hai yêu cầu quản trị không ghi đè nhau.
            model = await self._get_or_create(db, for_update=True)
            old_value = asdict(RuntimeSystemSettings.from_model(model))

            # exclude_unset giữ nguyên trường không có trong PATCH.
            for field_name, value in settings_in.model_dump(
                exclude_unset=True
            ).items():
                setattr(model, field_name, value)
            # updated_by liên kết lần thay đổi với quản trị viên đã xác thực.
            model.updated_by = actor.id
            # Snapshot mới được lấy sau setattr để audit phản ánh giá trị sắp commit.
            new_value = asdict(RuntimeSystemSettings.from_model(model))

            db.add(
                AuditLog(
                    actor_user_id=actor.id,
                    action="SYSTEM_SETTINGS_UPDATED",
                    entity_type="system_settings",
                    entity_id=SYSTEM_SETTINGS_AUDIT_ID,
                    occurred_at=datetime.now(timezone.utc),
                    old_value=old_value,
                    new_value=new_value,
                )
            )
            # Bản ghi cấu hình và audit cùng commit; cache chỉ đổi sau commit thành công.
            await db.commit()
            await db.refresh(model)
            # Cập nhật cache trong cùng lock để reader tiếp theo không nhìn thấy giá trị cũ.
            self._cached = RuntimeSystemSettings.from_model(model)
            return model

    def invalidate_cache(self) -> None:
        # Lần đọc tiếp theo sẽ nạp lại database; không tự thay đổi bản ghi lưu trữ.
        self._cached = None


# Singleton dùng chung giữa API cài đặt, TrackingService và PresenceService.
system_settings_service = SystemSettingsService()
