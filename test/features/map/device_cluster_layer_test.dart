import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:v_monitor/app/app_theme.dart';
import 'package:v_monitor/data/models/device_model.dart';
import 'package:v_monitor/features/map/widgets/device_cluster_layer.dart';

void main() {
  testWidgets(
    '5000 colocated devices use one marker and remain selectable at max zoom',
    (tester) async {
      tester.view.physicalSize = const Size(320, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      final controller = MapController();
      addTearDown(controller.dispose);
      var selected = 0;
      final devices = List.generate(
        5000,
        (id) => DeviceModel(
          id: '$id',
          deviceCode: 'GPS-$id',
          name: 'Thiết bị $id',
          type: 'VEHICLE',
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
                initialZoom: 18,
              ),
              children: [
                DeviceClusterLayer(
                  devices: devices,
                  markerBuilder: (_, device) => Marker(
                    point: LatLng(device.latitude!, device.longitude!),
                    child: const Icon(Icons.place),
                  ),
                  onClusterTap: (group) => selected = group.length,
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pump();
      expect(
        tester.widget<MarkerLayer>(find.byType(MarkerLayer)).markers.length,
        1,
      );
      await tester.tap(find.text('5000'));
      await tester.pump();
      expect(selected, 5000);
      expect(tester.takeException(), isNull);
      controller.move(const LatLng(0, 0), 18);
      await tester.pump();
      expect(
        tester.widget<MarkerLayer>(find.byType(MarkerLayer)).markers,
        isEmpty,
      );
    },
  );
}
