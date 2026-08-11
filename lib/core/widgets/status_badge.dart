import 'package:flutter/material.dart';

/// A small colored badge showing device status text.
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

    if (!isOnline) {
      bg = Colors.grey.shade200;
      fg = Colors.grey.shade700;
    } else if (isMoving) {
      bg = Colors.blue.shade50;
      fg = Colors.blue.shade700;
    } else {
      bg = Colors.green.shade50;
      fg = Colors.green.shade700;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: fg,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
