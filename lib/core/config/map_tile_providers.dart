/// Quản lý các nhà cung cấp nguồn bản đồ (Tile Providers) cho toàn bộ hệ thống v_monitor.
enum AppMapType {
  /// Bản đồ đường phố tiêu chuẩn (OpenStreetMap) - màu sắc sắc nét, rõ ràng
  standard,

  /// Bản đồ vệ tinh chi tiết cao (Google Hybrid Satellite kèm nhãn địa danh/đường bộ)
  satellite,
}

class MapTileProviders {
  /// URL OpenStreetMap đường phố chuẩn
  static const String streetUrl =
      'https://tile.openstreetmap.org/{z}/{x}/{y}.png';

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

  /// Max zoom hỗ trợ theo từng loại bản đồ
  static int getMaxZoom(AppMapType type) {
    switch (type) {
      case AppMapType.satellite:
        return 20;
      case AppMapType.standard:
        return 19;
    }
  }
}
