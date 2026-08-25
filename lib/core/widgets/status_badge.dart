// Huy hiệu trạng thái dùng icon, nhãn và màu ngữ nghĩa từ theme; chỉ trình bày
// kết quả đã được DeviceStatusResolver xác định, không tự suy luận nghiệp vụ.
import 'package:flutter/material.dart';

import '../theme/app_theme_colors.dart';

/// Badge màu nhỏ hiển thị nhãn và biểu tượng trạng thái, có hỗ trợ ngữ nghĩa truy cập.
// Badge trạng thái icon + nhãn; màu được truyền từ resolver/theme của màn hình gọi.
class StatusBadge extends StatelessWidget {
  const StatusBadge({
    super.key,
    required this.label,
    this.isOnline = false,
    this.isMoving = false,
  });

  final String label;
  final bool isOnline;
  final bool isMoving;

  @override
  Widget build(BuildContext context) {
    final appColors = context.appColors;
    final Color bg;
    final Color fg;
    final IconData icon;

    if (!isOnline) {
      bg = appColors.surfaceMuted;
      fg = appColors.offline;
      icon = Icons.wifi_off_rounded;
    } else if (isMoving) {
      bg = appColors.primarySoft;
      fg = appColors.primaryStrong;
      icon = Icons.navigation_rounded;
    } else {
      bg = appColors.successSoft;
      fg = appColors.successStrong;
      icon = Icons.pause_circle_rounded;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: fg),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              color: fg,
              fontSize: 11,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.1,
            ),
          ),
        ],
      ),
    );
  }
}
