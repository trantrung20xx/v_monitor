# Tài liệu mô tả hệ thống VMonitor

## 1. Mục đích

VMonitor tiếp nhận vị trí từ thiết bị qua MQTT hoặc REST, lưu dữ liệu vào PostgreSQL/PostGIS và cập nhật giao diện Flutter qua WebSocket. Hệ thống hỗ trợ:

- Giám sát vị trí và trạng thái online/offline.
- Xem lịch sử hành trình, điểm dừng và sự kiện di chuyển.
- Quản lý thiết bị và thiết bị MQTT đã phát hiện.
- Quản lý tài khoản, vai trò và thiết lập hệ thống.
- Tra cứu địa chỉ từ tọa độ qua dịch vụ geocoding.

## 2. Kiến trúc và luồng dữ liệu

### 2.1. Sơ đồ kiến trúc production

```mermaid
flowchart LR
    Device["Thiết bị GPS / IoT"]
    Broker["MQTT Broker<br/>Dịch vụ bên ngoài"]
    Client["Trình duyệt / Flutter Desktop"]
    Geocoding["Dịch vụ geocoding<br/>Photon hoặc Nominatim"]

    subgraph Server["Máy chủ Docker"]
        direction LR
        Caddy["web<br/>Caddy + Flutter Web<br/>Cổng 80 / 443"]
        Backend["backend<br/>FastAPI + MQTT worker<br/>REST + WebSocket"]
        Database[("db<br/>PostgreSQL 16 + PostGIS")]
        Volume[("postgres_data<br/>Dữ liệu bền vững")]

        Caddy <-->|"/api/* · /health · WebSocket"| Backend
        Backend <-->|"SQL bất đồng bộ"| Database
        Database --- Volume
    end

    Device -->|"Publish: &lt;MQTT_TOPIC_PREFIX&gt;/&lt;device_code&gt;"| Broker
    Broker -->|"Subscribe: &lt;MQTT_TOPIC_PREFIX&gt;/#"| Backend
    Client <-->|"HTTPS / WSS"| Caddy
    Backend -->|"Reverse geocoding"| Geocoding
```

MQTT Broker và dịch vụ geocoding không nằm trong `compose.yaml`. Địa chỉ kết nối được khai báo qua `.env.docker`.

### 2.2. Vai trò của từng service

| Service | Vai trò | Phạm vi truy cập |
|---|---|---|
| `web` | Phục vụ Flutter Web, kết thúc HTTPS và chuyển tiếp API/WebSocket | Public cổng `80`, `443` |
| `backend` | Xử lý REST, WebSocket, MQTT, xác thực và nghiệp vụ | Chỉ trong mạng Docker, cổng `8000` |
| `db` | Lưu dữ liệu nghiệp vụ và tọa độ không gian | Chỉ trong mạng Docker, cổng `5432` |
| `postgres_data` | Giữ dữ liệu PostgreSQL khi container được tạo lại | Docker volume, không public |

Caddy là điểm truy cập public duy nhất. REST, WebSocket và Flutter Web sử dụng chung `${DOMAIN}`; backend và database không mở cổng trực tiếp ra Internet.

### 2.3. Luồng tiếp nhận telemetry

1. Thiết bị publish bản tin đến `<MQTT_TOPIC_PREFIX>/<device_code>` trên MQTT Broker.
2. MQTT worker của backend đăng ký `<MQTT_TOPIC_PREFIX>/#` và nhận bản tin từ Broker.
3. Backend kiểm tra topic, payload, thiết bị, quyền nhận dữ liệu và `message_id` chống trùng.
4. Dữ liệu hợp lệ được lưu vào `telemetry_messages`, `location_samples`, `device_latest_state` và có thể tạo `device_events`.
5. Backend phát `DEVICE_UPDATE` hoặc `DEVICE_EVENT` qua WebSocket.
6. Flutter cập nhật giao diện theo thời gian thực; dữ liệu lịch sử được tải qua REST API.

```text
Thiết bị → MQTT Broker → Backend → PostgreSQL/PostGIS
                              └──→ WebSocket → Flutter
```

### 2.4. Luồng truy cập từ Flutter

| Yêu cầu | Đường đi | Kết quả |
|---|---|---|
| Mở ứng dụng web | Client → Caddy → tệp Flutter Web | Tải giao diện |
| Đăng nhập, xem thiết bị và lịch sử | Flutter → Caddy → FastAPI → PostgreSQL | Trả dữ liệu JSON |
| Nhận cập nhật trực tiếp | Flutter ⇄ Caddy ⇄ FastAPI WebSocket | Cập nhật trạng thái không cần tải lại |
| Tra cứu địa chỉ | Flutter → FastAPI → dịch vụ geocoding | Trả địa chỉ từ tọa độ |

### 2.5. Thứ tự khởi động Docker

1. `db` khởi động và vượt qua healthcheck PostgreSQL.
2. `backend` chạy `alembic upgrade head`, khởi động FastAPI và kết nối MQTT Broker.
3. `web` khởi động sau khi backend healthy; Caddy phục vụ Flutter Web và reverse proxy.

Caddy tự cấp chứng chỉ HTTPS khi DNS trỏ đúng về server và firewall cho phép cổng `80`, `443`.

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

`docker version` phải hiển thị cả `Client` và `Server`. Chỉ có phần `Client` nghĩa là Docker daemon chưa chạy.

Yêu cầu DNS `A` trỏ về server và firewall cho phép TCP `80`, `443`.

### 9.2 Tạo cấu hình

```bash
cp .env.docker.example .env.docker
openssl rand -hex 24
openssl rand -hex 32
nano .env.docker
```

Các giá trị bắt buộc:

- `DOMAIN`: domain thật đã trỏ DNS về server; phải thay giá trị mẫu `monitor.example.com`.
- `POSTGRES_DB`, `POSTGRES_USER`: tên database và tài khoản PostgreSQL.
- `POSTGRES_PASSWORD`: kết quả `openssl rand -hex 24`.
- `JWT_SECRET`: kết quả `openssl rand -hex 32`.
- `MQTT_*`: host, cổng, xác thực, TLS và topic prefix của broker production.

`DOMAIN` chỉ chứa hostname, không có `http://`, `https://`, đường dẫn hoặc dấu `/` cuối. Mật khẩu PostgreSQL trong cấu hình hiện tại chỉ nên chứa chữ và số vì được ghép trực tiếp vào `DATABASE_URL`.

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
2. `https://<DOMAIN>/health` trả HTTP `200`, `"status":"ok"`, `"database":"connected"`, `mqtt.connected: true` và `mqtt.subscribed: true`.
3. Trang `https://<DOMAIN>` tải được giao diện đăng nhập.
4. Log backend không có lỗi migration, database hoặc MQTT lặp liên tục.

Endpoint `/health` vẫn có thể trả HTTP `200` khi `"status":"degraded"`; trạng thái này chỉ xác nhận API còn phản hồi, chưa xác nhận pipeline database và MQTT đã sẵn sàng đầy đủ.

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

### 9.7 Chạy thử Docker trên Windows

Quy trình này chạy Flutter Web, FastAPI và PostgreSQL/PostGIS bằng Docker Desktop. Docker Desktop phải dùng Linux containers và hiển thị `Engine running`.

Kiểm tra Docker:

```powershell
docker version
docker compose version
```

`docker version` phải có cả `Client` và `Server`. Lỗi đường dẫn `dockerDesktopLinuxEngine` hoặc `The system cannot find the file specified` nghĩa là Docker Engine chưa chạy. Khôi phục theo thứ tự:

```powershell
wsl --shutdown
```

Sau đó mở lại Docker Desktop, chờ `Engine running` và kiểm tra lại `docker version`.

Tạo cấu hình local tại thư mục gốc:

```powershell
Copy-Item .env.docker.example .env.docker
[guid]::NewGuid().ToString("N")
[guid]::NewGuid().ToString("N") + [guid]::NewGuid().ToString("N")
notepad .env.docker
```

Thay các giá trị sau và giữ nguyên các biến còn lại:

```env
DOMAIN=localhost
POSTGRES_PASSWORD=<kết quả lệnh tạo chuỗi thứ nhất>
JWT_SECRET=<kết quả lệnh tạo chuỗi thứ hai>
MQTT_HOST=broker.emqx.io
MQTT_PORT=1883
MQTT_USE_TLS=false
MQTT_TOPIC_PREFIX=v_monitor/windows_test
```

Khởi động:

```powershell
docker compose --env-file .env.docker config --quiet
docker compose --env-file .env.docker up -d --build
docker compose --env-file .env.docker ps
```

Ba container `v-monitor-db-1`, `v-monitor-backend-1`, `v-monitor-web-1` phải xuất hiện; `db` và `backend` phải đạt `healthy`.

Kiểm tra bằng URL thô, không thêm dấu `[]` hoặc `()`:

```powershell
curl.exe -k https://localhost/health
```

Kết quả sẵn sàng phải có `"status":"ok"`. Caddy dùng chứng chỉ HTTPS nội bộ cho `localhost`, vì vậy trình duyệt có thể hiển thị cảnh báo chứng chỉ trong môi trường thử nghiệm.

Tạo tài khoản quản trị và mở giao diện:

```powershell
docker compose --env-file .env.docker exec backend python scripts/create_admin.py --username admin --full-name "Quản trị viên"
Start-Process https://localhost
```

Dừng nhưng giữ dữ liệu:

```powershell
docker compose --env-file .env.docker down
```

`docker compose --env-file .env.docker down -v` xóa database, tài khoản, lịch sử và chứng chỉ local; chỉ dùng khi cần tạo lại toàn bộ môi trường thử nghiệm.

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

Tạo tài khoản quản trị cục bộ sau khi backend và database đã khởi động:

```powershell
.\.venv\Scripts\python.exe backend\scripts\create_admin.py --username admin --full-name "Quản trị viên"
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

Trước khi build Flutter độc lập, thay `API_BASE_URL` trong `config/production.json` bằng `https://<DOMAIN>/api/v1`. Giá trị trong file mẫu `https://api.example.com/api/v1` không phải endpoint sử dụng thật.

```powershell
flutter build web --release --dart-define-from-file=config/production.json
flutter build windows --release --dart-define-from-file=config/production.json
```

Docker Web không đọc `config/production.json`; `docker/web.Dockerfile` tạo `API_BASE_URL` từ `DOMAIN` trong `.env.docker` khi build image.

Phân phối Windows bằng toàn bộ thư mục `build/windows/x64/runner/Release`. File `v_monitor.exe` không chạy độc lập nếu thiếu DLL, plugin và thư mục `data` đi kèm.

## 12. Xử lý lỗi thường gặp

| Hiện tượng | Kiểm tra |
|---|---|
| Docker chỉ hiện `Client`, không có `Server` | Docker Desktop phải ở trạng thái `Engine running`; chạy `wsl --shutdown`, sau đó mở lại Docker Desktop |
| Lỗi `dockerDesktopLinuxEngine` hoặc thiếu named pipe | Docker Desktop chưa chạy Linux Engine; chưa chạy lệnh Compose cho tới khi `docker version` có phần `Server` |
| Caddy xin chứng chỉ cho `monitor.example.com` | `.env.docker` vẫn dùng domain mẫu; production thay domain thật, local Windows đặt `DOMAIN=localhost`, sau đó build lại `web` |
| `/health` trả `status: degraded` | Xem riêng `database`, `mqtt.connected`, `mqtt.subscribed` và log backend |
| `curl` local báo lỗi chứng chỉ | Dùng đúng `curl.exe -k https://localhost/health`; URL không chứa định dạng Markdown `[]()` |
| Backend không khởi động | `DATABASE_URL`, PostGIS, `JWT_SECRET`, log Alembic |
| Web mở được nhưng API lỗi | DNS, HTTPS, `DOMAIN`, trạng thái backend, log Caddy |
| Flutter không kết nối | `API_BASE_URL` phải gồm `/api/v1`; build lại sau khi sửa JSON |
| WebSocket bị đóng mã `4401` | token hết hiệu lực, tài khoản bị khóa hoặc frame `AUTH` sai |
| Thiết bị không xuất hiện | topic prefix, `device_code`, quyền nhận dữ liệu, log MQTT |
| Thiết bị hiển thị offline | `last_seen_at`, timeout presence, đồng hồ server và kết nối MQTT |
| Địa chỉ không hiển thị | cấu hình geocoding, internet, hạn mức nhà cung cấp |
| Windows báo thiếu DLL | phân phối toàn bộ thư mục Release, không sao chép riêng EXE |
