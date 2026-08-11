import 'package:flutter/material.dart';

import '../../../core/widgets/stat_card.dart';
import '../dashboard_state.dart';

/// Row of stat cards for the dashboard overview.
class StatsOverview extends StatelessWidget {
  const StatsOverview({super.key, required this.state});

  final DashboardState state;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        SizedBox(
          width: 180,
          child: StatCard(
            label: 'Trực tuyến',
            value: '${state.onlineCount}',
            icon: Icons.wifi,
            color: Colors.green.shade600,
          ),
        ),
        SizedBox(
          width: 180,
          child: StatCard(
            label: 'Ngoại tuyến',
            value: '${state.offlineCount}',
            icon: Icons.wifi_off,
            color: Colors.grey.shade600,
          ),
        ),
        SizedBox(
          width: 180,
          child: StatCard(
            label: 'Di chuyển',
            value: '${state.movingCount}',
            icon: Icons.navigation,
            color: Colors.blue.shade600,
          ),
        ),
        SizedBox(
          width: 180,
          child: StatCard(
            label: 'Dừng',
            value: '${state.idleCount}',
            icon: Icons.pause_circle_outline,
            color: Colors.orange.shade600,
          ),
        ),
      ],
    );
  }
}
