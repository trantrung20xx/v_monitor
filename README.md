# v_monitor

Ứng dụng đa nền tảng phục vụ giám sát thiết bị và lịch sử di chuyển.

## Flutter

```powershell
flutter pub get
flutter run -d windows
```

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
