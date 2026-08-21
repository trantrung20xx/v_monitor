from pydantic import Field, model_validator

from app.schemas.common import BaseSchema


class SystemSettingsResponse(BaseSchema):
    offline_timeout_seconds: int
    movement_threshold_mps: float
    default_gap_threshold_seconds: int


class SystemSettingsUpdate(BaseSchema):
    offline_timeout_seconds: int | None = Field(
        default=None,
        ge=30,
        le=86400,
    )
    movement_threshold_mps: float | None = Field(
        default=None,
        ge=0.0,
        le=10.0,
    )
    default_gap_threshold_seconds: int | None = Field(
        default=None,
        ge=60,
        le=3600,
    )

    @model_validator(mode="after")
    def _require_change(self):
        if not self.model_fields_set:
            raise ValueError("Phải cung cấp ít nhất một cấu hình cần cập nhật")
        for field_name in self.model_fields_set:
            if getattr(self, field_name) is None:
                raise ValueError(f"{field_name} không được để null")
        return self
