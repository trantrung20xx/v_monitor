"""Rút gọn mô hình dữ liệu lỗi thời.

Revision ID: e2a4f6b8c0d1
Revises: c7d8e9f1a2b3
Create Date: 2026-08-20 09:30:00.000000

Phần nâng cấp được viết phòng vệ vì cơ sở dữ liệu phát triển có trước
lịch sử Alembic. Migration chỉ thực hiện thao tác tường minh theo đúng
thứ tự phụ thuộc và tuyệt đối không dùng CASCADE.
"""

from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects import postgresql


revision: str = "e2a4f6b8c0d1"
down_revision: Union[str, Sequence[str], None] = "c7d8e9f1a2b3"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def _inspector() -> sa.Inspector:
    return sa.inspect(op.get_bind())


def _has_table(table_name: str) -> bool:
    return table_name in _inspector().get_table_names()


def _has_column(table_name: str, column_name: str) -> bool:
    if not _has_table(table_name):
        return False
    return any(
        column["name"] == column_name
        for column in _inspector().get_columns(table_name)
    )


def _drop_foreign_keys_for_column(table_name: str, column_name: str) -> None:
    if not _has_table(table_name):
        return
    for foreign_key in _inspector().get_foreign_keys(table_name):
        if column_name in foreign_key.get("constrained_columns", []):
            op.drop_constraint(
                foreign_key["name"],
                table_name,
                type_="foreignkey",
            )


def _ensure_foreign_key(
    table_name: str,
    column_name: str,
    referred_table: str,
    referred_column: str,
    constraint_name: str,
    ondelete: str | None = None,
) -> None:
    if not _has_column(table_name, column_name):
        return
    for foreign_key in _inspector().get_foreign_keys(table_name):
        if column_name not in foreign_key.get("constrained_columns", []):
            continue
        current_ondelete = (foreign_key.get("options", {}).get("ondelete") or "").upper()
        expected_ondelete = (ondelete or "").upper()
        if (
            foreign_key.get("referred_table") == referred_table
            and foreign_key.get("referred_columns") == [referred_column]
            and current_ondelete == expected_ondelete
        ):
            return
        op.drop_constraint(foreign_key["name"], table_name, type_="foreignkey")
        break
    op.create_foreign_key(
        constraint_name,
        table_name,
        referred_table,
        [column_name],
        [referred_column],
        ondelete=ondelete,
    )


def _ensure_index(
    table_name: str,
    index_name: str,
    columns: list[str],
    unique: bool = False,
) -> None:
    if not _has_table(table_name):
        return
    index_names = {index["name"] for index in _inspector().get_indexes(table_name)}
    if index_name not in index_names:
        op.create_index(index_name, table_name, columns, unique=unique)


def _drop_column(table_name: str, column_name: str) -> None:
    if _has_column(table_name, column_name):
        op.drop_column(table_name, column_name)


def _drop_table(table_name: str) -> None:
    if _has_table(table_name):
        op.drop_table(table_name)


def _enum_exists(type_name: str) -> bool:
    result = op.get_bind().execute(
        sa.text(
            """
            SELECT EXISTS (
                SELECT 1
                FROM pg_type t
                JOIN pg_namespace n ON n.oid = t.typnamespace
                WHERE n.nspname = current_schema()
                  AND t.typname = :type_name
            )
            """
        ),
        {"type_name": type_name},
    )
    return bool(result.scalar_one())


def _timestamp_has_timezone(table_name: str, column_name: str) -> bool:
    for column in _inspector().get_columns(table_name):
        if column["name"] == column_name:
            return bool(getattr(column["type"], "timezone", False))
    return False


def upgrade() -> None:
    # 1. Loại bỏ phụ thuộc people khỏi các bảng nghiệp vụ được giữ lại.
    for table_name, column_name in (
        ("audit_logs", "actor_id"),
        ("device_events", "person_id"),
        ("usage_sessions", "user_id"),
        ("usage_sessions", "responsible_person_id"),
    ):
        _drop_foreign_keys_for_column(table_name, column_name)
        _drop_column(table_name, column_name)

    # 2. Revision lịch sử này khôi phục tạm tên cột pin legacy từng tồn tại trong
    # schema cũ. Revision a4c6e8f0b2d3 phía sau chịu trách nhiệm đổi sang
    # battery_pct, là mức pin của chính thiết bị được theo dõi.
    _drop_column("device_latest_state", "controller_battery_pct")
    if _has_table("device_latest_state") and not _has_column(
        "device_latest_state", "uav_battery_pct"
    ):
        op.add_column(
            "device_latest_state",
            sa.Column("uav_battery_pct", sa.Integer(), nullable=True),
        )
    if _has_table("device_latest_state") and not _has_column(
        "device_latest_state", "current_altitude_m"
    ):
        op.add_column(
            "device_latest_state",
            sa.Column("current_altitude_m", sa.Float(), nullable=True),
        )

    # 3. Xóa các bảng lá lỗi thời trước khi xóa people.
    for table_name in (
        "device_assignments",
        "uav_controller_profiles",
        "vehicle_profiles",
        "battery_samples",
    ):
        _drop_table(table_name)
    _drop_table("people")

    # 4. Chỉ xóa kiểu enum sau khi mọi cột phụ thuộc đã được xóa.
    for type_name in ("batterytype", "assignmenttype"):
        if _enum_exists(type_name):
            op.execute(sa.text(f'DROP TYPE "{type_name}"'))

    # Đồng bộ các timestamp cũ với khai báo ORM có múi giờ.
    for table_name, column_name in (
        ("devices", "created_at"),
        ("devices", "updated_at"),
        ("device_latest_state", "last_seen_at"),
        ("device_latest_state", "created_at"),
        ("device_latest_state", "updated_at"),
        ("usage_sessions", "created_at"),
        ("usage_sessions", "updated_at"),
    ):
        if (
            _has_column(table_name, column_name)
            and not _timestamp_has_timezone(table_name, column_name)
        ):
            op.alter_column(
                table_name,
                column_name,
                existing_type=sa.TIMESTAMP(timezone=False),
                type_=sa.TIMESTAMP(timezone=True),
                postgresql_using=f'"{column_name}" AT TIME ZONE \'UTC\'',
                existing_nullable=False,
            )

    if _has_table("location_samples"):
        index_names = {
            index["name"] for index in _inspector().get_indexes("location_samples")
        }
        if "ix_location_samples_device_measured" not in index_names:
            op.create_index(
                "ix_location_samples_device_measured",
                "location_samples",
                ["device_id", "measured_at"],
                unique=False,
            )

    # 5. Tạo mô hình tài khoản độc lập thay cho people đã bị loại bỏ.
    user_role = postgresql.ENUM(
        "ADMIN",
        "USER",
        name="userrole",
        create_type=False,
    )
    if not _enum_exists("userrole"):
        user_role.create(op.get_bind(), checkfirst=True)

    if not _has_table("user_accounts"):
        op.create_table(
            "user_accounts",
            sa.Column("username", sa.String(length=50), nullable=False),
            sa.Column("password_hash", sa.String(length=255), nullable=False),
            sa.Column("full_name", sa.String(length=255), nullable=False),
            sa.Column("email", sa.String(length=320), nullable=True),
            sa.Column(
                "role",
                user_role,
                server_default=sa.text("'USER'::userrole"),
                nullable=False,
            ),
            sa.Column(
                "is_active",
                sa.Boolean(),
                server_default=sa.true(),
                nullable=False,
            ),
            sa.Column("last_login_at", sa.TIMESTAMP(timezone=True), nullable=True),
            sa.Column("id", postgresql.UUID(as_uuid=True), nullable=False),
            sa.Column("created_at", sa.TIMESTAMP(timezone=True), nullable=False),
            sa.Column("updated_at", sa.TIMESTAMP(timezone=True), nullable=False),
            sa.CheckConstraint(
                "length(btrim(username)) >= 3",
                name="ck_user_accounts_username_length",
            ),
            sa.CheckConstraint(
                "length(btrim(full_name)) >= 1",
                name="ck_user_accounts_full_name_not_blank",
            ),
            sa.PrimaryKeyConstraint("id", name="user_accounts_pkey"),
        )
        op.create_index(
            "uq_user_accounts_username_ci",
            "user_accounts",
            [sa.text("lower(username)")],
            unique=True,
        )
        op.create_index(
            "uq_user_accounts_email_ci",
            "user_accounts",
            [sa.text("lower(email)")],
            unique=True,
            postgresql_where=sa.text("email IS NOT NULL"),
        )

    if not _has_table("user_settings"):
        op.create_table(
            "user_settings",
            sa.Column("user_id", postgresql.UUID(as_uuid=True), nullable=False),
            sa.Column(
                "theme",
                sa.String(length=20),
                server_default="system",
                nullable=False,
            ),
            sa.Column(
                "language",
                sa.String(length=10),
                server_default="vi",
                nullable=False,
            ),
            sa.Column(
                "timezone",
                sa.String(length=64),
                server_default="Asia/Ho_Chi_Minh",
                nullable=False,
            ),
            sa.Column(
                "notifications_enabled",
                sa.Boolean(),
                server_default=sa.true(),
                nullable=False,
            ),
            sa.Column("preferences", postgresql.JSONB(), nullable=True),
            sa.Column("created_at", sa.TIMESTAMP(timezone=True), nullable=False),
            sa.Column("updated_at", sa.TIMESTAMP(timezone=True), nullable=False),
            sa.ForeignKeyConstraint(
                ["user_id"],
                ["user_accounts.id"],
                name="user_settings_user_id_fkey",
                ondelete="CASCADE",
            ),
            sa.PrimaryKeyConstraint("user_id", name="user_settings_pkey"),
        )

    if _has_table("audit_logs") and not _has_column(
        "audit_logs", "actor_user_id"
    ):
        op.add_column(
            "audit_logs",
            sa.Column("actor_user_id", postgresql.UUID(as_uuid=True), nullable=True),
        )
    _ensure_foreign_key(
        "audit_logs",
        "actor_user_id",
        "user_accounts",
        "id",
        "audit_logs_actor_user_id_fkey",
        ondelete="SET NULL",
    )
    _ensure_index(
        "audit_logs",
        "ix_audit_logs_actor_user_id",
        ["actor_user_id"],
    )

    if _has_table("usage_sessions") and not _has_column(
        "usage_sessions", "user_account_id"
    ):
        op.add_column(
            "usage_sessions",
            sa.Column("user_account_id", postgresql.UUID(as_uuid=True), nullable=True),
        )
    _ensure_foreign_key(
        "usage_sessions",
        "user_account_id",
        "user_accounts",
        "id",
        "usage_sessions_user_account_id_fkey",
        ondelete="SET NULL",
    )
    _ensure_index(
        "usage_sessions",
        "ix_usage_sessions_user_account_id",
        ["user_account_id"],
    )

    # Khi xóa dữ liệu nguồn/tổng hợp, vẫn giữ lại sự kiện và GPS.
    _ensure_foreign_key(
        "device_events",
        "usage_session_id",
        "usage_sessions",
        "id",
        "device_events_usage_session_id_fkey",
        ondelete="SET NULL",
    )
    _ensure_foreign_key(
        "location_samples",
        "source_message_id",
        "telemetry_messages",
        "id",
        "location_samples_source_message_id_fkey",
        ondelete="SET NULL",
    )


def downgrade() -> None:
    """Khôi phục cấu trúc; dòng dữ liệu đã xóa chỉ có thể lấy lại từ bản sao lưu."""

    # Gỡ các ràng buộc tài khoản mới trước khi khôi phục schema cũ.
    for table_name, column_name in (
        ("audit_logs", "actor_user_id"),
        ("usage_sessions", "user_account_id"),
    ):
        _drop_foreign_keys_for_column(table_name, column_name)
        _drop_column(table_name, column_name)

    _ensure_foreign_key(
        "device_events",
        "usage_session_id",
        "usage_sessions",
        "id",
        "device_events_usage_session_id_fkey",
    )
    _ensure_foreign_key(
        "location_samples",
        "source_message_id",
        "telemetry_messages",
        "id",
        "location_samples_source_message_id_fkey",
    )

    _drop_table("user_settings")
    _drop_table("user_accounts")
    if _enum_exists("userrole"):
        op.execute(sa.text('DROP TYPE "userrole"'))

    bind = op.get_bind()
    assignment_type = postgresql.ENUM(
        "RESPONSIBLE",
        "OPERATOR",
        name="assignmenttype",
        create_type=False,
    )
    battery_type = postgresql.ENUM(
        "CONTROLLER",
        "UAV",
        "VEHICLE",
        name="batterytype",
        create_type=False,
    )
    if not _enum_exists("assignmenttype"):
        assignment_type.create(bind, checkfirst=True)
    if not _enum_exists("batterytype"):
        battery_type.create(bind, checkfirst=True)

    if not _has_table("people"):
        op.create_table(
            "people",
            sa.Column("person_code", sa.String(), nullable=False),
            sa.Column("full_name", sa.String(), nullable=False),
            sa.Column("phone", sa.String(), nullable=True),
            sa.Column("email", sa.String(), nullable=True),
            sa.Column("department", sa.String(), nullable=True),
            sa.Column("role", sa.String(), nullable=True),
            sa.Column("status", sa.String(), nullable=False),
            sa.Column("metadata", postgresql.JSONB(), nullable=True),
            sa.Column("id", postgresql.UUID(as_uuid=True), nullable=False),
            sa.Column("created_at", sa.TIMESTAMP(timezone=False), nullable=False),
            sa.Column("updated_at", sa.TIMESTAMP(timezone=False), nullable=False),
            sa.PrimaryKeyConstraint("id", name="people_pkey"),
        )
        op.create_index(
            "ix_people_person_code",
            "people",
            ["person_code"],
            unique=True,
        )

    if not _has_table("device_assignments"):
        op.create_table(
            "device_assignments",
            sa.Column("device_id", postgresql.UUID(as_uuid=True), nullable=False),
            sa.Column("person_id", postgresql.UUID(as_uuid=True), nullable=False),
            sa.Column("assigned_at", sa.TIMESTAMP(timezone=True), nullable=False),
            sa.Column("unassigned_at", sa.TIMESTAMP(timezone=True), nullable=True),
            sa.Column("assignment_type", assignment_type, nullable=False),
            sa.Column("notes", sa.String(), nullable=True),
            sa.Column("created_at", sa.TIMESTAMP(timezone=True), nullable=False),
            sa.Column("id", postgresql.UUID(as_uuid=True), nullable=False),
            sa.ForeignKeyConstraint(
                ["device_id"], ["devices.id"], name="device_assignments_device_id_fkey"
            ),
            sa.ForeignKeyConstraint(
                ["person_id"], ["people.id"], name="device_assignments_person_id_fkey"
            ),
            sa.PrimaryKeyConstraint("id", name="device_assignments_pkey"),
        )

    if not _has_table("uav_controller_profiles"):
        op.create_table(
            "uav_controller_profiles",
            sa.Column("device_id", postgresql.UUID(as_uuid=True), nullable=False),
            sa.Column("hardware_version", sa.String(), nullable=True),
            sa.Column("battery_capacity_mah", sa.Integer(), nullable=True),
            sa.Column("connection_type", sa.String(), nullable=True),
            sa.Column("metadata", postgresql.JSONB(), nullable=True),
            sa.Column("id", postgresql.UUID(as_uuid=True), nullable=False),
            sa.Column("created_at", sa.TIMESTAMP(timezone=False), nullable=False),
            sa.Column("updated_at", sa.TIMESTAMP(timezone=False), nullable=False),
            sa.ForeignKeyConstraint(
                ["device_id"], ["devices.id"], name="uav_controller_profiles_device_id_fkey"
            ),
            sa.PrimaryKeyConstraint("id", name="uav_controller_profiles_pkey"),
            sa.UniqueConstraint("device_id", name="uav_controller_profiles_device_id_key"),
        )

    if not _has_table("vehicle_profiles"):
        op.create_table(
            "vehicle_profiles",
            sa.Column("device_id", postgresql.UUID(as_uuid=True), nullable=False),
            sa.Column("license_plate", sa.String(), nullable=True),
            sa.Column("vin", sa.String(), nullable=True),
            sa.Column("vehicle_type", sa.String(), nullable=True),
            sa.Column("fuel_type", sa.String(), nullable=True),
            sa.Column("engine_type", sa.String(), nullable=True),
            sa.Column("model_year", sa.Integer(), nullable=True),
            sa.Column("odometer_km", sa.Float(), nullable=True),
            sa.Column("metadata", postgresql.JSONB(), nullable=True),
            sa.Column("id", postgresql.UUID(as_uuid=True), nullable=False),
            sa.Column("created_at", sa.TIMESTAMP(timezone=False), nullable=False),
            sa.Column("updated_at", sa.TIMESTAMP(timezone=False), nullable=False),
            sa.ForeignKeyConstraint(
                ["device_id"], ["devices.id"], name="vehicle_profiles_device_id_fkey"
            ),
            sa.PrimaryKeyConstraint("id", name="vehicle_profiles_pkey"),
            sa.UniqueConstraint("device_id", name="vehicle_profiles_device_id_key"),
        )

    if not _has_table("battery_samples"):
        op.create_table(
            "battery_samples",
            sa.Column("device_id", postgresql.UUID(as_uuid=True), nullable=False),
            sa.Column("battery_type", battery_type, nullable=False),
            sa.Column("measured_at", sa.TIMESTAMP(timezone=True), nullable=False),
            sa.Column("percent", sa.Integer(), nullable=True),
            sa.Column("voltage", sa.Float(), nullable=True),
            sa.Column("current_a", sa.Float(), nullable=True),
            sa.Column("temperature_c", sa.Float(), nullable=True),
            sa.Column("time_remaining_s", sa.Integer(), nullable=True),
            sa.Column("charge_state", sa.String(), nullable=True),
            sa.Column("source_message_id", postgresql.UUID(as_uuid=True), nullable=True),
            sa.Column("created_at", sa.TIMESTAMP(timezone=True), nullable=False),
            sa.Column("id", postgresql.UUID(as_uuid=True), nullable=False),
            sa.ForeignKeyConstraint(
                ["device_id"], ["devices.id"], name="battery_samples_device_id_fkey"
            ),
            sa.ForeignKeyConstraint(
                ["source_message_id"],
                ["telemetry_messages.id"],
                name="battery_samples_source_message_id_fkey",
            ),
            sa.PrimaryKeyConstraint("id", name="battery_samples_pkey"),
        )
        op.create_index(
            "ix_battery_samples_device_id",
            "battery_samples",
            ["device_id"],
            unique=False,
        )
        op.create_index(
            "ix_battery_samples_measured_at",
            "battery_samples",
            ["measured_at"],
            unique=False,
        )

    for table_name, column in (
        (
            "audit_logs",
            sa.Column("actor_id", postgresql.UUID(as_uuid=True), nullable=True),
        ),
        (
            "device_events",
            sa.Column("person_id", postgresql.UUID(as_uuid=True), nullable=True),
        ),
        (
            "usage_sessions",
            sa.Column("user_id", postgresql.UUID(as_uuid=True), nullable=True),
        ),
        (
            "usage_sessions",
            sa.Column(
                "responsible_person_id",
                postgresql.UUID(as_uuid=True),
                nullable=True,
            ),
        ),
    ):
        if _has_table(table_name) and not _has_column(table_name, column.name):
            op.add_column(table_name, column)

    if _has_table("audit_logs"):
        op.create_foreign_key(
            "audit_logs_actor_id_fkey",
            "audit_logs",
            "people",
            ["actor_id"],
            ["id"],
        )
    if _has_table("device_events"):
        op.create_foreign_key(
            "device_events_person_id_fkey",
            "device_events",
            "people",
            ["person_id"],
            ["id"],
        )
    if _has_table("usage_sessions"):
        op.create_foreign_key(
            "usage_sessions_user_id_fkey",
            "usage_sessions",
            "people",
            ["user_id"],
            ["id"],
        )
        op.create_foreign_key(
            "usage_sessions_responsible_person_id_fkey",
            "usage_sessions",
            "people",
            ["responsible_person_id"],
            ["id"],
        )

    if _has_table("device_latest_state") and not _has_column(
        "device_latest_state", "controller_battery_pct"
    ):
        op.add_column(
            "device_latest_state",
            sa.Column("controller_battery_pct", sa.Integer(), nullable=True),
        )
    _drop_column("device_latest_state", "current_altitude_m")
