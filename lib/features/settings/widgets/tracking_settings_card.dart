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
              Row(
                children: [
                  Icon(
                    Icons.sensors_rounded,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Theo dõi thiết bị',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'Các giá trị mới được áp dụng ngay cho backend và mọi màn hình đang mở, không cần khởi động lại.',
                style: TextStyle(color: Theme.of(context).colorScheme.outline),
              ),
              const SizedBox(height: 18),
              LayoutBuilder(
                builder: (context, constraints) {
                  final isWide = constraints.maxWidth >= 760;
                  final fields = [
                    _IntegerSettingField(
                      key: const Key('offline-timeout-field'),
                      controller: _offlineController,
                      label: 'Thời gian xác định ngoại tuyến',
                      suffix: 'giây',
                      minimum: 30,
                      maximum: 86400,
                    ),
                    _DoubleSettingField(
                      key: const Key('movement-threshold-field'),
                      controller: _movementController,
                      label: 'Ngưỡng xác định di chuyển',
                      suffix: 'm/s',
                      minimum: 0,
                      maximum: 10,
                    ),
                    _IntegerSettingField(
                      key: const Key('journey-gap-field'),
                      controller: _gapController,
                      label: 'Khoảng ngắt lộ trình mặc định',
                      suffix: 'giây',
                      minimum: 60,
                      maximum: 3600,
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
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (var index = 0; index < fields.length; index++) ...[
                        Expanded(child: fields[index]),
                        if (index < fields.length - 1)
                          const SizedBox(width: 14),
                      ],
                    ],
                  );
                },
              ),
              const SizedBox(height: 18),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton.icon(
                  key: const Key('save-system-settings'),
                  onPressed: widget.saving ? null : _save,
                  icon: widget.saving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.save_outlined),
                  label: Text(widget.saving ? 'Đang lưu...' : 'Lưu thay đổi'),
                ),
              ),
            ],
          ),
        ),
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
