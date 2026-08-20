import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Định dạng thời lượng ngắt quãng thân thiện với người dùng (tiếng Việt).
String formatGapDuration(Duration duration) {
  final totalMinutes = duration.inMinutes;
  if (totalMinutes <= 0) {
    return '${duration.inSeconds} giây';
  }
  if (totalMinutes < 60) {
    return '$totalMinutes phút';
  }
  final hours = totalMinutes ~/ 60;
  final remainingMinutes = totalMinutes % 60;
  if (remainingMinutes == 0) {
    return '$hours giờ';
  }
  return '$hours giờ $remainingMinutes phút';
}

/// Mở hộp thoại chọn mốc thời gian ngắt quãng tùy ý.
Future<Duration?> showCustomGapThresholdDialog(
  BuildContext context, {
  required Duration initialDuration,
}) {
  return showDialog<Duration>(
    context: context,
    builder: (ctx) => CustomGapThresholdDialog(initialDuration: initialDuration),
  );
}

/// Hộp thoại cấu hình khoảng thời gian ngắt quãng tùy ý.
/// Hỗ trợ cả chọn nhanh các mốc thực tế và nhập tùy ý theo Phút / Giờ.
class CustomGapThresholdDialog extends StatefulWidget {
  final Duration initialDuration;

  const CustomGapThresholdDialog({
    super.key,
    required this.initialDuration,
  });

  @override
  State<CustomGapThresholdDialog> createState() => _CustomGapThresholdDialogState();
}

class _CustomGapThresholdDialogState extends State<CustomGapThresholdDialog> {
  late TextEditingController _valueController;
  late String _unit; // 'minutes' hoặc 'hours'
  String? _errorMessage;

  static const Color _refPrimaryBlue = Color(0xFF2563EB);
  static const Color _refText = Color(0xFF0F172A);
  static const Color _refMuted = Color(0xFF64748B);
  static const Color _refBorder = Color(0xFFE2E8F0);
  static const Color _refCardBg = Color(0xFFF8FAFC);

  @override
  void initState() {
    super.initState();
    final initialMinutes = widget.initialDuration.inMinutes;
    if (initialMinutes >= 60 && initialMinutes % 60 == 0) {
      _unit = 'hours';
      _valueController = TextEditingController(text: '${initialMinutes ~/ 60}');
    } else {
      _unit = 'minutes';
      _valueController = TextEditingController(
        text: '${initialMinutes > 0 ? initialMinutes : 5}',
      );
    }
  }

  @override
  void dispose() {
    _valueController.dispose();
    super.dispose();
  }

  int? get _parsedMinutes {
    final text = _valueController.text.trim();
    if (text.isEmpty) return null;
    final val = int.tryParse(text);
    if (val == null || val <= 0) return null;
    if (_unit == 'hours') {
      return val * 60;
    }
    return val;
  }

  bool get _isValid {
    final mins = _parsedMinutes;
    if (mins == null) return false;
    // Ràng buộc: từ 1 phút đến 7 ngày (10080 phút)
    return mins >= 1 && mins <= 10080;
  }

  void _onPresetSelected(int value, String unit) {
    setState(() {
      _unit = unit;
      _valueController.text = value.toString();
      _errorMessage = null;
    });
  }

  void _submit() {
    final mins = _parsedMinutes;
    if (mins == null || mins < 1 || mins > 10080) {
      setState(() {
        _errorMessage = 'Vui lòng nhập khoảng thời gian hợp lệ (từ 1 phút đến 7 ngày).';
      });
      return;
    }
    Navigator.of(context).pop(Duration(minutes: mins));
  }

  @override
  Widget build(BuildContext context) {
    final mins = _parsedMinutes;
    final valid = _isValid;

    return AlertDialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      contentPadding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
      titlePadding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: _refPrimaryBlue.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(
              Icons.timer_outlined,
              size: 20,
              color: _refPrimaryBlue,
            ),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Text(
              'Tùy chọn ngưỡng ngắt quãng',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: _refText,
              ),
            ),
          ),
        ],
      ),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 4),
              const Text(
                'Khoảng thời gian gián đoạn dữ liệu GPS tối thiểu để chia tách chặng di chuyển hoặc tự động nhảy cóc khi xem lại hành trình.',
                style: TextStyle(
                  fontSize: 12,
                  color: _refMuted,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 16),

              // Gợi ý nhanh
              const Text(
                'Gợi ý nhanh:',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: _refText,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  _buildPresetChip(3, 'minutes', '3 phút'),
                  _buildPresetChip(10, 'minutes', '10 phút'),
                  _buildPresetChip(20, 'minutes', '20 phút'),
                  _buildPresetChip(45, 'minutes', '45 phút'),
                  _buildPresetChip(1, 'hours', '1 giờ'),
                  _buildPresetChip(2, 'hours', '2 giờ'),
                  _buildPresetChip(4, 'hours', '4 giờ'),
                  _buildPresetChip(8, 'hours', '8 giờ'),
                  _buildPresetChip(24, 'hours', '24 giờ'),
                ],
              ),
              const SizedBox(height: 16),

              // Ô nhập liệu tùy ý
              const Text(
                'Nhập mốc thời gian tùy ý:',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: _refText,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Số lượng
                  Expanded(
                    flex: 3,
                    child: TextFormField(
                      controller: _valueController,
                      keyboardType: TextInputType.number,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                        LengthLimitingTextInputFormatter(5),
                      ],
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: _refText,
                      ),
                      decoration: InputDecoration(
                        hintText: 'Nhập số...',
                        hintStyle: const TextStyle(fontSize: 12, color: _refMuted),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        filled: true,
                        fillColor: _refCardBg,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: const BorderSide(color: _refBorder),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: const BorderSide(color: _refBorder),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: const BorderSide(color: _refPrimaryBlue, width: 1.5),
                        ),
                      ),
                      onChanged: (_) {
                        setState(() {
                          _errorMessage = null;
                        });
                      },
                      onFieldSubmitted: (_) => _submit(),
                    ),
                  ),
                  const SizedBox(width: 8),

                  // Đơn vị
                  Expanded(
                    flex: 2,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      decoration: BoxDecoration(
                        color: _refCardBg,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: _refBorder),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: _unit,
                          isExpanded: true,
                          style: const TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                            color: _refText,
                          ),
                          items: const [
                            DropdownMenuItem(
                              value: 'minutes',
                              child: Text('Phút'),
                            ),
                            DropdownMenuItem(
                              value: 'hours',
                              child: Text('Giờ'),
                            ),
                          ],
                          onChanged: (val) {
                            if (val != null) {
                              setState(() {
                                _unit = val;
                                _errorMessage = null;
                              });
                            }
                          },
                        ),
                      ),
                    ),
                  ),
                ],
              ),

              if (_errorMessage != null) ...[
                const SizedBox(height: 8),
                Text(
                  _errorMessage!,
                  style: const TextStyle(
                    fontSize: 11.5,
                    color: Colors.redAccent,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],

              const SizedBox(height: 14),

              // Preview giải thích
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: valid
                      ? _refPrimaryBlue.withValues(alpha: 0.06)
                      : Colors.orange.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: valid
                        ? _refPrimaryBlue.withValues(alpha: 0.2)
                        : Colors.orange.withValues(alpha: 0.3),
                  ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      valid ? Icons.info_outline_rounded : Icons.warning_amber_rounded,
                      size: 16,
                      color: valid ? _refPrimaryBlue : Colors.orange[800],
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        valid
                            ? 'Áp dụng ngưỡng ngắt quãng: ${formatGapDuration(Duration(minutes: mins!))}'
                            : 'Vui lòng nhập giá trị hợp lệ từ 1 phút đến 7 ngày (168 giờ).',
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: valid ? FontWeight.w600 : FontWeight.w500,
                          color: valid ? _refPrimaryBlue : Colors.orange[900],
                          height: 1.3,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Hủy'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: _refPrimaryBlue,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          onPressed: valid ? _submit : null,
          child: const Text('Áp dụng'),
        ),
      ],
    );
  }

  Widget _buildPresetChip(int value, String unit, String label) {
    final isSelected = _unit == unit && _valueController.text.trim() == value.toString();

    return ActionChip(
      label: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
          color: isSelected ? _refPrimaryBlue : _refText,
        ),
      ),
      backgroundColor: isSelected ? _refPrimaryBlue.withValues(alpha: 0.1) : _refCardBg,
      side: BorderSide(
        color: isSelected ? _refPrimaryBlue : _refBorder,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0),
      visualDensity: VisualDensity.compact,
      onPressed: () => _onPresetSelected(value, unit),
    );
  }
}
