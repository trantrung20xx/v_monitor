import 'package:flutter/material.dart';

/// Đăng ký nhu cầu địa chỉ theo vòng đời item của danh sách lazy.
class VisibleDevice extends StatefulWidget {
  const VisibleDevice({
    super.key,
    required this.deviceId,
    required this.child,
    this.onVisibilityChanged,
  });
  final String deviceId;
  final Widget child;
  final void Function(String, bool)? onVisibilityChanged;

  @override
  State<VisibleDevice> createState() => _VisibleDeviceState();
}

class _VisibleDeviceState extends State<VisibleDevice> {
  bool _registered = false;
  bool _enabled = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _enabled = TickerMode.valuesOf(context).enabled;
    _schedule();
  }

  @override
  void didUpdateWidget(covariant VisibleDevice oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.deviceId != widget.deviceId ||
        oldWidget.onVisibilityChanged != widget.onVisibilityChanged) {
      if (_registered) {
        oldWidget.onVisibilityChanged?.call(oldWidget.deviceId, false);
      }
      _registered = false;
      _schedule();
    }
  }

  void _schedule() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _registered == _enabled) return;
      _registered = _enabled;
      widget.onVisibilityChanged?.call(widget.deviceId, _registered);
    });
  }

  @override
  void dispose() {
    if (_registered) widget.onVisibilityChanged?.call(widget.deviceId, false);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
