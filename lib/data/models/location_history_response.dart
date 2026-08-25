// Mô hình một trang lịch sử GPS: khoảng thời gian, danh sách mẫu, tổng số bản ghi
// và cờ truncated để UI biết dữ liệu đã bị giới hạn hay chưa.
import 'location_model.dart';

/// Phản hồi lịch sử hành trình từ Backend API
class LocationHistoryResponse {
  // Envelope truy vấn range gồm samples đã giới hạn, tổng số thật và cờ truncated.
  final String deviceId;
  final DateTime fromTime;
  final DateTime toTime;
  final List<LocationModel> samples;
  final int totalCount;
  final bool truncated;

  const LocationHistoryResponse({
    required this.deviceId,
    required this.fromTime,
    required this.toTime,
    required this.samples,
    required this.totalCount,
    this.truncated = false,
  });

  factory LocationHistoryResponse.fromJson(Map<String, dynamic> json) {
    // Mỗi phần tử samples được parse thành LocationModel trước khi Cubit làm sạch/tổng hợp.
    final rawSamples = json['samples'] as List<dynamic>? ?? [];
    final samples = rawSamples
        .map((s) => LocationModel.fromJson(Map<String, dynamic>.from(s as Map)))
        .toList();

    return LocationHistoryResponse(
      deviceId: json['device_id']?.toString() ?? '',
      fromTime: DateTime.parse(json['from_time'].toString()),
      toTime: DateTime.parse(json['to_time'].toString()),
      samples: samples,
      totalCount: json['total_count'] is int
          ? json['total_count'] as int
          : samples.length,
      truncated: json['truncated'] == true,
    );
  }
}
