// Xác nhận hai lớp bản đồ dùng URL HTTPS riêng và giữ đúng giới hạn thu phóng.
import 'package:flutter_test/flutter_test.dart';
import 'package:v_monitor/core/config/map_tile_providers.dart';

void main() {
  test(
    'street and satellite map types resolve to distinct HTTPS tile layers',
    () {
      expect(
        MapTileProviders.getUrl(AppMapType.standard),
        MapTileProviders.streetUrl,
      );
      expect(
        MapTileProviders.getUrl(AppMapType.satellite),
        MapTileProviders.satelliteUrl,
      );

      final street = Uri.parse(
        MapTileProviders.streetUrl
            .replaceAll('{x}', '6504')
            .replaceAll('{y}', '3606')
            .replaceAll('{z}', '13'),
      );
      final satellite = Uri.parse(
        MapTileProviders.satelliteUrl
            .replaceAll('{x}', '6504')
            .replaceAll('{y}', '3606')
            .replaceAll('{z}', '13'),
      );

      expect(street.scheme, 'https');
      expect(street.host, 'mt1.google.com');
      expect(street.queryParameters['lyrs'], 'm');
      expect(street.queryParameters['x'], '6504');
      expect(street.queryParameters['y'], '3606');
      expect(street.queryParameters['z'], '13');
      expect(satellite.path, contains('lyrs=y'));
      expect(street, isNot(satellite));
    },
  );

  test('map types keep their existing native zoom limits', () {
    expect(MapTileProviders.getMaxZoom(AppMapType.standard), 19);
    expect(MapTileProviders.getMaxZoom(AppMapType.satellite), 20);
  });
}
