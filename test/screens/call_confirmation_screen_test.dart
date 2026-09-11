import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smriti/core/app_services.dart';
import 'package:smriti/core/db/database.dart';
import 'package:smriti/screens/call_confirmation_screen.dart';

import '../core/repo/_test_db.dart';

void main() {
  late SmritiDatabase db;

  setUp(() {
    db = newTestDb();
  });

  tearDown(() async {
    await db.close();
  });

  Widget createSubject({
    required AppServices services,
    String? contactName,
    String? contactPhone,
    Future<void> Function(String phone)? onPlaceCall,
  }) {
    return MaterialApp(
      home: CallConfirmationScreen(
        services: services,
        contactName: contactName,
        contactPhone: contactPhone,
        onPlaceCall: onPlaceCall,
      ),
    );
  }

  testWidgets('renders header, green card, contact name and buttons',
      (tester) async {
    final services = AppServices(database: db);
    await tester.pumpWidget(
      createSubject(services: services, contactName: 'Bina'),
    );
    await tester.pumpAndSettle();

    expect(find.text('13'), findsOneWidget);
    expect(find.text('Call confirmation'), findsOneWidget);
    expect(find.text('Bina'), findsOneWidget);
    expect(find.text('Call Bina'), findsOneWidget);
    expect(find.text('Not now'), findsOneWidget);
    expect(find.byKey(const Key('confirm_call_button')), findsOneWidget);
    expect(find.byKey(const Key('cancel_call_button')), findsOneWidget);
  });

  testWidgets('tapping Not now pops the screen', (tester) async {
    final services = AppServices(database: db);
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => CallConfirmationScreen(
                  services: services,
                  contactName: 'Bina',
                ),
              ),
            ),
            child: const Text('Open Call'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open Call'));
    await tester.pumpAndSettle();

    expect(find.byType(CallConfirmationScreen), findsOneWidget);

    await tester.tap(find.byKey(const Key('cancel_call_button')));
    await tester.pumpAndSettle();

    expect(find.byType(CallConfirmationScreen), findsNothing);
    expect(find.text('Open Call'), findsOneWidget);
  });

  testWidgets('tapping Call Bina invokes onPlaceCall and pops', (tester) async {
    String? calledNumber;
    final services = AppServices(database: db);
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => CallConfirmationScreen(
                  services: services,
                  contactName: 'Bina',
                  contactPhone: '+919876543210',
                  onPlaceCall: (phone) async {
                    calledNumber = phone;
                  },
                ),
              ),
            ),
            child: const Text('Open Call'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open Call'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('confirm_call_button')));
    await tester.pumpAndSettle();

    expect(calledNumber, '+919876543210');
    expect(find.byType(CallConfirmationScreen), findsNothing);
    expect(find.text('Open Call'), findsOneWidget);
  });

  testWidgets('resolves contact name and phone from AppConfigsDao',
      (tester) async {
    await db.appConfigsDao.setValue('primaryContactName', 'Chaoba');
    await db.appConfigsDao.setValue('primaryContactPhone', '+919811122233');

    String? dialed;
    final services = AppServices(database: db);
    await tester.pumpWidget(
      createSubject(
        services: services,
        onPlaceCall: (p) async {
          dialed = p;
        },
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Chaoba'), findsOneWidget);
    expect(find.text('Call Chaoba'), findsOneWidget);

    await tester.tap(find.byKey(const Key('confirm_call_button')));
    await tester.pumpAndSettle();

    expect(dialed, '+919811122233');
  });
}
