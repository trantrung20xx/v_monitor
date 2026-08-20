import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/utils/device_formatters.dart';
import '../journey_history_state.dart';

class PlaybackControls extends StatelessWidget {
  final JourneyHistoryState state;
  final VoidCallback onPlay;
  final VoidCallback onPause;
  final VoidCallback onResume;
  final VoidCallback onReset;
  final VoidCallback? onStepBackward30s;
  final VoidCallback? onStepBackward60s;
  final VoidCallback? onStepForward30s;
  final VoidCallback? onStepForward60s;
  final ValueChanged<double> onSeekProgress;
  final ValueChanged<double> onSpeedChanged;
  final ValueChanged<bool> onFollowChanged;

  const PlaybackControls({
    super.key,
    required this.state,
    required this.onPlay,
    required this.onPause,
    required this.onResume,
    required this.onReset,
    this.onStepBackward30s,
    this.onStepBackward60s,
    this.onStepForward30s,
    this.onStepForward60s,
    required this.onSeekProgress,
    required this.onSpeedChanged,
    required this.onFollowChanged,
  });

  static final DateFormat _timeFormat = DateFormat('HH:mm:ss');
  static final DateFormat _dateFormat = DateFormat('dd/MM/yyyy HH:mm:ss');

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final width = MediaQuery.sizeOf(context).width;
    final isDesktop = width >= 800;
    final isCompact = width < 680;

    final hasSamples = state.validSamples.length >= 2;
    final startTimeStr = hasSamples
        ? _timeFormat.format(state.validSamples.first.measuredAt.toLocal())
        : '--:--:--';
    final endTimeStr = hasSamples
        ? _timeFormat.format(state.validSamples.last.measuredAt.toLocal())
        : '--:--:--';
    final currentTimeStr = state.currentReplayTime != null
        ? _dateFormat.format(state.currentReplayTime!.toLocal())
        : '--/--/---- --:--:--';

    final buttonsRow = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          icon: const Icon(Icons.fast_rewind_rounded, size: 22),
          tooltip: 'Lùi 60 giây (1 phút)',
          visualDensity: VisualDensity.compact,
          onPressed: hasSamples ? onStepBackward60s : null,
        ),
        IconButton(
          icon: const Icon(Icons.replay_30_rounded, size: 22),
          tooltip: 'Lùi 30 giây',
          visualDensity: VisualDensity.compact,
          onPressed: hasSamples ? onStepBackward30s : null,
        ),
        const SizedBox(width: 2),
        FilledButton.icon(
          style: FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          ),
          onPressed: !hasSamples
              ? null
              : state.isPlaying
              ? onPause
              : (state.isPaused ? onResume : onPlay),
          icon: Icon(
            state.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
            size: 20,
          ),
          label: Text(
            state.isPlaying
                ? 'Tạm dừng'
                : (state.isPaused
                      ? 'Tiếp tục'
                      : (state.isCompleted ? 'Phát lại' : 'Bắt đầu')),
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
        ),
        const SizedBox(width: 2),
        IconButton(
          icon: const Icon(Icons.forward_30_rounded, size: 22),
          tooltip: 'Tiến 30 giây',
          visualDensity: VisualDensity.compact,
          onPressed: hasSamples ? onStepForward30s : null,
        ),
        IconButton(
          icon: const Icon(Icons.fast_forward_rounded, size: 22),
          tooltip: 'Tiến 60 giây (1 phút)',
          visualDensity: VisualDensity.compact,
          onPressed: hasSamples ? onStepForward60s : null,
        ),
        IconButton(
          icon: const Icon(Icons.replay_rounded, size: 20),
          tooltip: 'Bắt đầu lại',
          visualDensity: VisualDensity.compact,
          onPressed: hasSamples ? onReset : null,
        ),
      ],
    );

    final speedAndFollowRow = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Tốc độ phát
        DropdownButton<double>(
          value: state.playbackSpeed,
          underline: const SizedBox.shrink(),
          isDense: true,
          style: theme.textTheme.labelMedium?.copyWith(
            fontWeight: FontWeight.bold,
            color: theme.colorScheme.onSurface,
          ),
          items: const [
            DropdownMenuItem(value: 0.5, child: Text('0.5x')),
            DropdownMenuItem(value: 1.0, child: Text('1x')),
            DropdownMenuItem(value: 2.0, child: Text('2x')),
            DropdownMenuItem(value: 4.0, child: Text('4x')),
            DropdownMenuItem(value: 8.0, child: Text('8x')),
            DropdownMenuItem(value: 16.0, child: Text('16x')),
          ],
          onChanged: (v) {
            if (v != null) onSpeedChanged(v);
          },
        ),
        const SizedBox(width: 8),

        // Toggle theo dõi thiết bị
        InkWell(
          borderRadius: BorderRadius.circular(6),
          onTap: () => onFollowChanged(!state.followCamera),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  state.followCamera
                      ? Icons.center_focus_strong_rounded
                      : Icons.center_focus_weak_rounded,
                  size: 18,
                  color: state.followCamera
                      ? theme.colorScheme.primary
                      : theme.colorScheme.outline,
                ),
                if (isDesktop || (!isCompact && width >= 500)) ...[
                  const SizedBox(width: 4),
                  Text(
                    'Theo dõi xe',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: state.followCamera
                          ? theme.colorScheme.primary
                          : theme.colorScheme.outline,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );

    return Card(
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: isCompact ? 10 : 16,
          vertical: isCompact ? 8 : 10,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 1. Mốc thời gian hiện tại
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.access_time_filled_rounded,
                      size: 16,
                      color: theme.colorScheme.primary,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      currentTimeStr,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                  ],
                ),
                if (state.currentSpeedMps != null)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '${DeviceFormatters.speedMps(state.currentSpeedMps)} · ${DeviceFormatters.heading(state.currentHeadingDeg)}',
                      style: theme.textTheme.labelSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: theme.colorScheme.onPrimaryContainer,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 4),

            // 2. Thanh trượt dòng thời gian.
            Row(
              children: [
                Text(
                  startTimeStr,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                Expanded(
                  child: SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      trackHeight: 4,
                      thumbShape: const RoundSliderThumbShape(
                        enabledThumbRadius: 7,
                      ),
                      overlayShape: const RoundSliderOverlayShape(
                        overlayRadius: 14,
                      ),
                    ),
                    child: Slider(
                      value: state.playbackProgress,
                      onChanged: hasSamples ? onSeekProgress : null,
                    ),
                  ),
                ),
                Text(
                  endTimeStr,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),

            const SizedBox(height: 2),

            // 3. Thanh nút điều khiển
            if (!isCompact)
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [buttonsRow, speedAndFollowRow],
              )
            else
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: buttonsRow,
                  ),
                  const SizedBox(height: 4),
                  speedAndFollowRow,
                ],
              ),
          ],
        ),
      ),
    );
  }
}
