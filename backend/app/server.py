# Entrypoint chạy Uvicorn bằng cùng Settings với toàn backend, tránh host/port/reload
# bị khai báo lặp trong script khởi động hoặc câu lệnh triển khai.
import uvicorn

from app.core.config import settings


def run() -> None:
    """Khởi động Uvicorn bằng cùng nguồn cấu hình `.env` với toàn backend."""
    uvicorn.run(
        "app.main:app",
        host=settings.api_host,
        port=settings.api_port,
        reload=settings.api_reload,
        proxy_headers=True,
    )


if __name__ == "__main__":
    run()
