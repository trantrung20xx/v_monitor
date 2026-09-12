import 'dart:ui' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:v_monitor/app/app_theme.dart';
import 'package:v_monitor/data/models/device_model.dart';
import 'package:v_monitor/features/map/widgets/device_icon_canvas.dart';
import 'package:v_monitor/features/map/widgets/device_marker_layer.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async => await DeviceIconAtlas.image);

  testWidgets('5000 colocated devices retain individual icons at every zoom', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final controller = MapController();
    addTearDown(controller.dispose);
    String? selected;
    final devices = List.generate(
      5000,
      (id) => _device(
        '$id',
        10,
        106,
        type: id.isEven ? 'VEHICLE' : 'UAV_CONTROLLER',
      ),
    );
    await _pumpLayer(tester, controller, devices, onTap: (id) => selected = id);
    for (final zoom in [5.0, 13.0, 18.0]) {
      controller.move(const LatLng(10, 106), zoom);
      await tester.pump();
      final markers = _markers(tester);
      expect(markers.length, 5000);
      expect(markers.map((m) => m.marker.key).toSet().length, 5000);
      expect(
        markers.every((m) => m.marker.point == const LatLng(10, 106)),
        isTrue,
      );
      expect(
        markers.where((m) => m.marker.deviceType == 'VEHICLE'),
        hasLength(2500),
      );
      expect(
        markers.where((m) => m.marker.deviceType == 'UAV_CONTROLLER'),
        hasLength(2500),
      );
      expect(find.text('5000'), findsNothing);
    }
    final box = tester.renderObject<RenderBox>(find.byType(DeviceIconCanvas));
    await tester.tapAt(box.localToGlobal(_markers(tester).last.position));
    await tester.pump();
    expect(selected, '4999');
    controller.move(const LatLng(0, 0), 18);
    await tester.pump();
    expect(_markers(tester), isEmpty);
    controller.move(const LatLng(10, 106), 13);
    await tester.pump();
    expect(_markers(tester).length, 5000);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'viewport, map rotation, hover and taps preserve device identity',
    (tester) async {
      final controller = MapController();
      addTearDown(controller.dispose);
      String? selected;
      final devices = [
        _device('vehicle', 10, 106),
        _device('controller', 10.002, 106.002, type: 'UAV_CONTROLLER'),
        _device('far', 0, 0),
        _device('no-latitude', null, 106),
        _device('no-longitude', 10, null),
      ];
      await _pumpLayer(
        tester,
        controller,
        devices,
        onTap: (id) => selected = id,
      );
      expect(_ids(tester), ['vehicle', 'controller']);
      controller.rotate(45);
      await tester.pump();
      final box = tester.renderObject<RenderBox>(find.byType(DeviceIconCanvas));
      final position = box.localToGlobal(_markers(tester).last.position);
      await tester.tapAt(position);
      expect(selected, 'controller');
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      await mouse.moveTo(position);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('controller'), findsOneWidget);
      await mouse.removePointer();
      final beforeDrag = controller.camera.center;
      await tester.drag(find.byType(DeviceIconCanvas), const Offset(80, 20));
      await tester.pump();
      expect(controller.camera.center, isNot(beforeDrag));
      controller.move(const LatLng(0, 0), 18);
      await tester.pump();
      expect(_ids(tester), ['far']);
      controller.move(const LatLng(10, 106), 13);
      await tester.pump();
      expect(_ids(tester), ['vehicle', 'controller']);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'updated and deleted devices replace their own visual and semantics',
    (tester) async {
      final semantics = tester.ensureSemantics();
      try {
        final controller = MapController();
        addTearDown(controller.dispose);
        await _pumpLayer(tester, controller, [
          _device('a', 10, 106),
          _device('b', 10.002, 106.002),
        ]);
        expect(_ids(tester), ['a', 'b']);
        expect(_semanticLabels(tester), containsAll(['a', 'b']));
        await _pumpLayer(tester, controller, [_device('a', 10.001, 106.001)]);
        expect(_ids(tester), ['a']);
        expect(
          _markers(tester).single.marker.point,
          const LatLng(10.001, 106.001),
        );
        expect(_semanticLabels(tester), isNot(contains('b')));
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      } finally {
        semantics.dispose();
      }
    },
  );
}

List<String> _semanticLabels(WidgetTester tester) {
  final labels = <String>[];
  void visit(SemanticsNode node) {
    labels.add(node.getSemanticsData().label);
    node.visitChildren((child) {
      visit(child);
      return true;
    });
  }

  visit(
    tester.binding.renderViews.single.owner!.semanticsOwner!.rootSemanticsNode!,
  );
  return labels;
}

DeviceModel _device(
  String id,
  double? latitude,
  double? longitude, {
  String type = 'VEHICLE',
}) => DeviceModel(
  id: id,
  deviceCode: id,
  name: id,
  type: type,
  status: 'ACTIVE',
  latitude: latitude,
  longitude: longitude,
);

List<ProjectedDeviceMarker> _markers(WidgetTester tester) =>
    tester.widget<DeviceIconCanvas>(find.byType(DeviceIconCanvas)).markers;

List<String> _ids(WidgetTester tester) => _markers(tester)
    .map(
      (m) => (m.marker.key! as ValueKey<String>).value.replaceFirst(
        'map-device-',
        '',
      ),
    )
    .toList();

Future<void> _pumpLayer(
  WidgetTester tester,
  MapController controller,
  List<DeviceModel> devices, {
  void Function(String)? onTap,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light,
      home: FlutterMap(
        mapController: controller,
        options: const MapOptions(
          initialCenter: LatLng(10, 106),
          initialZoom: 13,
        ),
        children: [
          DeviceMarkerLayer(
            devices: devices,
            markerBuilder: (_, device) => DeviceMapMarker(
              id: device.id,
              point: LatLng(device.latitude!, device.longitude!),
              deviceType: device.deviceType,
              color: Colors.blue,
              headingDegrees: 90,
              description: device.name,
              onTap: () => onTap?.call(device.id),
            ),
          ),
        ],
      ),
    ),
  );
  await tester.pump();
}
