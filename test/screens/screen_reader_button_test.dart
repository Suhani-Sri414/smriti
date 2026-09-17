import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smriti/core/voice/screen_reader_service.dart';
import 'package:smriti/screens/screen_reader_button.dart';

import '../core/voice/screen_reader_service_test.dart';

void main() {
  late FakeTtsAdapter fakeTts;
  late ScreenReaderService service;

  setUp(() {
    fakeTts = FakeTtsAdapter();
    service = ScreenReaderService(
      ttsAdapter: fakeTts,
    );
  });

  tearDown(() {
    service.dispose();
  });

  Widget buildButton({
    String text = 'Test reading text',
    bool compact = false,
    bool showLabel = true,
  }) {
    return MaterialApp(
      home: Scaffold(
        body: Center(
          child: ScreenReaderButton(
            text: text,
            service: service,
            compact: compact,
            showLabel: showLabel,
          ),
        ),
      ),
    );
  }

  group('ScreenReaderButton', () {
    testWidgets('renders speaker icon and default label', (tester) async {
      await tester.pumpWidget(buildButton());

      expect(find.byIcon(Icons.volume_up_outlined), findsOneWidget);
      expect(find.text('Read aloud'), findsOneWidget);
    });

    testWidgets('tapping toggles speak on and stop off', (tester) async {
      await tester.pumpWidget(buildButton(text: 'Welcome to Smriti.'));

      // 1. Initial idle state
      expect(service.isSpeaking, isFalse);
      expect(find.text('Read aloud'), findsOneWidget);

      // 2. Tap to start speaking
      await tester.tap(find.byType(ScreenReaderButton));
      await tester.pump();

      expect(service.isSpeaking, isTrue);
      expect(fakeTts.speakCalls, ['Welcome to Smriti.']);
      expect(find.text('Stop reading'), findsOneWidget);
      expect(find.byIcon(Icons.volume_up_rounded), findsOneWidget);

      // 3. Tap to stop speaking
      await tester.tap(find.byType(ScreenReaderButton));
      await tester.pump();

      expect(service.isSpeaking, isFalse);
      expect(fakeTts.stopCalls, 1);
      expect(find.text('Read aloud'), findsOneWidget);
    });

    testWidgets('respects showLabel false', (tester) async {
      await tester.pumpWidget(buildButton(showLabel: false));

      expect(find.byIcon(Icons.volume_up_outlined), findsOneWidget);
      expect(find.text('Read aloud'), findsNothing);
    });

    testWidgets('animates gently while speaking', (tester) async {
      await tester.pumpWidget(buildButton());

      await tester.tap(find.byType(ScreenReaderButton));
      await tester.pump();

      // Pump mid-animation frame
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byType(Transform), findsWidgets);

      // Stop speech and ensure animation resets
      await tester.tap(find.byType(ScreenReaderButton));
      await tester.pumpAndSettle();
      expect(find.text('Read aloud'), findsOneWidget);
    });
  });
}
