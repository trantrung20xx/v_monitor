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


SYSTEM_SETTINGS_ROW_ID = 1
SYSTEM_SETTINGS_AUDIT_ID = uuid.UUID("00000000-0000-0000-0000-000000000001")


@dataclass(frozen=True)
class RuntimeSystemSettings:
    offline_timeout_seconds: int
    movement_threshold_mps: float
    default_gap_threshold_seconds: int

    @classmethod
    def from_model(cls, model: SystemSetting) -> "RuntimeSystemSettings":
        return cls(
            offline_timeout_seconds=model.offline_timeout_seconds,
            movement_threshold_mps=model.movement_threshold_mps,
            default_gap_threshold_seconds=model.default_gap_threshold_seconds,
        )


class SystemSettingsService:
    """Đọc cấu hình dùng chung và giữ cache nhỏ cho luồng telemetry tần suất cao."""

    def __init__(self) -> None:
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
        query = select(SystemSetting).where(
            SystemSetting.id == SYSTEM_SETTINGS_ROW_ID
        )
        if for_update:
            query = query.with_for_update()
        result = await db.execute(query)
        model = result.scalar_one_or_none()
        if model is not None:
            return model

        model = self._default_model()
        db.add(model)
        await db.commit()
        await db.refresh(model)
        return model

    async def get_settings(self, db: AsyncSession) -> SystemSetting:
        # Tuần tự hóa lần khởi tạo hiếm hoi để hai request đầu tiên không cùng
        # chèn dòng singleton khi database bị thiếu dòng cấu hình.
        async with self._cache_lock:
            model = await self._get_or_create(db)
            self._cached = RuntimeSystemSettings.from_model(model)
            return model

    async def get_runtime_settings(self) -> RuntimeSystemSettings:
        cached = self._cached
        if cached is not None:
            return cached

        async with self._cache_lock:
            if self._cached is not None:
                return self._cached
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
        async with self._cache_lock:
            model = await self._get_or_create(db, for_update=True)
            old_value = asdict(RuntimeSystemSettings.from_model(model))

            for field_name, value in settings_in.model_dump(
                exclude_unset=True
            ).items():
                setattr(model, field_name, value)
            model.updated_by = actor.id
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
            await db.commit()
            await db.refresh(model)
            self._cached = RuntimeSystemSettings.from_model(model)
            return model

    def invalidate_cache(self) -> None:
        self._cached = None


system_settings_service = SystemSettingsService()
