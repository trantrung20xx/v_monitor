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
