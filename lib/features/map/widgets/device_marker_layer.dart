import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../../data/models/device_model.dart';

/// Dựng từng thiết bị trong vùng nhìn.
class DeviceMarkerLayer extends StatelessWidget {
  const DeviceMarkerLayer({
    super.key,
    required this.devices,
    required this.markerBuilder,
  });
  final List<DeviceModel> devices;
  final Marker Function(BuildContext, DeviceModel) markerBuilder;

  @override
  Widget build(BuildContext context) {
    final camera = MapCamera.of(context);
    final origin = camera.pixelOrigin;
    final size = camera.size;
    final markers = <Marker>[];
    for (final device in devices) {
      if (device.latitude == null || device.longitude == null) continue;
      final point = camera.project(LatLng(device.latitude!, device.longitude!));
      final x = point.x - origin.x;
      final y = point.y - origin.y;
      if (x < -140 || y < -140 || x > size.x + 140 || y > size.y + 140) {
        continue;
      }
      markers.add(markerBuilder(context, device));
    }
    return MarkerLayer(markers: markers);
  }
}
