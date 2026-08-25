// Điều phối trang chi tiết: tải hồ sơ/lịch sử/sự kiện, nhận realtime, giữ địa chỉ
// ổn định khi GPS đổi và phát state bất biến cho các tab.
import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../data/models/device_event_model.dart';
import '../../data/models/device_model.dart';
import '../../data/models/location_model.dart';
import '../../data/repositories/device_repository.dart';
import '../../data/repositories/geocoding_repository.dart';
import '../../data/repositories/tracking_repository.dart';

enum OverviewTimeRange {
  // Preset dùng cho truy vấn lịch sử của tab Tổng quan; custom giữ mốc người dùng chọn.
  today('Hôm nay'),
  yesterday('Hôm qua'),
  last24h('24h qua'),
  last7d('7 ngày'),
  custom('Tùy chọn');

  const OverviewTimeRange(this.label);
  // Nhãn thân thiện hiển thị trực tiếp trong bộ chọn khoảng thời gian.
  final String label;
}

// Snapshot bất biến của trang chi tiết, tách loading toàn trang và loading đổi khoảng.
class DeviceDetailState extends Equatable {
  const DeviceDetailState({
    this.isLoading = true,
    this.isRangeLoading = false,
    this.timeRange = OverviewTimeRange.today,
    this.rangeFrom,
    this.rangeTo,
    this.error,
    this.device,
    this.events = const [],
    this.locations = const [],
    this.address,
  });

  // isLoading dành cho lần tải toàn trang; isRangeLoading chỉ làm mờ vùng lịch sử
  // khi người dùng đổi khoảng mà vẫn giữ hồ sơ/sự kiện đang hiển thị.
  final bool isLoading;
  final bool isRangeLoading;
  // Khoảng chọn và hai mốc thực tế đã dùng để gọi backend.
  final OverviewTimeRange timeRange;
  final DateTime? rangeFrom;
  final DateTime? rangeTo;
  // error mô tả lỗi tải tổng; ba trường dữ liệu lấy từ nguồn REST/realtime thật.
  final String? error;
  final DeviceModel? device;
  final List<DeviceEventModel> events;
  final List<LocationModel> locations;
  // Địa chỉ là dữ liệu phụ được suy từ GPS; null không làm mất tọa độ gốc.
  final String? address;

  DeviceDetailState copyWith({
    bool? isLoading,
    bool? isRangeLoading,
    OverviewTimeRange? timeRange,
    DateTime? rangeFrom,
    DateTime? rangeTo,
    String? error,
    DeviceModel? device,
    List<DeviceEventModel>? events,
    List<LocationModel>? locations,
    String? address,
    bool clearAddress = false,
  }) {
    // clearAddress tách ý định gán null khỏi việc không truyền address, vì toán tử ??
    // mặc định phải giữ lại địa chỉ hiện có.
    return DeviceDetailState(
      isLoading: isLoading ?? this.isLoading,
      isRangeLoading: isRangeLoading ?? this.isRangeLoading,
      timeRange: timeRange ?? this.timeRange,
      rangeFrom: rangeFrom ?? this.rangeFrom,
      rangeTo: rangeTo ?? this.rangeTo,
      error: error,
      device: device ?? this.device,
      events: events ?? this.events,
      locations: locations ?? this.locations,
      address: clearAddress ? null : address ?? this.address,
    );
  }

  @override
  List<Object?> get props => [
    isLoading,
    isRangeLoading,
    timeRange,
    rangeFrom,
    rangeTo,
    error,
    device,
    events,
    locations,
    address,
  ];
}

// Điều phối REST ban đầu và hai stream realtime đã lọc đúng deviceId.
class DeviceDetailCubit extends Cubit<DeviceDetailState> {
  DeviceDetailCubit({
    required this.deviceId,
    required this.deviceRepo,
    required this.trackingRepo,
    required this.geocodingRepo,
  }) : super(const DeviceDetailState()) {
    // load lấy snapshot trước; subscription sau đó hợp nhất DEVICE_UPDATE/DEVICE_EVENT
    // của riêng thiết bị mà không cần reload toàn trang.
    load();
    _deviceUpdatesSub = deviceRepo.deviceUpdates
        .where((device) => device.id == deviceId)
        .listen(_onDeviceUpdated);
    _deviceEventsSub = deviceRepo.deviceEvents
        .where((event) => event.deviceId == deviceId)
        .listen(_onDeviceEventReceived);
  }

  final String deviceId;
  final DeviceRepository deviceRepo;
  final TrackingRepository trackingRepo;
  final GeocodingRepository geocodingRepo;

  // Cache theo tọa độ giảm request geocoding; activeAddressKey bảo vệ response chậm
  // của vị trí cũ không ghi đè địa chỉ vị trí mới.
  final Map<String, String> _addressCache = {};
  String? _activeAddressKey;
  StreamSubscription<DeviceModel>? _deviceUpdatesSub;
  StreamSubscription<DeviceEventModel>? _deviceEventsSub;

  (DateTime, DateTime) _calculateRange(
    OverviewTimeRange range, {
    DateTime? customFrom,
    DateTime? customTo,
  }) {
    // Mốc nhanh tính theo giờ cục bộ để khớp khái niệm hôm nay/hôm qua của người dùng;
    // repository chuyển DateTime thành ISO trước khi gọi backend.
    final now = DateTime.now();
    // Mỗi case trả cặp mốc thực tế; UI chỉ giữ enum để hiển thị nhãn lựa chọn.
    switch (range) {
      case OverviewTimeRange.today:
        final from = DateTime(now.year, now.month, now.day, 0, 0, 0);
        return (from, now);
      case OverviewTimeRange.yesterday:
        final yesterday = now.subtract(const Duration(days: 1));
        final from = DateTime(
          yesterday.year,
          yesterday.month,
          yesterday.day,
          0,
          0,
          0,
        );
        final to = DateTime(
          yesterday.year,
          yesterday.month,
          yesterday.day,
          23,
          59,
          59,
        );
        return (from, to);
      case OverviewTimeRange.last24h:
        return (now.subtract(const Duration(hours: 24)), now);
      case OverviewTimeRange.last7d:
        return (now.subtract(const Duration(days: 7)), now);
      case OverviewTimeRange.custom:
        // Mốc tùy chọn bị thiếu được bù bằng đầu ngày/hiện tại để hàm luôn trả cặp hợp lệ.
        final from =
            customFrom ?? DateTime(now.year, now.month, now.day, 0, 0, 0);
        final to = customTo ?? now;
        return (from, to);
    }
  }

  Future<List<LocationModel>> _fetchLocationsForRange(
    DateTime from,
    DateTime to,
  ) async {
    // Ưu tiên endpoint range có phân trang/giới hạn do backend quản lý.
    try {
      // Endpoint range trả cả metadata nhưng trang chi tiết chỉ cần danh sách samples.
      final response = await trackingRepo.getLocationHistoryRange(
        deviceId,
        from: from,
        to: to,
      );
      if (response != null) {
        return response.samples;
      }
    } catch (_) {
      // Lỗi endpoint mới được giữ kín để thử đường API cũ tương thích.
      // Dự phòng tương thích khi endpoint theo khoảng không khả dụng.
    }

    try {
      // Endpoint cũ trả các mẫu gần nhất; lọc cục bộ giữ đúng khoảng UI đã chọn.
      final history = await trackingRepo.getLocationHistory(deviceId);
      return history.where((loc) {
        return !loc.measuredAt.isBefore(from) && !loc.measuredAt.isAfter(to);
      }).toList();
    } catch (_) {
      // Cả hai nguồn lỗi trả danh sách rỗng để hồ sơ thiết bị vẫn hiển thị được.
      return const [];
    }
  }

  Future<void> load() async {
    // Phát loading nhưng giữ lựa chọn khoảng hiện tại để thao tác refresh không đổi ngữ cảnh.
    emit(state.copyWith(isLoading: true, error: null));
    try {
      // Tính mốc một lần rồi dùng cùng giá trị cho request và state hiển thị.
      final (from, to) = _calculateRange(
        state.timeRange,
        customFrom: state.rangeFrom,
        customTo: state.rangeTo,
      );

      // Hồ sơ, sự kiện và hành trình độc lập nên tải song song để giảm thời gian chờ.
      final results = await Future.wait([
        deviceRepo.getDevice(deviceId),
        trackingRepo.getEvents(deviceId),
        _fetchLocationsForRange(from, to),
      ]);

      // Future.wait giữ thứ tự kết quả đúng theo thứ tự ba Future ở trên.
      final device = results[0] as DeviceModel?;

      // Một emit duy nhất chuyển toàn trang từ loading sang snapshot đã đồng bộ.
      emit(
        state.copyWith(
          isLoading: false,
          device: device,
          events: results[1] as List<DeviceEventModel>,
          locations: results[2] as List<LocationModel>,
          rangeFrom: from,
          rangeTo: to,
          clearAddress: device?.latitude == null || device?.longitude == null,
        ),
      );

      // Reverse geocoding là bước phụ chạy sau khi dữ liệu chính đã hiển thị.
      if (device != null) {
        _resolveAddress(device.latitude, device.longitude);
      }
    } catch (e) {
      // Lỗi hồ sơ/sự kiện trong Future.wait làm lần tải tổng thất bại rõ ràng.
      emit(state.copyWith(isLoading: false, error: e.toString()));
    }
  }

  Future<void> setTimeRange(
    OverviewTimeRange range, {
    DateTime? customFrom,
    DateTime? customTo,
  }) async {
    // Chỉ tải lại locations; hồ sơ và sự kiện không phụ thuộc bộ chọn khoảng này.
    final (from, to) = _calculateRange(
      range,
      customFrom: customFrom,
      customTo: customTo,
    );
    emit(
      state.copyWith(
        timeRange: range,
        rangeFrom: from,
        rangeTo: to,
        isRangeLoading: true,
      ),
    );
    try {
      // Chỉ thay locations sau khi request mới hoàn tất, giữ dữ liệu cũ trong lúc chờ.
      final locations = await _fetchLocationsForRange(from, to);
      emit(
        state.copyWith(
          locations: locations,
          isRangeLoading: false,
        ),
      );
    } catch (e) {
      // Tắt loading nhưng giữ locations cũ để lỗi đổi bộ lọc không làm trang trắng.
      emit(state.copyWith(isRangeLoading: false));
    }
  }

  void _onDeviceUpdated(DeviceModel updatedDevice) {
    // So sánh khóa tọa độ làm tròn và measuredAt để nhận biết điểm realtime thực sự mới.
    final previousKey = _coordinateKey(
      state.device?.latitude,
      state.device?.longitude,
    );
    final nextKey = _coordinateKey(
      updatedDevice.latitude,
      updatedDevice.longitude,
    );
    final hasNewPosition =
        previousKey != nextKey ||
        state.device?.latestMeasuredAt != updatedDevice.latestMeasuredAt;
    // So sánh cả khóa tọa độ và mốc đo để nhận mẫu mới tại cùng vị trí đứng yên.

    List<LocationModel> updatedLocations = state.locations;
    // Chỉ chèn điểm realtime vào khoảng đang bao gồm hiện tại. Khoảng hôm qua/7 ngày
    // hoặc tùy chọn không được tự thêm mẫu nằm ngoài truy vấn đã chọn.
    if ((state.timeRange == OverviewTimeRange.today ||
            state.timeRange == OverviewTimeRange.last24h) &&
        updatedDevice.latitude != null &&
        updatedDevice.longitude != null &&
        hasNewPosition) {
      // Tạo LocationModel trình bày từ latest state đã commit; id `live-*` chỉ tồn tại
      // ở client và không giả làm UUID của location_samples trong database.
      final newLoc = LocationModel(
        id: 'live-${DateTime.now().millisecondsSinceEpoch}',
        deviceId: updatedDevice.id,
        latitude: updatedDevice.latitude!,
        longitude: updatedDevice.longitude!,
        measuredAt:
            updatedDevice.latestMeasuredAt ??
            updatedDevice.lastSeenAt ??
            DateTime.now(),
        altitudeM: updatedDevice.currentAltitudeM,
        speedMps: updatedDevice.currentSpeedMps,
        headingDeg: updatedDevice.currentHeadingDeg,
      );
      updatedLocations = [newLoc, ...state.locations];
    }

    emit(
      state.copyWith(
        device: updatedDevice,
        locations: updatedLocations,
        clearAddress: nextKey == null,
      ),
    );

    // Chỉ tra lại địa chỉ khi tọa độ làm tròn thực sự thay đổi.
    if (previousKey != nextKey) {
      _resolveAddress(updatedDevice.latitude, updatedDevice.longitude);
    }
  }

  void _onDeviceEventReceived(DeviceEventModel newEvent) {
    // Backend chỉ broadcast event sau commit; event mới nhất được đưa lên đầu timeline.
    final updatedEvents = [newEvent, ...state.events];
    emit(state.copyWith(events: updatedEvents));
  }

  Future<void> _resolveAddress(double? lat, double? lng) async {
    // Tọa độ thiếu xóa địa chỉ cũ; tọa độ có cache phát ngay; còn lại gọi repository.
    final cacheKey = _coordinateKey(lat, lng);
    // Cả key và hai số gốc được kiểm tra để không dùng toán tử `!` với null.
    if (cacheKey == null || lat == null || lng == null) {
      _activeAddressKey = null;
      emit(state.copyWith(clearAddress: true));
      return;
    }

    // Đúng tọa độ đang hiển thị và đã có địa chỉ thì không phát state lặp.
    if (_activeAddressKey == cacheKey && state.address?.isNotEmpty == true) {
      return;
    }

    _activeAddressKey = cacheKey;
    final cached = _addressCache[cacheKey];
    // Cache hit được emit đồng bộ, không chờ mạng.
    if (cached != null) {
      emit(state.copyWith(address: cached));
      return;
    }

    // Kết quả rỗng không ghi cache để lần sau có thể thử lại provider.
    final address = await geocodingRepo.reverseAddress(lat, lng);
    final normalizedAddress = address?.trim();
    if (normalizedAddress == null || normalizedAddress.isEmpty) {
      return;
    }

    _addressCache[cacheKey] = normalizedAddress;
    // Bỏ response nếu trong lúc chờ thiết bị đã chuyển sang tọa độ khác hoặc Cubit đóng.
    if (_activeAddressKey != cacheKey || isClosed) {
      return;
    }

    emit(state.copyWith(address: normalizedAddress));
  }

  String? _coordinateKey(double? lat, double? lng) {
    // Cùng độ chính xác với cache geocoding ở dashboard/backend.
    if (lat == null || lng == null) return null;
    return '${lat.toStringAsFixed(5)},${lng.toStringAsFixed(5)}';
  }

  @override
  Future<void> close() {
    // Dừng nghe realtime của riêng thiết bị khi rời trang chi tiết.
    _deviceUpdatesSub?.cancel();
    _deviceEventsSub?.cancel();
    return super.close();
  }
}
