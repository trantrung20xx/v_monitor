import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:v_monitor/features/journey_history/widgets/custom_gap_dialog.dart';

void main() {
  group('formatGapDuration Tests', () {
    test('formats seconds when duration < 1 minute', () {
      expect(formatGapDuration(const Duration(seconds: 30)), '30 giây');
    });

    test('formats minutes when duration < 60 minutes', () {
      expect(formatGapDuration(const Duration(minutes: 1)), '1 phút');
      expect(formatGapDuration(const Duration(minutes: 5)), '5 phút');
      expect(formatGapDuration(const Duration(minutes: 45)), '45 phút');
    });

    test('formats whole hours correctly', () {
      expect(formatGapDuration(const Duration(hours: 1)), '1 giờ');
      expect(formatGapDuration(const Duration(hours: 2)), '2 giờ');
      expect(formatGapDuration(const Duration(hours: 24)), '24 giờ');
    });

    test('formats hours and minutes combination correctly', () {
      expect(formatGapDuration(const Duration(minutes: 90)), '1 giờ 30 phút');
      expect(formatGapDuration(const Duration(minutes: 150)), '2 giờ 30 phút');
    });
  });

  group('CustomGapThresholdDialog Widget Tests', () {
    testWidgets('renders dialog with initial value, presets, and inputs', (tester) async {
      Duration? selectedDuration;

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: ElevatedButton(
                onPressed: () async {
                  selectedDuration = await showCustomGapThresholdDialog(
                    context,
                    initialDuration: const Duration(minutes: 5),
                  );
                },
                child: const Text('Open Dialog'),
              ),
            ),
          ),
        ),
      );

      // Open dialog
      await tester.tap(find.text('Open Dialog'));
      await tester.pumpAndSettle();

      expect(find.text('Tùy chọn ngưỡng ngắt quãng'), findsOneWidget);
      expect(find.text('Gợi ý nhanh:'), findsOneWidget);
      expect(find.text('10 phút'), findsOneWidget);
      expect(find.text('2 giờ'), findsOneWidget);
      expect(find.text('Áp dụng'), findsOneWidget);

      // Tap on preset chip '10 phút'
      await tester.tap(find.text('10 phút'));
      await tester.pumpAndSettle();

      expect(find.text('Áp dụng ngưỡng ngắt quãng: 10 phút'), findsOneWidget);

      // Tap 'Áp dụng'
      await tester.tap(find.text('Áp dụng'));
      await tester.pumpAndSettle();

      expect(selectedDuration, const Duration(minutes: 10));
    });

    testWidgets('allows manual numeric input and unit change', (tester) async {
      Duration? selectedDuration;

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: ElevatedButton(
                onPressed: () async {
                  selectedDuration = await showCustomGapThresholdDialog(
                    context,
                    initialDuration: const Duration(minutes: 5),
                  );
                },
                child: const Text('Open Dialog'),
              ),
            ),
          ),
        ),
      );

      // Open dialog
      await tester.tap(find.text('Open Dialog'));
      await tester.pumpAndSettle();

      // Enter value 3
      final textFieldFinder = find.byType(TextFormField);
      await tester.enterText(textFieldFinder, '3');
      await tester.pumpAndSettle();

      // Change unit to 'Giờ'
      await tester.tap(find.text('Phút'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Giờ').last);
      await tester.pumpAndSettle();

      expect(find.text('Áp dụng ngưỡng ngắt quãng: 3 giờ'), findsOneWidget);

      // Tap 'Áp dụng'
      await tester.tap(find.text('Áp dụng'));
      await tester.pumpAndSettle();

      expect(selectedDuration, const Duration(hours: 3));
    });

    testWidgets('disables apply button when input is empty or 0', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: ElevatedButton(
                onPressed: () => showCustomGapThresholdDialog(
                  context,
                  initialDuration: const Duration(minutes: 5),
                ),
                child: const Text('Open Dialog'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open Dialog'));
      await tester.pumpAndSettle();

      final textFieldFinder = find.byType(TextFormField);
      await tester.enterText(textFieldFinder, '');
      await tester.pumpAndSettle();

      final applyButton = tester.widget<FilledButton>(find.byType(FilledButton));
      expect(applyButton.onPressed, isNull);
      expect(find.text('Vui lòng nhập giá trị hợp lệ từ 1 phút đến 7 ngày (168 giờ).'), findsOneWidget);
    });
  });
}
