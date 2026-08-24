import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_theme_colors.dart';
import '../../../core/utils/device_formatters.dart';
import '../../../data/models/location_model.dart';
import '../../../domain/entities/device_status_resolver.dart';
import 'history_map_layers.dart';

typedef JourneyAddressResolver =
    Future<String?> Function(double latitude, double longitude);

class PointInfoPopup extends StatefulWidget {
  const PointInfoPopup({
    super.key,
    required this.point,
    required this.onClose,
    this.stopPoint,
    this.resolveAddress,
  });

  final LocationModel point;
  final VoidCallback onClose;
  final JourneyStopPoint? stopPoint;
  final JourneyAddressResolver? resolveAddress;

  @override
  State<PointInfoPopup> createState() => _PointInfoPopupState();
}

class _PointInfoPopupState extends State<PointInfoPopup> {
  Future<String?>? _addressFuture;

  @override
  void initState() {
    super.initState();
    _loadAddress();
  }

  @override
  void didUpdateWidget(covariant PointInfoPopup oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.point.latitude != widget.point.latitude ||
        oldWidget.point.longitude != widget.point.longitude ||
        oldWidget.resolveAddress != widget.resolveAddress) {
      _loadAddress();
    }
  }

  void _loadAddress() {
    final resolver = widget.resolveAddress;
    _addressFuture = resolver?.call(
      widget.point.latitude,
      widget.point.longitude,
    );
  }

  @override
  Widget build(BuildContext context) {
    final appColors = context.appColors;
    final point = widget.point;
    final stop = widget.stopPoint;
    final isParked = stop?.isPark ?? false;
    final isMoving =
        point.speedMps != null &&
        point.speedMps! > DeviceStatusResolver.movingThresholdMps;
    final isStopped = stop != null || (point.speedMps != null && !isMoving);
    final accentColor = isParked
        ? appColors.orange
        : isMoving
        ? appColors.primary
        : isStopped
        ? appColors.warning
        : appColors.textSecondary;
    final headerIcon = isParked
        ? Icons.local_parking_rounded
        : isMoving
        ? Icons.directions_car_filled_rounded
        : isStopped
        ? Icons.pause_circle_filled_rounded
        : Icons.location_on_rounded;
    final headerTitle = isParked
        ? 'ĐIỂM ĐỖ XE'
        : isMoving
        ? 'MỐC DI CHUYỂN'
        : isStopped
        ? 'ĐIỂM DỪNG'
        : 'MỐC GPS';

    return TapRegion(
      onTapOutside: (_) => widget.onClose(),
      child: Material(
        color: AppPalette.transparent,
        child: Container(
          constraints: const BoxConstraints(maxWidth: 310),
          decoration: BoxDecoration(
            color: appColors.surface.withValues(alpha: 0.98),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: accentColor.withValues(alpha: 0.28)),
            boxShadow: [
              BoxShadow(
                color: appColors.shadow.withValues(alpha: 0.18),
                blurRadius: 24,
                offset: Offset(0, 8),
              ),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: const EdgeInsets.fromLTRB(10, 5, 4, 5),
                color: accentColor,
                child: Row(
                  children: [
                    Container(
                      width: 22,
                      height: 22,
                      decoration: BoxDecoration(
                        color: AppPalette.onAccent.withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(
                        headerIcon,
                        size: 14,
                        color: AppPalette.onAccent,
                      ),
                    ),
                    const SizedBox(width: 7),
                    Expanded(
                      child: Text(
                        stop != null
                            ? '$headerTitle · ${stop.durationLabel}'
                            : headerTitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppPalette.onAccent,
                          fontSize: 11,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0.25,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: widget.onClose,
                      icon: const Icon(
                        Icons.close_rounded,
                        size: 18,
                        color: AppPalette.onAccent,
                      ),
                      tooltip: 'Đóng',
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(
                        minWidth: 28,
                        minHeight: 28,
                      ),
                      visualDensity: VisualDensity.compact,
                      splashRadius: 16,
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(8),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _PopupInfoRow(
                      icon: Icons.schedule_rounded,
                      label: 'Thời gian',
                      value: stop != null
                          ? _formatStopTime(stop)
                          : DeviceFormatters.dateTimeSeconds(point.measuredAt),
                      accentColor: accentColor,
                    ),
                    if (stop != null) ...[
                      const SizedBox(height: 6),
                      _PopupInfoRow(
                        icon: Icons.hourglass_bottom_rounded,
                        label: isParked ? 'Thời lượng đỗ' : 'Thời lượng dừng',
                        value: stop.durationLabel,
                        accentColor: accentColor,
                      ),
                    ],
                    if (isMoving && point.speedMps != null) ...[
                      const SizedBox(height: 6),
                      _PopupInfoRow(
                        icon: Icons.speed_rounded,
                        label: 'Tốc độ',
                        value: DeviceFormatters.speedMps(point.speedMps),
                        accentColor: accentColor,
                      ),
                    ],
                    const SizedBox(height: 6),
                    _PopupAddressRow(
                      addressFuture: _addressFuture,
                      accentColor: accentColor,
                    ),
                    const SizedBox(height: 6),
                    _PopupInfoRow(
                      icon: Icons.my_location_rounded,
                      label: 'Tọa độ',
                      value: DeviceFormatters.coordinates(
                        point.latitude,
                        point.longitude,
                      ),
                      accentColor: accentColor,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _formatStopTime(JourneyStopPoint stop) {
    final start = stop.startTime.toLocal();
    final end = stop.endTime.toLocal();
    final sameDay =
        start.year == end.year &&
        start.month == end.month &&
        start.day == end.day;
    if (sameDay) {
      return '${DateFormat('HH:mm:ss').format(start)} ➔ '
          '${DateFormat('HH:mm:ss').format(end)} '
          '(${DateFormat('dd/MM/yyyy').format(start)})';
    }
    return '${DateFormat('HH:mm:ss dd/MM/yyyy').format(start)} ➔ '
        '${DateFormat('HH:mm:ss dd/MM/yyyy').format(end)}';
  }
}

class _PopupAddressRow extends StatelessWidget {
  const _PopupAddressRow({
    required this.addressFuture,
    required this.accentColor,
  });

  final Future<String?>? addressFuture;
  final Color accentColor;

  @override
  Widget build(BuildContext context) {
    if (addressFuture == null) {
      return _PopupInfoRow(
        icon: Icons.location_on_rounded,
        label: 'Địa chỉ',
        value: 'Chưa xác định được địa chỉ',
        accentColor: accentColor,
      );
    }

    return FutureBuilder<String?>(
      future: addressFuture,
      builder: (context, snapshot) {
        final isLoading = snapshot.connectionState == ConnectionState.waiting;
        return _PopupInfoRow(
          icon: Icons.location_on_rounded,
          label: 'Địa chỉ',
          value: isLoading
              ? 'Đang xác định địa chỉ...'
              : (snapshot.data?.trim().isNotEmpty ?? false)
              ? snapshot.data!.trim()
              : 'Chưa xác định được địa chỉ',
          accentColor: accentColor,
          loading: isLoading,
        );
      },
    );
  }
}

class _PopupInfoRow extends StatelessWidget {
  const _PopupInfoRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.accentColor,
    this.loading = false,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color accentColor;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 22,
          height: 22,
          decoration: BoxDecoration(
            color: accentColor.withValues(alpha: 0.09),
            borderRadius: BorderRadius.circular(8),
          ),
          alignment: Alignment.center,
          child: loading
              ? SizedBox(
                  width: 12,
                  height: 12,
                  child: CircularProgressIndicator(
                    strokeWidth: 1.8,
                    color: accentColor,
                  ),
                )
              : Icon(icon, size: 12, color: accentColor),
        ),
        const SizedBox(width: 7),
        SizedBox(
          width: 66,
          child: Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              '$label:',
              style: TextStyle(
                color: context.appColors.textSecondary,
                fontSize: 9.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(top: 3),
            child: Text(
              value,
              style: TextStyle(
                color: context.appColors.textPrimary,
                fontSize: 10,
                fontWeight: FontWeight.w700,
                height: 1.35,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
