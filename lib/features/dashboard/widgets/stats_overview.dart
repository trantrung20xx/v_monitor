// Dải thống kê chuyển các bộ đếm DashboardState thành StatCard responsive;
// không tự đếm lại hoặc thay đổi ý nghĩa online/offline/moving.
import 'package:flutter/material.dart';

import '../../../core/theme/app_theme_colors.dart';
import '../../../core/widgets/stat_card.dart';
import '../dashboard_state.dart';

/// Dải thống kê cuộn ngang trên màn hình hẹp để thẻ không bị ép hoặc tràn chữ.
// Dải thẻ thống kê cho mobile, đọc trực tiếp các bộ đếm đã resolve trong DashboardState.
class StatsOverview extends StatelessWidget {
  const StatsOverview({super.key, required this.state});

  final DashboardState state;

  @override
  Widget build(BuildContext context) {
    // Wrap cho phép thẻ xuống dòng khi không đủ rộng, tránh ép nội dung hoặc overflow.
    final colors = context.appColors;
    final cards = [
      StatCard(
        label: 'Trực tuyến',
        value: '${state.onlineCount}',
        icon: Icons.wifi_rounded,
        color: colors.success,
      ),
      StatCard(
        label: 'Ngoại tuyến',
        value: '${state.offlineCount}',
        icon: Icons.wifi_off_rounded,
        color: colors.offline,
      ),
      StatCard(
        label: 'Di chuyển',
        value: '${state.movingCount}',
        icon: Icons.navigation_rounded,
        color: colors.primaryStrong,
      ),
      StatCard(
        label: 'Đang dừng',
        value: '${state.stoppedCount}',
        icon: Icons.pause_circle_rounded,
        color: colors.warning,
      ),
      StatCard(
        label: 'Mất tín hiệu',
        value: '${state.staleCount}',
        icon: Icons.signal_wifi_statusbar_connected_no_internet_4_rounded,
        color: colors.danger,
      ),
      StatCard(
        label: 'Cần kiểm tra',
        value: '${state.attentionCount}',
        icon: Icons.warning_amber_rounded,
        color: colors.orange,
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
