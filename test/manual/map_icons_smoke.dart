// Native release check with real REST/WebSocket clients and an isolated fixture server.
// flutter build windows --release --target test/manual/map_icons_smoke.dart
// Run from the repository root; results: build/verification/map_icons/.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';
import 'package:v_monitor/app/app_theme.dart';
import 'package:v_monitor/core/network/api_client.dart';
import 'package:v_monitor/core/network/websocket_client.dart';
import 'package:v_monitor/core/theme/app_theme_colors.dart';
import 'package:v_monitor/data/repositories/device_repository.dart';
import 'package:v_monitor/data/repositories/geocoding_repository.dart';
import 'package:v_monitor/features/map/map_view_page.dart';
import 'package:v_monitor/features/map/widgets/device_list_overlay.dart';
import 'package:v_monitor/features/map/widgets/device_icon_canvas.dart';
import '../support/settings_test_scope.dart';

final output = Directory('build/verification/map_icons');
final screenshotKey = GlobalKey();
final layout = ValueNotifier((
  size: const Size(1200, 650),
  dark: false,
  textScale: 1.0,
));
final errors = <String>[];
final results = <Map<String, Object?>>[];
final frames = <String, List<ui.FrameTiming>>{};
String? measuring;
const center = LatLng(21.0322, 105.80776);

List<T> widgets<T extends Widget>() {
  final found = <T>[];
  void visit(Element element) {
    if (element.widget is T) found.add(element.widget as T);
    element.visitChildren(visit);
  }

  WidgetsBinding.instance.rootElement?.visitChildren(visit);
  return found;
}

void check(bool value, String message) {
  if (!value) throw StateError(message);
}

Future<void> until(bool Function() predicate, String message) async {
  final deadline = DateTime.now().add(const Duration(seconds: 30));
  while (!predicate()) {
    if (DateTime.now().isAfter(deadline)) throw StateError(message);
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
}

Future<void> settle() async {
  await Future<void>.delayed(const Duration(milliseconds: 900));
  await WidgetsBinding.instance.endOfFrame;
}

List<DeviceMapMarker> mapMarkers() =>
    widgets<DeviceIconCanvas>().single.markers.map((m) => m.marker).toList();
DeviceMapMarker marker(String id) =>
    mapMarkers().firstWhere((m) => m.key == ValueKey('map-device-$id'));
DeviceMapMarker icon(String id) => marker(id);

Future<void> tapMarker(String id) async {
  RenderBox? target;
  void visit(Element element) {
    if (element.widget is DeviceIconCanvas) {
      target = element.findRenderObject() as RenderBox;
    }
    element.visitChildren(visit);
  }

  WidgetsBinding.instance.rootElement?.visitChildren(visit);
  final m = widgets<DeviceIconCanvas>().single.markers.firstWhere(
    (m) => m.marker.key == ValueKey('map-device-$id'),
  );
  await tapAt(target!.localToGlobal(m.position));
}

Future<void> tapWhere(bool Function(Widget) predicate) async {
  RenderBox? target;
  void visit(Element element) {
    if (target != null) return;
    if (predicate(element.widget)) {
      target = element.findRenderObject() as RenderBox?;
    }
    element.visitChildren(visit);
  }

  WidgetsBinding.instance.rootElement?.visitChildren(visit);
  check(target != null, 'Tap target exists');
  final position = target!.localToGlobal(target!.size.center(Offset.zero));
  await tapAt(position);
}

Future<void> tapAt(Offset position) async {
  GestureBinding.instance.handlePointerEvent(
    PointerDownEvent(pointer: 1, position: position),
  );
  await Future<void>.delayed(const Duration(milliseconds: 30));
  GestureBinding.instance.handlePointerEvent(
    PointerUpEvent(pointer: 1, position: position),
  );
}

Future<void> capture(String name) async {
  await settle();
  final boundary =
      screenshotKey.currentContext!.findRenderObject()!
          as RenderRepaintBoundary;
  final image = await boundary.toImage(pixelRatio: 1);
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  await File(
    '${output.path}/$name.png',
  ).writeAsBytes(bytes!.buffer.asUint8List());
  image.dispose();
  results.add({
    'stage': name,
    'markers': mapMarkers().length,
    'errors': errors.length,
  });
}

Future<void> main() async {
  final binding = WidgetsFlutterBinding.ensureInitialized();
  output.createSync(recursive: true);
  FlutterError.onError = (details) {
    errors.add(details.exceptionAsString());
    FlutterError.presentError(details);
  };
  ui.PlatformDispatcher.instance.onError = (error, stack) {
    errors.add('$error\n$stack');
    return true;
  };
  binding.addTimingsCallback((batch) {
    final phase = measuring;
    if (phase != null) (frames[phase] ??= []).addAll(batch);
  });
  final fixture = await FixtureServer.start();
  final client = ApiClient(
    dio: Dio(BaseOptions(baseUrl: 'http://127.0.0.1:${fixture.port}/api/v1')),
  );
  final websocket = WebsocketClient(
    connectionUri: Uri.parse('ws://127.0.0.1:${fixture.port}/ws'),
  );
  final repo = DeviceRepository(client, websocket);
  final router = GoRouter(
    routes: [
      GoRoute(path: '/', builder: (_, _) => const MapViewPage()),
      GoRoute(
        path: '/devices/:id',
        name: 'device-detail',
        builder: (_, state) =>
            Scaffold(body: Text('detail:${state.pathParameters['id']}')),
      ),
    ],
  );
  runApp(
    SettingsTestScope(
      child: MultiRepositoryProvider(
        providers: [
          RepositoryProvider<DeviceRepository>.value(value: repo),
          RepositoryProvider<GeocodingRepository>.value(
            value: GeocodingRepository(client),
          ),
        ],
        child: ValueListenableBuilder(
          valueListenable: layout,
          builder: (_, value, _) => MaterialApp.router(
            theme: AppTheme.light,
            darkTheme: AppTheme.dark,
            themeMode: value.dark ? ThemeMode.dark : ThemeMode.light,
            routerConfig: router,
            builder: (context, child) => Center(
              child: SizedBox(
                width: value.size.width,
                height: value.size.height,
                child: RepaintBoundary(
                  key: screenshotKey,
                  child: MediaQuery(
                    data: MediaQuery.of(context).copyWith(
                      size: value.size,
                      textScaler: TextScaler.linear(value.textScale),
                    ),
                    child: child!,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  websocket.connect();
  try {
    await until(
      () =>
          widgets<DeviceIconCanvas>().isNotEmpty && fixture.sockets.isNotEmpty,
      'Initial REST/WebSocket connection',
    );
    var controller = widgets<FlutterMap>().single.mapController!;
    controller.move(center, 16);
    await settle();
    check(mapMarkers().length == 12, 'All visual state samples present');
    for (final (i, color) in [
      (0, AppThemeColors.light.primary),
      (1, AppThemeColors.light.warning),
      (2, AppThemeColors.light.danger),
      (3, AppThemeColors.light.offline),
      (4, AppThemeColors.light.offline),
      (5, AppThemeColors.light.success),
      (6, AppThemeColors.light.primary),
      (7, AppThemeColors.light.warning),
      (8, AppThemeColors.light.danger),
      (9, AppThemeColors.light.offline),
      (10, AppThemeColors.light.offline),
      (11, AppThemeColors.light.success),
    ]) {
      check(icon('$i').color == color, 'Status color for fixture $i');
    }
    await capture('01-colors-and-bearings-light');
    controller.rotate(45);
    await capture('02-map-rotated-45');
    controller.rotate(0);
    layout.value = (size: const Size(1200, 650), dark: true, textScale: 1.0);
    await capture('03-colors-dark');
    check(
      icon('0').color == AppThemeColors.dark.primary,
      'Dark theme updates marker color',
    );
    layout.value = (size: const Size(1200, 650), dark: false, textScale: 1.0);
    await settle();
    await tapWhere(
      (widget) =>
          widget is Tooltip && widget.message == 'Chuyển sang bản đồ vệ tinh',
    );
    await capture('03-satellite');
    await tapWhere(
      (widget) =>
          widget is Tooltip && widget.message == 'Chuyển sang bản đồ đường phố',
    );
    await settle();

    // JSON crosses the socket and the production DeviceRepository/DashboardCubit.
    fixture.change('0', {
      'current_heading_deg': 270.0,
      'current_speed_mps': 10.0,
    });
    await until(
      () => icon('0').headingDegrees == 270,
      'Reported heading update',
    );
    fixture.change('0', {
      'current_heading_deg': null,
      'current_longitude':
          (fixture.devices['0']!['current_longitude'] as double) + .0002,
    });
    await until(
      () => (icon('0').headingDegrees! - 90).abs() < .01,
      'Inferred eastward heading',
    );
    await settle();
    fixture.change('0', {
      'current_heading_deg': 220.0,
      'current_speed_mps': 0.0,
    });
    await until(
      () => icon('0').color == AppThemeColors.light.warning,
      'Moving to stopped state',
    );
    check(
      (icon('0').headingDegrees! - 90).abs() < .01,
      'Stop does not spin the car',
    );
    await capture('04-realtime-stopped');
    fixture.remove('11');
    await until(() => mapMarkers().length == 11, 'WebSocket deletion');
    await tapMarker('6');
    await until(
      () => router.routeInformationProvider.value.uri.path == '/devices/6',
      'UAV detail route',
    );
    await until(
      () => widgets<Text>().any((text) => text.data == 'detail:6'),
      'Detail page rendered',
    );
    await settle();
    router.pop();
    await settle();
    controller = widgets<FlutterMap>().single.mapController!;

    layout.value = (size: const Size(320, 600), dark: false, textScale: 1.0);
    controller.move(center, 16);
    await capture('05-mobile');
    layout.value = (size: const Size(320, 600), dark: false, textScale: 3.0);
    await capture('05-mobile-large-text');
    layout.value = (size: const Size(320, 600), dark: false, textScale: 1.0);
    await settle();
    await tapWhere(
      (widget) =>
          widget is IconButton && widget.tooltip == 'Danh sách thiết bị',
    );
    await until(() => widgets<DeviceListOverlay>().isNotEmpty, 'Mobile list');
    await capture('06-mobile-list');
    await tapWhere((widget) => widget is Text && widget.data == 'Xe 0');
    await until(
      () => widgets<DeviceListOverlay>().isEmpty,
      'List selection closes sheet',
    );
    check(controller.camera.zoom == 18, 'List selection centers the device');
    layout.value = (size: const Size(1200, 650), dark: false, textScale: 1.0);

    for (final count in [500, 5000]) {
      fixture.replaceFleet(count);
      fixture.broadcast({'type': 'RESYNC_REQUIRED'});
      controller.move(center, 13);
      await until(
        () => mapMarkers().length == count,
        'REST resync to $count devices',
      );
      await settle();
      await benchmark(fixture, controller, count);
      for (final m in mapMarkers()) {
        final id = (m.key! as ValueKey<String>).value.replaceFirst(
          'map-device-',
          '',
        );
        final expected = fixture.devices[id]!;
        check(
          m.point ==
              LatLng(
                expected['current_latitude'] as double,
                expected['current_longitude'] as double,
              ),
          'Last realtime position $id',
        );
      }
      await capture('07-fleet-$count');
    }
    final connections = fixture.connections;
    for (final socket in fixture.sockets.toList()) {
      await socket.close();
    }
    await until(() => fixture.connections > connections, 'WebSocket reconnect');
    await settle();
    check(mapMarkers().length == 5000, 'Reconnect retains all 5000 devices');
    final aging = fixture.devices['0']!;
    aging['latest_measured_at'] = DateTime.now()
        .toUtc()
        .subtract(const Duration(seconds: 119))
        .toIso8601String();
    aging['last_seen_at'] = DateTime.now().toUtc().toIso8601String();
    fixture.broadcast({'type': 'DEVICE_UPDATE', 'device': aging});
    await until(
      () => icon('0').color == AppThemeColors.light.danger,
      'GPS age changes color without another packet',
    );
    aging['last_seen_at'] = DateTime.now()
        .toUtc()
        .subtract(const Duration(seconds: 299))
        .toIso8601String();
    fixture.broadcast({'type': 'DEVICE_UPDATE', 'device': aging});
    await until(
      () => icon('0').color == AppThemeColors.light.offline,
      'Presence age changes color without another packet',
    );
    results.add({
      'stage': '08-reconnect-and-status-timeouts',
      'markers': mapMarkers().length,
      'errors': errors.length,
    });
    check(errors.isEmpty, 'Runtime errors: ${errors.take(3).join('; ')}');
  } catch (error, stack) {
    errors.add('$error\n$stack');
  } finally {
    measuring = null;
    websocket.dispose();
    await fixture.close();
    final performance = <String, Object?>{};
    for (final entry in frames.entries) {
      double percentile(Iterable<int> values, double p) {
        final sorted = values.toList()..sort();
        return sorted.isEmpty
            ? 0
            : sorted[((sorted.length - 1) * p).round()] / 1000;
      }

      performance[entry.key] = {
        'frames': entry.value.length,
        'build_p95_ms': percentile(
          entry.value.map((f) => f.buildDuration.inMicroseconds),
          .95,
        ),
        'raster_p95_ms': percentile(
          entry.value.map((f) => f.rasterDuration.inMicroseconds),
          .95,
        ),
        'total_p95_ms': percentile(
          entry.value.map((f) => f.totalSpan.inMicroseconds),
          .95,
        ),
        'over_33ms_percent':
            entry.value
                .where(
                  (f) =>
                      f.buildDuration.inMicroseconds > 33333 ||
                      f.rasterDuration.inMicroseconds > 33333,
                )
                .length *
            100 /
            math.max(1, entry.value.length),
      };
    }
    File('${output.path}/result.json').writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert({
        'passed': errors.isEmpty,
        'stages': results,
        'errors': errors,
        'performance': performance,
        'rest_requests': fixture.restRequests,
        'websocket_messages': fixture.messageCount,
        'connections': fixture.connections,
        'image_cache_bytes':
            PaintingBinding.instance.imageCache.currentSizeBytes,
        'note':
            'Native Windows release; real HTTP/WebSocket clients with isolated synthetic server. Performance phases: 20s continuous camera pan and each device updates once per 5s. Screenshots and initial load excluded.',
      }),
    );
    exit(errors.isEmpty ? 0 : 1);
  }
}

Future<void> benchmark(
  FixtureServer fixture,
  MapController controller,
  int count,
) async {
  var cursor = 0;
  final updates = Timer.periodic(const Duration(milliseconds: 250), (_) {
    final messages = <Map<String, dynamic>>[];
    for (var n = 0; n < count ~/ 20; n++) {
      final id = '${cursor++ % count}';
      final device = fixture.devices[id]!;
      final angle = (int.parse(id) % 4) * math.pi / 2;
      device['current_latitude'] =
          (device['current_latitude'] as double) + .00015 * math.cos(angle);
      device['current_longitude'] =
          (device['current_longitude'] as double) + .00015 * math.sin(angle);
      device['last_seen_at'] = DateTime.now().toUtc().toIso8601String();
      device['latest_measured_at'] = device['last_seen_at'];
      messages.add({'type': 'DEVICE_UPDATE', 'device': device});
    }
    fixture.broadcast({'type': 'REALTIME_BATCH', 'messages': messages});
  });
  final ticker = Ticker((elapsed) {
    final t = elapsed.inMicroseconds / 1000000;
    controller.move(
      LatLng(
        center.latitude + .001 * math.sin(t),
        center.longitude + .001 * math.cos(t),
      ),
      13,
    );
  });
  ticker.start();
  await Future<void>.delayed(const Duration(seconds: 3));
  measuring = '$count-devices';
  await Future<void>.delayed(const Duration(seconds: 20));
  measuring = null;
  ticker.dispose();
  updates.cancel();
  await settle();
}

class FixtureServer {
  FixtureServer(this.server);
  final HttpServer server;
  final devices = <String, Map<String, dynamic>>{};
  final sockets = <WebSocket>{};
  int restRequests = 0, messageCount = 0, connections = 0;
  int get port => server.port;

  static Future<FixtureServer> start() async {
    final fixture = FixtureServer(
      await HttpServer.bind(InternetAddress.loopbackIPv4, 0),
    );
    for (var i = 0; i < 12; i++) {
      final now = DateTime.now().toUtc().subtract(const Duration(seconds: 2));
      final state = i % 6;
      fixture.devices['$i'] = {
        'id': '$i',
        'device_code': 'ICON-$i',
        'name': '${i < 6 ? 'Xe' : 'UAV'} $state',
        'device_type': i < 6 ? 'VEHICLE' : 'UAV_CONTROLLER',
        'status': state == 4 ? 'INACTIVE' : 'ACTIVE',
        'is_online': state != 3,
        'current_latitude': center.latitude + (i < 6 ? .0015 : -.0015),
        'current_longitude': center.longitude + (state - 2.5) * .0025,
        'current_speed_mps': state == 5
            ? null
            : state == 1
            ? 0.0
            : 10.0,
        'current_heading_deg': state == 5 ? null : (state * 90.0) % 360,
        'last_seen_at':
            (state == 3 ? now.subtract(const Duration(minutes: 10)) : now)
                .toIso8601String(),
        'latest_measured_at':
            (state == 2 ? now.subtract(const Duration(minutes: 3)) : now)
                .toIso8601String(),
        'battery_pct': 75,
      };
    }
    fixture.server.listen((request) async {
      if (WebSocketTransformer.isUpgradeRequest(request)) {
        final socket = await WebSocketTransformer.upgrade(request);
        fixture.sockets.add(socket);
        fixture.connections++;
        socket.listen((_) {}, onDone: () => fixture.sockets.remove(socket));
        return;
      }
      fixture.restRequests++;
      request.response.headers.contentType = ContentType.json;
      final path = request.uri.path;
      final Object body;
      if (path.endsWith('/devices/')) {
        body = fixture.devices.values.toList();
      } else if (path.endsWith('/geocoding/reverse')) {
        body = {'display_name': 'Hà Nội, Việt Nam'};
      } else {
        body = fixture.devices[path.split('/').last] ?? <String, dynamic>{};
      }
      request.response.write(jsonEncode(body));
      await request.response.close();
    });
    return fixture;
  }

  void broadcast(Map<String, dynamic> message) {
    messageCount += message['type'] == 'REALTIME_BATCH'
        ? (message['messages'] as List).length
        : 1;
    final encoded = jsonEncode(message);
    for (final socket in sockets.toList()) {
      socket.add(encoded);
    }
  }

  void change(String id, Map<String, dynamic> fields) {
    final device = devices[id]!;
    device.addAll(fields);
    device['last_seen_at'] = DateTime.now().toUtc().toIso8601String();
    device['latest_measured_at'] = device['last_seen_at'];
    broadcast({'type': 'DEVICE_UPDATE', 'device': device});
  }

  void remove(String id) {
    devices.remove(id);
    broadcast({'type': 'DEVICE_DELETED', 'device_id': id});
  }

  void replaceFleet(int count) {
    devices.clear();
    final now = DateTime.now().toUtc().toIso8601String();
    for (var i = 0; i < count; i++) {
      devices['$i'] = {
        'id': '$i',
        'device_code': 'ICON-$i',
        'name': 'Thiết bị $i',
        'device_type': i.isEven ? 'VEHICLE' : 'UAV_CONTROLLER',
        'status': 'ACTIVE',
        'is_online': true,
        'current_latitude':
            center.latitude + (i ~/ 100 - (count / 200)) * .0004,
        'current_longitude': center.longitude + (i % 100 - 50) * .0004,
        'current_speed_mps': 10.0,
        'current_heading_deg': i % 3 == 0 ? null : (i % 4) * 90.0,
        'last_seen_at': now,
        'latest_measured_at': now,
        'battery_pct': 75,
      };
    }
  }

  Future<void> close() async {
    for (final socket in sockets.toList()) {
      await socket.close();
    }
    await server.close(force: true);
  }
}
