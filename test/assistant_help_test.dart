import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:little_log/controller.dart';
import 'package:little_log/main.dart';
import 'package:little_log/models.dart';
import 'package:little_log/services/google_auth.dart';
import 'package:little_log/services/google_drive.dart';
import 'package:little_log/storage/repository.dart';
import 'package:little_log/widgets/assistant_help_page.dart';
import 'package:sembast/sembast_memory.dart' hide Finder;
import 'support/scroll_to.dart';

void main() {
  for (final platform in [TargetPlatform.iOS, TargetPlatform.android]) {
    for (final theme in [ThemeMode.light, ThemeMode.dark]) {
      testWidgets(
        '${platform.name} Settings opens app setup and platform voice help in ${theme.name} at large text',
        (t) async {
          debugDefaultTargetPlatformOverride = platform;
          addTearDown(() => debugDefaultTargetPlatformOverride = null);
          t.view.physicalSize = const Size(320, 640);
          t.view.devicePixelRatio = 1;
          t.platformDispatcher.textScaleFactorTestValue = 1.8;
          addTearDown(t.view.resetPhysicalSize);
          addTearDown(t.view.resetDevicePixelRatio);
          addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
          final db = (await t.runAsync(
            () => databaseFactoryMemory.openDatabase(newId.v4()),
          ))!;
          final auth = GoogleAuth();
          final c = AppController(Repository(db), auth, GoogleDrive(auth))
            ..loading = false
            ..themeMode = theme;
          await t.runAsync(() => c.createLocal('Sample family', 'Robin'));
          addTearDown(() async {
            c.dispose();
            await db.close();
          });
          await t.pumpWidget(LittleLogApp(controller: c));
          await t.pumpAndSettle();
          await t.tap(find.text('Settings').last);
          await t.pumpAndSettle();
          final siri = platform == TargetPlatform.iOS;
          final name = siri ? 'Siri' : 'Google Assistant';
          final other = siri ? 'Google Assistant' : 'Siri';
          final entry = find.byKey(const ValueKey('assistant-help'));
          await t.ensureVisible(entry);
          await t.pumpAndSettle();
          expect(
            t.getTopLeft(find.text('Help')).dy,
            greaterThan(t.getBottomRight(find.text('Support Little Log')).dy),
          );
          expect(
            t.getBottomRight(entry).dy,
            lessThan(t.getTopLeft(find.text(c.family!.storageLabel)).dy),
          );
          expect(find.text('Help'), findsOneWidget);
          expect(find.textContaining(name), findsNothing);
          expect(find.textContaining(other), findsNothing);
          await t.tap(entry);
          await t.pumpAndSettle();
          expect(find.byType(AssistantHelpPage), findsOneWidget);
          expect(
            find.descendant(
              of: find.byType(AppBar),
              matching: find.text('Help'),
            ),
            findsOneWidget,
          );
          expect(find.text(name), findsNothing);
          expect(find.textContaining(other), findsNothing);
          expect(
            find.text(siri ? 'Use Siri' : 'Use Google Assistant'),
            findsOneWidget,
          );
          final voice = find.text(siri ? 'Use Siri' : 'Use Google Assistant');
          final setup = find.text('Setup and troubleshooting');
          expect(t.widget<Text>(voice).style, t.widget<Text>(setup).style);
          expect(t.widget<Text>(voice).style!.letterSpacing, 0);
          expect(find.text('Diapers'), findsNothing);
          expect(
            find.text('Requests use the baby selected in Little Log.'),
            findsNothing,
          );
          expect(find.text('How answers work'), findsNothing);
          await t.tap(voice);
          await t.pumpAndSettle();
          expect(
            find.text('Requests use the baby selected in Little Log.'),
            findsOneWidget,
          );
          final page = t.widget<AssistantHelpPage>(
            find.byType(AssistantHelpPage),
          );
          expect(page.topics.map((topic) => topic.title), [
            'Diapers',
            'Feeding',
            'Sleep',
            'Pumping',
          ]);
          // The overview starts compact; reveal only the selected activity.
          for (final topic in page.topics) {
            expect(
              find.text(page.phrase(topic.questions.first, question: true)),
              findsNothing,
            );
          }
          for (final topic in page.topics) {
            final heading = find.text(topic.title);
            await scrollTo(t, heading);
            await t.tap(heading);
            await t.pumpAndSettle();
            for (final question in topic.questions) {
              final example = find.text(page.phrase(question, question: true));
              await scrollTo(t, example);
              expect(example, findsOneWidget);
              expect(t.takeException(), isNull);
            }
            for (final command in topic.actions) {
              final example = find.text(page.phrase(command));
              await scrollTo(t, example);
              expect(example, findsOneWidget);
              expect(t.takeException(), isNull);
            }
            await scrollTo(t, heading);
            await t.tap(heading);
            await t.pumpAndSettle();
            expect(
              find.text(page.phrase(topic.questions.first, question: true)),
              findsNothing,
            );
          }
          final voiceHelp = find.byKey(
            const PageStorageKey('assistant-help-voice-help'),
          );
          await scrollTo(t, voiceHelp);
          await t.tap(
            find.text(
              siri ? 'Shortcuts and Siri help' : 'Google Assistant help',
            ),
          );
          await t.pumpAndSettle();
          await scrollTo(
            t,
            find.text(siri ? 'Use Shortcuts' : 'If your phone uses Gemini'),
          );
          expect(
            find.text(siri ? 'Use Shortcuts' : 'If your phone uses Gemini'),
            findsOneWidget,
          );
          await scrollTo(t, find.text('How answers work'));
          expect(t.takeException(), isNull);
          await scrollTo(t, voice);
          await t.tap(voice);
          await t.pumpAndSettle();
          expect(
            find.text('Requests use the baby selected in Little Log.'),
            findsNothing,
          );
          expect(find.text('Diapers'), findsNothing);
          await scrollTo(t, setup);
          await t.tap(setup);
          await t.pumpAndSettle();
          expect(find.text('Use Shortcuts'), findsNothing);
          expect(find.text('If your phone uses Gemini'), findsNothing);
          for (final guide in setupHelpTopics) {
            final heading = find.text(guide.title);
            await scrollTo(t, heading);
            expect(find.text(guide.steps.first), findsNothing);
            await t.tap(heading);
            await t.pumpAndSettle();
            for (final step in guide.steps) {
              final instruction = find.text(step);
              await scrollTo(t, instruction);
              expect(instruction, findsOneWidget);
              expect(t.takeException(), isNull);
            }
            if (guide.note != null) {
              await scrollTo(t, find.text(guide.note!));
              expect(t.takeException(), isNull);
            }
            await scrollTo(t, heading);
            await t.tap(heading);
            await t.pumpAndSettle();
            expect(find.text(guide.steps.first), findsNothing);
          }
          expect(t.takeException(), isNull);
          await t.pageBack();
          await t.pumpAndSettle();
          expect(find.byType(AssistantHelpPage), findsNothing);
          expect(c.feeds, isEmpty);
          expect(c.timers, isEmpty);
          await t.pumpWidget(const SizedBox());
          await t.pumpAndSettle();
          debugDefaultTargetPlatformOverride = null;
        },
      );
    }
  }

  for (final platform in [
    TargetPlatform.linux,
    TargetPlatform.macOS,
    TargetPlatform.windows,
    TargetPlatform.fuchsia,
  ]) {
    testWidgets(
      '${platform.name} does not show mobile assistant instructions',
      (t) async {
        debugDefaultTargetPlatformOverride = platform;
        addTearDown(() => debugDefaultTargetPlatformOverride = null);
        await t.pumpWidget(
          const MaterialApp(home: Scaffold(body: AssistantHelpTile())),
        );
        expect(find.byKey(const ValueKey('assistant-help')), findsNothing);
        expect(find.text('Help'), findsNothing);
        await t.pumpWidget(const SizedBox());
        debugDefaultTargetPlatformOverride = null;
      },
    );
  }
}
