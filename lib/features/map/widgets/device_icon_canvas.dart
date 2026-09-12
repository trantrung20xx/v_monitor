import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../../core/widgets/device_icon.dart';
import 'device_map_icon.dart';

/// Dữ liệu của một icon độc lập; không tạo cây widget cho từng thiết bị.
class DeviceMapMarker extends Marker {
  DeviceMapMarker({
    required String id,
    required super.point,
    required this.deviceType,
    required this.color,
    required this.headingDegrees,
    required this.description,
    required this.onTap,
  }) : super(
         key: ValueKey('map-device-$id'),
         width: DeviceMapIcon.touchSize,
         height: DeviceMapIcon.touchSize,
         child: const SizedBox.shrink(),
       );

  final String deviceType;
  final Color color;
  final double? headingDegrees;
  final String description;
  final VoidCallback onTap;
}

class ProjectedDeviceMarker {
  const ProjectedDeviceMarker(this.marker, this.position);
  final DeviceMapMarker marker;
  final Offset position;
  Rect get bounds => Rect.fromCenter(
    center: position,
    width: DeviceMapIcon.touchSize,
    height: DeviceMapIcon.touchSize,
  );
}

/// Một atlas nhỏ dùng chung cho mọi thiết bị và mọi lần mở bản đồ.
class DeviceIconAtlas {
  // Kích thước nguồn cố định để atlas đã cache vẫn đúng khi đổi cỡ hiển thị.
  static const spriteSize = 168.0;
  static final Future<ui.Image> image = _load();

  static Future<ui.Image> _load() async {
    final images = <ui.Image>[];
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    try {
      for (final asset in [DeviceMapIcon.carAsset, DeviceMapIcon.uavAsset]) {
        final bytes = await rootBundle.load(asset);
        final codec = await ui.instantiateImageCodec(
          bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
          targetWidth: spriteSize.toInt(),
          targetHeight: spriteSize.toInt(),
        );
        try {
          final frame = await codec.getNextFrame();
          canvas.drawImage(
            frame.image,
            Offset(images.length * spriteSize, 0),
            Paint(),
          );
          // Viền trắng ~0,5 px màn hình được vẽ sẵn, không dùng blur mỗi khung.
          final outlinePaint = Paint()
            ..colorFilter = const ColorFilter.mode(
              Colors.white,
              BlendMode.srcIn,
            );
          for (final offset in const [
            Offset(-2, -2),
            Offset(0, -2),
            Offset(2, -2),
            Offset(-2, 0),
            Offset(2, 0),
            Offset(-2, 2),
            Offset(0, 2),
            Offset(2, 2),
          ]) {
            canvas.drawImage(
              frame.image,
              Offset(images.length * spriteSize, spriteSize) + offset,
              outlinePaint,
            );
          }
          images.add(frame.image);
        } finally {
          codec.dispose();
        }
      }
      final picture = recorder.endRecording();
      try {
        return await picture.toImage(
          (spriteSize * 2).toInt(),
          (spriteSize * 2).toInt(),
        );
      } finally {
        picture.dispose();
      }
    } finally {
      for (final image in images) {
        image.dispose();
      }
    }
  }
}

/// Dùng cùng ảnh và cách tô màu của bản đồ chính cho marker đơn lẻ.
class DeviceMarkerIcon extends StatelessWidget {
  const DeviceMarkerIcon({
    super.key,
    required this.deviceType,
    required this.color,
    this.headingDegrees,
  });

  final String deviceType;
  final Color color;
  final double? headingDegrees;

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: DeviceMapIcon.touchSize,
    child: ExcludeSemantics(
      child: FutureBuilder<ui.Image>(
        future: DeviceIconAtlas.image,
        builder: (context, snapshot) => CustomPaint(
          painter: DeviceIconPainter([
            ProjectedDeviceMarker(
              DeviceMapMarker(
                id: 'artwork',
                point: const LatLng(0, 0),
                deviceType: deviceType,
                color: color,
                headingDegrees: headingDegrees,
                description: '',
                onTap: () {},
              ),
              const Offset(
                DeviceMapIcon.touchSize / 2,
                DeviceMapIcon.touchSize / 2,
              ),
            ),
          ], snapshot.data),
        ),
      ),
    ),
  );
}

class DeviceIconCanvas extends StatefulWidget {
  const DeviceIconCanvas({super.key, required this.markers});
  final List<ProjectedDeviceMarker> markers;

  @override
  State<DeviceIconCanvas> createState() => _DeviceIconCanvasState();
}

class _DeviceIconCanvasState extends State<DeviceIconCanvas> {
  ui.Image? _atlas;
  Key? _hovered;
  final _tooltip = GlobalKey<TooltipState>();

  @override
  void initState() {
    super.initState();
    DeviceIconAtlas.image.then(
      (image) {
        if (mounted) setState(() => _atlas = image);
      },
      onError: (Object error, StackTrace stack) {
        // Dùng icon có sẵn nếu asset không tải được; bản đồ vẫn thao tác được.
        debugPrint('Map icon asset: $error');
      },
    );
  }

  void _showDescription(Offset? position) {
    final key = position == null
        ? null
        : DeviceIconPainter.hit(widget.markers, position)?.marker.key;
    if (key == _hovered) return;
    setState(() => _hovered = key);
    if (key != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _tooltip.currentState?.ensureTooltipVisible();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final hover = widget.markers
        .where((m) => m.marker.key == _hovered)
        .firstOrNull;
    return MouseRegion(
      opaque: false,
      onHover: (event) => _showDescription(event.localPosition),
      onExit: (_) => _showDescription(null),
      child: GestureDetector(
        onTapUp: (event) => DeviceIconPainter.hit(
          widget.markers,
          event.localPosition,
        )?.marker.onTap(),
        onLongPressStart: (event) => _showDescription(event.localPosition),
        onLongPressEnd: (_) => _showDescription(null),
        child: Stack(
          fit: StackFit.expand,
          children: [
            CustomPaint(painter: DeviceIconPainter(widget.markers, _atlas)),
            if (hover != null)
              Positioned.fromRect(
                rect: hover.bounds,
                child: IgnorePointer(
                  child: Tooltip(
                    key: _tooltip,
                    message: hover.marker.description,
                    excludeFromSemantics: true,
                    triggerMode: TooltipTriggerMode.manual,
                    child: const SizedBox.expand(),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Vẽ theo đúng thứ tự thiết bị; hit test chọn icon trên cùng khi trùng tọa độ.
class DeviceIconPainter extends CustomPainter {
  DeviceIconPainter(this.markers, this.atlas);
  final List<ProjectedDeviceMarker> markers;
  final ui.Image? atlas;

  static ProjectedDeviceMarker? hit(
    List<ProjectedDeviceMarker> markers,
    Offset point,
  ) {
    for (final marker in markers.reversed) {
      if (marker.bounds.contains(point)) return marker;
    }
    return null;
  }

  @override
  bool hitTest(Offset position) => hit(markers, position) != null;

  @override
  void paint(Canvas canvas, Size size) {
    final transforms = Float32List(markers.length * 8);
    final rects = Float32List(markers.length * 8);
    final colors = Int32List(markers.length * 2);
    final paint = Paint()..filterQuality = FilterQuality.low;
    final fallbacks = <(String, Color), TextPainter>{};
    var count = 0;
    void flush() {
      if (count == 0) return;
      canvas.drawRawAtlas(
        atlas!,
        Float32List.sublistView(transforms, 0, count * 4),
        Float32List.sublistView(rects, 0, count * 4),
        Int32List.sublistView(colors, 0, count),
        // Nhân màu thân ảnh, giữ sắc độ kính, bánh xe, cánh quạt và bóng khối.
        BlendMode.modulate,
        null,
        paint,
      );
      count = 0;
    }

    for (final projected in markers) {
      final m = projected.marker;
      final type = m.deviceType.trim().toUpperCase();
      final angle = (m.headingDegrees ?? 0) * math.pi / 180;
      if (atlas == null || (type != 'VEHICLE' && type != 'UAV_CONTROLLER')) {
        flush();
        final painter = fallbacks.putIfAbsent((type, m.color), () {
          final icon = DeviceIcon.iconFor(type);
          return TextPainter(
            textDirection: TextDirection.ltr,
            text: TextSpan(
              text: String.fromCharCode(icon.codePoint),
              style: TextStyle(
                fontFamily: icon.fontFamily,
                package: icon.fontPackage,
                fontSize: DeviceMapIcon.artworkSize,
                color: m.color,
              ),
            ),
          )..layout();
        });
        canvas.save();
        canvas.translate(projected.position.dx, projected.position.dy);
        canvas.rotate(angle);
        painter.paint(canvas, Offset(-painter.width / 2, -painter.height / 2));
        canvas.restore();
        continue;
      }
      const sourceSize = DeviceIconAtlas.spriteSize;
      const scale = DeviceMapIcon.artworkSize / sourceSize;
      final cosine = math.cos(angle) * scale;
      final sine = math.sin(angle) * scale;
      // Viền rồi đến thân cho từng thiết bị, giữ đúng thứ tự chồng hình/hit test.
      for (final outline in const [true, false]) {
        final i = count * 4;
        transforms[i] = cosine;
        transforms[i + 1] = sine;
        transforms[i + 2] =
            projected.position.dx - (cosine - sine) * sourceSize / 2;
        transforms[i + 3] =
            projected.position.dy - (sine + cosine) * sourceSize / 2;
        rects[i] = type == 'VEHICLE' ? 0 : sourceSize;
        rects[i + 1] = outline ? sourceSize : 0;
        rects[i + 2] = rects[i] + sourceSize;
        rects[i + 3] = rects[i + 1] + sourceSize;
        colors[count++] = (outline ? Colors.white : m.color).toARGB32();
      }
    }
    flush();
    for (final painter in fallbacks.values) {
      painter.dispose();
    }
  }

  @override
  SemanticsBuilderCallback get semanticsBuilder =>
      (_) => [
        for (final projected in markers)
          CustomPainterSemantics(
            key: projected.marker.key,
            rect: projected.bounds,
            properties: SemanticsProperties(
              label: projected.marker.description,
              textDirection: TextDirection.ltr,
              button: true,
              onTap: projected.marker.onTap,
            ),
          ),
      ];

  @override
  bool shouldRepaint(DeviceIconPainter oldDelegate) =>
      oldDelegate.markers != markers || oldDelegate.atlas != atlas;

  @override
  bool shouldRebuildSemantics(DeviceIconPainter oldDelegate) =>
      oldDelegate.markers != markers;
}
