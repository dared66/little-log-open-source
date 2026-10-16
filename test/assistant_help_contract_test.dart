import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:little_log/widgets/assistant_help_page.dart';

// Run on the host: compare help examples with the shipped native registrations.
// This checks the phrase inventory, not Siri/Assistant speech recognition.
void main() {
  test('every Siri help example matches a registered shortcut phrase', () {
    final source = File('ios/Runner/SiriActions.swift').readAsStringSync();
    List<String> values(String name) {
      final body = source.split('enum $name:').last.split('\n}\n').first;
      return RegExp(
        r'\.\w+: "([^"]+)"',
      ).allMatches(body).map((match) => match[1]!).toList();
    }

    final slots = {
      r'\.$kind': values('SiriDiaperKind'),
      r'\.$side': values('SiriNursingSide'),
      r'\.$activity': values('SiriHistoryActivity'),
      '.applicationName': ['Little Log'],
    };
    final templates = RegExp(
      r'"([^"\n]*\\\(\.applicationName\)[^"\n]*)"',
    ).allMatches(source).map((match) => match[1]!);
    final patterns = [
      for (final template in templates)
        RegExp(
          '^${template.splitMapJoin(RegExp(r'\\\(([^)]+)\)'), onMatch: (match) => '(?:${slots[match[1]]!.map(RegExp.escape).join('|')})', onNonMatch: RegExp.escape)}\u0024',
          caseSensitive: false,
        ),
    ];
    expect(patterns, isNotEmpty);
    for (final topic in const AssistantHelpPage(
      assistant: VoiceAssistant.siri,
    ).topics) {
      for (final example in [...topic.questions, ...topic.actions]) {
        final phrase =
            '${example.replaceFirst(RegExp(r'\?$'), '')} in Little Log';
        expect(
          patterns.any((pattern) => pattern.hasMatch(phrase)),
          isTrue,
          reason: phrase,
        );
      }
    }
  });

  test('every Google help example matches a registered query pattern', () {
    final source = File(
      'android/app/src/main/res/values/assistant_actions.xml',
    ).readAsStringSync();
    final patterns = [
      for (final array in RegExp(
        r'<string-array name="voice_queries_[^"]+">(.*?)</string-array>',
        dotAll: true,
      ).allMatches(source))
        for (final item in RegExp(r'<item>(.*?)</item>').allMatches(array[1]!))
          RegExp(
            '^${item[1]!.splitMapJoin(RegExp(r'\$(kind|side|amount|unit)'), onMatch: (_) => '[a-z0-9 ]+', onNonMatch: RegExp.escape)}\u0024',
            caseSensitive: false,
          ),
    ];
    expect(patterns, isNotEmpty);
    for (final topic in const AssistantHelpPage(
      assistant: VoiceAssistant.google,
    ).topics) {
      for (final example in [...topic.questions, ...topic.actions]) {
        final phrase = example.replaceFirst(RegExp(r'\?$'), '');
        expect(
          patterns.any((pattern) => pattern.hasMatch(phrase)),
          isTrue,
          reason: phrase,
        );
      }
    }
  });
}
