import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../../core/config/app_config.dart';
import '../../../core/theme/app_theme_colors.dart';
import '../../../data/models/device_model.dart';

/// Chỉ dựng marker trong vùng nhìn; gom các điểm cùng ô pixel theo mức zoom.
class DeviceClusterLayer extends StatelessWidget {
  const DeviceClusterLayer({
    super.key,
    required this.devices,
    required this.markerBuilder,
    required this.onClusterTap,
  });
  final List<DeviceModel> devices;
  final Marker Function(BuildContext, DeviceModel) markerBuilder;
  final void Function(List<DeviceModel>) onClusterTap;

  static List<List<DeviceModel>> groups(
    List<DeviceModel> devices,
    MapCamera camera, {
    double? cellPixels,
  }) {
    final cell = (cellPixels ?? AppConfig.mapClusterCellPixels.toDouble())
        .clamp(40.0, 200.0);
    final origin = camera.pixelOrigin;
    final size = camera.size;
    final groups = <(int, int), List<DeviceModel>>{};
    for (final device in devices) {
      if (device.latitude == null || device.longitude == null) continue;
      final point = camera.project(LatLng(device.latitude!, device.longitude!));
      final x = point.x - origin.x;
      final y = point.y - origin.y;
      if (x < -140 || y < -140 || x > size.x + 140 || y > size.y + 140) {
        continue;
      }
      final key = ((point.x / cell).floor(), (point.y / cell).floor());
      (groups[key] ??= []).add(device);
    }
    return groups.values.toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    final camera = MapCamera.of(context);
    final colors = context.appColors;
    return MarkerLayer(
      markers: groups(devices, camera)
          .map((group) {
            if (group.length == 1) return markerBuilder(context, group.single);
            final lat =
                group.fold<double>(0, (sum, d) => sum + d.latitude!) /
                group.length;
            final lng =
                group.fold<double>(0, (sum, d) => sum + d.longitude!) /
                group.length;
            return Marker(
              point: LatLng(lat, lng),
              width: 56,
              height: 56,
              child: Semantics(
                button: true,
                label: '${group.length} thiết bị, chạm để xem',
                child: Tooltip(
                  message: '${group.length} thiết bị',
                  child: Material(
                    color: colors.primary,
                    shape: const CircleBorder(),
                    elevation: 3,
                    child: InkWell(
                      customBorder: const CircleBorder(),
                      onTap: () => onClusterTap(group),
                      child: Padding(
                        padding: const EdgeInsets.all(9),
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            '${group.length}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );
          })
          .toList(growable: false),
    );
  }
}
