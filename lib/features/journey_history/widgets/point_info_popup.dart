import 'package:flutter/material.dart';
import '../../../core/utils/device_formatters.dart';
import '../../../data/models/location_model.dart';

class PointInfoPopup extends StatelessWidget {
  final LocationModel point;
  final VoidCallback onClose;

  const PointInfoPopup({
    super.key,
    required this.point,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return TapRegion(
      onTapOutside: (_) => onClose(),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 320),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface.withValues(alpha: 0.96),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: theme.colorScheme.outlineVariant),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.15),
              blurRadius: 16,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header
            Container(
              padding: const EdgeInsets.fromLTRB(12, 6, 6, 6),
              decoration: BoxDecoration(
                color: theme.colorScheme.primaryContainer.withValues(alpha: 0.5),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(11)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Icon(Icons.location_on_rounded, size: 16, color: theme.colorScheme.primary),
                      const SizedBox(width: 6),
                      Text(
                        'Chi tiết mốc GPS',
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: theme.colorScheme.onPrimaryContainer,
                        ),
                      ),
                    ],
                  ),
                  IconButton(
                    onPressed: onClose,
                    icon: const Icon(Icons.close_rounded, size: 18),
                    tooltip: 'Đóng',
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                      minWidth: 32,
                      minHeight: 32,
                    ),
                    visualDensity: VisualDensity.compact,
                    splashRadius: 16,
                  ),
                ],
              ),
            ),

          // Body
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildInfoRow(
                  theme,
                  Icons.access_time_rounded,
                  'Thời gian',
                  DeviceFormatters.dateTimeSeconds(point.measuredAt),
                ),
                const SizedBox(height: 6),
                _buildInfoRow(
                  theme,
                  Icons.speed_rounded,
                  'Vận tốc',
                  DeviceFormatters.speedMps(point.speedMps),
                ),
                const SizedBox(height: 6),
                _buildInfoRow(
                  theme,
                  Icons.explore_rounded,
                  'Hướng',
                  DeviceFormatters.heading(point.headingDeg),
                ),
                const SizedBox(height: 6),
                _buildInfoRow(
                  theme,
                  Icons.my_location_rounded,
                  'Tọa độ',
                  '${DeviceFormatters.latitudeText(point.latitude)}, ${DeviceFormatters.longitudeText(point.longitude)}',
                ),
                if (point.altitudeM != null) ...[
                  const SizedBox(height: 6),
                  _buildInfoRow(
                    theme,
                    Icons.height_rounded,
                    'Độ cao',
                    '${point.altitudeM!.toStringAsFixed(1)} m',
                  ),
                ],
                if (point.accuracyM != null) ...[
                  const SizedBox(height: 6),
                  _buildInfoRow(
                    theme,
                    Icons.gps_fixed_rounded,
                    'Độ chính xác',
                    '±${point.accuracyM!.toStringAsFixed(1)} m',
                  ),
                ],
                if (point.satelliteCount != null) ...[
                  const SizedBox(height: 6),
                  _buildInfoRow(
                    theme,
                    Icons.satellite_alt_rounded,
                    'Vệ tinh',
                    '${point.satelliteCount} vệ tinh',
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

  Widget _buildInfoRow(ThemeData theme, IconData icon, String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 14, color: theme.colorScheme.primary),
        const SizedBox(width: 6),
        SizedBox(
          width: 80,
          child: Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: theme.textTheme.bodySmall?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}
