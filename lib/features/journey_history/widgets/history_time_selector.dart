import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/utils/device_formatters.dart';
import '../../../data/models/device_model.dart';
import 'custom_gap_dialog.dart';

class HistoryTimeSelector extends StatelessWidget {
  final List<DeviceModel> devices;
  final DeviceModel? selectedDevice;
  final DateTime fromTime;
  final DateTime toTime;
  final Duration gapThreshold;
  final bool isLoading;
  final ValueChanged<DeviceModel?> onDeviceChanged;
  final ValueChanged<DateTime> onFromTimeChanged;
  final ValueChanged<DateTime> onToTimeChanged;
  final ValueChanged<Duration> onGapThresholdChanged;
  final VoidCallback onQuery;

  const HistoryTimeSelector({
    super.key,
    required this.devices,
    required this.selectedDevice,
    required this.fromTime,
    required this.toTime,
    required this.gapThreshold,
    required this.isLoading,
    required this.onDeviceChanged,
    required this.onFromTimeChanged,
    required this.onToTimeChanged,
    required this.onGapThresholdChanged,
    required this.onQuery,
  });

  static final DateFormat _dtFormat = DateFormat('dd/MM/yyyy HH:mm');

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDesktop = MediaQuery.of(context).size.width >= 800;

    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: isDesktop
            ? _buildDesktopLayout(context, theme)
            : _buildMobileLayout(context, theme),
      ),
    );
  }

  Widget _buildDesktopLayout(BuildContext context, ThemeData theme) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            // Chọn thiết bị
            Expanded(flex: 3, child: _buildDeviceDropdown(context, theme)),
            const SizedBox(width: 12),

            // Chọn mốc BẮT ĐẦU (FROM)
            Expanded(
              flex: 3,
              child: _buildDateTimePickerButton(
                context: context,
                label: 'Từ',
                currentValue: fromTime,
                onChanged: onFromTimeChanged,
              ),
            ),
            const SizedBox(width: 8),

            // Chọn mốc KẾT THÚC (TO)
            Expanded(
              flex: 3,
              child: _buildDateTimePickerButton(
                context: context,
                label: 'Đến',
                currentValue: toTime,
                onChanged: onToTimeChanged,
              ),
            ),
            const SizedBox(width: 12),

            // Nút Tra cứu
            SizedBox(
              height: 40,
              child: FilledButton.icon(
                onPressed: (selectedDevice == null || isLoading)
                    ? null
                    : onQuery,
                icon: isLoading
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.search_rounded, size: 18),
                label: const Text('Tra cứu'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        _buildQuickRangesAndGapConfig(context, theme),
      ],
    );
  }

  Widget _buildMobileLayout(BuildContext context, ThemeData theme) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildDeviceDropdown(context, theme),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: _buildDateTimePickerButton(
                context: context,
                label: 'Từ',
                currentValue: fromTime,
                onChanged: onFromTimeChanged,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _buildDateTimePickerButton(
                context: context,
                label: 'Đến',
                currentValue: toTime,
                onChanged: onToTimeChanged,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          height: 42,
          child: FilledButton.icon(
            onPressed: (selectedDevice == null || isLoading) ? null : onQuery,
            icon: isLoading
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.search_rounded, size: 18),
            label: const Text('Tra cứu lịch sử'),
          ),
        ),
        const SizedBox(height: 8),
        _buildQuickRangesAndGapConfig(context, theme),
      ],
    );
  }

  Widget _buildDeviceDropdown(BuildContext context, ThemeData theme) {
    return InputDecorator(
      decoration: const InputDecoration(
        labelText: 'Thiết bị',
        contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        isDense: true,
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<DeviceModel>(
          value: selectedDevice,
          isDense: true,
          isExpanded: true,
          hint: const Text('Chọn thiết bị', style: TextStyle(fontSize: 13)),
          items: devices.map((d) {
            return DropdownMenuItem<DeviceModel>(
              value: d,
              child: Text(
                DeviceFormatters.displayName(d),
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            );
          }).toList(),
          onChanged: onDeviceChanged,
        ),
      ),
    );
  }

  Widget _buildDateTimePickerButton({
    required BuildContext context,
    required String label,
    required DateTime currentValue,
    required ValueChanged<DateTime> onChanged,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () async {
        final now = DateTime.now();
        // 1. Chọn ngày
        final pickedDate = await showDatePicker(
          context: context,
          initialDate: currentValue,
          firstDate: DateTime(now.year - 3),
          lastDate: DateTime(now.year + 1),
          helpText: 'CHỌN NGÀY ($label)',
        );
        if (pickedDate == null || !context.mounted) return;

        // 2. Chọn giờ/phút
        final pickedTime = await showTimePicker(
          context: context,
          initialTime: TimeOfDay.fromDateTime(currentValue),
          helpText: 'CHỌN GIỜ:PHÚT ($label)',
        );
        if (pickedTime == null) return;

        final newDateTime = DateTime(
          pickedDate.year,
          pickedDate.month,
          pickedDate.day,
          pickedTime.hour,
          pickedTime.minute,
        );

        onChanged(newDateTime);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: Theme.of(
            context,
          ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: Theme.of(context).colorScheme.outlineVariant,
          ),
        ),
        child: Row(
          children: [
            Icon(
              Icons.calendar_today_rounded,
              size: 16,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 10,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    _dtFormat.format(currentValue),
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQuickRangesAndGapConfig(BuildContext context, ThemeData theme) {
    final now = DateTime.now();
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          // Nút chọn nhanh Hôm nay
          _buildQuickChip(
            label: 'Hôm nay',
            onTap: () {
              final start = DateTime(now.year, now.month, now.day, 0, 0, 0);
              final end = now;
              onFromTimeChanged(start);
              onToTimeChanged(end);
            },
          ),
          const SizedBox(width: 6),
          // Nút chọn nhanh Hôm qua
          _buildQuickChip(
            label: 'Hôm qua',
            onTap: () {
              final yesterday = now.subtract(const Duration(days: 1));
              final start = DateTime(
                yesterday.year,
                yesterday.month,
                yesterday.day,
                0,
                0,
                0,
              );
              final end = DateTime(
                yesterday.year,
                yesterday.month,
                yesterday.day,
                23,
                59,
                59,
              );
              onFromTimeChanged(start);
              onToTimeChanged(end);
            },
          ),
          const SizedBox(width: 6),
          // Nút chọn nhanh 24 giờ qua
          _buildQuickChip(
            label: '24h qua',
            onTap: () {
              onFromTimeChanged(now.subtract(const Duration(hours: 24)));
              onToTimeChanged(now);
            },
          ),
          const SizedBox(width: 6),
          // Nút chọn nhanh 7 ngày qua
          _buildQuickChip(
            label: '7 ngày qua',
            onTap: () {
              onFromTimeChanged(now.subtract(const Duration(days: 7)));
              onToTimeChanged(now);
            },
          ),
          const SizedBox(width: 16),
          // Cấu hình ngưỡng thời gian ngắt quãng.
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Ngắt quãng:',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(width: 4),
              () {
                const standardMinutes = [1, 5, 15, 30, 60];
                final currentMinutes = gapThreshold.inMinutes;
                final isCustom = !standardMinutes.contains(currentMinutes);

                return DropdownButton<int>(
                  value: currentMinutes,
                  isDense: true,
                  underline: const SizedBox.shrink(),
                  style: theme.textTheme.labelSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                  items: [
                    const DropdownMenuItem(value: 1, child: Text('1 phút')),
                    const DropdownMenuItem(value: 5, child: Text('5 phút')),
                    const DropdownMenuItem(value: 15, child: Text('15 phút')),
                    const DropdownMenuItem(value: 30, child: Text('30 phút')),
                    const DropdownMenuItem(value: 60, child: Text('1 giờ')),
                    if (isCustom)
                      DropdownMenuItem(
                        value: currentMinutes,
                        child: Text(
                          '${formatGapDuration(gapThreshold)} (Tùy ý)',
                        ),
                      ),
                    const DropdownMenuItem(
                      value: -1,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.tune_rounded, size: 13),
                          SizedBox(width: 4),
                          Text('Tùy ý...'),
                        ],
                      ),
                    ),
                  ],
                  onChanged: (val) async {
                    if (val == null) return;
                    if (val == -1) {
                      final customGap = await showCustomGapThresholdDialog(
                        context,
                        initialDuration: gapThreshold,
                      );
                      if (customGap != null) {
                        onGapThresholdChanged(customGap);
                      }
                    } else {
                      onGapThresholdChanged(Duration(minutes: val));
                    }
                  },
                );
              }(),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildQuickChip({required String label, required VoidCallback onTap}) {
    return ActionChip(
      label: Text(label, style: const TextStyle(fontSize: 11)),
      padding: EdgeInsets.zero,
      visualDensity: VisualDensity.compact,
      onPressed: onTap,
    );
  }
}
