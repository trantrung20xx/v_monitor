"""Chuẩn hóa tên trường pin của thiết bị.

Revision ID: a4c6e8f0b2d3
Revises: f3b5d7e9a1c2
Create Date: 2026-08-20 15:30:00.000000

Trường uav_battery_pct cũ gắn sai mức pin với UAV. Nghiệp vụ thực tế lưu mức
pin của chính bản ghi devices, có thể là ô tô, tay điều khiển UAV hoặc loại thiết
bị khác. Migration đổi tên thành battery_pct và giữ ràng buộc miền giá trị 0-100.
"""

from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


revision: str = "a4c6e8f0b2d3"
down_revision: Union[str, Sequence[str], None] = "f3b5d7e9a1c2"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


TABLE_NAME = "device_latest_state"
OLD_COLUMN = "uav_battery_pct"
NEW_COLUMN = "battery_pct"
OLD_CHECK = "ck_device_latest_state_uav_battery"
NEW_CHECK = "ck_device_latest_state_battery"


def _inspector() -> sa.Inspector:
    return sa.inspect(op.get_bind())


def _has_table() -> bool:
    return TABLE_NAME in _inspector().get_table_names()


def _has_column(column_name: str) -> bool:
    if not _has_table():
        return False
    return any(
        column["name"] == column_name
        for column in _inspector().get_columns(TABLE_NAME)
    )


def _has_check(check_name: str) -> bool:
    if not _has_table():
        return False
    return any(
        check["name"] == check_name
        for check in _inspector().get_check_constraints(TABLE_NAME)
    )


def _drop_check(check_name: str) -> None:
    if _has_check(check_name):
        op.drop_constraint(check_name, TABLE_NAME, type_="check")


def upgrade() -> None:
    if not _has_table():
        return

    # Ràng buộc cũ phải được gỡ trước khi đổi hoặc xóa cột mà biểu thức tham chiếu.
    _drop_check(OLD_CHECK)

    has_old_column = _has_column(OLD_COLUMN)
    has_new_column = _has_column(NEW_COLUMN)
    if has_old_column and not has_new_column:
        op.alter_column(
            TABLE_NAME,
            OLD_COLUMN,
            new_column_name=NEW_COLUMN,
            existing_type=sa.Integer(),
            existing_nullable=True,
        )
    elif has_old_column and has_new_column:
        # Trường hợp database được dựng từ metadata mới rồi chạy lại lịch sử migration:
        # ưu tiên giá trị đúng tên, chỉ lấy giá trị cũ khi battery_pct đang null.
        op.execute(
            f"UPDATE {TABLE_NAME} "
            f"SET {NEW_COLUMN} = COALESCE({NEW_COLUMN}, {OLD_COLUMN})"
        )
        op.drop_column(TABLE_NAME, OLD_COLUMN)
    elif not has_new_column:
        op.add_column(
            TABLE_NAME,
            sa.Column(NEW_COLUMN, sa.Integer(), nullable=True),
        )

    if not _has_check(NEW_CHECK):
        op.create_check_constraint(
            NEW_CHECK,
            TABLE_NAME,
            f"{NEW_COLUMN} IS NULL OR {NEW_COLUMN} BETWEEN 0 AND 100",
        )


def downgrade() -> None:
    if not _has_table():
        return

    _drop_check(NEW_CHECK)
    has_old_column = _has_column(OLD_COLUMN)
    has_new_column = _has_column(NEW_COLUMN)
    if has_new_column and not has_old_column:
        op.alter_column(
            TABLE_NAME,
            NEW_COLUMN,
            new_column_name=OLD_COLUMN,
            existing_type=sa.Integer(),
            existing_nullable=True,
        )
    elif has_new_column and has_old_column:
        op.execute(
            f"UPDATE {TABLE_NAME} "
            f"SET {OLD_COLUMN} = COALESCE({OLD_COLUMN}, {NEW_COLUMN})"
        )
        op.drop_column(TABLE_NAME, NEW_COLUMN)

    if _has_column(OLD_COLUMN) and not _has_check(OLD_CHECK):
        op.create_check_constraint(
            OLD_CHECK,
            TABLE_NAME,
            f"{OLD_COLUMN} IS NULL OR {OLD_COLUMN} BETWEEN 0 AND 100",
        )
