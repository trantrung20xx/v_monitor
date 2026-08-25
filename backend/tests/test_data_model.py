# Bảo vệ schema nghiệp vụ: bảng cần thiết, quan hệ, enum và nguyên tắc không lưu mật khẩu thô.
import os
import sys
import unittest
from pathlib import Path


os.environ.setdefault(
    "DATABASE_URL",
    "postgresql+asyncpg://test:test@localhost:5432/v_monitor_test",
)
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from app.domain.enums import UserRole  # noqa: E402
from app.models import Base  # noqa: E402


class DataModelTest(unittest.TestCase):
    def test_only_required_business_tables_are_registered(self):
        self.assertEqual(
            set(Base.metadata.tables),
            {
                "audit_logs",
                "device_events",
                "device_latest_state",
                "devices",
                "location_samples",
                "mqtt_device_sightings",
                "system_settings",
                "telemetry_messages",
                "user_accounts",
                "user_settings",
            },
        )

    def test_device_management_fields_are_registered(self):
        self.assertIn("is_enabled", Base.metadata.tables["devices"].columns)
        self.assertEqual(
            set(Base.metadata.tables["mqtt_device_sightings"].columns.keys()),
            {
                "device_code",
                "first_seen_at",
                "last_seen_at",
                "message_count",
                "last_topic",
            },
        )

    def test_device_state_contains_current_monitoring_values(self):
        self.assertEqual(
            set(Base.metadata.tables["device_latest_state"].columns.keys()),
            {
                "device_id",
                "last_seen_at",
                "latest_measured_at",
                "latest_sample_id",
                "is_online",
                "current_latitude",
                "current_longitude",
                "current_altitude_m",
                "current_speed_mps",
                "current_heading_deg",
                "battery_pct",
                "created_at",
                "updated_at",
            },
        )

    def test_account_roles_and_delete_rules(self):
        self.assertEqual({role.value for role in UserRole}, {"ADMIN", "USER"})
        expected_rules = {
            ("audit_logs", "actor_user_id"): ("user_accounts.id", "SET NULL"),
            ("user_settings", "user_id"): ("user_accounts.id", "CASCADE"),
            ("system_settings", "updated_by"): (
                "user_accounts.id",
                "SET NULL",
            ),
            ("location_samples", "source_message_id"): (
                "telemetry_messages.id",
                "SET NULL",
            ),
            ("device_latest_state", "latest_sample_id"): (
                "location_samples.id",
                "SET NULL",
            ),
        }
        for (table_name, column_name), expected in expected_rules.items():
            foreign_keys = list(
                Base.metadata.tables[table_name].columns[column_name].foreign_keys
            )
            self.assertEqual(len(foreign_keys), 1)
            self.assertEqual(
                (foreign_keys[0].target_fullname, foreign_keys[0].ondelete),
                expected,
            )

    def test_accounts_are_not_linked_to_devices_or_tracking(self):
        prohibited_targets = {"devices", "device_events", "location_samples"}
        for table_name in prohibited_targets:
            targets = {
                foreign_key.column.table.name
                for column in Base.metadata.tables[table_name].columns
                for foreign_key in column.foreign_keys
            }
            self.assertNotIn("user_accounts", targets)

    def test_account_never_stores_plain_password(self):
        account_columns = set(Base.metadata.tables["user_accounts"].columns.keys())
        self.assertIn("password_hash", account_columns)
        self.assertNotIn("password", account_columns)

    def test_usage_session_model_is_fully_removed(self):
        for table in Base.metadata.tables.values():
            self.assertNotIn("usage_session_id", table.columns)


if __name__ == "__main__":
    unittest.main()
