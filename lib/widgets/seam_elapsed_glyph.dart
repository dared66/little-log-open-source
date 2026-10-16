import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'elapsed_activity_glyph.dart';

/// Elapsed lettering replaces a measured section of the activity's contour.
/// Time changes the inscription only, never the color or shape.
class SeamElapsedGlyph extends StatelessWidget {
  const SeamElapsedGlyph({
    super.key,
    required this.method,
    required this.label,
    required this.elapsed,
    required this.color,
    this.size = 64,
    this.fontFamily,
  });
  final String method, label;
  final Duration? elapsed;
  final Color color;
  final double size;
  final String? fontFamily;

  @override
  Widget build(BuildContext context) {
    final value = elapsedIconLabel(elapsed);
    final side = size * MediaQuery.textScalerOf(context).scale(16) / 16;
    return Semantics(
      label: '$label · ${value.spoken}',
      child: ExcludeSemantics(
        child: SizedBox.square(
          dimension: side,
          child: TweenAnimationBuilder<double>(
            key: ValueKey('${value.primary}/${value.secondary}'),
            tween: Tween(begin: .97, end: 1),
            duration: MediaQuery.disableAnimationsOf(context)
                ? Duration.zero
                : const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
            builder: (context, registration, _) => CustomPaint(
              painter: SeamElapsedPainter(
                method: method,
                value: value,
                color: color,
                fontFamily:
                    fontFamily ??
                    Theme.of(context).textTheme.bodyMedium?.fontFamily,
                registration: registration,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class SeamElapsedPainter extends CustomPainter {
  const SeamElapsedPainter({
    required this.method,
    required this.value,
    required this.color,
    this.fontFamily,
    this.registration = 1,
  });
  final String method;
  final ElapsedIconLabel value;
  final Color color;
  final String? fontFamily;
  final double registration;
  String get inscription =>
      value.primary + (value.secondary.isEmpty ? '' : ' ${value.secondary}');

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    // Retain the contour's proportions even under an unusually tight parent.
    final side = math.min(size.width, size.height);
    canvas.translate((size.width - side) / 2, (size.height - side) / 2);
    canvas.scale(side / 64);
    canvas.clipRect(const Rect.fromLTWH(0, 0, 64, 64));
    seam(canvas);
    canvas.restore();
  }

  Paint pen({Color? ink, double width = 2}) => Paint()
    ..color = ink ?? color
    ..style = PaintingStyle.stroke
    ..strokeWidth = width
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round;
  Paint fill({Color? ink}) => Paint()..color = ink ?? color;
  void line(
    Canvas c,
    double x,
    double y,
    double xx,
    double yy, {
    double width = 2,
  }) => c.drawLine(Offset(x, y), Offset(xx, yy), pen(width: width));
  void circle(Canvas c, double x, double y, double r, {bool solid = false}) =>
      c.drawCircle(Offset(x, y), r, solid ? fill() : pen());
  void bottleNeck(Canvas c, {bool solid = false}) {
    final neck = Path()
      ..moveTo(23, 16)
      ..lineTo(23, 10)
      ..lineTo(28, 10)
      ..lineTo(28, 6)
      ..quadraticBezierTo(32, 0, 36, 6)
      ..lineTo(36, 10)
      ..lineTo(41, 10)
      ..lineTo(41, 16)
      ..close();
    c.drawPath(neck, solid ? fill() : pen());
    c.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(16, 16, 32, 7),
        const Radius.circular(2),
      ),
      solid ? fill() : pen(),
    );
    if (method == 'pumping') {
      line(c, 41, 10, 58, 10);
      line(c, 58, 10, 58, 23);
    }
  }

  /// Text and surviving stroke use exactly the same path. The gap follows
  /// the measured run width; glyphs share one baseline and its true tangent.
  void seamOnPath(
    Canvas c,
    Path path,
    String label, {
    double fontSize = 11,
    double maxGapFraction = .86,
    double padding = 2,
  }) {
    final metric = path.computeMetrics().first;
    if (label == '—') {
      // No elapsed record: retain the complete recognizable contour.
      c.drawPath(path, pen());
      return;
    }
    TextPainter measure(String text, double size) => TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          fontFamily: fontFamily,
          fontSize: size,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final natural = measure(label, fontSize);
    final available = metric.length * maxGapFraction - 2 * padding;
    final fittedSize = fontSize * math.min(1.0, available / natural.width);
    natural.dispose();
    final run = measure(label, fittedSize);
    final width = run.width * registration;
    final start = (metric.length - width) / 2;
    final gapStart = math.max(0.0, start - padding);
    // A small terminal optical allowance keeps curved unit letters from
    // crowding the round cap; glyph positions still follow the same path.
    final gapEnd = math.min(
      metric.length,
      start + width + padding + fittedSize * .035,
    );
    c.drawPath(metric.extractPath(0, gapStart), pen());
    c.drawPath(metric.extractPath(gapEnd, metric.length), pen());
    var previousWidth = 0.0;
    for (var i = 0; i < label.length; i++) {
      // Prefix advances retain the typeface's real spacing and kerning.
      final prefix = measure(label.substring(0, i + 1), fittedSize);
      final advance = prefix.width - previousWidth;
      final letter = measure(label[i], fittedSize);
      final distance = start + (previousWidth + advance / 2) * registration;
      final tangent = metric.getTangentForOffset(distance)!;
      final baseline = letter.computeLineMetrics().first.baseline;
      c.save();
      c.translate(tangent.position.dx, tangent.position.dy);
      // Canvas rotation uses screen-space y-down coordinates. Tangent.angle
      // negates atan2, so use the vector directly to follow this contour.
      c.rotate(math.atan2(tangent.vector.dy, tangent.vector.dx));
      c.scale(registration);
      // A common cap-height center anchors every glyph to the contour;
      // differing x-heights do not create independently bobbing letters.
      letter.paint(c, Offset(-letter.width / 2, -baseline + fittedSize * .35));
      c.restore();
      previousWidth = prefix.width;
      prefix.dispose();
      letter.dispose();
    }
    run.dispose();
  }

  void seam(Canvas c) {
    if (method == 'bottle' || method == 'pumping') {
      bottleNeck(c);
      // Both walls meet the existing collar at x16/x48. Rounded base
      // tangents join the straight sides without the previous inward kink.
      c.drawPath(
        Path()
          ..moveTo(48, 55)
          ..quadraticBezierTo(48, 62, 41, 62)
          ..lineTo(23, 62)
          ..quadraticBezierTo(16, 62, 16, 55)
          ..lineTo(16, 23),
        pen(),
      );
      seamOnPath(
        c,
        Path()
          ..moveTo(48, 55)
          ..lineTo(48, 23),
        value.primary + value.secondary,
        maxGapFraction: .92,
      );
    } else if (method == 'nursing') {
      circle(c, 18, 10, 5);
      circle(c, 44, 22, 4);
      c.drawPath(
        Path()
          ..moveTo(12, 23)
          ..cubicTo(5, 34, 5, 50, 14, 55)
          ..moveTo(53, 55)
          ..cubicTo(62, 50, 60, 43, 53, 38)
          ..moveTo(22, 23)
          ..lineTo(29, 32)
          ..lineTo(53, 38)
          ..quadraticBezierTo(38, 44, 24, 35),
        pen(),
      );
      line(c, 29, 32, 40, 23);
      seamOnPath(
        c,
        Path()
          ..moveTo(14, 55)
          ..cubicTo(23, 60, 44, 60, 53, 55),
        inscription,
      );
    } else if (method == 'diaper') {
      c.drawPath(
        Path()
          ..moveTo(57, 16)
          ..lineTo(52, 42)
          ..quadraticBezierTo(48, 57, 32, 59)
          ..quadraticBezierTo(16, 57, 12, 42)
          ..lineTo(7, 16),
        pen(),
      );
      line(c, 9, 25, 55, 25);
      // Leg seams meet the actual side and lower curves, rather than
      // ending at free-floating points inside the diaper silhouette.
      c.drawPath(
        Path()
          ..moveTo(10.654, 35)
          ..quadraticBezierTo(23, 37, 22.27, 56.015)
          ..moveTo(53.346, 35)
          ..quadraticBezierTo(41, 37, 41.73, 56.015),
        pen(),
      );
      seamOnPath(
        c,
        Path()
          ..moveTo(7, 16)
          ..lineTo(57, 16),
        inscription,
      );
    } else if (method == 'sleep') {
      const circle = Rect.fromLTWH(6, 5, 52, 52);
      final end = Offset(32 + 26 / math.sqrt2, 31 + 26 / math.sqrt2);
      // Circular outer crescent; only its bottom quarter carries the run.
      c.drawPath(
        Path()
          ..moveTo(end.dx, end.dy)
          ..arcTo(circle, math.pi / 4, .2 - math.pi / 4, false)
          ..cubicTo(40, 40, 28, 23, 32, 5)
          ..arcTo(circle, -math.pi / 2, -3 * math.pi / 4, false),
        pen(),
      );
      seamOnPath(
        c,
        Path()..addArc(circle, 3 * math.pi / 4, -math.pi / 2),
        inscription,
        maxGapFraction: .8,
      );
    } else {
      for (final x in [2.0, 5.0, 8.0]) {
        line(c, x, 14, x, 22, width: 1.6);
      }
      c.drawPath(
        Path()
          ..moveTo(2, 22)
          ..quadraticBezierTo(2, 27, 5, 27)
          ..quadraticBezierTo(8, 27, 8, 22),
        pen(width: 1.6),
      );
      line(c, 5, 27, 5, 58, width: 1.6);
      c.drawOval(const Rect.fromLTWH(57, 14, 5, 13), pen());
      line(c, 59.5, 27, 59.5, 58);
      const circle = Rect.fromLTWH(10, 11, 44, 44);
      c.drawPath(Path()..addArc(circle, math.pi / 4, -3 * math.pi / 2), pen());
      seamOnPath(
        c,
        Path()..addArc(circle, 3 * math.pi / 4, -math.pi / 2),
        inscription,
      );
    }
  }

  @override
  bool shouldRepaint(covariant SeamElapsedPainter oldDelegate) =>
      method != oldDelegate.method ||
      value != oldDelegate.value ||
      color != oldDelegate.color ||
      fontFamily != oldDelegate.fontFamily ||
      registration != oldDelegate.registration;
}
