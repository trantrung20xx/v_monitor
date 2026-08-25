# Xác nhận singleton settings, phân quyền ADMIN, giới hạn giá trị, audit và merge preferences.
import os
import sys
import unittest
import uuid
from pathlib import Path
from unittest.mock import AsyncMock, patch

from fastapi import HTTPException
from pydantic import ValidationError


os.environ.setdefault(
    "DATABASE_URL",
    "postgresql+asyncpg://test:test@localhost:5432/v_monitor_test",
)
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from app.api.auth_dependencies import _require_admin_role  # noqa: E402
from app.domain.enums import UserRole  # noqa: E402
from app.models.audit_log import AuditLog  # noqa: E402
from app.models.system_setting import SystemSetting  # noqa: E402
from app.models.user_account import UserAccount, UserSetting  # noqa: E402
from app.schemas.auth import UserSettingsUpdate  # noqa: E402
from app.schemas.system_settings import SystemSettingsUpdate  # noqa: E402
from app.services.system_settings_service import (  # noqa: E402
    SystemSettingsService,
)
from app.services.user_service import UserService  # noqa: E402


class _ScalarResult:
    def __init__(self, value):
        self._value = value

    def scalar_one_or_none(self):
        return self._value


class _FakeSession:
    def __init__(self, selected):
        self.selected = selected
        self.added = []
        self.commit_count = 0

    async def execute(self, _query):
        return _ScalarResult(self.selected)

    def add(self, value):
        self.added.append(value)

    async def commit(self):
        self.commit_count += 1

    async def refresh(self, _value):
        return None


def _account(role: UserRole) -> UserAccount:
    return UserAccount(
        id=uuid.uuid4(),
        username=f"test-{uuid.uuid4().hex[:8]}",
        password_hash="x" * 32,
        full_name="Tài khoản kiểm thử",
        role=role,
        is_active=True,
    )


class SystemSettingsValidationTest(unittest.TestCase):
    def test_accepts_boundary_values(self):
        value = SystemSettingsUpdate(
            offline_timeout_seconds=30,
            movement_threshold_mps=0,
            default_gap_threshold_seconds=3600,
        )
        self.assertEqual(value.offline_timeout_seconds, 30)
        self.assertEqual(value.movement_threshold_mps, 0)
        self.assertEqual(value.default_gap_threshold_seconds, 3600)

    def test_rejects_empty_or_null_update(self):
        with self.assertRaises(ValidationError):
            SystemSettingsUpdate()
        with self.assertRaises(ValidationError):
            SystemSettingsUpdate(movement_threshold_mps=None)

    def test_rejects_values_outside_every_range(self):
        invalid_payloads = [
            {"offline_timeout_seconds": 29},
            {"offline_timeout_seconds": 86401},
            {"movement_threshold_mps": -0.01},
            {"movement_threshold_mps": 10.01},
            {"default_gap_threshold_seconds": 59},
            {"default_gap_threshold_seconds": 3601},
        ]
        for payload in invalid_payloads:
            with self.subTest(payload=payload), self.assertRaises(ValidationError):
                SystemSettingsUpdate(**payload)

    def test_admin_guard_rejects_user_role(self):
        with self.assertRaises(HTTPException) as context:
            _require_admin_role(_account(UserRole.USER))
        self.assertEqual(context.exception.status_code, 403)

    def test_admin_guard_accepts_admin_role(self):
        admin = _account(UserRole.ADMIN)
        self.assertIs(_require_admin_role(admin), admin)


class SystemSettingsServiceTest(unittest.IsolatedAsyncioTestCase):
    async def test_partial_update_preserves_other_fields_and_writes_audit(self):
        model = SystemSetting(
            id=1,
            offline_timeout_seconds=300,
            movement_threshold_mps=0.5,
            default_gap_threshold_seconds=300,
        )
        session = _FakeSession(model)
        admin = _account(UserRole.ADMIN)
        service = SystemSettingsService()

        updated = await service.update_settings(
            session,
            SystemSettingsUpdate(movement_threshold_mps=1.0),
            actor=admin,
        )

        self.assertIs(updated, model)
        self.assertEqual(updated.offline_timeout_seconds, 300)
        self.assertEqual(updated.movement_threshold_mps, 1.0)
        self.assertEqual(updated.default_gap_threshold_seconds, 300)
        self.assertEqual(session.commit_count, 1)
        audit = next(value for value in session.added if isinstance(value, AuditLog))
        self.assertEqual(audit.action, "SYSTEM_SETTINGS_UPDATED")
        self.assertEqual(audit.actor_user_id, admin.id)
        self.assertEqual(audit.old_value["movement_threshold_mps"], 0.5)
        self.assertEqual(audit.new_value["movement_threshold_mps"], 1.0)
        runtime = await service.get_runtime_settings()
        self.assertEqual(runtime.movement_threshold_mps, 1.0)

    async def test_missing_singleton_is_recreated_with_compatible_defaults(self):
        session = _FakeSession(None)
        service = SystemSettingsService()

        model = await service.get_settings(session)

        self.assertEqual(model.id, 1)
        self.assertEqual(model.movement_threshold_mps, 0.5)
        self.assertEqual(session.commit_count, 1)
        self.assertIn(model, session.added)


class UserSettingsMergeTest(unittest.IsolatedAsyncioTestCase):
    async def test_preferences_patch_keeps_unrelated_keys(self):
        user = _account(UserRole.USER)
        settings = UserSetting(
            user_id=user.id,
            preferences={
                "map_type": "street",
                "speed_unit": "kmh",
                "existing_key": "keep",
            },
        )
        session = _FakeSession(None)

        with patch.object(
            UserService,
            "get_settings",
            new=AsyncMock(return_value=settings),
        ):
            result = await UserService.update_settings(
                session,
                user,
                UserSettingsUpdate(preferences={"map_type": "satellite"}),
            )

        self.assertEqual(
            result.preferences,
            {
                "map_type": "satellite",
                "speed_unit": "kmh",
                "existing_key": "keep",
            },
        )
        self.assertEqual(session.commit_count, 1)


if __name__ == "__main__":
    unittest.main()
