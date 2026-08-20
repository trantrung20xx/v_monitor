"""Căn chỉnh mô hình giám sát thiết bị và xác thực nội bộ.

Revision ID: f3b5d7e9a1c2
Revises: e2a4f6b8c0d1
Create Date: 2026-08-20 14:00:00.000000
"""

from typing import Sequence, Union

from alembic import op
from geoalchemy2 import Geography
import sqlalchemy as sa
from sqlalchemy.dialects import postgresql


revision: str = "f3b5d7e9a1c2"
down_revision: Union[str, Sequence[str], None] = "e2a4f6b8c0d1"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def _inspector() -> sa.Inspector:
    return sa.inspect(op.get_bind())


def _has_table(table_name: str) -> bool:
    return table_name in _inspector().get_table_names()


def _has_column(table_name: str, column_name: str) -> bool:
    return _has_table(table_name) and any(
        column["name"] == column_name
        for column in _inspector().get_columns(table_name)
    )


def _has_index(table_name: str, index_name: str) -> bool:
    return _has_table(table_name) and any(
        index["name"] == index_name
        for index in _inspector().get_indexes(table_name)
    )


def _drop_index(table_name: str, index_name: str) -> None:
    if _has_index(table_name, index_name):
        op.drop_index(index_name, table_name=table_name)


def _ensure_index(
    table_name: str,
    index_name: str,
    columns,
    *,
    unique: bool = False,
    where: sa.TextClause | None = None,
) -> None:
    if _has_table(table_name) and not _has_index(table_name, index_name):
        op.create_index(
            index_name,
            table_name,
            columns,
            unique=unique,
            postgresql_where=where,
        )


def _has_check(table_name: str, name: str) -> bool:
    return _has_table(table_name) and any(
        constraint["name"] == name
        for constraint in _inspector().get_check_constraints(table_name)
    )


def _ensure_check(table_name: str, name: str, condition: str) -> None:
    if _has_table(table_name) and not _has_check(table_name, name):
        op.create_check_constraint(name, table_name, condition)


def _drop_check(table_name: str, name: str) -> None:
    if _has_check(table_name, name):
        op.drop_constraint(name, table_name, type_="check")


def _has_unique(table_name: str, name: str) -> bool:
    return _has_table(table_name) and any(
        constraint["name"] == name
        for constraint in _inspector().get_unique_constraints(table_name)
    )


def _ensure_unique(table_name: str, name: str, columns: list[str]) -> None:
    if _has_table(table_name) and not _has_unique(table_name, name):
        op.create_unique_constraint(name, table_name, columns)


def _drop_unique(table_name: str, name: str) -> None:
    if _has_unique(table_name, name):
        op.drop_constraint(name, table_name, type_="unique")


def _drop_foreign_keys_for_column(table_name: str, column_name: str) -> None:
    if not _has_table(table_name):
        return
    for foreign_key in _inspector().get_foreign_keys(table_name):
        if column_name in foreign_key.get("constrained_columns", []):
            op.drop_constraint(foreign_key["name"], table_name, type_="foreignkey")


def _ensure_foreign_key(
    table_name: str,
    column_name: str,
    referred_table: str,
    constraint_name: str,
    *,
    ondelete: str | None = None,
) -> None:
    if not _has_column(table_name, column_name):
        return
    for foreign_key in _inspector().get_foreign_keys(table_name):
        if column_name not in foreign_key.get("constrained_columns", []):
            continue
        current_delete = (foreign_key.get("options", {}).get("ondelete") or "").upper()
        if (
            foreign_key.get("referred_table") == referred_table
            and foreign_key.get("referred_columns") == ["id"]
            and current_delete == (ondelete or "").upper()
        ):
            return
        op.drop_constraint(foreign_key["name"], table_name, type_="foreignkey")
        break
    op.create_foreign_key(
        constraint_name,
        table_name,
        referred_table,
        [column_name],
        ["id"],
        ondelete=ondelete,
    )


def _enum_exists(type_name: str) -> bool:
    result = op.get_bind().execute(
        sa.text(
            """
            SELECT EXISTS (
                SELECT 1 FROM pg_type t
                JOIN pg_namespace n ON n.oid = t.typnamespace
                WHERE n.nspname = current_schema() AND t.typname = :type_name
            )
            """
        ),
        {"type_name": type_name},
    )
    return bool(result.scalar_one())


def _add_column(table_name: str, column: sa.Column) -> None:
    if _has_table(table_name) and not _has_column(table_name, column.name):
        op.add_column(table_name, column)


def _drop_column(table_name: str, column_name: str) -> None:
    if _has_column(table_name, column_name):
        _drop_foreign_keys_for_column(table_name, column_name)
        op.drop_column(table_name, column_name)


def upgrade() -> None:
    # Không tồn tại khái niệm người vận hành hay phiên sử dụng trong nghiệp vụ giám sát.
    _drop_column("device_events", "usage_session_id")
    if _has_table("usage_sessions"):
        op.drop_table("usage_sessions")
    if _enum_exists("usagestatus"):
        op.execute(sa.text('DROP TYPE "usagestatus"'))

    # Trạng thái mới nhất tách thời điểm nhận và thời điểm đo để chống gói đến trễ.
    if _has_column("device_latest_state", "last_seen_at"):
        op.alter_column(
            "device_latest_state",
            "last_seen_at",
            existing_type=sa.TIMESTAMP(timezone=True),
            nullable=True,
        )
    if _has_table("device_latest_state") and _has_table("devices"):
        op.execute(
            sa.text(
                """
                INSERT INTO device_latest_state (
                    device_id, is_online, created_at, updated_at
                )
                SELECT device.id, false, now(), now()
                FROM devices AS device
                WHERE NOT EXISTS (
                    SELECT 1 FROM device_latest_state AS state
                    WHERE state.device_id = device.id
                )
                """
            )
        )
    _add_column(
        "device_latest_state",
        sa.Column("latest_measured_at", sa.TIMESTAMP(timezone=True), nullable=True),
    )
    _add_column(
        "device_latest_state",
        sa.Column("latest_sample_id", postgresql.UUID(as_uuid=True), nullable=True),
    )
    if _has_table("device_latest_state") and _has_table("location_samples"):
        op.execute(
            sa.text(
                """
                UPDATE device_latest_state AS state
                SET latest_measured_at = (
                        SELECT measured_at FROM location_samples
                        WHERE device_id = state.device_id
                        ORDER BY measured_at DESC, id DESC LIMIT 1
                    ),
                    latest_sample_id = (
                        SELECT id FROM location_samples
                        WHERE device_id = state.device_id
                        ORDER BY measured_at DESC, id DESC LIMIT 1
                    )
                WHERE state.latest_measured_at IS NULL
                """
            )
        )
    _ensure_foreign_key(
        "device_latest_state",
        "latest_sample_id",
        "location_samples",
        "device_latest_state_latest_sample_id_fkey",
        ondelete="SET NULL",
    )
    for name, condition in (
        ("ck_device_latest_state_latitude", "current_latitude IS NULL OR current_latitude BETWEEN -90 AND 90"),
        ("ck_device_latest_state_longitude", "current_longitude IS NULL OR current_longitude BETWEEN -180 AND 180"),
        ("ck_device_latest_state_speed", "current_speed_mps IS NULL OR current_speed_mps >= 0"),
        ("ck_device_latest_state_heading", "current_heading_deg IS NULL OR (current_heading_deg >= 0 AND current_heading_deg < 360)"),
        ("ck_device_latest_state_uav_battery", "uav_battery_pct IS NULL OR uav_battery_pct BETWEEN 0 AND 100"),
    ):
        _ensure_check("device_latest_state", name, condition)
    _ensure_index(
        "device_latest_state",
        "ix_device_latest_state_online_seen",
        ["last_seen_at"],
        where=sa.text("is_online"),
    )
    if _has_column("device_latest_state", "is_online"):
        op.alter_column(
            "device_latest_state",
            "is_online",
            existing_type=sa.Boolean(),
            existing_nullable=False,
            server_default=sa.false(),
        )

    # Lịch sử GPS giữ dữ liệu gốc và có chỉ mục đúng với truy vấn theo thiết bị/thời gian.
    _add_column(
        "location_samples",
        sa.Column("source_message_id", postgresql.UUID(as_uuid=True), nullable=True),
    )
    _ensure_foreign_key(
        "location_samples",
        "source_message_id",
        "telemetry_messages",
        "location_samples_source_message_id_fkey",
        ondelete="SET NULL",
    )
    _drop_index("location_samples", "ix_location_samples_device_id")
    _drop_index("location_samples", "ix_location_samples_device_measured")
    _drop_index("location_samples", "ix_location_samples_location")
    _ensure_index(
        "location_samples",
        "ix_location_samples_device_measured_id",
        ["device_id", "measured_at", "id"],
    )
    _ensure_unique(
        "location_samples",
        "uq_location_samples_source_message_id",
        ["source_message_id"],
    )
    for name, condition in (
        ("ck_location_samples_latitude", "latitude BETWEEN -90 AND 90"),
        ("ck_location_samples_longitude", "longitude BETWEEN -180 AND 180"),
        ("ck_location_samples_speed", "speed_mps IS NULL OR speed_mps >= 0"),
        ("ck_location_samples_heading", "heading_deg IS NULL OR (heading_deg >= 0 AND heading_deg < 360)"),
        ("ck_location_samples_accuracy", "accuracy_m IS NULL OR accuracy_m >= 0"),
        ("ck_location_samples_satellites", "satellite_count IS NULL OR satellite_count >= 0"),
    ):
        _ensure_check("location_samples", name, condition)

    # Sự kiện có trường mô tả trực tiếp và chỉ mục phục vụ dòng thời gian.
    _add_column("device_events", sa.Column("description", sa.String(), nullable=True))
    if _has_column("device_events", "event_type"):
        op.alter_column(
            "device_events",
            "event_type",
            existing_type=sa.String(),
            type_=sa.String(length=50),
            existing_nullable=False,
        )
    if not _has_column("device_events", "received_at"):
        _add_column(
            "device_events",
            sa.Column("received_at", sa.TIMESTAMP(timezone=True), nullable=True),
        )
        op.execute("UPDATE device_events SET received_at = occurred_at")
        op.alter_column("device_events", "received_at", nullable=False)
    _add_column("device_events", sa.Column("source", sa.String(), nullable=True))
    if not _has_column("device_events", "created_at"):
        _add_column(
            "device_events",
            sa.Column("created_at", sa.TIMESTAMP(timezone=True), nullable=True),
        )
        op.execute("UPDATE device_events SET created_at = occurred_at")
        op.alter_column("device_events", "created_at", nullable=False)
    for old_index in (
        "ix_device_events_device_id",
        "ix_device_events_event_type",
        "ix_device_events_occurred_at",
    ):
        _drop_index("device_events", old_index)
    _ensure_index(
        "device_events",
        "ix_device_events_device_occurred_id",
        ["device_id", "occurred_at", "id"],
    )
    _ensure_index(
        "device_events",
        "ix_device_events_device_type_occurred",
        ["device_id", "event_type", "occurred_at"],
    )

    # Bản tin gốc có khóa chống phát lại và trạng thái xử lý đủ để chẩn đoán.
    for column in (
        sa.Column("external_message_id", sa.String(length=128), nullable=True),
        sa.Column("topic", sa.String(length=255), nullable=True),
        sa.Column("qos", sa.SmallInteger(), nullable=True),
        sa.Column("protocol", sa.String(length=20), nullable=True),
        sa.Column("schema_version", sa.String(length=32), nullable=True),
        sa.Column("processed_at", sa.TIMESTAMP(timezone=True), nullable=True),
        sa.Column("retry_count", sa.Integer(), server_default="0", nullable=False),
    ):
        _add_column("telemetry_messages", column)
    for column_name, length in (
        ("message_type", 50),
        ("protocol", 20),
        ("schema_version", 32),
    ):
        if _has_column("telemetry_messages", column_name):
            op.alter_column(
                "telemetry_messages",
                column_name,
                existing_type=sa.String(),
                type_=sa.String(length=length),
                existing_nullable=True,
            )
    _drop_index("telemetry_messages", "ix_telemetry_messages_device_id")
    _ensure_unique(
        "telemetry_messages",
        "uq_telemetry_messages_device_external_message",
        ["device_id", "external_message_id"],
    )
    _ensure_index(
        "telemetry_messages",
        "ix_telemetry_messages_device_received",
        ["device_id", "received_at"],
    )
    _ensure_index(
        "telemetry_messages",
        "ix_telemetry_messages_pending_received",
        ["received_at"],
        where=sa.text("processing_status IN ('PENDING', 'FAILED')"),
    )
    _ensure_check(
        "telemetry_messages",
        "ck_telemetry_messages_qos",
        "qos IS NULL OR qos BETWEEN 0 AND 2",
    )
    _ensure_check(
        "telemetry_messages",
        "ck_telemetry_messages_retry_count",
        "retry_count >= 0",
    )

    # Tài khoản là danh tính đăng nhập độc lập; không liên hệ với thiết bị hay lộ trình.
    for column in (
        sa.Column("password_changed_at", sa.TIMESTAMP(timezone=True), nullable=True),
        sa.Column("failed_login_count", sa.Integer(), server_default="0", nullable=False),
        sa.Column("locked_until", sa.TIMESTAMP(timezone=True), nullable=True),
        sa.Column("token_version", sa.Integer(), server_default="0", nullable=False),
    ):
        _add_column("user_accounts", column)
    for name, condition in (
        ("ck_user_accounts_username_trimmed", "username = btrim(username)"),
        ("ck_user_accounts_password_hash", "length(btrim(password_hash)) >= 20"),
        ("ck_user_accounts_email", "email IS NULL OR (email = btrim(email) AND length(email) >= 3)"),
        ("ck_user_accounts_failed_login_count", "failed_login_count >= 0"),
        ("ck_user_accounts_token_version", "token_version >= 0"),
    ):
        _ensure_check("user_accounts", name, condition)
    for name, condition in (
        ("ck_user_settings_theme", "theme IN ('system', 'light', 'dark')"),
        ("ck_user_settings_language", "language = btrim(language) AND length(language) >= 2"),
        ("ck_user_settings_timezone", "timezone = btrim(timezone) AND length(timezone) >= 1"),
    ):
        _ensure_check("user_settings", name, condition)

    _drop_index("audit_logs", "ix_audit_logs_actor_user_id")
    _drop_index("audit_logs", "ix_audit_logs_occurred_at")
    _ensure_index(
        "audit_logs",
        "ix_audit_logs_actor_occurred",
        ["actor_user_id", "occurred_at"],
    )
    _ensure_index(
        "audit_logs",
        "ix_audit_logs_entity_occurred",
        ["entity_type", "entity_id", "occurred_at"],
    )
    _ensure_check("devices", "ck_devices_code_not_blank", "length(btrim(device_code)) >= 1")
    _ensure_check("devices", "ck_devices_name_not_blank", "length(btrim(name)) >= 1")
    _ensure_check("devices", "ck_devices_code_trimmed", "device_code = btrim(device_code)")
    _ensure_check("devices", "ck_devices_name_trimmed", "name = btrim(name)")


def downgrade() -> None:
    """Khôi phục schema của revision trước; không thể phục hồi dữ liệu phiên đã xóa."""
    _drop_check("devices", "ck_devices_name_trimmed")
    _drop_check("devices", "ck_devices_code_trimmed")
    _drop_check("devices", "ck_devices_name_not_blank")
    _drop_check("devices", "ck_devices_code_not_blank")

    _drop_index("audit_logs", "ix_audit_logs_entity_occurred")
    _drop_index("audit_logs", "ix_audit_logs_actor_occurred")
    _ensure_index("audit_logs", "ix_audit_logs_actor_user_id", ["actor_user_id"])
    _ensure_index("audit_logs", "ix_audit_logs_occurred_at", ["occurred_at"])

    for name in (
        "ck_user_settings_timezone",
        "ck_user_settings_language",
        "ck_user_settings_theme",
    ):
        _drop_check("user_settings", name)

    for name in (
        "ck_user_accounts_token_version",
        "ck_user_accounts_failed_login_count",
        "ck_user_accounts_email",
        "ck_user_accounts_password_hash",
        "ck_user_accounts_username_trimmed",
    ):
        _drop_check("user_accounts", name)
    for column_name in (
        "token_version",
        "locked_until",
        "failed_login_count",
        "password_changed_at",
    ):
        _drop_column("user_accounts", column_name)

    for name in (
        "ck_telemetry_messages_retry_count",
        "ck_telemetry_messages_qos",
    ):
        _drop_check("telemetry_messages", name)
    _drop_index("telemetry_messages", "ix_telemetry_messages_pending_received")
    _drop_index("telemetry_messages", "ix_telemetry_messages_device_received")
    _drop_unique("telemetry_messages", "uq_telemetry_messages_device_external_message")
    for column_name in (
        "retry_count",
        "processed_at",
        "qos",
        "topic",
        "external_message_id",
    ):
        _drop_column("telemetry_messages", column_name)
    _ensure_index("telemetry_messages", "ix_telemetry_messages_device_id", ["device_id"])
    for column_name, length in (
        ("message_type", 50),
        ("protocol", 20),
        ("schema_version", 32),
    ):
        if _has_column("telemetry_messages", column_name):
            op.alter_column(
                "telemetry_messages",
                column_name,
                existing_type=sa.String(length=length),
                type_=sa.String(),
                existing_nullable=True,
            )

    _drop_index("device_events", "ix_device_events_device_type_occurred")
    _drop_index("device_events", "ix_device_events_device_occurred_id")
    _drop_column("device_events", "description")
    if _has_column("device_events", "event_type"):
        op.alter_column(
            "device_events",
            "event_type",
            existing_type=sa.String(length=50),
            type_=sa.String(),
            existing_nullable=False,
        )
    _ensure_index("device_events", "ix_device_events_device_id", ["device_id"])
    _ensure_index("device_events", "ix_device_events_event_type", ["event_type"])
    _ensure_index("device_events", "ix_device_events_occurred_at", ["occurred_at"])

    for name in (
        "ck_location_samples_satellites",
        "ck_location_samples_accuracy",
        "ck_location_samples_heading",
        "ck_location_samples_speed",
        "ck_location_samples_longitude",
        "ck_location_samples_latitude",
    ):
        _drop_check("location_samples", name)
    _drop_unique("location_samples", "uq_location_samples_source_message_id")
    _drop_index("location_samples", "ix_location_samples_device_measured_id")
    _ensure_index(
        "location_samples",
        "ix_location_samples_device_measured",
        ["device_id", "measured_at"],
    )
    _ensure_index("location_samples", "ix_location_samples_device_id", ["device_id"])
    _ensure_index("location_samples", "ix_location_samples_location", ["location"])

    _drop_index("device_latest_state", "ix_device_latest_state_online_seen")
    for name in (
        "ck_device_latest_state_uav_battery",
        "ck_device_latest_state_heading",
        "ck_device_latest_state_speed",
        "ck_device_latest_state_longitude",
        "ck_device_latest_state_latitude",
    ):
        _drop_check("device_latest_state", name)
    _drop_column("device_latest_state", "latest_sample_id")
    _drop_column("device_latest_state", "latest_measured_at")
    if _has_column("device_latest_state", "last_seen_at"):
        op.execute("UPDATE device_latest_state SET last_seen_at = now() WHERE last_seen_at IS NULL")
        op.alter_column(
            "device_latest_state",
            "last_seen_at",
            existing_type=sa.TIMESTAMP(timezone=True),
            nullable=False,
        )
    if _has_column("device_latest_state", "is_online"):
        op.alter_column(
            "device_latest_state",
            "is_online",
            existing_type=sa.Boolean(),
            existing_nullable=False,
            server_default=None,
        )

    usage_status = postgresql.ENUM(
        "ACTIVE",
        "COMPLETED",
        "CANCELLED",
        "UNKNOWN",
        name="usagestatus",
        create_type=False,
    )
    if not _enum_exists("usagestatus"):
        usage_status.create(op.get_bind(), checkfirst=True)
    if not _has_table("usage_sessions"):
        op.create_table(
            "usage_sessions",
            sa.Column("device_id", postgresql.UUID(as_uuid=True), nullable=False),
            sa.Column("started_at", sa.TIMESTAMP(timezone=True), nullable=False),
            sa.Column("ended_at", sa.TIMESTAMP(timezone=True), nullable=True),
            sa.Column("start_location", Geography("POINT", srid=4326), nullable=True),
            sa.Column("end_location", Geography("POINT", srid=4326), nullable=True),
            sa.Column("distance_m", sa.Float(), nullable=True),
            sa.Column("avg_speed_mps", sa.Float(), nullable=True),
            sa.Column("max_speed_mps", sa.Float(), nullable=True),
            sa.Column("moving_duration_s", sa.Integer(), nullable=True),
            sa.Column("stopped_duration_s", sa.Integer(), nullable=True),
            sa.Column("route_geometry", Geography("LINESTRING", srid=4326), nullable=True),
            sa.Column("status", usage_status, nullable=False),
            sa.Column("end_reason", sa.String(), nullable=True),
            sa.Column("user_account_id", postgresql.UUID(as_uuid=True), nullable=True),
            sa.Column("id", postgresql.UUID(as_uuid=True), nullable=False),
            sa.Column("created_at", sa.TIMESTAMP(timezone=True), nullable=False),
            sa.Column("updated_at", sa.TIMESTAMP(timezone=True), nullable=False),
            sa.ForeignKeyConstraint(["device_id"], ["devices.id"]),
            sa.ForeignKeyConstraint(
                ["user_account_id"],
                ["user_accounts.id"],
                ondelete="SET NULL",
            ),
            sa.PrimaryKeyConstraint("id"),
        )
        _ensure_index("usage_sessions", "ix_usage_sessions_device_id", ["device_id"])
        _ensure_index("usage_sessions", "ix_usage_sessions_started_at", ["started_at"])
        _ensure_index(
            "usage_sessions",
            "ix_usage_sessions_user_account_id",
            ["user_account_id"],
        )
    _add_column(
        "device_events",
        sa.Column("usage_session_id", postgresql.UUID(as_uuid=True), nullable=True),
    )
    _ensure_foreign_key(
        "device_events",
        "usage_session_id",
        "usage_sessions",
        "device_events_usage_session_id_fkey",
        ondelete="SET NULL",
    )
