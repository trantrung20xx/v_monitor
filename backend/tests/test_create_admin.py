# Xác nhận công cụ tạo ADMIN dùng cùng giới hạn mật khẩu và báo lỗi dòng lệnh an toàn.
import unittest
from contextlib import redirect_stderr
from io import StringIO
from unittest.mock import patch

from pydantic import ValidationError

from app.schemas.auth import ChangePasswordRequest, ResetPasswordRequest, UserCreate
from scripts.create_admin import _password_error, _read_password


class CreateAdminScriptTest(unittest.TestCase):
    def test_rejects_short_password_without_traceback(self):
        self.assertEqual(
            _password_error("abc123"),
            "Mật khẩu phải có ít nhất 8 ký tự.",
        )
        with redirect_stderr(StringIO()):
            self.assertIsNone(_read_password("abc123"))

    def test_accepts_password_with_required_length(self):
        self.assertIsNone(_password_error("atl132456"))
        self.assertEqual(_read_password("atl132456"), "atl132456")

    def test_account_and_password_schemas_use_eight_character_minimum(self):
        UserCreate(
            username="admin",
            password="12345678",
            full_name="Quản trị viên",
        )
        ChangePasswordRequest(
            current_password="mat-khau-cu",
            new_password="12345678",
        )
        ResetPasswordRequest(new_password="12345678")

        invalid_inputs = (
            lambda: UserCreate(
                username="admin",
                password="1234567",
                full_name="Quản trị viên",
            ),
            lambda: ChangePasswordRequest(
                current_password="mat-khau-cu",
                new_password="1234567",
            ),
            lambda: ResetPasswordRequest(new_password="1234567"),
        )
        for build_request in invalid_inputs:
            with self.subTest(build_request=build_request):
                with self.assertRaises(ValidationError):
                    build_request()

    @patch("scripts.create_admin.getpass")
    def test_interactive_mode_reprompts_until_password_is_valid(self, getpass_mock):
        getpass_mock.side_effect = [
            "abc123",
            "abc123",
            "atl132456",
            "khong-khop",
            "atl132456",
            "atl132456",
        ]

        with redirect_stderr(StringIO()):
            self.assertEqual(_read_password(None), "atl132456")
        self.assertEqual(getpass_mock.call_count, 6)


if __name__ == "__main__":
    unittest.main()
