# Nghiệp vụ danh mục thiết bị: truy vấn kèm latest state, tạo/sửa thiết bị và tổng hợp
# thiết bị MQTT lạ. Service trả entity/schema, router chỉ chịu trách nhiệm HTTP.
from datetime import datetime, timezone
from typing import List, Optional
import uuid

from sqlalchemy import delete, exists, select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload

from app.models.device import Device
from app.models.audit_log import AuditLog
from app.models.device_latest_state import DeviceLatestState
from app.models.mqtt_device_sighting import MqttDeviceSighting
from app.schemas.device import DeviceCreate, DeviceUpdate


class DeviceService:
    # Đọc và thay đổi danh mục thiết bị đã được quản trị viên chấp thuận.

    @staticmethod
    async def get_devices(
        db: AsyncSession,
        skip: int = 0,
        limit: int = 100,
    ) -> List[dict]:
        # Lấy trang thiết bị kèm latest state, sắp theo mã để kết quả ổn định.
        result = await db.execute(
            select(Device)
            .options(selectinload(Device.latest_state))
            .order_by(Device.device_code.asc())
            .offset(skip)
            .limit(limit)
        )
        # Mỗi ORM Device được chuyển thành payload phẳng để router có thể validate
        # trực tiếp bằng DeviceResponse.
        return [DeviceService._format_device(device) for device in result.scalars()]

    @staticmethod
    async def get_device(
        db: AsyncSession,
        device_id: uuid.UUID,
    ) -> Optional[dict]:
        # Lấy một thiết bị kèm trạng thái hiện tại; trả None khi không tồn tại.
        result = await db.execute(
            select(Device)
            .options(selectinload(Device.latest_state))
            .where(Device.id == device_id)
        )
        device = result.scalar_one_or_none()
        # None được giữ để router phân biệt và trả HTTP 404.
        return DeviceService._format_device(device) if device else None

    @staticmethod
    def _format_device(device: Device) -> dict:
        # Ghép hồ sơ quản lý và latest state thành hợp đồng API phẳng.
        # status/is_enabled thuộc quản trị; is_online/tọa độ/pin thuộc dữ liệu vận hành.
        # Giữ hai nhóm riêng về nguồn dù API trả chúng trong cùng một object.
        data = {
            "id": str(device.id),
            "device_code": device.device_code,
            "name": device.name,
            "device_type": device.device_type,
            "serial_number": device.serial_number,
            "manufacturer": device.manufacturer,
            "model": device.model,
            "firmware_version": device.firmware_version,
            "status": device.status,
            "is_enabled": device.is_enabled,
            "metadata_json": device.metadata_json,
            "created_at": device.created_at.isoformat() if device.created_at else None,
            "updated_at": device.updated_at.isoformat() if device.updated_at else None,
        }
        # latest_state có thể thiếu ở dữ liệu cũ; khi thiếu, các trường realtime
        # không được giả lập và frontend nhận giá trị mặc định từ model của nó.
        if device.latest_state:
            state = device.latest_state
            data.update(
                {
                    "is_online": state.is_online,
                    "current_latitude": state.current_latitude,
                    "current_longitude": state.current_longitude,
                    "current_altitude_m": state.current_altitude_m,
                    "current_speed_mps": state.current_speed_mps,
                    "current_heading_deg": state.current_heading_deg,
                    "battery_pct": state.battery_pct,
                    "last_seen_at": state.last_seen_at.isoformat()
                    if state.last_seen_at
                    else None,
                    "latest_measured_at": state.latest_measured_at.isoformat()
                    if state.latest_measured_at
                    else None,
                }
            )
        return data

    @staticmethod
    async def create_device(
        db: AsyncSession,
        device_in: DeviceCreate,
        *,
        actor_user_id: uuid.UUID | None = None,
    ) -> dict:
        # Đăng ký thiết bị, tạo latest state rỗng và ghi audit trong một transaction.
        # Pydantic schema đã giới hạn/chuẩn hóa trường; ORM nhận đúng hồ sơ quản trị,
        # không nhận các trường latest state do client tự khai báo.
        device = Device(**device_in.model_dump())
        db.add(device)
        # Flush lấy UUID và kiểm tra constraint trong transaction nhưng chưa commit.
        await db.flush()

        # Mã vừa được quản trị viên đăng ký không còn nằm trong danh sách chờ.
        # Lệnh xóa không lỗi nếu mã chưa từng xuất hiện ở MQTT.
        await db.execute(
            delete(MqttDeviceSighting).where(
                MqttDeviceSighting.device_code == device.device_code
            )
        )

        # Tạo trạng thái rỗng trong cùng giao dịch để không có thiết bị dở dang.
        latest_state = DeviceLatestState(device_id=device.id)
        db.add(latest_state)
        db.add(
            AuditLog(
                actor_user_id=actor_user_id,
                action="DEVICE_CREATED",
                entity_type="device",
                entity_id=device.id,
                occurred_at=datetime.now(timezone.utc),
                new_value={
                    "device_code": device.device_code,
                    "name": device.name,
                    "device_type": device.device_type.value,
                    "is_enabled": device.is_enabled,
                },
            )
        )
        # Một commit bao gồm hồ sơ, trạng thái rỗng, xóa sighting và audit. Nếu bất kỳ
        # bước nào lỗi, caller rollback và không để lại thiết bị đăng ký dở dang.
        await db.commit()
        # Refresh lấy timestamp/default do PostgreSQL sinh.
        await db.refresh(device)

        # Gắn latest_state đã tạo để formatter không cần một truy vấn eager-load mới.
        device.latest_state = latest_state
        return DeviceService._format_device(device)

    @staticmethod
    async def update_device(
        db: AsyncSession,
        device_id: uuid.UUID,
        device_in: DeviceUpdate,
        *,
        actor_user_id: uuid.UUID | None = None,
    ) -> Optional[dict]:
        # Chỉ cập nhật trường client gửi lên, khóa dòng để tránh hai lần sửa đè nhau.
        result = await db.execute(
            select(Device)
            .options(selectinload(Device.latest_state))
            .where(Device.id == device_id)
            .with_for_update()
        )
        device = result.scalar_one_or_none()
        # Không tạo mới ngầm trong PATCH; router sẽ chuyển None thành 404.
        if device is None:
            return None

        # `exclude_unset` phân biệt trường không gửi với trường chủ động gửi null,
        # đúng ngữ nghĩa PATCH và tránh ghi đè dữ liệu ngoài ý muốn.
        changes = device_in.model_dump(exclude_unset=True)
        # old_value/new_value chỉ chứa dữ liệu quản trị cần truy vết, không sao chép
        # latest state thay đổi liên tục vào audit log.
        old_value = {
            "device_code": device.device_code,
            "name": device.name,
            "device_type": device.device_type.value,
            "serial_number": device.serial_number,
            "manufacturer": device.manufacturer,
            "model": device.model,
            "firmware_version": device.firmware_version,
            "is_enabled": device.is_enabled,
        }
        # setattr chỉ chạy trên các trường schema cho phép, không nhận tên trường tùy ý.
        for field_name, value in changes.items():
            setattr(device, field_name, value)

        # Ngắt trạng thái online ngay khi quản trị viên khóa nhận telemetry.
        # Việc bật lại không tự đánh dấu online; phải chờ gói thật từ thiết bị.
        if changes.get("is_enabled") is False and device.latest_state is not None:
            device.latest_state.is_online = False

        # Chỉ cần dọn sighting khi mã thiết bị thực sự nằm trong payload PATCH.
        if "device_code" in changes:
            # Nếu mã mới từng xuất hiện ở MQTT khi chưa đăng ký, xóa bản chờ tương ứng.
            await db.execute(
                delete(MqttDeviceSighting).where(
                    MqttDeviceSighting.device_code == device.device_code
                )
            )

        db.add(
            AuditLog(
                actor_user_id=actor_user_id,
                action="DEVICE_UPDATED",
                entity_type="device",
                entity_id=device.id,
                occurred_at=datetime.now(timezone.utc),
                old_value=old_value,
                new_value={
                    "device_code": device.device_code,
                    "name": device.name,
                    "device_type": device.device_type.value,
                    "serial_number": device.serial_number,
                    "manufacturer": device.manufacturer,
                    "model": device.model,
                    "firmware_version": device.firmware_version,
                    "is_enabled": device.is_enabled,
                },
            )
        )
        # Commit hồ sơ, latest state khi khóa và audit như một thay đổi nguyên tử.
        await db.commit()
        await db.refresh(device)
        return DeviceService._format_device(device)

    @staticmethod
    async def get_mqtt_sightings(
        db: AsyncSession,
        *,
        skip: int = 0,
        limit: int = 100,
    ) -> list[MqttDeviceSighting]:
        # Lấy các mã MQTT chưa có Device tương ứng, mới thấy gần nhất đứng trước.
        # `NOT EXISTS` lọc động nên sighting của mã vừa đăng ký không xuất hiện ngay
        # cả khi một transaction cũ chưa kịp dọn bản ghi tổng hợp.
        result = await db.execute(
            select(MqttDeviceSighting)
            .where(
                ~exists().where(
                    Device.device_code == MqttDeviceSighting.device_code
                )
            )
            .order_by(MqttDeviceSighting.last_seen_at.desc())
            .offset(skip)
            .limit(limit)
        )
        return list(result.scalars().all())
