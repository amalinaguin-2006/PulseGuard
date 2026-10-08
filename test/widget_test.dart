// test/widget_test.dart
//
// Widget and UI tests for PulseGuard.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pulse_guard/widgets/gradient_pill_button.dart';
import 'package:pulse_guard/widgets/pulse_guard_header.dart';
import 'package:pulse_guard/widgets/pulsing_heart_logo.dart';

void main() {
  testWidgets('GradientPillButton renders label and triggers tap', (WidgetTester tester) async {
    bool tapped = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: GradientPillButton(
            text: 'Test Button',
            onPressed: () => tapped = true,
          ),
        ),
      ),
    );

    expect(find.text('Test Button'), findsOneWidget);
    await tester.tap(find.text('Test Button'));
    expect(tapped, isTrue);
  });

  testWidgets('PulseGuardHeader renders brand title and user name', (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: PulseGuardHeader(userName: 'Alex Mercer'),
        ),
      ),
    );

    expect(find.text('PulseGuard'), findsOneWidget);
    expect(find.text('Alex'), findsOneWidget);
  });

  testWidgets('HeartShieldPainter paints successfully', (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: CustomPaint(
            size: Size(100, 100),
            painter: HeartShieldPainter(),
          ),
        ),
      ),
    );

    expect(find.byType(CustomPaint), findsWidgets);
  });
}
