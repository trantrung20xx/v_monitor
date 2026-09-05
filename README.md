# VMonitor

VMonitor là hệ thống giám sát vị trí thiết bị theo thời gian thực, xem lịch sử hành trình và quản trị thiết bị, tài khoản. Hệ thống gồm Flutter, FastAPI, PostgreSQL/PostGIS, MQTT và WebSocket.

Tài liệu kiến trúc, cấu hình, API và vận hành đầy đủ nằm tại [docs/SYSTEM_DOCUMENTATION.md](docs/SYSTEM_DOCUMENTATION.md).

## Cách chạy khuyến nghị: Docker trên Ubuntu Server

### 1. Chuẩn bị

- Ubuntu Server có Docker Engine và Docker Compose v2.
- Domain có bản ghi DNS `A` trỏ về IP server.
- Firewall mở TCP `80` và `443`.
- Source code được đặt trên server.

Kiểm tra Docker trước khi triển khai:

```bash
docker version
docker compose version
```

`docker version` phải hiển thị cả `Client` và `Server`.

### 2. Cấu hình

Chạy tại thư mục gốc dự án:

```bash
cp .env.docker.example .env.docker
openssl rand -hex 24
openssl rand -hex 32
nano .env.docker
```

Điền các giá trị sau trong `.env.docker`:

- `DOMAIN`: tên miền thật đã trỏ DNS về server; phải thay `monitor.example.com`, không thêm `https://` và không thêm dấu `/` cuối.
- `POSTGRES_PASSWORD`: kết quả của `openssl rand -hex 24`.
- `JWT_SECRET`: kết quả của `openssl rand -hex 32`.
- `MQTT_*`: thông tin broker MQTT production.

Không đưa `.env.docker` vào Git hoặc gói source code. Broker công cộng trong file mẫu chỉ dùng để thử kết nối; production cần broker riêng có tài khoản và TLS.

### 3. Khởi động

```bash
docker compose --env-file .env.docker config --quiet
docker compose --env-file .env.docker up -d --build
docker compose --env-file .env.docker ps
```

Lệnh `config --quiet` không xuất lỗi nghĩa là cấu hình Compose hợp lệ. Kiểm tra `https://<DOMAIN>/health`; kết quả sẵn sàng phải có `"status":"ok"`, `"database":"connected"`, `mqtt.connected: true` và `mqtt.subscribed: true`. HTTP `200` kèm `"status":"degraded"` chưa phải trạng thái production sẵn sàng.

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

## Chạy thử Docker trên Windows

Quy trình này chạy Flutter Web, FastAPI và PostgreSQL/PostGIS bằng Docker Desktop. Bản Flutter Windows `.exe` được build riêng, không chạy trong container.

### 1. Kiểm tra Docker Desktop

Docker Desktop phải chạy Linux containers và hiển thị `Engine running`.

```powershell
docker version
docker compose version
```

`docker version` phải có cả `Client` và `Server`. Lỗi `dockerDesktopLinuxEngine` hoặc `The system cannot find the file specified` nghĩa là Docker Engine chưa chạy. Khởi động lại theo thứ tự:

```powershell
wsl --shutdown
```

Sau đó mở lại Docker Desktop và chờ `Engine running` trước khi chạy lệnh Compose.

### 2. Tạo cấu hình local

Chạy tại thư mục gốc dự án:

```powershell
Copy-Item .env.docker.example .env.docker
[guid]::NewGuid().ToString("N")
[guid]::NewGuid().ToString("N") + [guid]::NewGuid().ToString("N")
notepad .env.docker
```

Cấu hình tối thiểu cần thay:

```env
DOMAIN=localhost
POSTGRES_PASSWORD=<kết quả lệnh tạo chuỗi thứ nhất>
JWT_SECRET=<kết quả lệnh tạo chuỗi thứ hai>
MQTT_HOST=broker.emqx.io
MQTT_PORT=1883
MQTT_USE_TLS=false
MQTT_TOPIC_PREFIX=v_monitor/windows_test
```

Giữ nguyên các biến còn lại trong file mẫu. Broker công cộng chỉ phù hợp kiểm tra local.

### 3. Khởi động và xác nhận

```powershell
docker compose --env-file .env.docker config --quiet
docker compose --env-file .env.docker up -d --build
docker compose --env-file .env.docker ps
```

Ba container phải xuất hiện: `v-monitor-db-1`, `v-monitor-backend-1`, `v-monitor-web-1`. `db` và `backend` phải đạt `healthy`.

Kiểm tra endpoint bằng URL thô, không thêm `[]` hoặc `()`:

```powershell
curl.exe -k https://localhost/health
```

Kết quả sẵn sàng phải có `"status":"ok"`. Chứng chỉ HTTPS local do Caddy phát hành có thể tạo cảnh báo trong trình duyệt; cảnh báo này chỉ áp dụng cho `localhost`.

Tạo tài khoản quản trị:

```powershell
docker compose --env-file .env.docker exec backend python scripts/create_admin.py --username admin --full-name "Quản trị viên"
```

Mở giao diện:

```powershell
Start-Process https://localhost
```

Dừng container nhưng giữ database và chứng chỉ:

```powershell
docker compose --env-file .env.docker down
```

`docker compose --env-file .env.docker down -v` xóa toàn bộ database local và các volume; chỉ dùng khi cần tạo lại môi trường thử nghiệm từ đầu.

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
.\.venv\Scripts\python.exe -m unittest discover -s backend\tests -v
docker compose --env-file .env.docker.example config --quiet
```

Trước khi build Flutter độc lập, thay `API_BASE_URL` mẫu trong `config/production.json` bằng `https://<DOMAIN>/api/v1`, sau đó chạy:

```powershell
flutter build web --release --dart-define-from-file=config/production.json
flutter build windows --release --dart-define-from-file=config/production.json
```

Docker Web lấy domain trực tiếp từ `.env.docker`, không đọc `config/production.json`.

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
