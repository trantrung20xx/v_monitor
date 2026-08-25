// Kết quả đổi GPS thành địa chỉ. bestAddress ưu tiên chuỗi đã chuẩn hóa rồi mới
// dùng displayName, giúp mọi màn hình hiển thị cùng một quy tắc.
class ReverseGeocodeModel {
  // Hợp đồng địa chỉ đã được backend chuẩn hóa, độc lập payload riêng của Photon/Nominatim.
  const ReverseGeocodeModel({
    required this.latitude,
    required this.longitude,
    this.formattedAddress,
    this.displayName,
    required this.provider,
  });

  final double latitude;
  final double longitude;
  final String? formattedAddress;
  final String? displayName;
  final String provider;

  String? get bestAddress {
    final formatted = formattedAddress?.trim();
    if (formatted != null && formatted.isNotEmpty) return formatted;

    final display = displayName?.trim();
    if (display != null && display.isNotEmpty) return display;

    return null;
  }

  factory ReverseGeocodeModel.fromJson(Map<String, dynamic> json) {
    // Ưu tiên formatted_address; display_name giữ làm fallback và thông tin chẩn đoán.
    return ReverseGeocodeModel(
      latitude: _doubleOrZero(json['latitude']),
      longitude: _doubleOrZero(json['longitude']),
      formattedAddress: _stringOrNull(json['formatted_address']),
      displayName: _stringOrNull(json['display_name']),
      provider: json['provider']?.toString() ?? 'unknown',
    );
  }

  static double _doubleOrZero(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? 0;
  }

  static String? _stringOrNull(dynamic value) {
    if (value == null) return null;
    final text = value.toString().trim();
    return text.isEmpty ? null : text;
  }
}
