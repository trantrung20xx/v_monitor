import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:v_monitor/data/models/location_model.dart';
import 'package:v_monitor/domain/entities/route_segment.dart';
import 'package:v_monitor/features/journey_history/journey_history_state.dart';
import 'package:v_monitor/features/journey_history/widgets/history_map_layers.dart';

void main() {
  group('HistoryMapLayers Tests', () {
    test('extractStopAndParkPoints identifies parking points (>= 5 minutes)', () {
      final baseTime = DateTime(2026, 8, 19, 8, 0, 0);

      final samples = [
        // Xe đang chạy
        LocationModel(
          id: '1',
          deviceId: 'dev-1',
          measuredAt: baseTime,
          latitude: 21.0285,
          longitude: 105.8542,
          speedMps: 10.0,
        ),
        // Xe bắt đầu đỗ lúc 08:05:00 đến 08:15:00 (10 phút = 600s >= 300s -> Park)
        LocationModel(
          id: '2',
          deviceId: 'dev-1',
          measuredAt: baseTime.add(const Duration(minutes: 5)),
          latitude: 21.0300,
          longitude: 105.8550,
          speedMps: 0.0,
        ),
        LocationModel(
          id: '3',
          deviceId: 'dev-1',
          measuredAt: baseTime.add(const Duration(minutes: 10)),
          latitude: 21.0300,
          longitude: 105.8550,
          speedMps: 0.0,
        ),
        LocationModel(
          id: '4',
          deviceId: 'dev-1',
          measuredAt: baseTime.add(const Duration(minutes: 15)),
          latitude: 21.0300,
          longitude: 105.8550,
          speedMps: 0.0,
        ),
        // Xe tiếp tục chạy lúc 08:16:00
        LocationModel(
          id: '5',
          deviceId: 'dev-1',
          measuredAt: baseTime.add(const Duration(minutes: 16)),
          latitude: 21.0350,
          longitude: 105.8600,
          speedMps: 8.0,
        ),
      ];

      final stops = HistoryMapLayers.extractStopAndParkPoints(samples);

      expect(stops.length, 1);
      expect(stops.first.isPark, isTrue);
      expect(stops.first.durationSeconds, 600);
      expect(stops.first.compactDurationLabel, '10p');
      expect(stops.first.durationLabel, '10 phút');
    });

    test('extractStopAndParkPoints identifies short stops (< 5 minutes)', () {
      final baseTime = DateTime(2026, 8, 19, 8, 0, 0);

      final samples = [
        LocationModel(
          id: '1',
          deviceId: 'dev-1',
          measuredAt: baseTime,
          latitude: 21.0285,
          longitude: 105.8542,
          speedMps: 10.0,
        ),
        // Dừng đèn đỏ 1 phút (60s)
        LocationModel(
          id: '2',
          deviceId: 'dev-1',
          measuredAt: baseTime.add(const Duration(minutes: 2)),
          latitude: 21.0300,
          longitude: 105.8550,
          speedMps: 0.0,
        ),
        LocationModel(
          id: '3',
          deviceId: 'dev-1',
          measuredAt: baseTime.add(const Duration(minutes: 3)),
          latitude: 21.0300,
          longitude: 105.8550,
          speedMps: 0.0,
        ),
        LocationModel(
          id: '4',
          deviceId: 'dev-1',
          measuredAt: baseTime.add(const Duration(minutes: 4)),
          latitude: 21.0350,
          longitude: 105.8600,
          speedMps: 9.0,
        ),
      ];

      final stops = HistoryMapLayers.extractStopAndParkPoints(samples);

      expect(stops.length, 1);
      expect(stops.first.isPark, isFalse);
      expect(stops.first.durationSeconds, 60);
      expect(stops.first.compactDurationLabel, '1p');
    });

    test('buildPolylines scales stroke width based on zoom level', () {
      final sample1 = LocationModel(
        id: '1',
        deviceId: 'dev-1',
        measuredAt: DateTime(2026, 8, 19, 8, 0),
        latitude: 21.0285,
        longitude: 105.8542,
        speedMps: 10.0,
      );
      final sample2 = LocationModel(
        id: '2',
        deviceId: 'dev-1',
        measuredAt: DateTime(2026, 8, 19, 8, 5),
        latitude: 21.0300,
        longitude: 105.8550,
        speedMps: 10.0,
      );

      final seg = RouteSegment(
        samples: [sample1, sample2],
        distanceM: 1000.0,
        movingDurationS: 300,
        stoppedDurationS: 0,
      );

      final polylinesZoom10 = HistoryMapLayers.buildPolylines(
        segments: [seg],
        primaryColor: Colors.blue,
        currentZoom: 10.0,
      );

      final polylinesZoom18 = HistoryMapLayers.buildPolylines(
        segments: [seg],
        primaryColor: Colors.blue,
        currentZoom: 18.0,
      );

      expect(polylinesZoom10.length, 2);
      expect(polylinesZoom18.length, 2);
      expect(
        polylinesZoom18.last.strokeWidth,
        greaterThan(polylinesZoom10.last.strokeWidth),
      );
    });

    test('buildGapPolylines marks unknown travel between route segments', () {
      final baseTime = DateTime(2026, 8, 19, 8);
      LocationModel sample(String id, int minute, double latitude) {
        return LocationModel(
          id: id,
          deviceId: 'dev-1',
          measuredAt: baseTime.add(Duration(minutes: minute)),
          latitude: latitude,
          longitude: 105.8542,
          speedMps: 5,
        );
      }

      final segments = [
        RouteSegment(
          samples: [sample('1', 0, 21.00), sample('2', 1, 21.01)],
          distanceM: 1000,
          movingDurationS: 60,
          stoppedDurationS: 0,
        ),
        RouteSegment(
          samples: [sample('3', 20, 21.02), sample('4', 21, 21.03)],
          distanceM: 1000,
          movingDurationS: 60,
          stoppedDurationS: 0,
        ),
      ];

      final gaps = HistoryMapLayers.buildGapPolylines(segments: segments);

      expect(gaps, hasLength(1));
      expect(gaps.single.points.first.latitude, 21.01);
      expect(gaps.single.points.last.latitude, 21.02);
    });

    test('direction arrows use distance-based density and stay bounded', () {
      final baseTime = DateTime(2026, 8, 19, 8);
      final samples = List.generate(101, (index) {
        return LocationModel(
          id: '$index',
          deviceId: 'dev-1',
          measuredAt: baseTime.add(Duration(seconds: index * 5)),
          latitude: 21.0 + index * 0.0001,
          longitude: 105.8542,
          speedMps: 5,
        );
      });
      final segment = RouteSegment(
        samples: samples,
        distanceM: 1110,
        movingDurationS: 500,
        stoppedDurationS: 0,
      );

      final arrows = HistoryMapLayers.buildDirectionArrows(
        segments: [segment],
        currentZoom: 13,
        arrowColor: Colors.white,
      );

      expect(arrows, isNotEmpty);
      expect(arrows.length, lessThan(20));
      expect(
        HistoryMapLayers.buildDirectionArrows(
          segments: [segment],
          currentZoom: 10,
          arrowColor: Colors.white,
        ),
        isEmpty,
      );
    });

    test('two stopped samples across a long GPS gap are not parking', () {
      final baseTime = DateTime(2026, 8, 19, 8);
      final samples = [
        LocationModel(
          id: '1',
          deviceId: 'dev-1',
          measuredAt: baseTime,
          latitude: 21.0,
          longitude: 105.8542,
          speedMps: 0,
        ),
        LocationModel(
          id: '2',
          deviceId: 'dev-1',
          measuredAt: baseTime.add(const Duration(minutes: 20)),
          latitude: 21.0,
          longitude: 105.8542,
          speedMps: 0,
        ),
      ];

      expect(HistoryMapLayers.extractStopAndParkPoints(samples), isEmpty);
    });

    test('route nodes stay visible even when GPS speed is missing', () {
      final baseTime = DateTime(2026, 8, 19, 8);
      final samples = List.generate(21, (index) {
        return LocationModel(
          id: '$index',
          deviceId: 'dev-1',
          measuredAt: baseTime.add(Duration(minutes: index)),
          latitude: 21.0 + index * 0.0005,
          longitude: 105.8542,
        );
      });

      final nodes = HistoryMapLayers.extractRouteNodes(samples);

      expect(nodes.first.type, JourneyRouteNodeType.start);
      expect(nodes.last.type, JourneyRouteNodeType.end);
      expect(
        nodes.where((node) => node.type == JourneyRouteNodeType.place),
        isNotEmpty,
      );

      final markers = HistoryMapLayers.buildSamplePoints(
        validSamples: samples,
        onPointSelected: (_) {},
      );
      expect(markers.length, nodes.length);
      expect(
        markers.every((marker) => marker.alignment == Alignment.center),
        isTrue,
      );
    });

    test('route nodes are not cut off by an arbitrary display limit', () {
      final baseTime = DateTime(2026, 8, 19, 8);
      final samples = List.generate(101, (index) {
        return LocationModel(
          id: '$index',
          deviceId: 'dev-1',
          measuredAt: baseTime.add(Duration(minutes: index * 2)),
          latitude: 21 + index * 0.0018,
          longitude: 105,
        );
      });

      final placeNodes = HistoryMapLayers.extractRouteNodes(
        samples,
      ).where((node) => node.type == JourneyRouteNodeType.place);

      expect(placeNodes.length, greaterThan(8));
    });

    testWidgets('every route node renders its complete location label', (
      tester,
    ) async {
      final baseTime = DateTime(2026, 8, 19, 8);
      final samples = List.generate(25, (index) {
        return LocationModel(
          id: '$index',
          deviceId: 'dev-1',
          measuredAt: baseTime.add(Duration(minutes: index * 2)),
          latitude: 21.0 + index * 0.0006,
          longitude: 105.8542 + index * 0.0002,
        );
      });
      final nodes = HistoryMapLayers.extractRouteNodes(samples);
      final addresses = <String, String>{};
      for (var i = 0; i < nodes.length; i++) {
        addresses[HistoryMapLayers.routeNodeKey(nodes[i].sample)] =
            'Địa điểm ${i + 1}, Phường Thanh Xuân Trung, Hà Nội';
      }

      final markers = HistoryMapLayers.buildSamplePoints(
        validSamples: samples,
        nodeAddresses: addresses,
        onPointSelected: (_) {},
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: Column(
                children: markers.map((marker) => marker.child).toList(),
              ),
            ),
          ),
        ),
      );

      expect(markers.length, nodes.length);
      for (final address in addresses.values) {
        final label = find.text(address);
        expect(label, findsOneWidget);
        final text = tester.widget<Text>(label);
        expect(text.maxLines, isNull);
        expect(text.overflow, isNull);
      }
      expect(find.textContaining('MỐC '), findsNothing);
      expect(find.textContaining('19/08/2026 · '), findsWidgets);
    });

    testWidgets('route label toggle keeps nodes and hides only bubbles', (
      tester,
    ) async {
      final samples = [
        LocationModel(
          id: 'start',
          deviceId: 'dev-1',
          measuredAt: DateTime(2026, 8, 19, 8),
          latitude: 21,
          longitude: 105,
        ),
        LocationModel(
          id: 'end',
          deviceId: 'dev-1',
          measuredAt: DateTime(2026, 8, 19, 9),
          latitude: 21.01,
          longitude: 105.01,
        ),
      ];
      final hiddenMarkers = HistoryMapLayers.buildSamplePoints(
        validSamples: samples,
        showLabels: false,
        nodeAddresses: {
          HistoryMapLayers.routeNodeKey(samples.first): 'Điểm xuất phát',
          HistoryMapLayers.routeNodeKey(samples.last): 'Điểm kết thúc',
        },
        onPointSelected: (_) {},
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Row(
              children: hiddenMarkers.map((marker) => marker.child).toList(),
            ),
          ),
        ),
      );

      expect(hiddenMarkers, hasLength(2));
      expect(hiddenMarkers.every((marker) => marker.width == 24), isTrue);
      expect(hiddenMarkers.every((marker) => marker.height == 24), isTrue);
      expect(
        hiddenMarkers.every((marker) => marker.alignment == Alignment.center),
        isTrue,
      );
      expect(find.text('Điểm xuất phát'), findsNothing);
      expect(find.text('Điểm kết thúc'), findsNothing);
    });

    test('buildSamplePoints generates Start and End pins and Park markers', () {
      final baseTime = DateTime(2026, 8, 19, 8, 0, 0);

      final samples = [
        LocationModel(
          id: '1',
          deviceId: 'dev-1',
          measuredAt: baseTime,
          latitude: 21.0285,
          longitude: 105.8542,
          speedMps: 5.0,
        ),
        // Đỗ 15 phút tại điểm giữa
        LocationModel(
          id: '2',
          deviceId: 'dev-1',
          measuredAt: baseTime.add(const Duration(minutes: 5)),
          latitude: 21.0500,
          longitude: 105.8700,
          speedMps: 0.0,
        ),
        LocationModel(
          id: '3',
          deviceId: 'dev-1',
          measuredAt: baseTime.add(const Duration(minutes: 10)),
          latitude: 21.0500,
          longitude: 105.8700,
          speedMps: 0.0,
        ),
        LocationModel(
          id: '4',
          deviceId: 'dev-1',
          measuredAt: baseTime.add(const Duration(minutes: 15)),
          latitude: 21.0500,
          longitude: 105.8700,
          speedMps: 0.0,
        ),
        LocationModel(
          id: '5',
          deviceId: 'dev-1',
          measuredAt: baseTime.add(const Duration(minutes: 20)),
          latitude: 21.0500,
          longitude: 105.8700,
          speedMps: 0.0,
        ),
        // Điểm kết thúc
        LocationModel(
          id: '6',
          deviceId: 'dev-1',
          measuredAt: baseTime.add(const Duration(minutes: 35)),
          latitude: 21.0800,
          longitude: 105.9000,
          speedMps: 0.0,
        ),
      ];

      final markers = HistoryMapLayers.buildSamplePoints(
        validSamples: samples,
        onPointSelected: (_) {},
      );

      // Ít nhất có Start Pin, End Pin, và Park Pin [P]
      expect(markers.length, greaterThanOrEqualTo(3));
    });

    testWidgets('replay marker is compact and only labels current speed', (
      tester,
    ) async {
      final marker = HistoryMapLayers.buildReplayMarker(
        state: JourneyHistoryState(
          status: JourneyHistoryStatus.playing,
          currentPosition: const LatLng(21.0285, 105.8542),
          currentReplayTime: DateTime(2026, 8, 19, 9, 15),
          currentSpeedMps: 10,
        ),
        theme: ThemeData.light(),
      );

      expect(marker, isNotNull);
      expect(marker!.width, 86);
      expect(marker.height, 52);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: Center(child: marker.child)),
        ),
      );

      expect(find.text('36 km/h'), findsOneWidget);
      expect(find.textContaining('19/08/2026'), findsNothing);
      expect(find.textContaining('09:15'), findsNothing);
    });
  });
}
