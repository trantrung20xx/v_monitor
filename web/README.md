# Chú giải cấu hình Flutter Web

Các tệp JSON trong thư mục này không hỗ trợ comment. Chú giải được đặt riêng để
trình duyệt và Flutter vẫn đọc đúng định dạng, không làm thay đổi giá trị cấu hình.

## `manifest.json`

- `name`: tên đầy đủ khi trình duyệt hoặc hệ điều hành giới thiệu ứng dụng web.
- `short_name`: tên rút gọn dưới biểu tượng khi không đủ không gian.
- `start_url`: đường dẫn mở đầu; `.` giữ ứng dụng tại thư mục đang được triển khai.
- `display`: `standalone` mở như một ứng dụng, không hiện thanh địa chỉ trình duyệt.
- `background_color`: màu nền trong giai đoạn ứng dụng web đang khởi động.
- `theme_color`: màu hệ thống dùng cho thanh tiêu đề hoặc khung ứng dụng web.
- `description`: mô tả ngắn trong metadata của ứng dụng web.
- `orientation`: hướng màn hình ưu tiên khi chạy như ứng dụng đã cài.
- `prefer_related_applications`: `false` ưu tiên chính bản web thay vì chuyển sang app khác.
- `icons`: các biểu tượng theo kích thước; mục có `purpose: maskable` cho phép hệ điều
  hành bo/cắt biểu tượng mà không làm mất nội dung chính.

## `index.html`

Đây là trang bootstrap của Flutter Web. Thẻ `base` quyết định đường dẫn tương đối khi
deploy dưới domain hoặc thư mục con; manifest và script Flutter được tải từ đây.
