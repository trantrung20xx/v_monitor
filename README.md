# v_monitor

Ứng dụng đa nền tảng phục vụ giám sát thiết bị và lịch sử di chuyển.

## Flutter

```powershell
flutter pub get
flutter run -d windows --dart-define-from-file=config/development.json
```

### Cấu hình kết nối frontend

Flutter nhận cấu hình tại thời điểm build bằng `--dart-define-from-file`. Ba
hồ sơ mẫu nằm trong `config/`:

- `development.json`: backend chạy trên chính máy phát triển.
- `cloudflare.json`: backend được public qua Cloudflare Tunnel.
- `production.json`: domain API của máy chủ doanh nghiệp.

Trong trường hợp REST API và WebSocket cùng một domain, chỉ cần thay
`API_BASE_URL`. Ứng dụng tự đổi `https` thành `wss` và dùng `WS_PATH` để tạo URL
WebSocket. Chỉ khai báo thêm `WS_BASE_URL` khi WebSocket thật sự nằm trên domain
khác.

Ví dụ build web với Cloudflare:

```powershell
flutter build web --release --dart-define-from-file=config/cloudflare.json
```

Thiết bị vật lý không thể dùng `127.0.0.1` để gọi backend trên máy phát triển.
Khi chạy Android, iOS hoặc một máy khác, đặt `API_BASE_URL` thành địa chỉ HTTPS
của Cloudflare hoặc địa chỉ LAN mà thiết bị truy cập được. Bản triển khai thật
nên dùng HTTPS/WSS để tương thích chính sách mạng của Android và iOS.

### Public backend bằng Cloudflare Tunnel

Tạo một published application route trỏ domain công khai tới dịch vụ cục bộ,
ví dụ `http://127.0.0.1:8000`. REST API và WebSocket dùng chung route; frontend
chỉ cần một `API_BASE_URL`, ví dụ:

```json
{
  "APP_ENV": "cloudflare",
  "API_BASE_URL": "https://monitor-api.example.com/api/v1",
  "WS_PATH": "/api/v1/ws"
}
```

Đồng thời đặt origin của frontend trong `backend/.env`:

```ini
CORS_ORIGINS=https://monitor.example.com
API_RELOAD=false
```

WebSocket client đã gửi heartbeat và tự kết nối lại với backoff tăng dần. Không
cần tạo URL hoặc tiến trình WebSocket riêng khi Cloudflare route cùng backend.

## Cấu hình backend

Thiết lập một lần trên máy Windows mới từ thư mục gốc dự án:

```powershell
py -m venv .venv
.\.venv\Scripts\python.exe -m pip install -r backend\requirements.txt
Copy-Item backend\.env.example backend\.env
```

Trên macOS hoặc Linux, tạo môi trường bằng `python3 -m venv .venv`, cài bằng
`.venv/bin/python -m pip install -r backend/requirements.txt`, sau đó chạy backend
từ thư mục `backend` bằng `../.venv/bin/python -m app.server`.

Thay các nhóm cấu hình PostgreSQL, MQTT, API và geocoding trong `backend/.env`.
Mọi giá trị kết nối được đọc từ tệp này; không cần sửa source code khi đổi server.

- `DATABASE_URL`: chuỗi kết nối PostgreSQL sử dụng `postgresql+asyncpg://`.
- `DATABASE_POOL_*`: giới hạn pool theo tài nguyên và giới hạn kết nối của DB.
- `MQTT_HOST`, `MQTT_PORT`, `MQTT_USERNAME`, `MQTT_PASSWORD`: broker đang dùng.
- `MQTT_CLIENT_ID`: có thể để trống để backend tự sinh id riêng cho mỗi máy.
- `MQTT_RECONNECT_*`: khoảng chờ reconnect tăng dần khi broker gián đoạn.
- `API_HOST`, `API_PORT`, `API_RELOAD`: địa chỉ và chế độ chạy Uvicorn.

Khởi động trên Windows bằng `run_backend.bat`. Script chạy Alembic rồi gọi
`app.server`; host, port và reload đều lấy trực tiếp từ `backend/.env`.

## Cơ sở dữ liệu

Backend sử dụng PostgreSQL, PostGIS và Alembic. Schema nghiệp vụ hiện gồm:

- `devices`
- `device_latest_state`
- `location_samples`
- `telemetry_messages`
- `device_events`
- `audit_logs`
- `user_accounts`
- `user_settings`

`user_accounts.role` dùng enum `userrole` với hai vai trò `ADMIN` và `USER`.
Tài khoản chỉ dùng để xác thực người xem nội bộ và phân quyền quản trị, hoàn
toàn không liên kết với thiết bị, lộ trình hay người vận hành. Không có API
đăng ký công khai và không lưu mật khẩu thô; mật khẩu được băm Argon2 trong
`password_hash`.

`alembic_version` và các đối tượng do PostGIS quản lý như `spatial_ref_sys`
là hạ tầng, không phải bảng nghiệp vụ.

Sau khi cấu hình `backend/.env`, chạy migration từ thư mục `backend`:

```powershell
alembic upgrade head
```

Tạo tài khoản quản trị đầu tiên bằng dòng lệnh (mật khẩu được nhập kín):

```powershell
python scripts/create_admin.py --username admin --full-name "Quản trị viên"
```

Frontend đã yêu cầu đăng nhập trước khi mở màn hình giám sát. Giữ
`AUTH_REQUIRED=true` và cấu hình `JWT_SECRET` ngẫu nhiên có ít nhất 32 ký tự.
Khóa đăng nhập không tự hết hạn, được lưu trong kho bảo mật của hệ điều hành và
được thu hồi bằng `user_accounts.token_version` khi đổi mật khẩu, reset mật khẩu,
đổi quyền hoặc vô hiệu hóa tài khoản. Kiến trúc không dùng refresh token, bảng
phiên đăng nhập hay blacklist token.

Backend nhận MQTT qua hàng đợi hữu hạn với nhiều worker, chống xử lý trùng bằng
`message_id`, không cho gói đến trễ ghi đè trạng thái hiện tại và hỗ trợ trả tối
đa 5.000 thiết bị cho giao diện theo cấu hình `DEVICE_LIST_MAX_LIMIT`.

Với cơ sở dữ liệu cũ đã có bảng nghiệp vụ nhưng `alembic_version` đang rỗng,
hãy sao lưu và thử trên bản sao trước. Sau khi xác nhận đúng là schema cũ của
dự án, đánh dấu revision lịch sử rồi mới chạy migration mới; cách này tránh
chạy lại migration xóa pin cũ vốn đã tồn tại trong lịch sử:

```powershell
alembic stamp c7d8e9f1a2b3
alembic upgrade head
alembic check
```

Không dùng quy trình `stamp` trên cơ sở dữ liệu mới hoặc cơ sở dữ liệu đã có
revision Alembic.
