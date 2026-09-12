import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';

import '../../../data/models/device_model.dart';
import 'device_icon_canvas.dart';

/// Dựng từng thiết bị trong vùng nhìn.
class DeviceMarkerLayer extends StatefulWidget {
  const DeviceMarkerLayer({
    super.key,
    required this.devices,
    required this.markerBuilder,
  });
  final List<DeviceModel> devices;
  final DeviceMapMarker Function(BuildContext, DeviceModel) markerBuilder;

  @override
  State<DeviceMarkerLayer> createState() => _DeviceMarkerLayerState();
}

class _DeviceMarkerLayerState extends State<DeviceMarkerLayer> {
  List<DeviceMapMarker>? _icons;
  ThemeData? _theme;

  @override
  void didUpdateWidget(DeviceMarkerLayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Snapshot, trạng thái theo thời gian hoặc cấu hình đổi đều dựng lại mô tả.
    _icons = null;
  }

  @override
  Widget build(BuildContext context) {
    final camera = MapCamera.of(context);
    final theme = Theme.of(context);
    if (_theme != theme) {
      _theme = theme;
      _icons = null;
    }
    // Kéo/zoom chỉ chiếu lại tọa độ, không phân giải trạng thái 5.000 lần mỗi khung.
    final icons = _icons ??= [
      for (final device in widget.devices)
        if (device.latitude != null && device.longitude != null)
          widget.markerBuilder(context, device),
    ];
    final origin = camera.pixelOrigin;
    final size = camera.size;
    final markers = <ProjectedDeviceMarker>[];
    for (final icon in icons) {
      final point = camera.project(icon.point);
      final x = point.x - origin.x;
      final y = point.y - origin.y;
      if (x < -140 || y < -140 || x > size.x + 140 || y > size.y + 140) {
        continue;
      }
      markers.add(ProjectedDeviceMarker(icon, Offset(x, y)));
    }
    return MobileLayerTransformer(child: DeviceIconCanvas(markers: markers));
  }
}
