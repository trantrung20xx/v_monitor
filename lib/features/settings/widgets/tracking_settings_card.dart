import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../data/models/system_settings_model.dart';
import '../settings_cubit.dart';

class TrackingSettingsCard extends StatefulWidget {
  const TrackingSettingsCard({
    super.key,
    required this.settings,
    required this.saving,
  });

  final SystemSettingsModel settings;
  final bool saving;

  @override
  State<TrackingSettingsCard> createState() => _TrackingSettingsCardState();
}

class _TrackingSettingsCardState extends State<TrackingSettingsCard> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _offlineController;
  late final TextEditingController _movementController;
  late final TextEditingController _gapController;
  bool _dirty = false;

  @override
  void initState() {
    super.initState();
    _offlineController = TextEditingController();
    _movementController = TextEditingController();
    _gapController = TextEditingController();
    _synchronizeControllers(widget.settings);
  }

  @override
  void didUpdateWidget(covariant TrackingSettingsCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Không ghi đè dữ liệu Admin đang nhập khi một sự kiện WebSocket đến giữa chừng.
    if (!_dirty && oldWidget.settings != widget.settings) {
      _synchronizeControllers(widget.settings);
    }
  }

  @override
  void dispose() {
    _offlineController.dispose();
    _movementController.dispose();
    _gapController.dispose();
    super.dispose();
  }

  void _synchronizeControllers(SystemSettingsModel settings) {
    _offlineController.text = settings.offlineTimeoutSeconds.toString();
    _movementController.text = settings.movementThresholdMps.toString();
    _gapController.text = settings.defaultGapThresholdSeconds.toString();
  }

  Future<void> _save() async {
    if (widget.saving || !(_formKey.currentState?.validate() ?? false)) return;
    final value = SystemSettingsModel(
      offlineTimeoutSeconds: int.parse(_offlineController.text.trim()),
      movementThresholdMps: double.parse(
        _movementController.text.trim().replaceFirst(',', '.'),
      ),
      defaultGapThresholdSeconds: int.parse(_gapController.text.trim()),
    );
    final error = await context.read<SettingsCubit>().saveSystemSettings(value);
    if (!mounted || error != null) return;
    setState(() => _dirty = false);
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(content: Text('Đã lưu cấu hình theo dõi thiết bị.')),
      );
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      key: const Key('tracking-settings-content'),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _formKey,
          onChanged: () {
            if (!_dirty) setState(() => _dirty = true);
          },
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const _TrackingSettingsHeader(),
              const SizedBox(height: 20),
              LayoutBuilder(
                builder: (context, constraints) {
                  final isWide = constraints.maxWidth >= 760;
                  final fields = [
                    _TrackingSettingPanel(
                      key: const Key('offline-setting-panel'),
                      icon: Icons.cloud_off_outlined,
                      title: 'Thời gian xác định ngoại tuyến',
                      description:
                          'Không nhận dữ liệu trong khoảng này thì thiết bị được xem là ngoại tuyến.',
                      rangeLabel: 'Phạm vi: 30–86400 giây',
                      field: _IntegerSettingField(
                        key: const Key('offline-timeout-field'),
                        controller: _offlineController,
                        label: 'Giá trị',
                        suffix: 'giây',
                        minimum: 30,
                        maximum: 86400,
                      ),
                    ),
                    _TrackingSettingPanel(
                      key: const Key('movement-setting-panel'),
                      icon: Icons.speed_rounded,
                      title: 'Ngưỡng xác định di chuyển',
                      description:
                          'Tốc độ từ ngưỡng này trở lên được xem là thiết bị đang di chuyển.',
                      rangeLabel: 'Phạm vi: 0–10 m/s',
                      field: _DoubleSettingField(
                        key: const Key('movement-threshold-field'),
                        controller: _movementController,
                        label: 'Giá trị',
                        suffix: 'm/s',
                        minimum: 0,
                        maximum: 10,
                      ),
                    ),
                    _TrackingSettingPanel(
                      key: const Key('journey-gap-setting-panel'),
                      icon: Icons.route_outlined,
                      title: 'Khoảng ngắt lộ trình mặc định',
                      description:
                          'Khoảng gián đoạn dùng để nhận biết và tách các đoạn lộ trình.',
                      rangeLabel: 'Phạm vi: 60–3600 giây',
                      field: _IntegerSettingField(
                        key: const Key('journey-gap-field'),
                        controller: _gapController,
                        label: 'Giá trị',
                        suffix: 'giây',
                        minimum: 60,
                        maximum: 3600,
                      ),
                    ),
                  ];
                  if (!isWide) {
                    return Column(
                      children: [
                        for (var index = 0; index < fields.length; index++) ...[
                          fields[index],
                          if (index < fields.length - 1)
                            const SizedBox(height: 14),
                        ],
                      ],
                    );
                  }
                  return IntrinsicHeight(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (var index = 0; index < fields.length; index++) ...[
                          Expanded(child: fields[index]),
                          if (index < fields.length - 1)
                            const SizedBox(width: 14),
                        ],
                      ],
                    ),
                  );
                },
              ),
              const SizedBox(height: 16),
              _TrackingSavePanel(
                dirty: _dirty,
                saving: widget.saving,
                onSave: _save,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TrackingSettingsHeader extends StatelessWidget {
  const _TrackingSettingsHeader();

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final heading = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: colors.primaryContainer,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(Icons.sensors_rounded, color: colors.onPrimaryContainer),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Theo dõi thiết bị',
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 4),
              Text(
                'Thiết lập cách hệ thống nhận biết trạng thái, chuyển động và các đoạn lộ trình.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: colors.onSurfaceVariant,
                  height: 1.35,
                ),
              ),
            ],
          ),
        ),
      ],
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 620;
        if (compact) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              heading,
              const SizedBox(height: 12),
              const _ImmediateApplyBadge(),
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: heading),
            const SizedBox(width: 18),
            const _ImmediateApplyBadge(),
          ],
        );
      },
    );
  }
}

class _ImmediateApplyBadge extends StatelessWidget {
  const _ImmediateApplyBadge();

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: colors.tertiaryContainer.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.bolt_rounded, size: 16, color: colors.onTertiaryContainer),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              'Áp dụng ngay sau khi lưu',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: colors.onTertiaryContainer,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TrackingSettingPanel extends StatelessWidget {
  const _TrackingSettingPanel({
    super.key,
    required this.icon,
    required this.title,
    required this.description,
    required this.rangeLabel,
    required this.field,
  });

  final IconData icon;
  final String title;
  final String description;
  final String rangeLabel;
  final Widget field;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.surfaceContainerLowest,
        border: Border.all(color: colors.outlineVariant),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: colors.secondaryContainer.withValues(alpha: 0.72),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, size: 20, color: colors.onSecondaryContainer),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                    height: 1.25,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            description,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: colors.onSurfaceVariant,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 14),
          field,
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(
                Icons.info_outline_rounded,
                size: 15,
                color: colors.onSurfaceVariant,
              ),
              const SizedBox(width: 5),
              Expanded(
                child: Text(
                  rangeLabel,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _TrackingSavePanel extends StatelessWidget {
  const _TrackingSavePanel({
    required this.dirty,
    required this.saving,
    required this.onSave,
  });

  final bool dirty;
  final bool saving;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final statusTitle = saving
        ? 'Đang áp dụng cấu hình...'
        : dirty
        ? 'Có thay đổi chưa lưu'
        : 'Cấu hình đã đồng bộ';
    final statusDescription = saving
        ? 'Hệ thống đang đồng bộ các giá trị mới đến các màn hình đang mở.'
        : dirty
        ? 'Kiểm tra các giá trị trước khi áp dụng cho hệ thống.'
        : 'Các giá trị đang hiển thị là cấu hình hiện tại.';
    final statusIcon = saving
        ? Icons.sync_rounded
        : dirty
        ? Icons.pending_actions_outlined
        : Icons.check_circle_outline_rounded;

    final hasPendingChanges = dirty && !saving;
    final status = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: hasPendingChanges
                ? colors.tertiaryContainer
                : colors.primaryContainer,
            shape: BoxShape.circle,
          ),
          child: Icon(
            statusIcon,
            size: 20,
            color: hasPendingChanges
                ? colors.onTertiaryContainer
                : colors.onPrimaryContainer,
          ),
        ),
        const SizedBox(width: 11),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                statusTitle,
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 2),
              Text(
                statusDescription,
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ],
    );

    final saveButton = FilledButton.icon(
      key: const Key('save-system-settings'),
      onPressed: saving ? null : onSave,
      icon: saving
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white,
              ),
            )
          : const Icon(Icons.save_outlined),
      label: Text(saving ? 'Đang lưu...' : 'Lưu thay đổi'),
    );

    return Container(
      key: const Key('tracking-save-panel'),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        border: Border.all(color: colors.outlineVariant),
        borderRadius: BorderRadius.circular(12),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 600;
          if (compact) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [status, const SizedBox(height: 14), saveButton],
            );
          }
          return Row(
            children: [
              Expanded(child: status),
              const SizedBox(width: 20),
              saveButton,
            ],
          );
        },
      ),
    );
  }
}

class _IntegerSettingField extends StatelessWidget {
  const _IntegerSettingField({
    super.key,
    required this.controller,
    required this.label,
    required this.suffix,
    required this.minimum,
    required this.maximum,
  });

  final TextEditingController controller;
  final String label;
  final String suffix;
  final int minimum;
  final int maximum;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      keyboardType: TextInputType.number,
      decoration: InputDecoration(labelText: label, suffixText: suffix),
      validator: (rawValue) {
        final value = int.tryParse(rawValue?.trim() ?? '');
        if (value == null) return 'Phải là số nguyên.';
        if (value < minimum || value > maximum) {
          return 'Từ $minimum đến $maximum.';
        }
        return null;
      },
    );
  }
}

class _DoubleSettingField extends StatelessWidget {
  const _DoubleSettingField({
    super.key,
    required this.controller,
    required this.label,
    required this.suffix,
    required this.minimum,
    required this.maximum,
  });

  final TextEditingController controller;
  final String label;
  final String suffix;
  final double minimum;
  final double maximum;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      decoration: InputDecoration(labelText: label, suffixText: suffix),
      validator: (rawValue) {
        final value = double.tryParse(
          (rawValue ?? '').trim().replaceFirst(',', '.'),
        );
        if (value == null || !value.isFinite) return 'Phải là một số hợp lệ.';
        if (value < minimum || value > maximum) {
          return 'Từ $minimum đến $maximum.';
        }
        return null;
      },
    );
  }
}
