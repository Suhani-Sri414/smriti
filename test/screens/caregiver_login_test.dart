import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smriti/core/auth/pairing_service.dart';
import 'package:smriti/core/db/database.dart';
import 'package:smriti/core/repo/ability_repo.dart';
import 'package:smriti/screens/login_screen.dart';
import 'package:smriti/screens/pairing/code_entry_screen.dart';
import 'package:smriti/screens/pairing/scan_screen.dart';

import '../core/auth/pairing_service_test.dart'
    show FakePairingGateway, successBody;
import '../core/repo/_test_db.dart';

void main() {
  late SmritiDatabase db;

  setUp(() => db = newTestDb());
  tearDown(() async => db.close());

  Widget buildLoginScreen({
    required PairingService service,
    VoidCallback? onPaired,
  }) {
    return MaterialApp(
      home: LoginScreen(
        pairingService: service,
        onPaired: onPaired,
      ),
    );
  }

  testWidgets('renders device pairing options without email or password fields',
      (tester) async {
    final gateway = FakePairingGateway(
      response: PairingResponse(status: 200, data: successBody()),
    );
    final service = PairingService(
      configs: db.appConfigsDao,
      abilityRepo: AbilityRepo(db),
      gateway: gateway,
    );

    await tester.pumpWidget(buildLoginScreen(service: service));
    await tester.pumpAndSettle();

    expect(find.byType(LoginScreen), findsOneWidget);
    expect(find.text('Device Pairing'), findsOneWidget);
    expect(find.text('Memories for a brighter tomorrow'), findsOneWidget);
    expect(find.byKey(const Key('scan_qr_button')), findsOneWidget);
    expect(find.byKey(const Key('enter_code_button')), findsOneWidget);
    expect(find.text('Scan QR Code'), findsOneWidget);
    expect(find.text('Enter Pairing Code'), findsOneWidget);

    // Verify email and password options are absent
    expect(find.byType(TextField), findsNothing);
    expect(find.byKey(const Key('sign_in_button')), findsNothing);
    expect(find.text('Sign In'), findsNothing);
    expect(find.text('Email address'), findsNothing);
    expect(find.text('Password'), findsNothing);
  });

  testWidgets('tapping scan QR opens ScanScreen and triggers onPaired on success',
      (tester) async {
    var onPairedCalled = false;
    final gateway = FakePairingGateway(
      response: PairingResponse(status: 200, data: successBody()),
    );
    final service = PairingService(
      configs: db.appConfigsDao,
      abilityRepo: AbilityRepo(db),
      gateway: gateway,
    );

    await tester.pumpWidget(
      buildLoginScreen(
        service: service,
        onPaired: () => onPairedCalled = true,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('scan_qr_button')));
    await tester.pumpAndSettle();

    expect(find.byType(ScanScreen), findsOneWidget);

    // Pop with true to simulate successful scan pairing
    Navigator.of(tester.element(find.byType(ScanScreen))).pop(true);
    await tester.pumpAndSettle();

    expect(find.byType(LoginScreen), findsOneWidget);
    expect(onPairedCalled, isTrue);
  });

  testWidgets(
      'tapping enter pairing code opens CodeEntryScreen and triggers onPaired on success',
      (tester) async {
    var onPairedCalled = false;
    final gateway = FakePairingGateway(
      response: PairingResponse(status: 200, data: successBody()),
    );
    final service = PairingService(
      configs: db.appConfigsDao,
      abilityRepo: AbilityRepo(db),
      gateway: gateway,
    );

    await tester.pumpWidget(
      buildLoginScreen(
        service: service,
        onPaired: () => onPairedCalled = true,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('enter_code_button')));
    await tester.pumpAndSettle();

    expect(find.byType(CodeEntryScreen), findsOneWidget);

    // Pop with true to simulate successful code pairing
    Navigator.of(tester.element(find.byType(CodeEntryScreen))).pop(true);
    await tester.pumpAndSettle();

    expect(find.byType(LoginScreen), findsOneWidget);
    expect(onPairedCalled, isTrue);
  });

  testWidgets('backing out without pairing does not trigger onPaired',
      (tester) async {
    var onPairedCalled = false;
    final gateway = FakePairingGateway(
      response: PairingResponse(status: 200, data: successBody()),
    );
    final service = PairingService(
      configs: db.appConfigsDao,
      abilityRepo: AbilityRepo(db),
      gateway: gateway,
    );

    await tester.pumpWidget(
      buildLoginScreen(
        service: service,
        onPaired: () => onPairedCalled = true,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('enter_code_button')));
    await tester.pumpAndSettle();

    expect(find.byType(CodeEntryScreen), findsOneWidget);

    // Back out without completing pairing
    await tester.tap(find.byIcon(Icons.arrow_back));
    await tester.pumpAndSettle();

    expect(find.byType(LoginScreen), findsOneWidget);
    expect(onPairedCalled, isFalse);
  });
}
