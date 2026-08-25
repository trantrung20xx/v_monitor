# Xác nhận băm mật khẩu, yêu cầu secret và các claim nhận dạng/version trong JWT.
import os
import sys
import unittest
import uuid
from pathlib import Path


os.environ.setdefault(
    "DATABASE_URL",
    "postgresql+asyncpg://test:test@localhost:5432/v_monitor_test",
)
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from app.core import security  # noqa: E402


class _User:
    id = uuid.uuid4()
    token_version = 3


class SecurityTest(unittest.TestCase):
    def setUp(self):
        self.old_secret = security.settings.jwt_secret
        security.settings.jwt_secret = "x" * 48

    def tearDown(self):
        security.settings.jwt_secret = self.old_secret

    def test_password_is_hashed_and_verified(self):
        password_hash = security.hash_password("Mat-khau-rat-manh-123")
        self.assertNotIn("Mat-khau-rat-manh-123", password_hash)
        self.assertTrue(security.verify_password("Mat-khau-rat-manh-123", password_hash))
        self.assertFalse(security.verify_password("sai-mat-khau", password_hash))

    def test_token_contains_identity_and_version(self):
        token = security.create_access_token(_User())
        payload = security.decode_access_token(token)
        self.assertEqual(payload["sub"], str(_User.id))
        self.assertEqual(payload["ver"], 3)
        self.assertNotIn("exp", payload)
        self.assertNotIn("role", payload)

    def test_short_secret_is_rejected(self):
        security.settings.jwt_secret = "too-short"
        with self.assertRaises(RuntimeError):
            security.create_access_token(_User())


if __name__ == "__main__":
    unittest.main()
