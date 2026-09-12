# Kiểm tra icon bản đồ trên Windows

Chạy từ thư mục gốc dự án bằng PowerShell:

```powershell
flutter build windows --release --target test/manual/map_icons_smoke.dart
& .\build\windows\x64\runner\Release\v_monitor.exe
```

Bản kiểm tra tự mở HTTP/WebSocket trên cổng loopback ngẫu nhiên, dùng `ApiClient`, `WebsocketClient`, repository, `DashboardCubit` và trang bản đồ thật. Dữ liệu thiết bị được tạo trong bộ nhớ; không cần tài khoản hay thay đổi cơ sở dữ liệu. Nền bản đồ vẫn tải từ nguồn tile đang dùng trong ứng dụng.

Các ca chạy gồm màu trạng thái, hướng gửi lên và hướng suy từ GPS, xe dừng, xoay bản đồ, theme sáng/tối, đường phố/vệ tinh, màn hình rộng/hẹp, chữ lớn, chạm mở đúng chi tiết, danh sách thiết bị, cập nhật/xóa, lấy lại snapshot và kết nối lại WebSocket. Route chi tiết trong bản kiểm tra chỉ ghi ID để xác nhận điều hướng.

Mỗi pha 500 và 5.000 thiết bị có 3 giây khởi động rồi đo 20 giây kéo camera liên tục; mỗi thiết bị cập nhật mỗi 5 giây, phân bố theo lô 250 ms. Cuối pha đối chiếu tọa độ từng marker với bản tin cuối. `FrameTiming` ghi p95 dựng/vẽ khung hình và tỷ lệ khung vượt 33 ms. Ảnh chụp và lần tải đầu không nằm trong khoảng đo. Đây là kiểm tra giao diện Windows với máy chủ mô phỏng, không đo năng lực MQTT/PostgreSQL hoặc các trình duyệt.

Kết quả và ảnh chụp: `build/verification/map_icons/`. Kiểm tra `result.json`: `passed: true`, `errors: []`. Chỉ số hiệu năng phụ thuộc máy và tác vụ chạy cùng lúc. Bộ test tự động còn kiểm tra pixel ảnh thật, vùng chạm, semantics, GPS nhiễu/trễ/trùng timestamp và 5.000 thiết bị trùng tọa độ ở các mức zoom.

Sau khi kiểm tra, dựng lại ứng dụng chính để file chạy trở về màn hình đăng nhập bình thường:

```powershell
flutter build windows --release --target lib/main.dart
```
