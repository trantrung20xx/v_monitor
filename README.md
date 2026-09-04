# VMonitor

VMonitor là hệ thống giám sát vị trí thiết bị theo thời gian thực, xem lịch sử hành trình và quản trị thiết bị, tài khoản. Hệ thống gồm Flutter, FastAPI, PostgreSQL/PostGIS, MQTT và WebSocket.

Tài liệu kiến trúc, cấu hình, API, vận hành và bàn giao đầy đủ nằm tại [docs/SYSTEM_DOCUMENTATION.md](docs/SYSTEM_DOCUMENTATION.md).

## Cách chạy khuyến nghị: Docker trên Ubuntu Server

### 1. Chuẩn bị

- Ubuntu Server có Docker Engine và Docker Compose v2.
- Domain có bản ghi DNS `A` trỏ về IP server.
- Firewall mở TCP `80` và `443`.
- Source code được đặt trên server.

### 2. Cấu hình

Chạy tại thư mục gốc dự án:

```bash
cp .env.docker.example .env.docker
openssl rand -hex 24
openssl rand -hex 32
nano .env.docker
```

Điền các giá trị sau trong `.env.docker`:

- `DOMAIN`: tên miền, không thêm `https://` và không thêm dấu `/` cuối.
- `POSTGRES_PASSWORD`: kết quả của `openssl rand -hex 24`.
- `JWT_SECRET`: kết quả của `openssl rand -hex 32`.
- `MQTT_*`: thông tin broker MQTT production.

Không commit hoặc bàn giao `.env.docker` qua Git. Broker công cộng trong file mẫu chỉ dùng để thử kết nối; production cần broker riêng có tài khoản và TLS.

### 3. Khởi động

```bash
docker compose --env-file .env.docker up -d --build
docker compose --env-file .env.docker ps
```

Kiểm tra `https://<DOMAIN>/health`. Kết quả hợp lệ có HTTP `200` và trạng thái hệ thống trong JSON.

Tạo tài khoản quản trị đầu tiên:

```bash
docker compose --env-file .env.docker exec backend \
  python scripts/create_admin.py --username admin --full-name "Quản trị viên"
```

Mật khẩu được nhập ẩn tại terminal. Sau đó mở `https://<DOMAIN>` và đăng nhập.

### 4. Xem log và cập nhật

```bash
docker compose --env-file .env.docker logs -f --tail=100
```

```bash
git pull
docker compose --env-file .env.docker up -d --build
```

Migration Alembic tự chạy trước khi backend khởi động. Các service có chính sách `restart: unless-stopped`; dữ liệu PostgreSQL và chứng chỉ HTTPS nằm trong Docker volume.

## Chạy môi trường phát triển trên Windows

### 1. Yêu cầu

- Flutter `3.44.6` hoặc phiên bản tương thích với Dart `^3.12.2`.
- Python `3.12` trở lên.
- PostgreSQL có PostGIS.
- Broker MQTT có thể truy cập từ máy chạy backend.

### 2. Backend

```powershell
py -m venv .venv
.\.venv\Scripts\python.exe -m pip install --upgrade pip
.\.venv\Scripts\python.exe -m pip install -r backend\requirements.txt
Copy-Item backend\.env.example backend\.env
```

Sửa `backend/.env`, tối thiểu gồm `DATABASE_URL`, `MQTT_*`, `JWT_SECRET` và `CORS_ORIGINS`. Sau đó chạy:

```powershell
.\run_backend.bat
```

Script tự chạy `alembic upgrade head` rồi mở API theo `API_HOST` và `API_PORT`. Alembic chỉ bootstrap schema khi database không có bảng nghiệp vụ.

### 3. Flutter

Mở terminal khác tại thư mục gốc:

```powershell
flutter pub get
flutter run -d windows --dart-define-from-file=config/development.json
```

`API_BASE_URL` trong `config/development.json` phải truy cập được backend và phải chứa `/api/v1`.

## Kiểm tra trước khi phát hành

```powershell
flutter analyze
flutter test
flutter build web --release --dart-define-from-file=config/production.json
flutter build windows --release --dart-define-from-file=config/production.json
.\.venv\Scripts\python.exe -m unittest discover -s backend\tests -v
docker compose --env-file .env.docker.example config --quiet
```

Bản Windows phải phân phối toàn bộ thư mục `build/windows/x64/runner/Release`; không phân phối riêng `v_monitor.exe`.

## Cấu trúc chính

```text
backend/                 FastAPI, Alembic, model, service và test backend
lib/                     mã nguồn Flutter
test/                    test Flutter
config/                  cấu hình frontend theo môi trường build
docker/                  Dockerfile và Caddy
scripts/test_mqtt.py     công cụ gửi dữ liệu MQTT thử nghiệm
compose.yaml             PostGIS, backend và web production
```

Không sửa trực tiếp migration cũ đã chạy trên production. Không đưa `backend/.env`, `.env.docker`, mật khẩu database, MQTT hoặc JWT secret vào Git.
