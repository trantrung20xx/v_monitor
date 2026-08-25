# API theo dõi gồm nhận một mẫu GPS, truy vấn lịch sử theo khoảng thời gian và
# đọc sự kiện thiết bị. TrackingService chịu trách nhiệm thứ tự thời gian và trạng thái mới nhất.
from datetime import datetime
from typing import List, Optional
import uuid

from fastapi import APIRouter, Depends, HTTPException, Query, status
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.auth_dependencies import require_admin_if_enabled, require_viewer_if_enabled
from app.core.database import get_db
from app.models.device import Device
from app.schemas.device import DeviceResponse
from app.schemas.tracking import (
    DeviceEventResponse,
    LocationHistoryResponse,
    LocationSampleCreate,
    LocationSampleResponse,
)
from app.services.device_service import DeviceService
from app.services.realtime_service import realtime_service
from app.services.tracking_service import DeviceNotFoundError, TrackingService


router = APIRouter()


def _event_payload(event) -> dict:
    # Chuẩn hóa model sự kiện thành envelope realtime/REST gọn. Cột riêng được ưu
    # tiên, metadata giữ tương thích với dữ liệu cũ từng lưu source/description trong JSON.
    metadata = event.metadata_ or {}
    # Chuyển UUID/datetime sang chuỗi để cùng payload dùng được cho send_json và REST.
    return {
        "id": str(event.id),
        "device_id": str(event.device_id),
        "event_type": event.event_type,
        "occurred_at": event.occurred_at.isoformat() if event.occurred_at else None,
        "source": event.source or metadata.get("source"),
        "description": event.description or metadata.get("description"),
    }


@router.post("/", response_model=LocationSampleResponse)
async def add_location(
    location: LocationSampleCreate,
    db: AsyncSession = Depends(get_db),
    _current_user=Depends(require_admin_if_enabled),
):
    # Endpoint này dành cho nhập GPS có kiểm soát ngoài MQTT. Cả hai đường đều gọi
    # TrackingService nên dùng chung quy tắc latest state và sinh sự kiện.
    try:
        result, generated_events = await TrackingService.add_location(db, location)
    except DeviceNotFoundError as exc:
        raise HTTPException(status_code=404, detail=str(exc))

    # Đọc lại snapshot sau commit để frontend nhận đúng trạng thái vừa được lưu.
    device = await DeviceService.get_device(db, location.device_id)
    # Trường hợp hiếm thiết bị bị xóa sau commit được bỏ qua broadcast thay vì phát payload rỗng.
    if device:
        await realtime_service.broadcast_telemetry(
            {
                "type": "DEVICE_UPDATE",
                "device": DeviceResponse.model_validate(device).model_dump(mode="json"),
            }
        )
    # Mỗi cạnh ONLINE/MOVEMENT tạo một event độc lập cho timeline frontend.
    for event in generated_events:
        await realtime_service.broadcast_telemetry(
            {"type": "DEVICE_EVENT", "event": _event_payload(event)}
        )
    return result


@router.get("/{device_id}/history", response_model=List[LocationSampleResponse])
async def get_history(
    device_id: uuid.UUID,
    limit: int = Query(100, ge=1, le=100000),
    db: AsyncSession = Depends(get_db),
    _current_user=Depends(require_viewer_if_enabled),
):
    # Trả tối đa `limit` mẫu gần nhất; dùng cho phần xem nhanh, không phải toàn bộ hành trình.
    return await TrackingService.get_location_history(db, device_id, limit)


@router.get("/{device_id}/history/range", response_model=LocationHistoryResponse)
async def get_history_range(
    device_id: uuid.UUID,
    from_time: datetime = Query(..., alias="from"),
    to_time: datetime = Query(..., alias="to"),
    max_samples: Optional[int] = Query(None, ge=1, le=100000),
    db: AsyncSession = Depends(get_db),
    _current_user=Depends(require_viewer_if_enabled),
):
    # Khoảng thời gian phải có thứ tự rõ ràng trước khi chạy count và truy vấn mẫu.
    # Dấu bằng cũng bị từ chối vì khoảng có độ dài bằng 0 không chứa một hành trình.
    if from_time >= to_time:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Thời điểm bắt đầu phải nhỏ hơn thời điểm kết thúc",
        )
    # Kiểm tra hồ sơ trước để UUID hợp lệ nhưng không tồn tại trả 404 thay vì danh sách rỗng.
    if await DeviceService.get_device(db, device_id) is None:
        raise HTTPException(status_code=404, detail="Không tìm thấy thiết bị")

    # Service trả cả tổng số bản ghi và cờ truncated để UI không hiểu nhầm dữ liệu
    # đã cắt theo giới hạn là toàn bộ hành trình.
    samples, total_count, truncated = await TrackingService.get_location_history_range(
        db=db,
        device_id=device_id,
        from_time=from_time,
        to_time=to_time,
        max_samples=max_samples,
    )
    return LocationHistoryResponse(
        device_id=device_id,
        from_time=from_time,
        to_time=to_time,
        samples=[LocationSampleResponse.model_validate(sample) for sample in samples],
        total_count=total_count,
        truncated=truncated,
    )


@router.get("/{device_id}/events", response_model=List[DeviceEventResponse])
async def get_events(
    device_id: str,
    limit: int = Query(100, ge=1, le=10000),
    event_type: Optional[str] = Query(None, max_length=50),
    db: AsyncSession = Depends(get_db),
    _current_user=Depends(require_viewer_if_enabled),
):
    # Cho phép client dùng UUID nội bộ hoặc device_code dễ đọc. Mã không tồn tại
    # trả danh sách rỗng để tab sự kiện hiển thị trạng thái trống ổn định.
    try:
        # Nhánh nhanh khi path đã là UUID chuẩn.
        resolved_uuid = uuid.UUID(device_id)
    except (ValueError, TypeError):
        # Chuỗi không phải UUID được hiểu là device_code và tra đúng một lần.
        result = await db.execute(
            select(Device.id).where(Device.device_code == device_id)
        )
        resolved_uuid = result.scalar_one_or_none()

    # Mã không khớp thiết bị nào là trạng thái trống hợp lệ của timeline.
    if not resolved_uuid:
        return []
    # event_type được service chuẩn hóa chữ hoa; limit đã được Query kiểm tra biên.
    events = await TrackingService.get_device_events(
        db,
        resolved_uuid,
        limit,
        event_type=event_type,
    )
    return [_event_payload(event) for event in events]
