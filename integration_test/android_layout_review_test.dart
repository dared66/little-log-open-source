import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sembast/sembast_memory.dart' hide Finder;
import 'package:little_log/controller.dart';
import 'package:little_log/main.dart';
import 'package:little_log/models.dart';
import 'package:little_log/services/family_csv.dart';
import 'package:little_log/services/google_auth.dart';
import 'package:little_log/services/google_drive.dart';
import 'package:little_log/services/import_file.dart';
import 'package:little_log/services/tip_jar.dart';
import 'package:little_log/storage/repository.dart';
import 'package:little_log/widgets/activity_flow.dart';
import 'package:little_log/widgets/appearance_page.dart';
import 'package:little_log/widgets/import_page.dart';
import 'package:little_log/widgets/onboarding.dart';
import 'package:little_log/widgets/profile_page.dart';
import 'package:little_log/widgets/quick_log_settings_page.dart';
import 'package:little_log/widgets/settings_page.dart';
import 'package:little_log/widgets/summary_settings_page.dart';
import 'package:little_log/widgets/tip_jar_page.dart';
import '../test/flow_journey_test.dart' as journey;
import '../test/tip_jar_test.dart' show FakeStore;

// Synthetic data only. Captures use the device's real viewport, font scaling,
// status bar and keyboard insets. No viewport overrides or live cloud writes.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  final manifest = <Map<String, Object?>>[];
  Future<void> capture(WidgetTester t, String title) async {
    await t.pump(const Duration(milliseconds: 400));
    expect(t.takeException(), isNull, reason: title);
    final expected = double.parse(
      const String.fromEnvironment('NATIVE_QA_EXPECTED_DPR'),
    );
    expect(t.view.devicePixelRatio, closeTo(expected, .001));
    final folder = Directory(
      '${(await getExternalStorageDirectory())!.path}/qa-android-layout',
    );
    await folder.create(recursive: true);
    final id = (manifest.length + 1).toString().padLeft(3, '0');
    final name = '$id-${title.replaceAll(RegExp(r'[^a-zA-Z0-9]+'), '-')}.png';
    final ready = File('${folder.path}/$name.ready');
    if (await ready.exists()) await ready.delete();
    final metadata = <String, Object?>{
      'id': id,
      'title': title,
      'file': name,
      'devicePixelRatio': t.view.devicePixelRatio,
      'physicalSize': '${t.view.physicalSize}',
      'textScale':
          MediaQuery.textScalerOf(
            t.element(find.byType(Scaffold).last),
          ).scale(14) /
          14,
    };
    // The host captures the full emulator screen and acknowledges the frame.
    // Avoid converting Flutter's render surface during repeated navigation.
    // ignore: avoid_print
    print(
      'ANDROID_LAYOUT_CHECKPOINT ${jsonEncode({'ready': ready.path, 'metadata': metadata})}',
    );
    await t.runAsync(() async {
      final deadline = Stopwatch()..start();
      while (!await ready.exists()) {
        if (deadline.elapsed > const Duration(seconds: 30)) {
          throw StateError('The host did not capture $title');
        }
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
    });
    manifest.add(metadata);
    await File(
      '${folder.path}/manifest.json',
    ).writeAsString(const JsonEncoder.withIndent('  ').convert(manifest));
    // ignore: avoid_print
    print('ANDROID_LAYOUT_CAPTURE $id $title');
  }

  if (const String.fromEnvironment(
        'LAYOUT_REVIEW_PHASE',
        defaultValue: 'full',
      ) ==
      'full') {
    journey.runJourney(
      native: true,
      includeConnectedFixture: true,
      checkpoint: (t, title) => capture(t, 'Light / $title'),
    );
  }

  for (final mode in [ThemeMode.light, ThemeMode.dark]) {
    testWidgets(
      '${mode.name} settings, management, edit and recovery screens',
      (t) async {
        final db = await databaseFactoryMemory.openDatabase(newId.v4());
        final auth = GoogleAuth()..ready = true;
        final c = AppController(Repository(db), auth, GoogleDrive(auth))
          ..loading = false;
        addTearDown(() async {
          c.dispose();
          await db.close();
        });
        await c.setThemeMode(mode);
        await t.pumpWidget(LittleLogApp(controller: c));
        await t.pumpAndSettle();
        Future<void> snap(String title) => capture(t, '${mode.name} / $title');
        Future<void> settle() async {
          await t.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 100)),
          );
          await t.pump(const Duration(milliseconds: 300));
          if (find.byType(AlertDialog).evaluate().isEmpty) {
            await t.pumpAndSettle();
          }
        }

        Future<void> tap(String label) async {
          final target = find.text(label).last;
          await t.ensureVisible(target);
          if (find.byType(AlertDialog).evaluate().isEmpty) {
            await t.pumpAndSettle();
          }
          await t.tap(target);
          await settle();
        }

        Future<void> back() async {
          await t.binding.handlePopRoute();
          await settle();
        }

        Future<void> bottom(String title) async {
          final scrolls = find.byType(Scrollable).hitTestable();
          if (scrolls.evaluate().isEmpty) return;
          final position = t.state<ScrollableState>(scrolls.last).position;
          if (position.maxScrollExtent > 0) {
            position.jumpTo(position.maxScrollExtent);
            await t.pumpAndSettle();
            await snap('$title / bottom');
          }
        }

        Future<void> open(Widget page) async {
          unawaited(
            Navigator.of(
              t.element(find.byType(HomePage)),
            ).push(MaterialPageRoute<void>(builder: (_) => page)),
          );
          await settle();
        }

        if (const String.fromEnvironment('LAYOUT_REVIEW_PHASE') == 'pages') {
          await c.createLocal('Synthetic QA', 'Alexandria Robin');
          await settle();
          final store = FakeStore();
          final jar = TipJar(store)..start();
          final pages = <String, Widget>{
            'Units': SettingsPage(controller: c),
            'Appearance': AppearancePage(controller: c),
            'Profile': ProfilePage(controller: c),
            'Import': ImportPage(controller: c),
            'Quick log': QuickLogSettingsPage(controller: c),
            'Summary': SummarySettingsPage(controller: c),
            'Support': TipJarPage(jar: jar),
          };
          for (final entry in pages.entries) {
            await open(entry.value);
            final frame = t.getRect(find.byType(Scrollable).first);
            expect(
              frame.top,
              closeTo(t.getRect(find.byType(AppBar).last).bottom, .1),
              reason: entry.key,
            );
            await snap('Final alignment / ${entry.key}');
            await back();
          }
          await t.pumpWidget(const SizedBox());
          jar.dispose();
          await store.events.close();
          return;
        }

        final at = DateTime.now().subtract(const Duration(hours: 1));
        final recoveryOnly =
            const String.fromEnvironment('LAYOUT_REVIEW_PHASE') == 'recovery';
        if (recoveryOnly) {
          await c.createLocal('Synthetic QA', 'Alexandria Robin');
          await settle();
        } else {
          await tap('Next');
          await snap('Introduction / tracking');
          await tap('Next');
          await snap('Introduction / setup');
          await tap('Set up my baby');
          await snap('Setup / storage choices');
          await tap('Use Google Drive');
          await snap('Setup / Google backup');
          await tap('Save only on this device');
          await snap('Setup / local name');
          await t.pumpWidget(const SizedBox());
          await c.createLocal('Synthetic QA', 'Alexandria Robin');
          await c.createLocal('Synthetic QA', 'Casey');
          await t.pumpWidget(LittleLogApp(controller: c));
          await settle();
          await snap('Log / second baby');
          await tap('Casey');
          await snap('Baby picker / two babies');
          await back();
          await tap('See all activities');
          await snap('Activity chooser / aligned');
          await back();
          await tap('Settings');
          await snap('Settings / top');
          await bottom('Settings');
          for (final label in ['Units', 'Appearance', 'Baby profile']) {
            await tap(label);
            await snap(label);
            await bottom(label);
            if (label == 'Baby profile') {
              await tap('Birth date');
              await snap('Profile / date picker');
              await tap('Cancel');
              await tap('Night begins');
              await snap('Profile / time picker');
              await tap('Cancel');
            }
            await back();
          }
          await open(QuickLogSettingsPage(controller: c));
          await snap('Customize quick log');
          await bottom('Customize quick log');
          await back();
          await open(SummarySettingsPage(controller: c));
          await snap('Customize summary');
          await back();
          await tap('Manage baby');
          await snap('Manage baby');
          await bottom('Manage baby');
          await tap('Edit name');
          await snap('Edit baby name');
          await back();
          await tap('Add baby');
          await snap('Add baby');
          await tap('Add baby');
          await snap('Add baby / validation');
          await back();
          await tap('Delete baby');
          await snap('Delete baby / confirmation');
          await back();
          await back();

          for (final method in activityCatalog.keys) {
            final record = Feeding(
              id: newId.v4(),
              familyId: c.family!.id,
              at: at,
              method: method,
              amountMl: ['bottle', 'pumping'].contains(method) ? 90 : null,
              diaperKind: method == 'diaper' ? 'both' : null,
              leftSeconds: method == 'nursing' ? 600 : null,
              rightSeconds: method == 'nursing' ? 300 : null,
              endedAt: ['nursing', 'sleep', 'pumping'].contains(method)
                  ? at.add(const Duration(minutes: 15))
                  : null,
              note: 'Synthetic sample',
              details: switch (method) {
                'solids' => {
                  'food': 'Pear',
                  'reaction': 'No reaction observed',
                },
                'growth' => {
                  'measurement': 'Weight',
                  'value': 6.2,
                  'unit': 'kg',
                },
                'health' => {
                  'kind': 'Medication',
                  'name': 'Sample',
                  'dose': '1 ml',
                },
                'routine' || 'milestone' => {'name': 'Sample activity'},
                _ => {},
              },
            );
            await c.repository.add(record);
            unawaited(
              editActivity(t.element(find.byType(HomePage)), c, record),
            );
            await settle();
            await snap('Edit / $method');
            await bottom('Edit / $method');
            await back();
          }
        }
        ImportFile selected = ImportFile(
          'synthetic-backup.csv',
          FamilyCsv(c.family!, [
            Feeding(
              id: newId.v4(),
              familyId: c.family!.id,
              at: at,
              method: 'bottle',
              amountMl: 75,
            ),
          ]).encode(),
        );
        await open(ImportPage(controller: c, pickFile: () async => selected));
        await snap('Import / empty');
        await tap('Choose file');
        await snap('Import / preview');
        await bottom('Import / preview');
        await tap('Import these entries');
        await snap('Import / completed');
        await bottom('Import / completed');
        await tap('Import history');
        await snap('Import / history');
        await tap('Undo last import');
        await snap('Import / undo confirmation');
        await tap('Keep import');
        selected = const ImportFile('malformed.csv', 'not a care export');
        await tap(
          find.text('Change file').evaluate().isEmpty
              ? 'Choose file'
              : 'Change file',
        );
        await snap('Import / invalid file');
        await back();

        final store = FakeStore();
        final jar = TipJar(store)..start();
        await open(TipJarPage(jar: jar));
        await snap('Support / available synthetic store');
        await back();
        jar.dispose();
        await store.events.close();
        await open(
          OnboardingPage(controller: c, initialStage: OnboardingStage.join),
        );
        await snap('Join / signed out');
        await bottom('Join / signed out');
        await back();
        await t.pumpWidget(const SizedBox());
      },
    );
  }
}
