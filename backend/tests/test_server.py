# Xác nhận Uvicorn lấy host, port và reload từ Settings dùng chung.
import os
import sys
import unittest
from pathlib import Path
from unittest import mock


os.environ.setdefault(
    "DATABASE_URL",
    "postgresql+asyncpg://test:test@localhost:5432/v_monitor_test",
)
os.environ.setdefault("JWT_SECRET", "x" * 48)
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from app.core.config import Settings  # noqa: E402
from app import server  # noqa: E402


class ServerTest(unittest.TestCase):
    def test_uses_the_shared_backend_settings(self):
        runtime_settings = Settings(
            _env_file=None,
            database_url="postgresql+asyncpg://user:pass@localhost:5432/app",
            api_host="127.0.0.1",
            api_port=9100,
            api_reload=True,
        )

        with (
            mock.patch.object(server, "settings", runtime_settings),
            mock.patch.object(server.uvicorn, "run") as run_server,
        ):
            server.run()

        run_server.assert_called_once_with(
            "app.main:app",
            host="127.0.0.1",
            port=9100,
            reload=True,
            proxy_headers=True,
        )


if __name__ == "__main__":
    unittest.main()
