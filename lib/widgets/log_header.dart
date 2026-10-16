import 'package:flutter/material.dart';
import 'package:intl/intl.dart' show DateFormat;
import '../controller.dart';
import '../design.dart';
import 'baby_picker.dart';

/// The name, date label and calendar number share one typographic centerline.
class LogHeader extends StatelessWidget {
  const LogHeader({
    super.key,
    required this.controller,
    required this.day,
    required this.onChooseDay,
  });
  final AppController controller;
  final DateTime day;
  final VoidCallback? onChooseDay;

  @override
  Widget build(BuildContext context) {
    final today = DateUtils.isSameDay(day, DateTime.now());
    final label = today
        ? 'Today'
        : DateFormat(
            day.year == DateTime.now().year ? 'E, MMM' : 'MMM yyyy',
          ).format(day);
    final iconScale = MediaQuery.textScalerOf(context).scale(14) / 14 * .75;
    final base = DefaultTextStyle.of(context).style.copyWith(
      color: logPalette(context).actionInk,
      height: 1,
      letterSpacing: 0,
    );
    return Row(
      children: [
        Expanded(
          child: BabyPickerButton(
            controller: controller,
            showChevron: false,
            identity: HeaderType(
              controller.family!.babyName,
              style: base.copyWith(fontSize: 26, fontWeight: FontWeight.w700),
            ),
          ),
        ),
        if (onChooseDay != null) ...[
          const SizedBox(width: 20),
          Flexible(
            fit: FlexFit.tight,
            child: TextButton(
              key: const ValueKey('log-day-picker'),
              onPressed: onChooseDay,
              style: TextButton.styleFrom(
                padding: EdgeInsets.zero,
                minimumSize: const Size(44, 44),
                alignment: Alignment.centerRight,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: HeaderType(
                      label,
                      style: base.copyWith(
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Semantics(
                    label: DateFormat.yMMMMd().format(day),
                    child: Transform.translate(
                      // Center the numeral in the open calendar body.
                      offset: Offset(0, -1.5 * iconScale),
                      child: CustomPaint(
                        size: Size(28 * iconScale, 32 * iconScale),
                        painter: _CalendarDay(
                          day.day,
                          base.copyWith(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                          ),
                          Directionality.of(context),
                          iconScale,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// Lay out text around its cap-height rather than the font's leading.
/// Text remains a native accessible widget and respects system text scaling.
class HeaderType extends StatelessWidget {
  const HeaderType(this.text, {super.key, required this.style});
  final String text;
  final TextStyle style;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final scaler = MediaQuery.textScalerOf(context);
      final painter = TextPainter(
        text: TextSpan(text: text, style: style),
        textDirection: Directionality.of(context),
        textScaler: scaler,
        maxLines: 1,
        ellipsis: '…',
      )..layout(maxWidth: constraints.maxWidth);
      final width = painter.width;
      final height = painter.height;
      final baseline = painter.computeDistanceToActualBaseline(
        TextBaseline.alphabetic,
      );
      final capHeight = scaler.scale(style.fontSize!) * .71;
      painter.dispose();
      return SizedBox(
        width: width,
        height: capHeight,
        child: OverflowBox(
          alignment: Alignment.topLeft,
          minWidth: width,
          maxWidth: width,
          minHeight: height,
          maxHeight: height,
          child: Transform.translate(
            offset: Offset(0, capHeight - baseline),
            child: Text(
              text,
              style: style,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
      );
    },
  );
}

/// Largest common numeral size for all month days in the existing 28x32 geometry.
/// The 0.65 optical inset leaves 23.7 px between the inner frame edges.
double calendarDayFontSize(TextStyle style, TextDirection direction) {
  const maxWidth = 23.7;
  const maxCapHeight = 22.0;
  var widest = 0.0;
  for (var day = 1; day <= 31; day++) {
    final text = TextPainter(
      text: TextSpan(text: '$day', style: style.copyWith(fontSize: 20)),
      textDirection: direction,
    )..layout();
    if (text.width > widest) widest = text.width;
    text.dispose();
  }
  var candidate = (maxWidth * 20 / widest).clamp(0.0, maxCapHeight / .71);
  candidate = (candidate * 10).floor() / 10;
  // Recheck at the chosen size to account for font hinting and optical sizing.
  while (candidate > 0) {
    var fits = true;
    for (var day = 1; day <= 31; day++) {
      final text = TextPainter(
        text: TextSpan(
          text: '$day',
          style: style.copyWith(fontSize: candidate),
        ),
        textDirection: direction,
      )..layout();
      fits = fits && text.width <= maxWidth;
      text.dispose();
    }
    if (fits) return candidate;
    candidate = ((candidate * 10).round() - 1) / 10;
  }
  return 14;
}

class _CalendarDay extends CustomPainter {
  const _CalendarDay(this.day, this.style, this.direction, this.scale);
  final int day;
  final TextStyle style;
  final TextDirection direction;
  final double scale;
  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(scale);
    final stroke = Paint()
      ..color = style.color!
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(.75, 3.75, 26.5, 27.5),
        const Radius.circular(4),
      ),
      stroke,
    );
    canvas.drawLine(const Offset(6.75, .75), const Offset(6.75, 6.25), stroke);
    canvas.drawLine(
      const Offset(21.25, .75),
      const Offset(21.25, 6.25),
      stroke,
    );
    final fontSize = calendarDayFontSize(style, direction);
    final text = TextPainter(
      text: TextSpan(
        text: '$day',
        style: style.copyWith(fontSize: fontSize),
      ),
      textDirection: direction,
    )..layout();
    final baseline = text.computeDistanceToActualBaseline(
      TextBaseline.alphabetic,
    );
    // The outline and date well are fixed geometry; the numeral has one optical inset.
    text.paint(
      canvas,
      Offset((28 - text.width) / 2 - .65, 17.5 + fontSize * .71 / 2 - baseline),
    );
    text.dispose();
    canvas.restore();
  }

  @override
  bool shouldRepaint(_CalendarDay old) =>
      old.day != day ||
      old.style != style ||
      old.direction != direction ||
      old.scale != scale;
}
