import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:v_monitor/core/widgets/device_icon.dart';
import 'package:v_monitor/data/models/device_model.dart';
import 'package:v_monitor/features/map/widgets/device_map_icon.dart';

void main() {
  for (final (type, asset) in [
    ('VEHICLE', DeviceMapIcon.carAsset),
    ('UAV_CONTROLLER', DeviceMapIcon.uavAsset),
    (' vehicle ', DeviceMapIcon.carAsset),
    (' uav_controller ', DeviceMapIcon.uavAsset),
  ]) {
    testWidgets('$type uses the same shaded PNG as the map', (tester) async {
      final device = DeviceModel.fromJson({
        'id': 'vehicle',
        'device_code': 'vehicle',
        'device_type': type,
      });
      await tester.pumpWidget(
        MaterialApp(
          home: Center(
            child: DeviceIcon(
              deviceType: device.deviceType,
              color: Colors.blue,
              size: 32,
            ),
          ),
        ),
      );
      final artwork = tester.widget<Image>(find.byType(Image));
      final provider = artwork.image as ResizeImage;
      expect((provider.imageProvider as AssetImage).assetName, asset);
      expect(artwork.colorBlendMode, BlendMode.modulate);
      expect(find.byType(Icon), findsNothing);
      expect(tester.getSize(find.byType(DeviceIcon)), const Size(32, 32));
    });
  }

  testWidgets(
    'OTHER remains unclassified until the device record is corrected',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: DeviceIcon(deviceType: 'OTHER')),
      );
      expect(find.byType(Image), findsNothing);
      expect(find.byIcon(Icons.devices_other_rounded), findsOneWidget);
    },
  );
}
