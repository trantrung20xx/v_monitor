// Các hằng URL tương thích cho phần mã cũ; giá trị thật luôn ủy quyền AppConfig
// để không xuất hiện thêm một nguồn cấu hình kết nối độc lập.
import 'config/app_config.dart';

/// Các hằng dùng chung toàn ứng dụng.
class ApiConstants {
  // Getter ủy quyền AppConfig để code cũ luôn nhận cùng URL đã chuẩn hóa tại runtime.
  static String get baseUrl => AppConfig.apiOrigin;
  static String get wsUrl => AppConfig.websocketUrl;
  static String get apiPrefix => AppConfig.apiPathPrefix;
}

class AppConstants {
  // Tên kỹ thuật ổn định dùng khi cần định danh ứng dụng ngoài chuỗi UI.
  static const String appName = 'v_monitor';
}
