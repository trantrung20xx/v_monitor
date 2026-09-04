"""Môi trường migration Alembic bất đồng bộ của v_monitor."""

import asyncio
from logging.config import fileConfig

from alembic import context
from sqlalchemy import pool
import sqlalchemy as sa
from sqlalchemy.ext.asyncio import async_engine_from_config

from app.core.config import settings
from app.models import Base  # noqa: F401 - nạp toàn bộ model vào metadata

# Đối tượng config của lần chạy Alembic hiện tại, ban đầu lấy từ alembic.ini.
config = context.config

if config.config_file_name is not None:
    fileConfig(config.config_file_name)

# Metadata hợp nhất của mọi model, dùng cho autogenerate và bootstrap database mới.
target_metadata = Base.metadata

# Tên bảng thuộc extension được nạp khi chạy online để không bị xem là schema ứng dụng.
extension_table_names: set[str] = set()


def _extension_tables(connection) -> set[str]:
    rows = connection.execute(
        sa.text(
            """
            SELECT relation.relname
            FROM pg_depend AS dependency
            JOIN pg_extension AS extension
              ON extension.oid = dependency.refobjid
            JOIN pg_class AS relation
              ON relation.oid = dependency.objid
            WHERE dependency.classid = 'pg_class'::regclass
              AND dependency.refclassid = 'pg_extension'::regclass
              AND dependency.deptype = 'e'
              AND relation.relkind IN ('r', 'p')
            """
        )
    )
    return set(rows.scalars())


def include_object(object_, name, type_, reflected, compare_to):
    """Bỏ qua hạ tầng do PostGIS quản lý khi Alembic so sánh schema."""
    if type_ == "table" and name in extension_table_names | {"spatial_ref_sys"}:
        return False
    parent_table = getattr(object_, "table", None)
    if reflected and getattr(parent_table, "name", None) in extension_table_names:
        return False
    return True


def _is_upgrade_command() -> bool:
    """Chỉ cho phép khởi tạo schema trong lệnh Alembic upgrade."""
    command = getattr(getattr(config, "cmd_opts", None), "cmd", None)
    if not isinstance(command, tuple) or not command:
        return False
    return getattr(command[0], "__name__", "") == "upgrade"


def _bootstrap_empty_database(connection) -> None:
    """Khởi tạo schema khi database PostGIS hoàn toàn chưa có bảng nghiệp vụ."""
    if not _is_upgrade_command():
        return
    infrastructure_tables = {
        "alembic_version",
        "spatial_ref_sys",
        *extension_table_names,
    }
    application_tables = set(sa.inspect(connection).get_table_names()) - infrastructure_tables
    if not application_tables:
        # Kiểu geography của các bảng vị trí do PostGIS cung cấp. Extension phải
        # được tạo trước create_all để database PostgreSQL hoàn toàn mới có thể
        # dựng các cột và chỉ mục không gian ngay trong lần upgrade đầu tiên.
        connection.execute(sa.text("CREATE EXTENSION IF NOT EXISTS postgis"))
        target_metadata.create_all(connection)
    # Cả thao tác inspect và create_all đều có thể mở transaction ngầm;
    # kết thúc transaction này trước khi Alembic ghi nhận revision.
    connection.commit()

# Lấy URL từ .env để không phải lặp thông tin xác thực trong alembic.ini.
config.set_main_option(
    "sqlalchemy.url",
    settings.database_url,
)


def run_migrations_offline() -> None:
    """Chạy migration ngoại tuyến và xuất câu lệnh SQL ra stdout."""
    url = config.get_main_option("sqlalchemy.url")
    context.configure(
        url=url,
        target_metadata=target_metadata,
        include_object=include_object,
        literal_binds=True,
        dialect_opts={"paramstyle": "named"},
    )
    with context.begin_transaction():
        context.run_migrations()


def do_run_migrations(connection):
    global extension_table_names
    extension_table_names = _extension_tables(connection)
    # Cấu hình context trên kết nối đồng bộ do AsyncConnection chuyển giao.
    _bootstrap_empty_database(connection)
    context.configure(
        connection=connection,
        target_metadata=target_metadata,
        include_object=include_object,
    )
    with context.begin_transaction():
        context.run_migrations()


async def run_async_migrations() -> None:
    """Chạy migration trực tuyến bằng engine bất đồng bộ."""
    connectable = async_engine_from_config(
        config.get_section(config.config_ini_section, {}),
        prefix="sqlalchemy.",
        poolclass=pool.NullPool,
    )
    async with connectable.connect() as connection:
        await connection.run_sync(do_run_migrations)
    await connectable.dispose()


def run_migrations_online() -> None:
    # Cầu nối đồng bộ mà Alembic gọi để chạy quy trình async qua asyncio.
    asyncio.run(run_async_migrations())


if context.is_offline_mode():
    run_migrations_offline()
else:
    run_migrations_online()
