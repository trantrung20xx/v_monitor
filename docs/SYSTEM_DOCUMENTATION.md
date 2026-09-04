# Tài liệu mô tả hệ thống VMonitor

## 1. Mục đích

VMonitor tiếp nhận vị trí từ thiết bị qua MQTT hoặc REST, lưu dữ liệu vào PostgreSQL/PostGIS và cập nhật giao diện Flutter qua WebSocket. Hệ thống hỗ trợ:

- Giám sát vị trí và trạng thái online/offline.
- Xem lịch sử hành trình, điểm dừng và sự kiện di chuyển.
- Quản lý thiết bị và thiết bị MQTT đã phát hiện.
- Quản lý tài khoản, vai trò và thiết lập hệ thống.
- Tra cứu địa chỉ từ tọa độ qua dịch vụ geocoding.

## 2. Kiến trúc và luồng dữ liệu

```text
Thiết bị GPS
    │ MQTT: <MQTT_TOPIC_PREFIX>/<device_code>
    ▼
FastAPI ─────► PostgreSQL + PostGIS
    │                 │
    │ WebSocket       │ REST API
    └────────────┬────┘
                 ▼
             Flutter App
```

Thành phần production trong Docker:

| Service | Vai trò | Truy cập ngoài server |
|---|---|---|
| `db` | PostgreSQL 16 và PostGIS | Không public cổng |
| `backend` | FastAPI, MQTT worker, WebSocket, Alembic | Không public cổng `8000` |
| `web` | Caddy, Flutter Web, HTTPS, reverse proxy | TCP `80`, `443` |

Caddy tự cấp chứng chỉ HTTPS khi DNS và firewall đúng. REST, WebSocket và Flutter Web dùng chung domain.

## 3. Cấu trúc mã nguồn

| Đường dẫn | Nội dung |
|---|---|
| `lib/app` | router, theme và khung ứng dụng Flutter |
| `lib/core` | cấu hình, REST client, WebSocket và widget dùng chung |
| `lib/features` | đăng nhập, dashboard, chi tiết thiết bị, hành trình, cài đặt |
| `backend/app/api/v1` | endpoint REST và WebSocket |
| `backend/app/services` | nghiệp vụ thiết bị, tracking, MQTT, realtime, auth |
| `backend/app/models` | model SQLAlchemy |
| `backend/app/schemas` | hợp đồng request/response Pydantic |
| `backend/alembic` | lịch sử migration database |
| `backend/tests` | unit test backend |
| `test` | unit và widget test Flutter |
| `config` | cấu hình frontend tại thời điểm build |
| `docker` | image backend, image Flutter Web và Caddy |

## 4. Cơ sở dữ liệu

Các bảng nghiệp vụ hiện hành:

| Bảng | Mục đích |
|---|---|
| `devices` | thông tin và quyền nhận dữ liệu của thiết bị |
| `device_latest_state` | trạng thái mới nhất và thời điểm xuất hiện gần nhất |
| `location_samples` | lịch sử tọa độ bất biến |
| `telemetry_messages` | nhật ký gói MQTT và chống trùng |
| `device_events` | sự kiện bắt đầu/dừng di chuyển và sự kiện thiết bị |
| `mqtt_device_sightings` | thiết bị MQTT đã thấy nhưng chưa đăng ký |
| `user_accounts` | tài khoản, vai trò, khóa đăng nhập và phiên bản token |
| `user_settings` | thiết lập riêng của tài khoản |
| `system_settings` | thiết lập dùng chung toàn hệ thống |
| `audit_logs` | nhật ký thao tác quản trị |

`alembic_version` và `spatial_ref_sys` là dữ liệu hạ tầng của Alembic/PostGIS, không phải bảng nghiệp vụ để xóa.

Migration mới phải được tạo thành revision mới. Không sửa hoặc xóa migration đã chạy trên production. Trước mọi thay đổi schema phải sao lưu database và thử trên bản sao.

Database cũ có bảng nghiệp vụ nhưng thiếu hoặc rỗng `alembic_version` phải được sao lưu và thử nâng cấp trên bản sao trước. Không tự chạy `alembic stamp` trên production khi chưa xác định chính xác revision tương ứng với schema hiện có.

## 5. Xác thực và phân quyền

- `AUTH_REQUIRED=true` là cấu hình production bắt buộc.
- `JWT_SECRET` phải có ít nhất 32 ký tự và phải được giữ bí mật.
- Vai trò `ADMIN` quản trị tài khoản, thiết bị và thiết lập hệ thống.
- Vai trò `USER` sử dụng chức năng giám sát được cấp phép.
- `user_accounts.is_active` là quyền đăng nhập của tài khoản, không phải trạng thái thiết bị.
- Trạng thái thiết bị sử dụng `is_online`, được suy ra từ thời điểm nhận dữ liệu gần nhất và `DEVICE_OFFLINE_TIMEOUT_SECONDS`.
- Thay đổi mật khẩu, vai trò hoặc trạng thái tài khoản làm tăng `token_version`, từ đó thu hồi token cũ.

Không có API đăng ký công khai. Tài khoản quản trị đầu tiên được tạo bằng script dòng lệnh.

## 6. API và WebSocket

Tiền tố mặc định: `/api/v1`.

| Nhóm | Endpoint chính |
|---|---|
| Auth | `POST /auth/login`, `GET /auth/me`, `POST /auth/change-password`, `GET/PATCH /auth/settings` |
| Devices | `GET/POST /devices/`, `GET/PATCH/DELETE /devices/{device_id}` và danh sách MQTT discovery |
| Tracking | `POST /tracking/`, `GET /tracking/{device_id}/history`, `/history/range`, `/events` |
| Geocoding | `GET /geocoding/reverse` |
| Users | `GET/POST /users/`, `PATCH /users/{user_id}`, `POST /users/{user_id}/reset-password` |
| System | `GET/PATCH /system/settings` |
| Realtime | `WS /ws` |
| Health | `GET /health`, không có tiền tố `/api/v1` |

REST sử dụng header:

```http
Authorization: Bearer <access_token>
```

Khi mở WebSocket với xác thực bật, frame đầu tiên phải được gửi trong 10 giây:

```json
{"type":"AUTH","access_token":"<access_token>"}
```

Server trả `{"type":"AUTH_OK"}` khi hợp lệ. Heartbeat sử dụng `PING` và `PONG`. Các cập nhật nghiệp vụ như `DEVICE_UPDATE` và `DEVICE_EVENT` được backend broadcast tới frontend đã xác thực.

## 7. Hợp đồng MQTT

Topic:

```text
<MQTT_TOPIC_PREFIX>/<device_code>
```

Ví dụ payload:

```json
{
  "message_id": "a0b1c2d3-e4f5-4678-9012-3456789abcde",
  "latitude": 10.7769,
  "longitude": 106.7009,
  "altitude_m": 12.5,
  "speed_mps": 4.2,
  "heading_deg": 180.0,
  "measured_at": "2026-09-04T08:00:00Z"
}
```

Quy ước:

- `message_id` phải duy nhất cho mỗi lần đo để chống xử lý trùng khi dùng QoS 1.
- `latitude` và `longitude` bắt buộc để tạo mẫu vị trí.
- `altitude_m`, `speed_mps`, `heading_deg`, `measured_at` là dữ liệu tùy chọn được hỗ trợ.
- `heading_deg` nằm trong khoảng từ `0` đến nhỏ hơn `360`; `speed_mps` không âm.
- `device_code` phải trùng thiết bị đã đăng ký. Thiết bị chưa đăng ký được ghi nhận vào danh sách MQTT discovery.

Gửi dữ liệu thử:

```powershell
$env:DEVICE_CODE="DEVICE_CODE_THAT"
.\.venv\Scripts\python.exe scripts\test_mqtt.py
```

Script đọc cấu hình MQTT từ `backend/.env` và phát QoS 1.

## 8. Cấu hình

### 8.1 Frontend Flutter

Flutter nhận cấu hình tại thời điểm build qua `--dart-define-from-file`:

| File | Mục đích |
|---|---|
| `config/development.json` | backend cục bộ |
| `config/cloudflare.json` | backend qua Cloudflare Tunnel |
| `config/production.json` | domain production |

Biến quan trọng:

- `API_BASE_URL`: URL đầy đủ, gồm `/api/v1`.
- `WS_PATH`: mặc định `/api/v1/ws`.
- `WS_BASE_URL`: chỉ khai báo khi WebSocket dùng host khác REST.
- `CONNECT_TIMEOUT_SECONDS`: timeout mở kết nối HTTP.

Khi `WS_BASE_URL` để trống, ứng dụng tự suy ra `ws://` hoặc `wss://` từ `API_BASE_URL`. Thay đổi file JSON không ảnh hưởng bản đã build; phải build lại Flutter.

### 8.2 Backend chạy cục bộ

Backend đọc biến môi trường và `backend/.env`. File này không được commit.

| Nhóm | Biến cần kiểm tra |
|---|---|
| API | `API_HOST`, `API_PORT`, `API_RELOAD`, `CORS_ORIGINS` |
| Database | `DATABASE_URL`, `DATABASE_POOL_*` |
| MQTT | `MQTT_HOST`, `MQTT_PORT`, `MQTT_USERNAME`, `MQTT_PASSWORD`, `MQTT_USE_TLS`, `MQTT_TOPIC_PREFIX` |
| Auth | `AUTH_REQUIRED`, `JWT_SECRET`, giới hạn đăng nhập sai |
| Presence | `DEVICE_OFFLINE_TIMEOUT_SECONDS`, `DEVICE_OFFLINE_SCAN_INTERVAL_SECONDS` |
| Geocoding | `GEOCODING_PROVIDER`, `GEOCODING_BASE_URL`, `GEOCODING_USER_AGENT` |

`DATABASE_URL` bắt buộc dùng dạng:

```text
postgresql+asyncpg://USER:PASSWORD@HOST:5432/DATABASE
```

`CORS_ORIGINS` là origin frontend, ví dụ `https://monitor.example.com`; không phải địa chỉ bind của backend. Production không dùng `*`.

### 8.3 Docker production

Toàn bộ cấu hình vận hành thường xuyên nằm trong `.env.docker`. `compose.yaml` chuyển các giá trị này vào container. Không sửa source khi chỉ đổi domain, mật khẩu hoặc broker.

## 9. Quy trình triển khai Docker từ đầu

### 9.1 Chuẩn bị server

```bash
docker --version
docker compose version
git --version
```

Yêu cầu DNS `A` trỏ về server và firewall cho phép TCP `80`, `443`.

### 9.2 Tạo cấu hình

```bash
cp .env.docker.example .env.docker
openssl rand -hex 24
openssl rand -hex 32
nano .env.docker
```

Kiểm tra cấu hình trước khi chạy:

```bash
docker compose --env-file .env.docker config --quiet
```

### 9.3 Khởi động và xác nhận

```bash
docker compose --env-file .env.docker up -d --build
docker compose --env-file .env.docker ps
docker compose --env-file .env.docker logs backend --tail=100
```

Kiểm tra lần lượt:

1. Service `db`, `backend`, `web` ở trạng thái chạy; `db` và `backend` đạt `healthy`.
2. `https://<DOMAIN>/health` trả HTTP `200`.
3. Trang `https://<DOMAIN>` tải được giao diện đăng nhập.
4. Log backend không có lỗi migration, database hoặc MQTT lặp liên tục.

Tạo quản trị viên đầu tiên:

```bash
docker compose --env-file .env.docker exec backend \
  python scripts/create_admin.py --username admin --full-name "Quản trị viên"
```

Tên đăng nhập dài tối thiểu 3 ký tự. Mật khẩu được nhập ẩn, dài từ 8 đến 128 ký tự.

### 9.4 Cập nhật

```bash
git pull
docker compose --env-file .env.docker up -d --build
docker compose --env-file .env.docker ps
```

### 9.5 Sao lưu database

```bash
mkdir -p backups
docker compose --env-file .env.docker exec -T db sh -c \
  'pg_dump -U "$POSTGRES_USER" -d "$POSTGRES_DB" -Fc' \
  > "backups/v_monitor-$(date +%F-%H%M).dump"
```

Kiểm tra file sao lưu có dung lượng lớn hơn `0` trước khi cập nhật schema hoặc server.

### 9.6 Dừng hệ thống

```bash
docker compose --env-file .env.docker down
```

Lệnh trên giữ nguyên volume dữ liệu. Không thêm `--volumes` trên production nếu không có kế hoạch xóa toàn bộ database và chứng chỉ.

## 10. Chạy cục bộ

### 10.1 Windows

```powershell
py -m venv .venv
.\.venv\Scripts\python.exe -m pip install --upgrade pip
.\.venv\Scripts\python.exe -m pip install -r backend\requirements.txt
Copy-Item backend\.env.example backend\.env
```

Sửa `backend/.env`, tạo database PostgreSQL có PostGIS, sau đó chạy:

```powershell
.\run_backend.bat
```

Mở terminal khác:

```powershell
flutter pub get
flutter run -d windows --dart-define-from-file=config/development.json
```

### 10.2 Linux hoặc macOS

```bash
python3 -m venv .venv
.venv/bin/python -m pip install --upgrade pip
.venv/bin/python -m pip install -r backend/requirements.txt
cp backend/.env.example backend/.env
cd backend
../.venv/bin/python -m alembic upgrade head
../.venv/bin/python -m app.server
```

Mở terminal khác tại thư mục gốc:

```bash
flutter pub get
flutter run --dart-define-from-file=config/development.json
```

## 11. Kiểm thử và build

Chạy tại thư mục gốc sau mọi thay đổi:

```powershell
flutter analyze
flutter test
.\.venv\Scripts\python.exe -m unittest discover -s backend\tests -v
docker compose --env-file .env.docker.example config --quiet
```

Build production:

```powershell
flutter build web --release --dart-define-from-file=config/production.json
flutter build windows --release --dart-define-from-file=config/production.json
```

Phân phối Windows bằng toàn bộ thư mục `build/windows/x64/runner/Release`. File `v_monitor.exe` không chạy độc lập nếu thiếu DLL, plugin và thư mục `data` đi kèm.

## 12. Xử lý lỗi thường gặp

| Hiện tượng | Kiểm tra |
|---|---|
| Backend không khởi động | `DATABASE_URL`, PostGIS, `JWT_SECRET`, log Alembic |
| Web mở được nhưng API lỗi | DNS, HTTPS, `DOMAIN`, trạng thái backend, log Caddy |
| Flutter không kết nối | `API_BASE_URL` phải gồm `/api/v1`; build lại sau khi sửa JSON |
| WebSocket bị đóng mã `4401` | token hết hiệu lực, tài khoản bị khóa hoặc frame `AUTH` sai |
| Thiết bị không xuất hiện | topic prefix, `device_code`, quyền nhận dữ liệu, log MQTT |
| Thiết bị hiển thị offline | `last_seen_at`, timeout presence, đồng hồ server và kết nối MQTT |
| Địa chỉ không hiển thị | cấu hình geocoding, internet, hạn mức nhà cung cấp |
| Windows báo thiếu DLL | phân phối toàn bộ thư mục Release, không sao chép riêng EXE |

## 13. Danh sách bàn giao

- Source code và lịch sử Git ở revision đã kiểm thử.
- Domain, DNS và thông tin server được ghi trong hồ sơ vận hành riêng.
- `.env.docker` hoặc `backend/.env` được chuyển qua kênh bí mật, không đưa vào repository.
- Mật khẩu database, MQTT và JWT secret được lưu trong kho bí mật của công ty.
- Tài khoản `ADMIN` đầu tiên đăng nhập thành công và đã đổi mật khẩu.
- MQTT production nhận được ít nhất một gói thật và cập nhật frontend qua WebSocket.
- Sao lưu PostgreSQL được tạo và thử quy trình phục hồi trên môi trường riêng.
- Các lệnh kiểm thử tại mục 11 đạt trước khi phát hành.
