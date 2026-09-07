"""Add durable realtime notifications and configurable dashboard cadence."""
from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects import postgresql

revision = "c8e0f2a4b6d8"
down_revision = "d8e9f0a1b2c3"
branch_labels = None
depends_on = None


def upgrade() -> None:
    inspector = sa.inspect(op.get_bind())
    if "realtime_outbox" not in inspector.get_table_names():
        op.create_table(
            "realtime_outbox",
            sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True),
            sa.Column("payload", postgresql.JSONB(), nullable=False),
            sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
            sa.Column("available_at", sa.DateTime(timezone=True), nullable=False),
            sa.Column("claim_token", postgresql.UUID(as_uuid=True), nullable=True),
        )
        op.create_index("ix_realtime_outbox_available", "realtime_outbox", ["available_at", "created_at"])
    if "dashboard_update_interval_ms" not in {
        c["name"] for c in inspector.get_columns("system_settings")
    }:
        op.add_column("system_settings", sa.Column(
            "dashboard_update_interval_ms", sa.Integer(), nullable=False, server_default="500"
        ))
        op.create_check_constraint(
            "ck_system_settings_dashboard_interval", "system_settings",
            "dashboard_update_interval_ms BETWEEN 250 AND 1000",
        )


def downgrade() -> None:
    op.drop_constraint("ck_system_settings_dashboard_interval", "system_settings", type_="check")
    op.drop_column("system_settings", "dashboard_update_interval_ms")
    op.drop_index("ix_realtime_outbox_available", table_name="realtime_outbox")
    op.drop_table("realtime_outbox")
