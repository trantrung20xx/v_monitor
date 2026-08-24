/// Quản lý các nhà cung cấp nguồn bản đồ (Tile Providers) cho toàn bộ hệ thống v_monitor.
enum AppMapType {
  /// Bản đồ đường phố tiêu chuẩn
  standard,

  /// Bản đồ vệ tinh chi tiết cao (Google Hybrid Satellite kèm nhãn địa danh/đường bộ)
  satellite,
}

class MapTileProviders {
  /// URL bản đồ đường phố. Dùng cùng hạ tầng tile đang hoạt động với lớp vệ
  /// tinh để tránh toàn bộ nền bản đồ bị trắng khi máy khách không phân giải
  /// được miền tile.openstreetmap.org.
  static const String streetUrl =
      'https://mt1.google.com/vt?lyrs=m&x={x}&y={y}&z={z}';

  /// URL Bản đồ vệ tinh Google Hybrid (kèm đường và tên địa danh)
  static const String satelliteUrl =
      'https://mt1.google.com/vt/lyrs=y&x={x}&y={y}&z={z}';

  /// Lấy URL mẫu theo loại bản đồ đã chọn
  static String getUrl(AppMapType type) {
    switch (type) {
      case AppMapType.satellite:
        return satelliteUrl;
      case AppMapType.standard:
        return streetUrl;
    }
  }

  /// Mức phóng to tối đa của từng loại bản đồ.
  static int getMaxZoom(AppMapType type) {
    switch (type) {
      case AppMapType.satellite:
        return 20;
      case AppMapType.standard:
        return 19;
    }
  }
}
