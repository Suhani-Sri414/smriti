// Smoke test for the app shell: an unpaired tablet must open on the login
// screen. MyApp is pumped directly rather than calling main(), so this test
// does not require a live Supabase.initialize().

import 'package:flutter_test/flutter_test.dart';

import 'package:smriti/core/app_services.dart';
import 'package:smriti/main.dart';
import 'package:smriti/screens/login_screen.dart';

import 'core/repo/_test_db.dart';

void main() {
  testWidgets('an unpaired tablet opens on the login screen with pairing options', (tester) async {
    final db = newTestDb();
    addTearDown(db.close);

    await tester.pumpWidget(MyApp(services: AppServices(database: db)));
    await tester.pumpAndSettle();

    expect(find.byType(LoginScreen), findsOneWidget);
    expect(find.text('Scan QR Code'), findsOneWidget);
    expect(find.text('Enter Pairing Code'), findsOneWidget);
    expect(find.text('Sign In'), findsNothing);
  });
}
