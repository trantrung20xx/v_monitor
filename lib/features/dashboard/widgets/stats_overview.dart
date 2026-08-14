import 'package:flutter/material.dart';

import '../../../core/widgets/stat_card.dart';
import '../dashboard_state.dart';

/// Horizontal scrollable stats overview for mobile.
class StatsOverview extends StatelessWidget {
  const StatsOverview({super.key, required this.state});

  final DashboardState state;

  @override
  Widget build(BuildContext context) {
    final cards = [
      StatCard(
        label: 'Trực tuyến',
        value: '${state.onlineCount}',
        icon: Icons.wifi_rounded,
        color: const Color(0xFF16A34A),
      ),
      StatCard(
        label: 'Ngoại tuyến',
        value: '${state.offlineCount}',
        icon: Icons.wifi_off_rounded,
        color: Colors.grey.shade600,
      ),
      StatCard(
        label: 'Di chuyển',
        value: '${state.movingCount}',
        icon: Icons.navigation_rounded,
        color: const Color(0xFF2563EB),
      ),
      StatCard(
        label: 'Đang dừng',
        value: '${state.stoppedCount}',
        icon: Icons.pause_circle_rounded,
        color: const Color(0xFFD97706),
      ),
      StatCard(
        label: 'Mất tín hiệu',
        value: '${state.staleCount}',
        icon: Icons.signal_wifi_statusbar_connected_no_internet_4_rounded,
        color: const Color(0xFFDC2626),
      ),
      StatCard(
        label: 'Cần kiểm tra',
        value: '${state.attentionCount}',
        icon: Icons.warning_amber_rounded,
        color: const Color(0xFFEA580C),
      ),
    ];

    return SizedBox(
      height: 82,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        clipBehavior: Clip.none,
        child: Row(
          children: cards.map((card) {
            return Padding(
              padding: const EdgeInsets.only(right: 10),
              child: SizedBox(width: 150, height: 82, child: card),
            );
          }).toList(),
        ),
      ),
    );
  }
}
