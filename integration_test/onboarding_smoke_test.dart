import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:little_log/controller.dart';
import 'package:little_log/main.dart';
import 'package:little_log/services/google_auth.dart';
import 'package:little_log/services/google_drive.dart';
import 'package:little_log/storage/repository.dart';
import 'package:sembast/sembast_memory.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('setup and invitation routes open on device', (tester) async {
    final db = await databaseFactoryMemory.openDatabase('onboarding-device');
    final auth = GoogleAuth()..ready = true;
    final controller = AppController(Repository(db), auth, GoogleDrive(auth))
      ..loading = false;
    await tester.pumpWidget(LittleLogApp(controller: controller));
    await tester.pumpAndSettle();
    expect(find.text('Join an existing baby log'), findsOneWidget);

    await tester.tap(find.text('Join an existing baby log'));
    await tester.pumpAndSettle();
    expect(find.text('Join your baby’s shared log'), findsOneWidget);
    expect(find.text('Sign in with Google'), findsOneWidget);

    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Skip introduction'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Set up my baby'));
    await tester.pumpAndSettle();
    expect(
      find.text('Where would you like to save your baby’s log?'),
      findsOneWidget,
    );
    await tester.tap(find.text('Use Google Drive'));
    await tester.pumpAndSettle();
    expect(find.text('Set up with Google Drive'), findsOneWidget);
    expect(find.text('Baby’s name'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox());
    controller.dispose();
    await db.close();
  });
}
