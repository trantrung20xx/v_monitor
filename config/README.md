# Chú giải hồ sơ cấu hình Flutter

Các file JSON trong thư mục này được truyền cho Flutter bằng
`--dart-define-from-file`. JSON không hỗ trợ comment, vì vậy chú giải đặt tại đây
để giữ nguyên khả năng parse và không làm thay đổi giá trị cấu hình.

## Ý nghĩa từng biến

- `APP_ENV`: nhãn môi trường dùng nhận diện bản build; không tự thay đổi server.
- `API_BASE_URL`: URL REST đầy đủ, gồm scheme, domain/cổng và `/api/v1`.
- `WS_PATH`: đường dẫn WebSocket trên cùng backend; ứng dụng tự đổi HTTPS thành WSS.
- `CONNECT_TIMEOUT_SECONDS`: số giây tối đa chờ mở kết nối HTTP.
- `WS_BASE_URL`: biến tùy chọn, chỉ khai báo khi WebSocket nằm trên host khác REST.
- `HTTP_GET_RETRY_COUNT`: số lần thử thêm cho GET tạm lỗi; POST/PATCH không retry.
- `HTTP_RETRY_DELAY_MS`: độ trễ cơ sở của backoff GET, tính bằng mili giây.
- `WS_RECONNECT_MIN_SECONDS`: khoảng chờ reconnect WebSocket đầu tiên.
- `WS_RECONNECT_MAX_SECONDS`: trần khoảng chờ reconnect khi lỗi kéo dài.
- `WS_HEARTBEAT_SECONDS`: chu kỳ gửi PING để giữ và kiểm tra phiên WebSocket.

## Vai trò từng file

- `development.json`: backend trên chính máy phát triển; `127.0.0.1` không dùng được từ điện thoại khác.
- `cloudflare.json`: backend công khai qua Cloudflare Tunnel; phải thay hostname mẫu trước khi build.
- `production.json`: domain ổn định của máy chủ doanh nghiệp; phải thay domain mẫu khi triển khai.

Các biến không xuất hiện trong JSON sẽ dùng giá trị mặc định được ghi rõ trong
`lib/core/config/app_config.dart`.
