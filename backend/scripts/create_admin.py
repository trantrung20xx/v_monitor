"""Tạo tài khoản quản trị đầu tiên bằng dòng lệnh"""

import argparse
import asyncio
from getpass import getpass
from pathlib import Path
import sys

from pydantic import ValidationError


sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

# Windows có thể mặc định dùng cp1252; ép UTF-8 để thông báo tiếng Việt không lỗi.
if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
if hasattr(sys.stderr, "reconfigure"):
    sys.stderr.reconfigure(encoding="utf-8", errors="replace")

from app.core.database import AsyncSessionLocal, engine
from app.domain.enums import UserRole
from app.schemas.auth import UserCreate
from app.services.user_service import DuplicateAccountError, UserService


MIN_PASSWORD_LENGTH = 8
MAX_PASSWORD_LENGTH = 128


def _arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Tạo tài khoản quản trị v_monitor")
    parser.add_argument("--username", required=True, help="Tên đăng nhập")
    parser.add_argument("--full-name", required=True, help="Tên hiển thị")
    parser.add_argument("--email", help="Email nội bộ, không bắt buộc")
    parser.add_argument(
        "--password",
        help=(
            "Mật khẩu từ 8 đến 128 ký tự; không nên truyền trực tiếp, "
            "bỏ trống để nhập kín từ bàn phím"
        ),
    )
    return parser.parse_args()


async def _create_admin(arguments: argparse.Namespace) -> int:
    password = _read_password(arguments.password)
    if password is None:
        return 2

    try:
        account = UserCreate(
            username=arguments.username,
            password=password,
            full_name=arguments.full_name,
            email=arguments.email,
            role=UserRole.ADMIN,
            is_active=True,
        )
        async with AsyncSessionLocal() as db:
            user = await UserService.create_account(
                db,
                account,
                actor_user_id=None,
            )
    except ValidationError as exc:
        _print_validation_errors(exc)
        return 2
    except DuplicateAccountError as exc:
        print(str(exc), file=sys.stderr)
        return 1
    finally:
        await engine.dispose()

    print(f"Đã tạo tài khoản quản trị '{user.username}'")
    return 0


def _password_error(password: str) -> str | None:
    if len(password) < MIN_PASSWORD_LENGTH:
        return f"Mật khẩu phải có ít nhất {MIN_PASSWORD_LENGTH} ký tự."
    if len(password) > MAX_PASSWORD_LENGTH:
        return f"Mật khẩu không được vượt quá {MAX_PASSWORD_LENGTH} ký tự."
    return None


def _read_password(provided_password: str | None) -> str | None:
    if provided_password is not None:
        error = _password_error(provided_password)
        if error:
            print(error, file=sys.stderr)
            return None
        return provided_password

    while True:
        password = getpass("Mật khẩu quản trị (tối thiểu 8 ký tự): ")
        confirmation = getpass("Nhập lại mật khẩu: ")
        if password != confirmation:
            print("Hai lần nhập mật khẩu không khớp. Vui lòng nhập lại.", file=sys.stderr)
            continue

        error = _password_error(password)
        if error:
            print(f"{error} Vui lòng nhập lại.", file=sys.stderr)
            continue
        return password


def _print_validation_errors(exc: ValidationError) -> None:
    # Dữ liệu dòng lệnh phải được báo ngắn gọn thay vì in traceback nội bộ của
    # Pydantic. Giá trị mật khẩu tuyệt đối không được đưa vào nội dung lỗi.
    field_names = {
        "username": "Tên đăng nhập",
        "password": "Mật khẩu",
        "full_name": "Tên hiển thị",
        "email": "Email",
    }
    for error in exc.errors(include_url=False, include_input=False):
        field = str(error.get("loc", ("dữ liệu",))[0])
        label = field_names.get(field, field)
        message = error.get("msg", "Giá trị không hợp lệ")
        print(f"{label} không hợp lệ: {message}", file=sys.stderr)


if __name__ == "__main__":
    raise SystemExit(asyncio.run(_create_admin(_arguments())))
