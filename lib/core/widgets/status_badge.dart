import 'package:flutter/material.dart';

/// A small colored badge showing device status text + icon for accessibility.
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
    final Color bg;
    final Color fg;
    final IconData icon;

    if (!isOnline) {
      bg = Colors.grey.shade100;
      fg = Colors.grey.shade600;
      icon = Icons.wifi_off_rounded;
    } else if (isMoving) {
      bg = Colors.blue.shade50;
      fg = Colors.blue.shade700;
      icon = Icons.navigation_rounded;
    } else {
      bg = Colors.green.shade50;
      fg = Colors.green.shade700;
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
