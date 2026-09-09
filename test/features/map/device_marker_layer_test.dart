import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:v_monitor/app/app_theme.dart';
import 'package:v_monitor/core/widgets/device_icon.dart';
import 'package:v_monitor/data/models/device_model.dart';
import 'package:v_monitor/features/map/widgets/device_marker_layer.dart';

void main() {
  testWidgets(
    '5000 colocated vehicles and controllers keep separate markers at every zoom',
    (tester) async {
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
        (id) => DeviceModel(
          id: '$id',
          deviceCode: 'GPS-$id',
          name: 'Thiết bị $id',
          type: id.isEven ? 'VEHICLE' : 'UAV_CONTROLLER',
          status: 'ACTIVE',
          latitude: 10,
          longitude: 106,
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(3)),
            child: FlutterMap(
              mapController: controller,
              options: const MapOptions(
                initialCenter: LatLng(10, 106),
                initialZoom: 5,
              ),
              children: [
                DeviceMarkerLayer(
                  devices: devices,
                  markerBuilder: (_, device) => Marker(
                    point: LatLng(device.latitude!, device.longitude!),
                    key: ValueKey(device.id),
                    child: GestureDetector(
                      onTap: () => selected = device.id,
                      child: Icon(DeviceIcon.iconFor(device.deviceType)),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pump();
      for (final zoom in [5.0, 13.0, 18.0]) {
        controller.move(const LatLng(10, 106), zoom);
        await tester.pump();
        final markers = tester
            .widget<MarkerLayer>(find.byType(MarkerLayer))
            .markers;
        expect(markers.length, 5000);
        expect(markers.map((marker) => marker.key).toSet().length, 5000);
        expect(
          markers.every((marker) => marker.point == const LatLng(10, 106)),
          isTrue,
        );
        expect(find.text('5000'), findsNothing);
        expect(find.byIcon(Icons.directions_car_rounded), findsNWidgets(2500));
        expect(find.byIcon(Icons.gamepad_rounded), findsNWidgets(2500));
      }
      await tester.tap(find.byKey(const ValueKey('4999')));
      await tester.pump();
      expect(selected, '4999');
      expect(tester.takeException(), isNull);
      controller.move(const LatLng(0, 0), 18);
      await tester.pump();
      expect(
        tester.widget<MarkerLayer>(find.byType(MarkerLayer)).markers,
        isEmpty,
      );
      controller.move(const LatLng(10, 106), 13);
      await tester.pump();
      expect(
        tester.widget<MarkerLayer>(find.byType(MarkerLayer)).markers.length,
        5000,
      );
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'nearby markers, viewport changes and missing GPS stay independent',
    (tester) async {
      final controller = MapController();
      addTearDown(controller.dispose);
      final devices = [
        _device('vehicle', 10, 106),
        _device('controller', 10.00001, 106.00001, type: 'UAV_CONTROLLER'),
        _device('far', 0, 0),
        _device('no-latitude', null, 106),
        _device('no-longitude', 10, null),
      ];
      await _pumpLayer(tester, controller, devices);
      expect(_markerIds(tester), ['vehicle', 'controller']);
      controller.rotate(45);
      await tester.pump();
      expect(_markerIds(tester), ['vehicle', 'controller']);
      controller.move(const LatLng(0, 0), 18);
      await tester.pump();
      expect(_markerIds(tester), ['far']);
      controller.move(const LatLng(10, 106), 13);
      await tester.pump();
      expect(_markerIds(tester), ['vehicle', 'controller']);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('updated and deleted devices replace only their own markers', (
    tester,
  ) async {
    final controller = MapController();
    addTearDown(controller.dispose);
    await _pumpLayer(tester, controller, [
      _device('a', 10, 106),
      _device('b', 10, 106),
    ]);
    expect(_markerIds(tester), ['a', 'b']);
    await _pumpLayer(tester, controller, [_device('a', 10.001, 106.001)]);
    final markers = tester
        .widget<MarkerLayer>(find.byType(MarkerLayer))
        .markers;
    expect(_markerIds(tester), ['a']);
    expect(markers.single.point, const LatLng(10.001, 106.001));
    expect(find.byKey(const ValueKey('b')), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
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

List<String> _markerIds(WidgetTester tester) => tester
    .widget<MarkerLayer>(find.byType(MarkerLayer))
    .markers
    .map((marker) => (marker.key! as ValueKey<String>).value)
    .toList();

Future<void> _pumpLayer(
  WidgetTester tester,
  MapController controller,
  List<DeviceModel> devices,
) async {
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
            markerBuilder: (_, device) => Marker(
              key: ValueKey(device.id),
              point: LatLng(device.latitude!, device.longitude!),
              child: Icon(DeviceIcon.iconFor(device.deviceType)),
            ),
          ),
        ],
      ),
    ),
  );
  await tester.pump();
}
