"""Nạp catalog LTE CSV vào PostgreSQL bằng upsert theo identity đầy đủ.

Script là đường nạp có kiểm tra cho nguồn anchor đã được cấp quyền. Không lấy
catalog từ Internet trong MQTT worker: dữ liệu được kiểm tra trước, import theo
lô, rồi worker chỉ đọc index nội bộ có độ trễ ổn định.

Ví dụ:
  uv run python scripts/import_cell_catalog.py --input towers.csv --source provider-2026-09
"""
import argparse
import asyncio
import csv
from pathlib import Path

from pydantic import ValidationError
from sqlalchemy.dialects.postgresql import insert

from app.core.database import AsyncSessionLocal
from app.models.cell_tower import CellTower
from app.schemas.cellular import CellTowerImportRow


def _arguments() -> argparse.Namespace:
    # --source được lưu trên mọi row để sau này biết estimate đã dựa vào phiên
    # bản/dataset nào; đây không phải URL được worker gọi tại runtime.
    parser = argparse.ArgumentParser(description="Nạp LTE cell catalog đã được cấp quyền sử dụng")
    parser.add_argument("--input", required=True, type=Path, help="CSV UTF-8 có header canonical")
    parser.add_argument("--source", required=True, help="Tên/phiên bản nguồn catalog")
    parser.add_argument("--dry-run", action="store_true", help="Chỉ kiểm tra dữ liệu, không ghi database")
    return parser.parse_args()


def _values(row: CellTowerImportRow, source: str) -> dict:
    # Lat/lon tồn tại song song với Geography: công thức Python dùng Float còn
    # PostGIS dùng WKT có thứ tự kinh độ, vĩ độ (X, Y), không phải lat/lon.
    values = row.model_dump(exclude_none=True)
    values["source"] = source
    values["location"] = f"SRID=4326;POINT({row.longitude} {row.latitude})"
    return values


async def _import(arguments: argparse.Namespace) -> int:
    if not arguments.input.is_file():
        raise FileNotFoundError(f"Không tìm thấy file catalog: {arguments.input}")
    accepted = 0
    rejected = 0
    # Một transaction cho cả file: nếu process/DB lỗi giữa chừng sẽ không để lại
    # catalog nửa chừng. Dòng validation lỗi được báo riêng để người vận hành sửa
    # file thay vì âm thầm bỏ qua.
    async with AsyncSessionLocal() as db:
        with arguments.input.open("r", encoding="utf-8-sig", newline="") as file:
            for line_number, raw in enumerate(csv.DictReader(file), start=2):
                try:
                    row = CellTowerImportRow.model_validate(raw)
                except ValidationError as exc:
                    rejected += 1
                    print(f"REJECT line={line_number} reason={exc.errors()[0]['msg']}")
                    continue
                accepted += 1
                if arguments.dry_run:
                    continue
                values = _values(row, arguments.source)
                # Upsert theo identity giữ id row ổn định, cập nhật vị trí/chất
                # lượng mới mà không tạo anchor trùng khiến estimator đếm sai.
                statement = insert(CellTower).values(**values)
                statement = statement.on_conflict_do_update(
                    constraint="uq_cell_towers_identity",
                    set_={
                        column: value
                        for column, value in values.items()
                        if column not in {"rat", "mcc", "mnc", "tac", "cell_id"}
                    },
                )
                await db.execute(statement)
        # dry-run vẫn parse toàn bộ CSV và đếm rejected nhưng rollback bắt buộc để
        # không có một row nào chạm vào catalog production.
        if arguments.dry_run:
            await db.rollback()
        else:
            await db.commit()
    print(f"CELL_CATALOG_IMPORT accepted={accepted} rejected={rejected} dry_run={arguments.dry_run}")
    return 0 if rejected == 0 else 2


if __name__ == "__main__":
    raise SystemExit(asyncio.run(_import(_arguments())))
