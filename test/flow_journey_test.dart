import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:sembast/sembast_memory.dart' hide Finder;
import 'package:little_log/main.dart';
import 'package:little_log/controller.dart';
import 'package:little_log/models.dart';
import 'package:little_log/design.dart';
import 'package:little_log/widgets/activity_flow.dart';
import 'package:little_log/widgets/activity_panel.dart';
import 'package:little_log/widgets/care_entry_form.dart';
import 'package:little_log/storage/repository.dart';
import 'package:little_log/services/google_auth.dart';
import 'package:little_log/services/google_drive.dart';

class SampleAccount implements GoogleSignInAccount {
  @override
  String get id => 'sample-account';
  @override
  String get email => 'caregiver@example.com';
  @override
  String get displayName => 'Sample caregiver';
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

void main() => runJourney();

void runJourney({
  bool native = false,
  bool includeConnectedFixture = false,
  Future<Database> Function()? openDatabase,
  Future<void> Function(WidgetTester tester, String title)? checkpoint,
}) {
  const capture = bool.fromEnvironment('CAPTURE_REVIEW');
  const reviewFolder = String.fromEnvironment(
    'REVIEW_FOLDER',
    defaultValue: 'flow-redesign',
  );
  testWidgets(
    'real navigation covers every activity, timer lifecycle, saved history and family screens',
    (t) async {
      final previousHitTestPolicy =
          WidgetController.hitTestWarningShouldBeFatal;
      WidgetController.hitTestWarningShouldBeFatal = true;
      addTearDown(() {
        WidgetController.hitTestWarningShouldBeFatal = previousHitTestPolicy;
      });
      if (!native) {
        debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
        addTearDown(() => debugDefaultTargetPlatformOverride = null);
        t.view.physicalSize = const Size(390, 844);
        t.view.devicePixelRatio = 1;
        addTearDown(t.view.resetPhysicalSize);
        addTearDown(t.view.resetDevicePixelRatio);
      }
      if (capture) {
        for (final font in [
          'Roboto',
          'MaterialIcons',
          'CupertinoSystemText',
          'CupertinoSystemDisplay',
        ]) {
          final loader = FontLoader(font)
            ..addFont(
              Future.value(
                ByteData.sublistView(
                  File(
                    font.startsWith('Cupertino')
                        ? '/System/Library/Fonts/SFNS.ttf'
                        : '/opt/homebrew/share/flutter/bin/cache/artifacts/material_fonts/${font == 'Roboto' ? 'Roboto-Regular.ttf' : 'MaterialIcons-Regular.otf'}',
                  ).readAsBytesSync(),
                ),
              ),
            );
          await loader.load();
        }
      }
      final db = (await t.runAsync(
        openDatabase ?? () => databaseFactoryMemory.openDatabase(newId.v4()),
      ))!;
      final auth = GoogleAuth()..ready = true;
      final c = AppController(Repository(db), auth, GoogleDrive(auth))
        ..loading = false;
      final rows = <Map<String, String>>[];
      Future<void> settle() async {
        await t.pump();
        if (find.byType(LinearProgressIndicator).evaluate().isNotEmpty ||
            find.byType(CircularProgressIndicator).evaluate().isNotEmpty) {
          await t.pump(const Duration(milliseconds: 500));
        } else {
          await t.pumpAndSettle();
        }
      }

      Future<void> snap(String title, String route, {String note = ''}) async {
        expect(t.takeException(), isNull, reason: title);
        if (checkpoint != null) await checkpoint(t, title);
        if (!capture) return;
        const filter = String.fromEnvironment('CAPTURE_FILTER');
        if (filter.isNotEmpty && !RegExp(filter).hasMatch(title)) return;
        final id = 'S${(rows.length + 1).toString().padLeft(2, '0')}';
        await expectLater(
          find.byType(MaterialApp),
          matchesGoldenFile('../../output/$reviewFolder/screens/$id.png'),
        );
        rows.add({
          'id': id,
          'title': title,
          'group': route.split(' > ').first,
          'note': 'Route: $route. $note',
        });
        File(
          '../output/$reviewFolder/screens/manifest.json',
        ).writeAsStringSync(const JsonEncoder.withIndent('  ').convert(rows));
      }

      Future<void> tapFinder(Finder f, {bool async = false}) async {
        Future<void> waitForAction() async {
          if (!native) return;
          final deadline = Stopwatch()..start();
          while (c.recording) {
            if (deadline.elapsed > const Duration(seconds: 10)) {
              fail('Controller action did not finish: ${c.message}');
            }
            await t.runAsync(
              () => Future<void>.delayed(const Duration(milliseconds: 50)),
            );
            await t.pump();
          }
        }

        await waitForAction();
        await t.ensureVisible(f);
        await settle();
        final targetDescription = f.toString();
        if (async) {
          final targetCenter = t.getCenter(f);
          await t.runAsync(() async {
            await t.tapAt(targetCenter);
            await Future<void>.delayed(const Duration(milliseconds: 60));
          });
        } else {
          await t.tap(f);
        }
        await waitForAction();
        await settle();
        expect(t.takeException(), isNull, reason: 'Tap $targetDescription');
      }

      Future<void> tap(String label, {bool async = false}) async {
        if (label == 'Today' || label == 'History') {
          await tapFinder(find.text('Log').last);
          final homeScroll = find
              .descendant(
                of: find.byKey(const PageStorageKey('today')),
                matching: find.byType(Scrollable),
              )
              .first;
          t.state<ScrollableState>(homeScroll).position.jumpTo(0);
          await settle();
          if (label == 'Today' &&
              find.text('Back to today').evaluate().isNotEmpty) {
            await tapFinder(find.text('Back to today'));
          }
          await t.scrollUntilVisible(
            find.byKey(const ValueKey('log-activity-heading')),
            200,
            scrollable: homeScroll,
          );
          await settle();
          if (label == 'History' &&
              find.text('View all').evaluate().isNotEmpty) {
            await tapFinder(find.text('View all'));
          } else if (label == 'Today' &&
              find.text('Show less').evaluate().isNotEmpty) {
            await tapFinder(find.text('Show less'));
          }
          if (label == 'Today') {
            t.state<ScrollableState>(homeScroll).position.jumpTo(0);
            await settle();
          }
          return;
        }
        final shortcut = find.widgetWithText(OutlinedButton, label);
        if (['Bottle', 'Nursing', 'Diaper', 'Sleep'].contains(label) &&
            find.byType(BottomSheet).evaluate().isEmpty &&
            find.byType(ModalBarrier).evaluate().length <= 1) {
          final homeScroll = find
              .descendant(
                of: find.byKey(const PageStorageKey('today')),
                matching: find.byType(Scrollable),
              )
              .first;
          t.state<ScrollableState>(homeScroll).position.jumpTo(0);
          await settle();
          await t.scrollUntilVisible(shortcut, -180, scrollable: homeScroll);
          await settle();
          await tapFinder(shortcut.last, async: async);
          return;
        }
        await tapFinder(find.text(label).last, async: async);
      }

      Future<void> close() => tapFinder(find.byTooltip('Close').last);
      Future<void> enter(String label, String value) async {
        final f = find.widgetWithText(TextFormField, label);
        await t.ensureVisible(f);
        await settle();
        await t.enterText(f, value);
        await settle();
      }

      Future<void> select(String label, String value) async {
        if (label == 'Poop color' || label == 'Consistency') {
          await tapFinder(find.widgetWithText(FilterChip, value));
          return;
        }
        if (label == 'Activity') {
          await t.scrollUntilVisible(
            (label == 'Activity'
                ? find.widgetWithText(DropdownButtonFormField<String>, label)
                : find.descendant(
                    of: find.byKey(ValueKey('field-$label')),
                    matching: find.byType(DropdownButtonFormField<String>),
                  )),
            -260,
            scrollable: find.byType(Scrollable).last,
          );
        }
        final field = label == 'Activity'
            ? find.widgetWithText(DropdownButtonFormField<String>, label)
            : find.descendant(
                of: find.byKey(ValueKey('field-$label')),
                matching: find.byType(DropdownButtonFormField<String>),
              );
        await tapFinder(field);
        final item = find.widgetWithText(DropdownMenuItem<String>, value).last;
        final selectedValue = t.widget<DropdownMenuItem<String>>(item).value;
        // A menu item's outer box can extend past the clipped menu viewport.
        // Tap its visible label, and verify the actual form value changed.
        await tapFinder(find.descendant(of: item, matching: find.text(value)));
        expect(t.state<FormFieldState<String>>(field).value, selectedValue);
      }

      Future<void> choose(String label) async {
        ScaffoldMessenger.of(t.element(find.byType(HomePage))).clearSnackBars();
        await t.pump(const Duration(seconds: 5));
        await settle();
        await tap('Today');
        final scrollState = t.state<ScrollableState>(
          find.byType(Scrollable).last,
        );
        scrollState.position.jumpTo(0);
        await settle();
        await t.scrollUntilVisible(
          find.text('See all activities'),
          260,
          scrollable: find.byType(Scrollable).last,
        );
        await tap('See all activities');
        await tapFinder(
          find.descendant(
            of: find.byType(BottomSheet),
            matching: find.text(label),
          ),
        );
      }

      Future<void> save(String method, String note) async {
        await enter('Notes (optional)', note);
        await tap('Save $method', async: true);
        // Native storage may finish before the modal's pop animation. Wait for
        // the sheet to leave before targeting the navigation underneath it.
        if (native) {
          bool saveSheetOpen() =>
              find.byType(ActivityForm).evaluate().isNotEmpty ||
              find.byType(TimedActivityFlow).evaluate().isNotEmpty ||
              find.byType(BottleEntryForm).evaluate().isNotEmpty ||
              find.byType(DiaperEntryForm).evaluate().isNotEmpty ||
              find.byType(NursingEntryForm).evaluate().isNotEmpty;
          for (var attempt = 0; attempt < 30 && saveSheetOpen(); attempt++) {
            await t.pump(const Duration(milliseconds: 100));
          }
          expect(find.byType(ActivityForm), findsNothing);
          expect(find.byType(TimedActivityFlow), findsNothing);
          expect(find.byType(BottleEntryForm), findsNothing);
          expect(find.byType(DiaperEntryForm), findsNothing);
          expect(find.byType(NursingEntryForm), findsNothing);
          await SystemChannels.textInput.invokeMethod<void>('TextInput.hide');
          // The save snackbar can temporarily cover the bottom navigation on
          // the native iPhone viewport even after the sheet has closed.
          await t.pump(const Duration(seconds: 3));
          await settle();
        }
        final record = c.feeds.firstWhere((r) => r.note == note);
        expect(record.method, method);
        final stored = (await t.runAsync(
          () => c.repository.feeds(c.family!.id),
        ))!;
        expect(
          stored.firstWhere((r) => r.id == record.id).toJson(),
          record.toJson(),
        );
        await snap(
          '$method / saved on Today',
          'Today > $method > Save $method',
          note: 'The saved record was checked in persistent storage.',
        );
        await tap('History');
        // Manual sleep/pumping starts one hour ago, which is yesterday when
        // this journey runs shortly after midnight (including UTC CI).
        if (!DateUtils.isSameDay(record.at.toLocal(), DateTime.now())) {
          await tapFinder(find.byKey(const ValueKey('log-day-picker')));
          await tapFinder(find.byTooltip('Previous day'));
          await tapFinder(find.text('Show day'));
          await tap('History');
        }
        await t.pump(const Duration(seconds: 3));
        await settle();
        final row = find.byWidgetPredicate(
          (w) => w is RecordRow && w.record.id == record.id,
        );
        await t.scrollUntilVisible(
          row,
          260,
          scrollable: find.byType(Scrollable).last,
        );
        await settle();
        await tapFinder(
          find.descendant(of: row, matching: find.byType(InkWell)).first,
        );
        expect(
          find.descendant(of: row, matching: find.text(note)),
          findsOneWidget,
        );
        await snap(
          '$method / saved in History',
          'Today > $method > Save > History > saved entry',
        );
        await tap('Today');
      }

      await t.pumpWidget(LittleLogApp(controller: c));
      await settle();
      await snap('Welcome', 'Welcome');
      await tap('Join an existing baby log');
      await snap(
        'Join a family / signed out',
        'Welcome > Join an existing baby log',
      );
      await tapFinder(find.byTooltip('Back'));
      await tap('New baby log');
      await tap('This device');
      await tap('Create baby log');
      await snap('Welcome / missing name', 'Welcome > Create baby log');
      await t.enterText(find.byType(TextFormField), 'Robin');
      FocusManager.instance.primaryFocus?.unfocus();
      await settle();
      await t.scrollUntilVisible(
        find.text('Create baby log'),
        160,
        scrollable: find.byType(Scrollable).last,
      );
      await tap('Create baby log', async: true);
      await snap('Today / empty', 'Welcome > enter Robin > Create baby log');
      await tap('History');
      await snap('History / empty', 'Today > History');
      await tap('Today');
      await tap('See all activities');
      await snap('Choose an activity / top', 'Today > All activities');
      await t.ensureVisible(find.widgetWithText(ListTile, 'Milestone'));
      await settle();
      await snap(
        'Choose an activity / more',
        'Today > All activities > scroll',
      );
      await close();
      await tap('Bottle');
      expect(find.text('Duration (minutes)'), findsNothing);
      expect(find.text('Enter manually'), findsNothing);
      await snap('Bottle / details', 'Today > Bottle');
      await tap('Save bottle');
      await snap('Bottle / validation', 'Today > Bottle > Save without amount');
      await tapFinder(find.byKey(const ValueKey('volume-oz')));
      await enter('Amount (oz)', '3');
      await snap('Bottle / ounces', 'Today > Bottle > oz');
      await tapFinder(find.byKey(const ValueKey('volume-ml')));
      await snap('Bottle / converted milliliters', 'Today > Bottle > oz > ml');
      await enter('Amount (ml)', '90');
      await tapFinder(find.byKey(const ValueKey('Started-date')));
      await snap('Choose date', 'Today > Bottle > Started > Date');
      await tap('OK');
      expect(find.byType(TimePickerDialog), findsNothing);
      await tapFinder(find.byKey(const ValueKey('Started-time')));
      await snap('Choose time', 'Today > Bottle > Started > Time');
      await tap('Cancel');
      await save('bottle', 'After waking');
      for (final kind in ['Wet', 'Dirty', 'Both', 'Dry']) {
        await choose('Diaper');
        if (kind == 'Dirty' || kind == 'Dry') {
          await tapFinder(find.widgetWithText(FilterChip, 'Wet'));
        }
        if (kind == 'Dirty' || kind == 'Both') {
          await tapFinder(find.widgetWithText(FilterChip, 'Dirty'));
        }
        await snap(
          'Diaper / ${kind.toLowerCase()}',
          'Today > All activities > Diaper > $kind',
        );
        if (kind == 'Both') {
          await select('Poop color', 'Yellow');
          await select('Consistency', 'Seedy');
          await tapFinder(find.widgetWithText(SwitchListTile, 'Blowout'));
          await snap(
            'Diaper / observations',
            'Today > All activities > Diaper > Both > observations',
          );
          await save('diaper', 'Changed after the bottle');
          final f = c.feeds.firstWhere((r) => r.isDiaper);
          expect(f.details, {
            'poopColor': 'yellow',
            'poopConsistency': 'seedy',
            'blowout': true,
            'rash': false,
          });
        } else {
          await close();
        }
      }
      for (final method in ['nursing', 'sleep', 'pumping']) {
        final label = activityCatalog[method]!;
        await choose(label);
        await snap(
          '$label / choose timer or manual',
          'Today > All activities > $label',
        );
        await tap('Enter manually');
        if (method != 'nursing') expect(find.text('60:00'), findsOneWidget);
        await snap(
          '$label / manual details',
          'Today > All activities > $label > Enter manually',
        );
        if (method == 'nursing') {
          final left = find.widgetWithText(TextFormField, 'Minutes').first;
          await t.ensureVisible(left);
          await t.enterText(left, '12');
        }
        if (method == 'pumping') {
          await tapFinder(find.byKey(const ValueKey('volume-oz')));
          await enter('Milk pumped (oz)', '2.5');
          await snap(
            'Pumping / manual ounces',
            'Today > Pumping > Enter manually > oz',
          );
          await tapFinder(find.byKey(const ValueKey('volume-ml')));
          await enter('Milk pumped (ml)', '60');
        }
        await save(method, '$label entered manually');
        await choose(label);
        await tap(
          method == 'nursing' ? 'Start left' : 'Start $method',
          async: true,
        );
        await snap(
          '$label / timer running',
          'Today > All activities > $label > Start',
        );
        if (method == 'nursing') {
          await tap('Switch to right', async: true);
          expect(c.nursing!.side, 'right');
          await snap(
            'Nursing / switch sides',
            'Today > Nursing > Start left > Switch to right',
          );
          await tap('Pause nursing', async: true);
          expect(c.nursing!.paused, isTrue);
          await snap('Nursing / paused', 'Today > Nursing > Pause nursing');
        }
        await close();
        await t.scrollUntilVisible(
          find.byType(ActiveSessions),
          -250,
          scrollable: find.byType(Scrollable).first,
        );
        await settle();
        if (method == 'nursing') {
          final paused = t
              .widget<Text>(
                find.descendant(
                  of: find.byType(ActiveSessions),
                  matching: find.textContaining(' · paused'),
                ),
              )
              .data!;
          await t.pump(const Duration(seconds: 2));
          expect(
            t
                .widget<Text>(
                  find.descendant(
                    of: find.byType(ActiveSessions),
                    matching: find.textContaining(' · paused'),
                  ),
                )
                .data,
            paused,
          );
          await snap('Nursing / paused on Today', 'Today > Nursing paused');
          await tapFinder(
            find.descendant(
              of: find.byType(ActiveSessions),
              matching: find.text(label),
            ),
          );
          await tap('Resume nursing', async: true);
          expect(c.nursing!.paused, isFalse);
          await close();
          await settle();
        }
        await snap(
          '$label / active on Today',
          'Today > $label > Start > Close',
        );
        await tapFinder(
          find.descendant(
            of: find.byType(ActiveSessions),
            matching: find.text(label),
          ),
        );
        if (method == 'nursing') {
          final f = find.widgetWithText(TextField, 'Notes (optional)');
          await t.ensureVisible(f);
          await t.enterText(f, 'Nursing timed');
          await tap('Pause nursing', async: true);
          await tap('Finish nursing', async: true);
          expect(c.nursing, isNull);
          final r = c.feeds.firstWhere((r) => r.note == 'Nursing timed');
          expect(r.leftSeconds, isNotNull);
          expect(r.rightSeconds, isNotNull);
          final stored = (await t.runAsync(
            () => c.repository.feeds(c.family!.id),
          ))!;
          expect(stored.firstWhere((f) => f.id == r.id).note, 'Nursing timed');
          await snap('Nursing / saved', 'Today > Nursing > notes > Finish');
        } else if (method == 'sleep') {
          await tap('Finish sleep', async: true);
          expect(c.timers.where((t) => t.method == 'sleep'), isEmpty);
          expect(c.feeds.any((r) => r.method == 'sleep'), isTrue);
          await snap('Sleep / saved', 'Today > Sleep > Finish');
        } else {
          expect(find.text('Finish pumping'), findsNothing);
          await tap('Pause pumping', async: true);
          await tap('Finish pumping', async: true);
          await snap('Pumping / review', 'Today > Pumping > Pause > Finish');
          expect(find.text('Back to timer'), findsNothing);
          final count = c.feeds.length;
          await close();
          expect(c.feeds.length, count);
          expect(
            c.timers.singleWhere((t) => t.method == 'pumping').phase,
            'review',
          );
          await choose(label);
          await tapFinder(find.byKey(const ValueKey('volume-oz')));
          await enter('Milk pumped (oz)', '3');
          await snap(
            'Pumping / timer review ounces',
            'Today > Pumping > Review > oz',
          );
          await tapFinder(find.byKey(const ValueKey('volume-ml')));
          await enter('Milk pumped (ml)', '75');
          await save(method, '$label timed');
          expect(c.timers.where((t) => t.method == method), isEmpty);
        }
      }
      for (final method in [
        'solids',
        'growth',
        'health',
        'routine',
        'milestone',
      ]) {
        await choose(activityCatalog[method]!);
        await snap(
          '${activityCatalog[method]} / details',
          'Today > All activities > ${activityCatalog[method]}',
        );
        if (method == 'solids') {
          await enter('Food / foods', 'Avocado');
          await select('Reaction', 'No reaction observed');
        }
        if (method == 'growth') {
          for (final measure in ['Length', 'Head circumference', 'Weight']) {
            await select('Measurement', measure);
            await snap(
              'Growth / $measure',
              'Today > All activities > Growth > $measure',
            );
          }
          await enter('Measured value (kg)', '6.2');
        }
        if (method == 'health') {
          for (final kind in [
            'Vaccine',
            'Temperature',
            'Symptom',
            'Doctor visit',
            'Medication',
          ]) {
            await select('Health record', kind);
            await snap(
              'Health / $kind',
              'Today > All activities > Health > $kind',
            );
          }
          await enter('Medicine name', 'Sample medicine');
          await enter('Dose given (include unit)', '1 ml');
          await enter('Temperature (°C)', '38');
          await snap(
            'Health / medication with temperature',
            'Today > Health > Medication + Temperature',
          );
        }
        if (method == 'routine') {
          await enter('Routine (e.g. tummy time, bath)', 'Tummy time');
        }
        if (method == 'milestone') {
          await enter('Milestone (e.g. first smile)', 'First smile');
        }
        await save(method, '${activityCatalog[method]} sample note');
        if (method == 'health') {
          final healthRecord = c.feeds.firstWhere((f) => f.method == 'health');
          expect(healthRecord.details['temperature'], 38);
          expect(healthRecord.details['temperatureUnit'], '°C');
        }
      }
      await tap('History');
      await select('Activity', 'Diaper');
      await snap('History / filtered', 'Today > History > Activity > Diaper');
      await tapFinder(find.byKey(const ValueKey('log-day-picker')));
      final yesterday = DateTime.now().subtract(const Duration(days: 1));
      if (yesterday.month != DateTime.now().month) {
        await tapFinder(find.byTooltip('Previous month'));
      }
      await tapFinder(find.text('${yesterday.day}').last);
      await tap('Show day');
      await snap(
        'History / previous day',
        'History > Activity > Diaper > Previous day',
      );
      await tap('Back to today');
      await tap('History');
      await select('Activity', 'All activities');
      await tap('Settings');
      await snap('Family / signed out', 'Today > Family');
      await tap('Units');
      await snap('Settings / default milliliters', 'Family > Settings');
      await tap('oz', async: true);
      await snap(
        'Settings / default ounces',
        'Family > Settings > US fluid ounces',
      );
      await t.pageBack();
      await settle();
      await tap('Today');
      await t.scrollUntilVisible(
        find.byKey(const ValueKey('today-summary')),
        180,
        scrollable: find.byType(Scrollable).last,
      );
      await snap('Today / ounces only', 'Settings > oz > Today');
      expect(find.text('3.04 oz'), findsOneWidget);
      expect(find.textContaining('90 ml'), findsNothing);
      await tap('History');
      await t.scrollUntilVisible(
        find.byKey(const ValueKey('today-summary')),
        -180,
        scrollable: find.byType(Scrollable).last,
      );
      await snap('History / ounces only', 'Settings > oz > History');
      expect(find.text('3.04 oz'), findsOneWidget);
      expect(find.textContaining('135 ml'), findsNothing);
      await tap('Settings');
      await tap('Units');
      await tap('ml', async: true);
      await t.pageBack();
      await settle();
      await tap('Data & storage');
      await snap('Family / storage', 'Family > Data & storage');
      await tap('Export baby log', async: true);
      await snap('Family / export', 'Baby > Data & storage > Export baby log');
      await tap('Close', async: true);
      if (capture || includeConnectedFixture) {
        final local = c.family!;
        // Account and connection fixtures are explicit: no external calls are made.
        auth.user = SampleAccount();
        await t.pumpWidget(const SizedBox());
        await t.pumpWidget(LittleLogApp(controller: c));
        await settle();
        await tap('Settings');
        await snap(
          'Family / signed in',
          'Family',
          note:
              'Sample signed-in account fixture; Google sign-in is outside this review.',
        );
        auth.driveConnected = true;
        c.lastSync = DateTime.now();
        c.family = Family(
          id: local.id,
          name: local.name,
          babyName: local.babyName,
          driveFileId: 'sample-file',
          accountId: 'sample-account',
        );
        await t.pumpWidget(const SizedBox());
        await t.pumpWidget(LittleLogApp(controller: c));
        await settle();
        await tap('Settings');
        await snap(
          'Family / connected',
          'Family',
          note:
              'Sample connected-account fixture; live sync is not verified here.',
        );
        await tap('Invite a caregiver');
        await tap('Share invitation');
        await snap(
          'Family / invitation validation',
          'Family > Share invitation with blank email',
          note: 'No invitation was sent.',
        );
        await t.pageBack();
        await settle();
        await tap('Join an existing baby log');
        await snap(
          'Family / join or restore',
          'Settings > Join an existing baby log',
        );
        await t.pageBack();
        await settle();
        await tap('Data & storage');
        await snap('Family / connected storage', 'Family > Data & storage');
        auth.user = null;
        auth.driveConnected = false;
        c.family = local;
        await t.pumpWidget(const SizedBox());
        await t.pumpWidget(LittleLogApp(controller: c));
        await settle();
      }
      await tap('Settings');
      await tap('Units');
      await tap('lb', async: true);
      expect(c.weightUnit, 'lb');
      await tap('in', async: true);
      await tap('°F', async: true);
      expect(c.lengthUnit, 'in');
      expect(c.temperatureUnit, '°F');
      await snap('Settings / unit defaults', 'Settings > Units');
      await t.pageBack();
      await settle();
      await choose('Growth');
      expect(find.text('lb'), findsOneWidget);
      await snap('Growth / preferred pounds', 'Today > Growth');
      await select('Measurement', 'Length');
      expect(find.text('Measured value (in)'), findsOneWidget);
      await snap('Growth / preferred inches', 'Today > Growth > Length');
      await close();
      await choose('Health');
      expect(find.text('Temperature (°F)'), findsOneWidget);
      await snap('Health / preferred Fahrenheit', 'Today > Health');
      await close();
      await tap('Today');
      final deleting = c.feeds.first;
      final deletingRow = find.byWidgetPredicate(
        (w) => w is RecordRow && w.record.id == deleting.id,
      );
      await t.scrollUntilVisible(
        deletingRow,
        250,
        scrollable: find.byType(Scrollable).last,
      );
      await settle();
      await t.drag(deletingRow, const Offset(-350, 0));
      await settle();
      await snap(
        'Activity / swipe delete confirmation',
        'Today > Swipe entry left',
      );
      await tap('Cancel');
      expect(c.feeds.any((f) => f.id == deleting.id), isTrue);
      await t.drag(deletingRow, const Offset(-350, 0));
      await settle();
      await tap('Delete', async: true);
      expect(c.feeds.any((f) => f.id == deleting.id), isFalse);
      await settle();
      expect(deletingRow, findsNothing);
      await snap('Today / entry deleted', 'Today > Swipe left > Delete');
      if (!native) {
        t.view.physicalSize = const Size(320, 640);
        t.platformDispatcher.textScaleFactorTestValue = 1.8;
        addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
        await settle();
        await snap(
          'Small phone / Today',
          'Today',
          note: '320 × 640, text at 180%.',
        );
        await choose('Sleep');
        await snap(
          'Small phone / timer choice',
          'Today > All activities > Sleep',
          note: '320 × 640, text at 180%.',
        );
        expect(find.text('Enter manually').hitTestable(), findsOneWidget);
        await close();
        await choose('Bottle');
        await tapFinder(find.byKey(const ValueKey('volume-oz')));
        await enter('Amount (oz)', '3.5');
        await snap(
          'Small phone / bottle ounces',
          'Today > All activities > Bottle > oz',
          note: '320 x 640, text at 180%.',
        );
        expect(find.text('Save bottle').hitTestable(), findsOneWidget);
        await close();
        await tap('Settings');
        await tap('Units');
        await snap(
          'Small phone / Settings',
          'Family > Settings',
          note: '320 x 640, text at 180%.',
        );
      }
      await t.pumpWidget(const SizedBox());
      debugDefaultTargetPlatformOverride = null;
      c.dispose();
      await t.runAsync(db.close);
    },
  );
}
