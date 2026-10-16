import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'activity_glyph.dart';

const elapsedIconActivities = {
  'bottle',
  'nursing',
  'diaper',
  'sleep',
  'pumping',
  'solids',
};

typedef ElapsedIconLabel = ({String primary, String secondary, String spoken});

/// Optical parameters for the isolated design study. No time value changes
/// the outline, tint, or stroke: these remain category identity, never a gauge.
@immutable
class ElapsedGlyphDesign {
  const ElapsedGlyphDesign({
    this.stroke = .95,
    this.weight = FontWeight.w500,
    this.fontFamily,
    this.textWidth = 1,
    this.bodyWidth = 1,
    this.typeSize = 1,
    this.curvedMoon = false,
    this.singleLine = false,
    this.wash = 0,
    this.name = 'Original',
    this.polished = false,
    this.selectiveWidth = false,
  });
  final double stroke, textWidth, bodyWidth, typeSize, wash;
  final FontWeight weight;
  final String? fontFamily;
  final bool curvedMoon, singleLine;
  final bool polished, selectiveWidth;
  final String name;
}

ElapsedIconLabel elapsedIconLabel(Duration? elapsed) {
  if (elapsed == null) {
    return (primary: '—', secondary: '', spoken: 'No previous log');
  }
  if (elapsed > const Duration(days: 1)) {
    return (primary: '>1d', secondary: '', spoken: 'More than one day ago');
  }
  if (elapsed == const Duration(days: 1)) {
    return (primary: '1d', secondary: '', spoken: 'One day ago');
  }
  if (elapsed.inMinutes <= 0) {
    return (primary: 'now', secondary: '', spoken: 'Just now');
  }
  String unit(int count, String name) => '$count $name${count == 1 ? '' : 's'}';
  if (elapsed.inHours == 0) {
    return (
      primary: '${elapsed.inMinutes}m',
      secondary: '',
      spoken: '${unit(elapsed.inMinutes, 'minute')} ago',
    );
  }
  final minutes = elapsed.inMinutes % 60;
  return (
    primary: '${elapsed.inHours}h',
    secondary: minutes == 0 ? '' : '${minutes}m',
    spoken:
        '${unit(elapsed.inHours, 'hour')}${minutes == 0 ? '' : ' and ${unit(minutes, 'minute')}'} ago',
  );
}

/// Prototype glyph: elapsed time is drawn within the category silhouette.
/// Only the six frequent activities encode time. Existing CareGlyph callers
/// continue to use their original compact icons.
class ElapsedActivityGlyph extends StatelessWidget {
  const ElapsedActivityGlyph({
    super.key,
    required this.method,
    required this.label,
    required this.fallback,
    required this.elapsed,
    required this.color,
    this.size = 96,
    this.design = const ElapsedGlyphDesign(),
  });

  final String method;
  final String label;
  final IconData fallback;
  final Duration? elapsed;
  final Color color;
  final double size;
  final ElapsedGlyphDesign design;

  @override
  Widget build(BuildContext context) {
    if (!elapsedIconActivities.contains(method)) {
      return CareGlyph(
        method: method,
        fallback: fallback,
        size: size,
        color: color,
      );
    }
    final text = elapsedIconLabel(elapsed);
    // Grow the artwork with accessibility text instead of shrinking the time
    // until it fits inside an unchanged outline.
    final side = size * MediaQuery.textScalerOf(context).scale(16) / 16;
    return Semantics(
      label: '$label · ${text.spoken}',
      child: ExcludeSemantics(
        child: SizedBox.square(
          dimension: side,
          child: TweenAnimationBuilder<double>(
            key: ValueKey('${text.primary}/${text.secondary}'),
            tween: Tween(begin: design.polished ? .94 : 1, end: 1),
            duration: MediaQuery.disableAnimationsOf(context)
                ? Duration.zero
                : const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            builder: (context, progress, child) => CustomPaint(
              painter: _ElapsedPainter(
                method: method,
                text: text,
                color: color,
                fontFamily: Theme.of(context).textTheme.bodyMedium?.fontFamily,
                design: design,
                textProgress: progress,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ElapsedPainter extends CustomPainter {
  const _ElapsedPainter({
    required this.method,
    required this.text,
    required this.color,
    required this.fontFamily,
    required this.design,
    required this.textProgress,
  });

  final String method;
  final ElapsedIconLabel text;
  final Color color;
  final String? fontFamily;
  final ElapsedGlyphDesign design;
  final double textProgress;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 32, size.height / 32);
    canvas.translate(16, 16);
    final bodyWidth = design.selectiveWidth
        ? switch (method) {
            'bottle' || 'pumping' => design.bodyWidth,
            'nursing' || 'diaper' => .92,
            _ => 1.0,
          }
        : design.bodyWidth;
    canvas.scale(bodyWidth, 1);
    canvas.translate(-16, -16);
    final pen = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = design.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    void line(double x1, double y1, double x2, double y2) {
      canvas.drawLine(Offset(x1, y1), Offset(x2, y2), pen);
    }

    void circle(double x, double y, double r) {
      canvas.drawCircle(Offset(x, y), r, pen);
    }

    final wash = Paint()..color = color.withValues(alpha: design.wash);

    var anchor = const Offset(16, 20);
    var availableWidth = 12.0;
    if (method == 'bottle' || method == 'pumping') {
      if (design.polished && design.wash > 0) {
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            const Rect.fromLTWH(9, 11, 14, 19),
            const Radius.circular(3),
          ),
          wash,
        );
      }
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          const Rect.fromLTWH(9, 11, 14, 19),
          const Radius.circular(3),
        ),
        pen,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          const Rect.fromLTWH(9, 8, 14, 3),
          const Radius.circular(1),
        ),
        pen,
      );
      canvas.drawPath(
        Path()
          ..moveTo(12, 8)
          ..lineTo(12, 5)
          ..lineTo(14, 5)
          ..lineTo(14, 3)
          ..quadraticBezierTo(16, 0, 18, 3)
          ..lineTo(18, 5)
          ..lineTo(20, 5)
          ..lineTo(20, 8),
        pen,
      );
      if (method == 'pumping') {
        line(21, 5, 28, 5);
        line(28, 5, 28, 11);
      }
      // A single line uses the bottle's height, with consistent lettering
      // for the hours, minutes, and units.
      canvas.save();
      canvas.translate(16, 20.5);
      canvas.rotate(text.primary == '—' ? 0 : -math.pi / 2);
      _paintText(
        canvas,
        text.primary + text.secondary,
        Offset.zero,
        fontSize: 5.6,
        maxWidth: 16.5,
      );
      canvas.restore();
      canvas.restore();
      return;
    } else if (method == 'diaper') {
      if (design.polished && design.wash > 0) {
        canvas.drawPath(
          Path()
            ..moveTo(4, 12)
            ..lineTo(28, 12)
            ..lineTo(27, 20)
            ..quadraticBezierTo(26, 27, 16, 29)
            ..quadraticBezierTo(6, 27, 5, 20)
            ..close(),
          wash,
        );
      }
      canvas.drawPath(
        Path()
          ..moveTo(3, 8)
          ..lineTo(29, 8)
          ..lineTo(27, 20)
          ..quadraticBezierTo(26, 27, 16, 29)
          ..quadraticBezierTo(6, 27, 5, 20)
          ..close(),
        pen,
      );
      line(4, 12, 28, 12);
      canvas.drawPath(
        Path()
          ..moveTo(5, 17)
          ..quadraticBezierTo(
            design.singleLine && design.polished ? 8.5 : 10,
            18,
            design.singleLine && design.polished ? 8.5 : 10,
            26,
          )
          ..moveTo(27, 17)
          ..quadraticBezierTo(
            design.singleLine && design.polished ? 23.5 : 22,
            18,
            design.singleLine && design.polished ? 23.5 : 22,
            26,
          ),
        pen,
      );
      anchor = Offset(16, design.polished ? 20 : 20.5);
      availableWidth = design.singleLine && design.polished ? 14 : 11;
    } else if (method == 'nursing') {
      if (design.polished && design.wash > 0) {
        canvas.drawPath(
          Path()
            ..moveTo(6, 20)
            ..quadraticBezierTo(17, 24, 28, 20)
            ..quadraticBezierTo(30, 24, 26, 29)
            ..lineTo(7, 29)
            ..close(),
          wash,
        );
      }
      circle(9, 5, 3);
      circle(22, 11, 2.7);
      canvas.drawPath(
        Path()
          ..moveTo(6, 11)
          ..quadraticBezierTo(2, 19, 7, 29)
          ..lineTo(26, 29)
          ..quadraticBezierTo(30, 24, 28, 20)
          ..moveTo(11, 11)
          ..lineTo(14, 16)
          ..lineTo(27, 19)
          ..quadraticBezierTo(21, 22, 13, 17),
        pen,
      );
      line(14, 16, 18, 13);
      anchor = Offset(18, design.polished ? 24.3 : 25);
      availableWidth = 16;
    } else if (method == 'sleep') {
      final moon = design.polished
          ? (Path()
              ..moveTo(29, 17)
              ..cubicTo(22, 20, 15, 12, 17, 3)
              ..cubicTo(1, 3, 0, 32, 18, 29)
              ..cubicTo(23, 28, 27, 24, 29, 17)
              ..close())
          : (Path()
              ..moveTo(28, 20)
              ..cubicTo(17, 24, 7, 13, 13, 3)
              ..cubicTo(-3, 7, 7, 39, 28, 20)
              ..close());
      if (design.wash > 0) {
        canvas.drawPath(
          moon,
          Paint()..color = color.withValues(alpha: design.wash),
        );
      }
      canvas.drawPath(moon, pen);
      if (design.curvedMoon) {
        _paintCurve(canvas, text.primary + text.secondary);
        canvas.restore();
        return;
      }
      anchor = design.polished
          ? const Offset(14.5, 21)
          : const Offset(22, 11.5);
      availableWidth = design.polished ? 13 : 14;
    } else if (method == 'solids') {
      if (design.polished && design.wash > 0) {
        canvas.drawCircle(const Offset(16, 18), 10, wash);
      }
      circle(16, 18, 10);
      if (!design.polished) {
        canvas.drawCircle(
          const Offset(16, 18),
          8.5,
          Paint()
            ..color = color.withValues(alpha: .16)
            ..style = PaintingStyle.stroke
            ..strokeWidth = .95,
        );
      }
      canvas.drawPath(
        Path()
          ..moveTo(1, 7)
          ..lineTo(1, 13)
          ..quadraticBezierTo(3, 16, 5, 13)
          ..lineTo(5, 7),
        pen,
      );
      line(3, 7, 3, 29);
      canvas.drawOval(const Rect.fromLTWH(27, 7, 4, 8), pen);
      line(29, 15, 29, 29);
      anchor = const Offset(16, 18);
      availableWidth = 16;
    }

    // The blanket is shallow; long hour/minute strings use its full width.
    // A long diaper/plate inscription instead uses two rows to keep digits
    // readable, rather than squeezing increasingly long single-line type.
    final longValue = text.primary.length >= 3 && text.secondary.length >= 3;
    final singleLine =
        method == 'nursing' && design.polished ||
        design.singleLine && !(design.polished && longValue);
    final twoLines = text.secondary.isNotEmpty && !singleLine;
    _paintText(
      canvas,
      text.primary +
          (singleLine && text.secondary.isNotEmpty
              ? '${design.polished ? ' ' : ''}${text.secondary}'
              : ''),
      anchor.translate(0, twoLines ? -2.1 : 0),
      fontSize: 5.2,
      maxWidth: availableWidth,
    );
    if (twoLines) {
      _paintText(
        canvas,
        text.secondary,
        anchor.translate(0, 3),
        fontSize: 4.4,
        maxWidth: availableWidth,
        weight: design.weight,
      );
    }
    canvas.restore();
  }

  void _paintText(
    Canvas canvas,
    String value,
    Offset center, {
    required double fontSize,
    required double maxWidth,
    FontWeight? weight,
  }) {
    final painter = TextPainter(
      text: TextSpan(
        text: value,
        style: TextStyle(
          color: color,
          fontFamily: design.fontFamily ?? fontFamily,
          fontSize: fontSize * design.typeSize,
          fontWeight: weight ?? design.weight,
        ),
      ),
      textDirection: TextDirection.ltr,
      textScaler: TextScaler.noScaling,
    )..layout();
    canvas.save();
    canvas.translate(center.dx, center.dy);
    final fit = math.min(1.0, maxWidth / (painter.width * design.textWidth));
    canvas.scale(fit * design.textWidth * textProgress, fit * textProgress);
    painter.paint(canvas, Offset(-painter.width / 2, -painter.height / 2));
    canvas.restore();
    painter.dispose();
  }

  // Typography follows a fixed inner lunar curve. It conveys elapsed text,
  // never a time-normalized arc. Whole letters are rotated along the tangent.
  void _paintCurve(Canvas canvas, String value) {
    final arc = design.polished
        ? (Path()
            ..moveTo(8, 21)
            ..quadraticBezierTo(15, 27, 25, 23))
        : (Path()
            ..moveTo(7.5, 18.5)
            ..quadraticBezierTo(11, 29, 24.5, 24));
    final metric = arc.computeMetrics().first;
    final letters = <TextPainter>[];
    for (final character in value.split('')) {
      letters.add(
        TextPainter(
          text: TextSpan(
            text: character,
            style: TextStyle(
              color: color,
              fontFamily: design.fontFamily ?? fontFamily,
              fontSize: 4.5 * design.typeSize,
              fontWeight: design.weight,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout(),
      );
    }
    final width = letters.fold<double>(
      0,
      (sum, p) => sum + p.width * design.textWidth,
    );
    final fit = math.min(1.0, (metric.length - 2) / width);
    var distance = (metric.length - width * fit) / 2;
    for (final letter in letters) {
      final advance = letter.width * design.textWidth * fit;
      final tangent = metric.getTangentForOffset(distance + advance / 2)!;
      canvas.save();
      canvas.translate(tangent.position.dx, tangent.position.dy);
      canvas.rotate(tangent.angle);
      canvas.scale(fit * design.textWidth * textProgress, fit * textProgress);
      letter.paint(canvas, Offset(-letter.width / 2, -letter.height / 2));
      canvas.restore();
      distance += advance;
      letter.dispose();
    }
  }

  @override
  bool shouldRepaint(_ElapsedPainter old) =>
      method != old.method ||
      text != old.text ||
      color != old.color ||
      fontFamily != old.fontFamily ||
      design != old.design ||
      textProgress != old.textProgress;
}
