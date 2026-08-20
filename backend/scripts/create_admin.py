"""Tạo tài khoản quản trị đầu tiên bằng dòng lệnh"""

import argparse
import asyncio
from getpass import getpass
from pathlib import Path
import sys


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


def _arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Tạo tài khoản quản trị v_monitor")
    parser.add_argument("--username", required=True, help="Tên đăng nhập")
    parser.add_argument("--full-name", required=True, help="Tên hiển thị")
    parser.add_argument("--email", help="Email nội bộ, không bắt buộc")
    parser.add_argument(
        "--password",
        help="Không nên truyền trực tiếp; bỏ trống để nhập kín từ bàn phím",
    )
    return parser.parse_args()


async def _create_admin(arguments: argparse.Namespace) -> int:
    password = arguments.password or getpass("Mật khẩu quản trị: ")
    if arguments.password is None:
        confirmation = getpass("Nhập lại mật khẩu: ")
        if password != confirmation:
            print("Hai lần nhập mật khẩu không khớp", file=sys.stderr)
            return 2

    account = UserCreate(
        username=arguments.username,
        password=password,
        full_name=arguments.full_name,
        email=arguments.email,
        role=UserRole.ADMIN,
        is_active=True,
    )
    try:
        async with AsyncSessionLocal() as db:
            user = await UserService.create_account(
                db,
                account,
                actor_user_id=None,
            )
    except DuplicateAccountError as exc:
        print(str(exc), file=sys.stderr)
        return 1
    finally:
        await engine.dispose()

    print(f"Đã tạo tài khoản quản trị '{user.username}'")
    return 0


if __name__ == "__main__":
    raise SystemExit(asyncio.run(_create_admin(_arguments())))
