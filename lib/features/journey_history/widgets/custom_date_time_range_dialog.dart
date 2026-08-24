import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_theme_colors.dart';

/// Mở hộp thoại chọn khoảng ngày giờ tùy chọn (đồng bộ giữa Tổng quan và Hành trình).
Future<DateTimeRange?> showCustomDateTimeRangeDialog(
  BuildContext context, {
  required DateTime initialFrom,
  required DateTime initialTo,
}) {
  return showDialog<DateTimeRange>(
    context: context,
    builder: (ctx) => CustomDateTimeRangeDialog(
      initialFrom: initialFrom,
      initialTo: initialTo,
    ),
  );
}

/// Hộp thoại chọn khoảng ngày giờ tùy chọn
class CustomDateTimeRangeDialog extends StatefulWidget {
  const CustomDateTimeRangeDialog({
    super.key,
    required this.initialFrom,
    required this.initialTo,
  });

  final DateTime initialFrom;
  final DateTime initialTo;

  @override
  State<CustomDateTimeRangeDialog> createState() =>
      _CustomDateTimeRangeDialogState();
}

class _CustomDateTimeRangeDialogState extends State<CustomDateTimeRangeDialog> {
  late DateTime tempFrom;
  late DateTime tempTo;

  static final DateFormat dateFormat = DateFormat('dd/MM/yyyy');
  static final DateFormat timeFormat = DateFormat('HH:mm');

  @override
  void initState() {
    super.initState();
    tempFrom = widget.initialFrom;
    tempTo = widget.initialTo;
  }

  @override
  Widget build(BuildContext context) {
    final appColors = context.appColors;
    final isValid = tempFrom.isBefore(tempTo);

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      title: Row(
        children: [
          Icon(
            Icons.edit_calendar_rounded,
            size: 20,
            color: appColors.primaryStrong,
          ),
          const SizedBox(width: 8),
          Text(
            'Tùy chọn khoảng thời gian',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: appColors.textPrimary,
            ),
          ),
        ],
      ),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Mốc bắt đầu (Từ):',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 12.5,
                color: appColors.textPrimary,
              ),
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  flex: 3,
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 8,
                      ),
                      side: BorderSide(color: appColors.border),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    icon: Icon(
                      Icons.calendar_today_rounded,
                      size: 14,
                      color: appColors.primaryStrong,
                    ),
                    label: Text(
                      dateFormat.format(tempFrom),
                      style: TextStyle(
                        fontSize: 12,
                        color: appColors.textPrimary,
                      ),
                    ),
                    onPressed: () async {
                      final pickedDate = await showDatePicker(
                        context: context,
                        initialDate: tempFrom,
                        firstDate: DateTime(DateTime.now().year - 3),
                        lastDate: DateTime(DateTime.now().year + 1),
                      );
                      if (pickedDate != null) {
                        setState(() {
                          tempFrom = DateTime(
                            pickedDate.year,
                            pickedDate.month,
                            pickedDate.day,
                            tempFrom.hour,
                            tempFrom.minute,
                            tempFrom.second,
                          );
                        });
                      }
                    },
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 2,
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 8,
                      ),
                      side: BorderSide(color: appColors.border),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    icon: Icon(
                      Icons.access_time_rounded,
                      size: 14,
                      color: appColors.primaryStrong,
                    ),
                    label: Text(
                      timeFormat.format(tempFrom),
                      style: TextStyle(
                        fontSize: 12,
                        color: appColors.textPrimary,
                      ),
                    ),
                    onPressed: () async {
                      final pickedTime = await showTimePicker(
                        context: context,
                        initialTime: TimeOfDay(
                          hour: tempFrom.hour,
                          minute: tempFrom.minute,
                        ),
                      );
                      if (pickedTime != null) {
                        setState(() {
                          tempFrom = DateTime(
                            tempFrom.year,
                            tempFrom.month,
                            tempFrom.day,
                            pickedTime.hour,
                            pickedTime.minute,
                            0,
                          );
                        });
                      }
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),

            Text(
              'Mốc kết thúc (Đến):',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 12.5,
                color: appColors.textPrimary,
              ),
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  flex: 3,
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 8,
                      ),
                      side: BorderSide(color: appColors.border),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    icon: Icon(
                      Icons.calendar_today_rounded,
                      size: 14,
                      color: appColors.primaryStrong,
                    ),
                    label: Text(
                      dateFormat.format(tempTo),
                      style: TextStyle(
                        fontSize: 12,
                        color: appColors.textPrimary,
                      ),
                    ),
                    onPressed: () async {
                      final pickedDate = await showDatePicker(
                        context: context,
                        initialDate: tempTo,
                        firstDate: DateTime(DateTime.now().year - 3),
                        lastDate: DateTime(DateTime.now().year + 1),
                      );
                      if (pickedDate != null) {
                        setState(() {
                          tempTo = DateTime(
                            pickedDate.year,
                            pickedDate.month,
                            pickedDate.day,
                            tempTo.hour,
                            tempTo.minute,
                            tempTo.second,
                          );
                        });
                      }
                    },
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 2,
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 8,
                      ),
                      side: BorderSide(color: appColors.border),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    icon: Icon(
                      Icons.access_time_rounded,
                      size: 14,
                      color: appColors.primaryStrong,
                    ),
                    label: Text(
                      timeFormat.format(tempTo),
                      style: TextStyle(
                        fontSize: 12,
                        color: appColors.textPrimary,
                      ),
                    ),
                    onPressed: () async {
                      final pickedTime = await showTimePicker(
                        context: context,
                        initialTime: TimeOfDay(
                          hour: tempTo.hour,
                          minute: tempTo.minute,
                        ),
                      );
                      if (pickedTime != null) {
                        setState(() {
                          tempTo = DateTime(
                            tempTo.year,
                            tempTo.month,
                            tempTo.day,
                            pickedTime.hour,
                            pickedTime.minute,
                            59,
                          );
                        });
                      }
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            if (!isValid)
              Text(
                'Thời gian bắt đầu phải trước thời gian kết thúc!',
                style: TextStyle(
                  color: appColors.danger,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Hủy'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: appColors.primaryStrong,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          onPressed: isValid
              ? () => Navigator.of(
                  context,
                ).pop(DateTimeRange(start: tempFrom, end: tempTo))
              : null,
          child: const Text('Áp dụng'),
        ),
      ],
    );
  }
}
