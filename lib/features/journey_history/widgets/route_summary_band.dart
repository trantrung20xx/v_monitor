import 'package:flutter/material.dart';
import '../../../core/theme/app_theme_colors.dart';
import '../../../core/utils/device_formatters.dart';
import '../journey_history_state.dart';

class RouteSummaryBand extends StatelessWidget {
  final JourneyHistoryState state;

  const RouteSummaryBand({super.key, required this.state});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final appColors = context.appColors;

    final items = [
      _SummaryItem(
        icon: Icons.route_rounded,
        label: 'Tổng quãng đường',
        value: DeviceFormatters.distance(state.totalDistanceM),
        color: appColors.primaryStrong,
      ),
      _SummaryItem(
        icon: Icons.navigation_rounded,
        label: 'Thời gian di chuyển',
        value: DeviceFormatters.secondsDuration(state.movingDurationS),
        color: appColors.success,
      ),
      _SummaryItem(
        icon: Icons.pause_circle_rounded,
        label: 'Thời gian dừng',
        value: DeviceFormatters.secondsDuration(state.stoppedDurationS),
        color: appColors.warning,
      ),
      _SummaryItem(
        icon: Icons.speed_rounded,
        label: 'Tốc độ tối đa',
        value: DeviceFormatters.speedMps(state.maxSpeedMps),
        color: appColors.danger,
      ),
      _SummaryItem(
        icon: Icons.scatter_plot_rounded,
        label: 'Số mẫu GPS',
        value:
            '${state.validSamples.length} điểm${state.segments.length > 1 ? ' (${state.segments.length} đoạn)' : ''}',
        color: theme.colorScheme.primary,
      ),
    ];

    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (var i = 0; i < items.length; i++) ...[
                if (i > 0) const SizedBox(width: 10),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: items[i].color.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: items[i].color.withValues(alpha: 0.2),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(items[i].icon, size: 16, color: items[i].color),
                      const SizedBox(width: 6),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            items[i].label,
                            style: theme.textTheme.labelSmall?.copyWith(
                              fontSize: 9.5,
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                          Text(
                            items[i].value,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _SummaryItem {
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  const _SummaryItem({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });
}
