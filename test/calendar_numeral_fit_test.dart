import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:little_log/widgets/log_header.dart';
import 'support/test_fonts.dart';

void main() => calendarFitTests();

void calendarFitTests({bool native = false}) {
  testWidgets(
    'maximum common numeral size fits every day without growing the calendar',
    (t) async {
      if (!native) await t.runAsync(loadTestFonts);
      late TextStyle style;
      await t.pumpWidget(
        MaterialApp(
          home: Scaffold(
            appBar: AppBar(
              title: Builder(
                builder: (context) {
                  style = DefaultTextStyle.of(context).style.copyWith(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    height: 1,
                    letterSpacing: 0,
                  );
                  return const Text('Calendar size check');
                },
              ),
            ),
          ),
        ),
      );
      final fit = calendarDayFontSize(style, TextDirection.ltr);
      var widest = 0.0;
      var nextWidest = 0.0;
      for (var day = 1; day <= 31; day++) {
        final text = TextPainter(
          text: TextSpan(
            text: '$day',
            style: style.copyWith(fontSize: fit),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        expect(text.width, lessThanOrEqualTo(23.7), reason: 'Day $day');
        if (text.width > widest) widest = text.width;
        text.dispose();
        final next = TextPainter(
          text: TextSpan(
            text: '$day',
            style: style.copyWith(fontSize: fit + .1),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        if (next.width > nextWidest) nextWidest = next.width;
        next.dispose();
      }
      expect(fit * .71, lessThanOrEqualTo(22));
      expect(nextWidest > 23.7 || (fit + .1) * .71 > 22, isTrue);
      debugPrint(
        'CALENDAR FIT: font=${style.fontFamily}; base=$fit; displayed=${fit * .75}; widest=${widest * .75}; calendar=21x24; all 31 days fit; next size fails.',
      );
    },
  );
}
