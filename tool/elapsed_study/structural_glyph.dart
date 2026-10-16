import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:little_log/widgets/elapsed_activity_glyph.dart';
import 'package:little_log/widgets/seam_elapsed_glyph.dart';

enum IconConstruction { seam, cutout, landscape, numeral, folded }

/// A second study that changes object construction, rather than optical styling.
class StructuralElapsedGlyph extends StatelessWidget {
  const StructuralElapsedGlyph({
    super.key,
    required this.method,
    required this.label,
    required this.elapsed,
    required this.color,
    required this.background,
    required this.construction,
    this.size = 96,
  });
  final String method, label;
  final Duration? elapsed;
  final Color color, background;
  final IconConstruction construction;
  final double size;
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
            builder: (context, registration, child) => CustomPaint(
              painter: _StructuralPainter(
                method: method,
                value: value,
                color: color,
                background: background,
                construction: construction,
                registration: registration,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _StructuralPainter extends CustomPainter {
  const _StructuralPainter({
    required this.method,
    required this.value,
    required this.color,
    required this.background,
    required this.construction,
    required this.registration,
  });
  final String method;
  final ElapsedIconLabel value;
  final Color color, background;
  final IconConstruction construction;
  final double registration;
  String get inscription =>
      value.primary + (value.secondary.isEmpty ? '' : ' ${value.secondary}');

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 64, size.height / 64);
    canvas.clipRect(const Rect.fromLTWH(0, 0, 64, 64));
    if (construction == IconConstruction.numeral && value.primary == '—') {
      seam(canvas);
    } else {
      switch (construction) {
        case IconConstruction.seam:
          seam(canvas);
        case IconConstruction.cutout:
          cutout(canvas);
        case IconConstruction.landscape:
          landscape(canvas);
        case IconConstruction.numeral:
          numeral(canvas);
        case IconConstruction.folded:
          folded(canvas);
      }
    }
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
  void text(
    Canvas c,
    String text,
    Offset center, {
    double fontSize = 11,
    double maxWidth = 40,
    Color? ink,
    double angle = 0,
    FontWeight weight = FontWeight.w600,
  }) {
    final p = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          fontFamily:
              construction == IconConstruction.cutout ||
                  construction == IconConstruction.numeral
              ? 'StudyRounded'
              : 'StudyCompact',
          fontSize: fontSize,
          fontWeight: weight,
          color: ink ?? color,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    c.save();
    c.translate(center.dx, center.dy);
    c.rotate(angle);
    final fit = math.min(1.0, maxWidth / p.width);
    c.scale(fit * registration);
    p.paint(c, Offset(-p.width / 2, -p.height / 2));
    c.restore();
    p.dispose();
  }

  void curveText(
    Canvas c,
    String text,
    Path path, {
    double fontSize = 10,
    Color? ink,
  }) {
    final metric = path.computeMetrics().first;
    final letters = <TextPainter>[];
    for (final char in text.split('')) {
      letters.add(
        TextPainter(
          text: TextSpan(
            text: char,
            style: TextStyle(
              fontFamily: construction == IconConstruction.cutout
                  ? 'StudyRounded'
                  : 'StudyCompact',
              fontSize: fontSize,
              fontWeight: FontWeight.w600,
              color: ink ?? color,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout(),
      );
    }
    final width = letters.fold<double>(0, (sum, p) => sum + p.width);
    final fit = math.min(1.0, (metric.length - 4) / width);
    var distance = (metric.length - width * fit) / 2;
    for (final p in letters) {
      final tangent = metric.getTangentForOffset(distance + p.width * fit / 2)!;
      c.save();
      c.translate(tangent.position.dx, tangent.position.dy);
      c.rotate(tangent.angle.clamp(-math.pi / 9, math.pi / 9));
      c.scale(fit * registration);
      p.paint(c, Offset(-p.width / 2, -p.height / 2));
      c.restore();
      distance += p.width * fit;
      p.dispose();
    }
  }

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

  void utensils(Canvas c, {bool solid = false}) {
    final width = solid ? 3.3 : 2.0;
    line(c, 3, 14, 3, 22, width: width);
    line(c, 7, 14, 7, 22, width: width);
    c.drawPath(
      Path()
        ..moveTo(3, 22)
        ..quadraticBezierTo(5, 28, 7, 22),
      pen(width: width),
    );
    line(c, 5, 26, 5, 58, width: width);
    c.drawOval(const Rect.fromLTWH(57, 14, 5, 13), solid ? fill() : pen());
    line(c, 59.5, 27, 59.5, 58, width: width);
  }

  Path get diaper => Path()
    ..moveTo(7, 16)
    ..lineTo(57, 16)
    ..lineTo(52, 42)
    ..quadraticBezierTo(48, 57, 32, 59)
    ..quadraticBezierTo(16, 57, 12, 42)
    ..close();
  Path get moon => Path()
    ..moveTo(33, 5)
    ..cubicTo(28, 23, 40, 40, 57, 36)
    ..cubicTo(50, 56, 31, 65, 15, 52)
    ..cubicTo(-4, 37, 6, 8, 33, 5)
    ..close();

  void seam(Canvas c) => SeamElapsedPainter(
    method: method,
    value: value,
    color: color,
    fontFamily: 'StudyCompact',
    registration: registration,
  ).paint(c, const Size(64, 64));

  void landscape(Canvas c) {
    if (method == 'bottle' || method == 'pumping') {
      c.drawRRect(
        RRect.fromRectAndRadius(
          const Rect.fromLTWH(19, 21, 41, 25),
          const Radius.circular(7),
        ),
        pen(),
      );
      c.drawRRect(
        RRect.fromRectAndRadius(
          const Rect.fromLTWH(12, 24, 7, 19),
          const Radius.circular(2),
        ),
        pen(),
      );
      c.drawPath(
        Path()
          ..moveTo(12, 27)
          ..lineTo(7, 27)
          ..lineTo(7, 30)
          ..quadraticBezierTo(0, 33.5, 7, 37)
          ..lineTo(7, 40)
          ..lineTo(12, 40),
        pen(),
      );
      if (method == 'pumping') {
        line(c, 16, 24, 16, 10);
        line(c, 16, 10, 5, 10);
      }
      text(c, inscription, const Offset(39, 33), fontSize: 11.5, maxWidth: 34);
    } else if (method == 'nursing') {
      circle(c, 13, 13, 5);
      circle(c, 44, 26, 4);
      c.drawPath(
        Path()
          ..moveTo(10, 23)
          ..cubicTo(4, 42, 18, 55, 35, 56)
          ..moveTo(22, 32)
          ..quadraticBezierTo(42, 26, 57, 36)
          ..quadraticBezierTo(61, 48, 37, 52)
          ..quadraticBezierTo(15, 49, 22, 32)
          ..moveTo(23, 23)
          ..quadraticBezierTo(22, 30, 35, 33),
        pen(),
      );
      text(c, inscription, const Offset(39, 41), fontSize: 11, maxWidth: 29);
    } else if (method == 'diaper') {
      c.drawRRect(
        RRect.fromRectAndRadius(
          const Rect.fromLTWH(2, 23, 19, 11),
          const Radius.circular(3),
        ),
        pen(),
      );
      c.drawRRect(
        RRect.fromRectAndRadius(
          const Rect.fromLTWH(43, 23, 19, 11),
          const Radius.circular(3),
        ),
        pen(),
      );
      c.drawPath(
        Path()
          ..moveTo(20, 24)
          ..lineTo(44, 24)
          ..lineTo(48, 44)
          ..quadraticBezierTo(45, 54, 32, 55)
          ..quadraticBezierTo(19, 54, 16, 44)
          ..close(),
        pen(),
      );
      line(c, 20, 31, 44, 31);
      text(c, inscription, const Offset(32, 43), fontSize: 11, maxWidth: 27);
    } else if (method == 'sleep') {
      c.drawPath(
        Path()
          ..moveTo(6, 24)
          ..cubicTo(19, 46, 48, 44, 58, 17)
          ..cubicTo(61, 39, 37, 66, 16, 51)
          ..cubicTo(8, 44, 5, 34, 6, 24)
          ..close(),
        pen(),
      );
      curveText(
        c,
        inscription,
        Path()
          ..moveTo(15, 42)
          ..quadraticBezierTo(34, 55, 52, 34),
        fontSize: 11,
      );
    } else {
      c.drawOval(const Rect.fromLTWH(11, 22, 43, 11), pen());
      c.drawPath(
        Path()
          ..moveTo(11, 27)
          ..quadraticBezierTo(12, 50, 32, 52)
          ..quadraticBezierTo(52, 50, 54, 27),
        pen(),
      );
      utensils(c);
      text(c, inscription, const Offset(32, 42), fontSize: 11, maxWidth: 31);
    }
  }

  // The main elapsed digits occupy the space otherwise filled by the object.
  // Small recognition fragments complete the category, without a time badge.
  void architectedNumber(
    Canvas c, {
    Color? ink,
    Offset center = const Offset(29, 40),
    double fontSize = 31,
    double maxWidth = 37,
    double secondaryFontSize = 11,
    double secondaryShift = 17,
    double secondaryMaxWidth = 34,
  }) {
    final display = value.primary == 'now' ? '0m' : value.primary;
    final match = RegExp(r'^(>?)(\d+)([hmd])$').firstMatch(display);
    if (match == null) {
      text(
        c,
        value.primary,
        center,
        fontSize: 23,
        maxWidth: 45,
        ink: ink,
        weight: FontWeight.w700,
      );
    } else {
      text(
        c,
        match[2]!,
        center,
        fontSize: fontSize,
        maxWidth: maxWidth,
        ink: ink,
        weight: FontWeight.w700,
      );
      text(
        c,
        match[3]!,
        center.translate(match[2]!.length == 1 ? 13 : 23, 6),
        fontSize: 11,
        maxWidth: 12,
        ink: ink,
      );
      if (match[1]!.isNotEmpty) {
        text(
          c,
          '>',
          center.translate(-19, 0),
          fontSize: 11,
          maxWidth: 10,
          ink: ink,
        );
      }
    }
    if (value.secondary.isNotEmpty) {
      text(
        c,
        value.secondary,
        center.translate(3, secondaryShift),
        fontSize: secondaryFontSize,
        maxWidth: secondaryMaxWidth,
        ink: ink,
      );
    }
  }

  void numeral(Canvas c) {
    if (method == 'bottle' || method == 'pumping') {
      bottleNeck(c);
      c.drawPath(
        Path()
          ..moveTo(16, 23)
          ..lineTo(16, 38)
          ..quadraticBezierTo(16, 43, 21, 44)
          ..moveTo(48, 23)
          ..quadraticBezierTo(48, 29, 44, 34),
        pen(),
      );
      architectedNumber(c, center: const Offset(28, 35));
    } else if (method == 'nursing') {
      circle(c, 18, 8, 5);
      circle(c, 44, 21, 4);
      c.drawPath(
        Path()
          ..moveTo(12, 20)
          ..quadraticBezierTo(4, 34, 9, 44)
          ..moveTo(23, 19)
          ..lineTo(29, 30)
          ..lineTo(53, 35),
        pen(),
      );
      line(c, 29, 30, 37, 23);
      architectedNumber(
        c,
        center: const Offset(28, 42),
        fontSize: 29,
        maxWidth: 36,
      );
    } else if (method == 'diaper') {
      line(c, 7, 17, 57, 17);
      line(c, 7, 17, 9, 31);
      line(c, 57, 17, 55, 31);
      line(c, 26, 17, 26, 22);
      c.drawPath(
        Path()
          ..moveTo(9, 31)
          ..quadraticBezierTo(9, 39, 14, 44)
          ..quadraticBezierTo(24, 43, 24, 53)
          ..quadraticBezierTo(32, 58, 40, 53)
          ..quadraticBezierTo(40, 43, 50, 44)
          ..quadraticBezierTo(55, 39, 55, 31),
        pen(),
      );
      architectedNumber(
        c,
        center: const Offset(28, 30),
        fontSize: 29,
        secondaryFontSize: 9,
        secondaryShift: 16,
        secondaryMaxWidth: 17,
      );
    } else if (method == 'sleep') {
      c.drawPath(
        Path()
          ..moveTo(33, 5)
          ..cubicTo(6, 6, 0, 36, 14, 51)
          ..moveTo(33, 5)
          ..quadraticBezierTo(28, 23, 44, 29)
          ..lineTo(57, 29),
        pen(),
      );
      architectedNumber(
        c,
        center: const Offset(29, 34),
        fontSize: 29,
        maxWidth: 33,
      );
      line(c, 44, 29, 38, 25);
      if (value.secondary.isNotEmpty) {
        // The secondary row completes the lunar belly, rather than floating
        // under the crescent. Erase the ordinary row and place it on the curve.
        c.drawRect(const Rect.fromLTWH(14, 46, 41, 14), fill(ink: background));
        curveText(
          c,
          value.secondary,
          Path()
            ..moveTo(18, 51)
            ..quadraticBezierTo(34, 59, 51, 46),
          fontSize: 11,
        );
      }
    } else {
      utensils(c);
      architectedNumber(
        c,
        center: const Offset(27, 31),
        fontSize: 30,
        maxWidth: 34,
      );
      c.drawPath(
        Path()
          ..moveTo(14, 48)
          ..quadraticBezierTo(32, 58, 51, 48),
        pen(),
      );
    }
  }

  // A large aperture cuts through object material. The cut changes the
  // silhouette's negative space; it is deliberately not a printed small label.
  void carvedLabel(
    Canvas c, {
    required Offset primary,
    required double fontSize,
    required double maxWidth,
    required Offset secondary,
    double secondarySize = 11,
    double secondaryWidth = 30,
  }) {
    text(
      c,
      value.primary,
      primary,
      fontSize: fontSize,
      maxWidth: maxWidth,
      ink: background,
      weight: FontWeight.w700,
    );
    if (value.secondary.isNotEmpty) {
      text(
        c,
        value.secondary,
        secondary,
        fontSize: secondarySize,
        maxWidth: secondaryWidth,
        ink: background,
      );
    }
  }

  void cutout(Canvas c) {
    final long = value.primary.length >= 3;
    if (method == 'bottle' || method == 'pumping') {
      bottleNeck(c, solid: true);
      c.drawRRect(
        RRect.fromRectAndRadius(
          const Rect.fromLTWH(12, 24, 42, 37),
          const Radius.circular(8),
        ),
        fill(),
      );
      carvedLabel(
        c,
        primary: const Offset(32, 39),
        fontSize: 34,
        maxWidth: long ? 34 : 49,
        secondary: const Offset(32, 55),
        secondaryWidth: 34,
      );
    } else if (method == 'nursing') {
      circle(c, 18, 8, 5, solid: true);
      circle(c, 44, 21, 4, solid: true);
      c.drawPath(
        Path()
          ..moveTo(12, 20)
          ..quadraticBezierTo(5, 34, 12, 45)
          ..moveTo(23, 19)
          ..lineTo(29, 30)
          ..lineTo(53, 35),
        pen(width: 3),
      );
      c.drawPath(
        Path()
          ..moveTo(9, 35)
          ..quadraticBezierTo(31, 44, 57, 35)
          ..quadraticBezierTo(61, 54, 49, 61)
          ..lineTo(17, 61)
          ..quadraticBezierTo(5, 51, 9, 35)
          ..close(),
        fill(),
      );
      carvedLabel(
        c,
        primary: Offset(33, value.secondary.isEmpty ? 49 : 46),
        fontSize: long && value.secondary.isNotEmpty ? 18 : 29,
        maxWidth: long ? 35 : 51,
        secondary: const Offset(33, 58),
        secondarySize: 9,
        secondaryWidth: 35,
      );
    } else if (method == 'diaper') {
      c.drawPath(diaper, fill());
      c.drawLine(
        const Offset(9, 23),
        const Offset(55, 23),
        pen(ink: background, width: 1.4),
      );
      carvedLabel(
        c,
        primary: Offset(32, long ? 33 : 37),
        fontSize: 31,
        maxWidth: long ? 26 : 48,
        secondary: const Offset(32, 54),
        secondarySize: 10,
      );
      c.drawPath(
        Path()
          ..moveTo(12, 38)
          ..quadraticBezierTo(20, 42, 21, 53)
          ..moveTo(52, 38)
          ..quadraticBezierTo(44, 42, 43, 53),
        pen(ink: background, width: 2),
      );
    } else if (method == 'sleep') {
      c.drawPath(
        Path()
          ..moveTo(34, 5)
          ..cubicTo(31, 16, 43, 27, 60, 19)
          ..cubicTo(56, 57, 31, 67, 12, 53)
          ..cubicTo(-4, 38, 6, 8, 34, 5)
          ..close(),
        fill(),
      );
      carvedLabel(
        c,
        primary: long ? const Offset(25, 33) : const Offset(27, 31),
        fontSize: 25,
        maxWidth: long ? 30 : 41,
        secondary: const Offset(28, 54),
        secondarySize: 10,
        secondaryWidth: 27,
      );
    } else {
      utensils(c, solid: true);
      c.drawRRect(
        RRect.fromRectAndRadius(
          const Rect.fromLTWH(12, 13, 41, 43),
          const Radius.circular(15),
        ),
        fill(),
      );
      carvedLabel(
        c,
        primary: const Offset(32, 30),
        fontSize: 31,
        maxWidth: long ? 32 : 49,
        secondary: const Offset(32, 47),
        secondaryWidth: 32,
      );
    }
  }

  void face(Canvas c, Path shape, {double opacity = .1}) {
    c.drawPath(shape, fill(ink: color.withValues(alpha: opacity)));
    c.drawPath(shape, pen(width: 1.6));
  }

  void folded(Canvas c) {
    if (method == 'bottle' || method == 'pumping') {
      c.drawPath(
        Path()
          ..moveTo(27, 13)
          ..lineTo(27, 8)
          ..quadraticBezierTo(32, 0, 37, 6)
          ..lineTo(37, 12),
        pen(),
      );
      c.drawOval(const Rect.fromLTWH(18, 12, 30, 9), pen());
      face(
        c,
        Path()
          ..moveTo(18, 22)
          ..quadraticBezierTo(32, 25, 48, 22)
          ..quadraticBezierTo(53, 24, 51, 52)
          ..cubicTo(50, 64, 18, 63, 18, 54)
          ..quadraticBezierTo(16, 41, 18, 22)
          ..close(),
      );
      face(
        c,
        Path()
          ..moveTo(43, 23)
          ..quadraticBezierTo(47, 39, 42, 58)
          ..quadraticBezierTo(51, 59, 51, 52)
          ..quadraticBezierTo(53, 24, 48, 22)
          ..close(),
        opacity: .15,
      );
      c.drawArc(
        const Rect.fromLTWH(18, 51, 33, 10),
        0,
        math.pi,
        false,
        pen(width: 1.3),
      );
      text(
        c,
        value.primary + value.secondary,
        const Offset(31, 40),
        fontSize: 12,
        maxWidth: 30,
        angle: value.primary == '—' ? 0 : -math.pi / 2,
      );
      if (method == 'pumping') {
        line(c, 47, 14, 60, 14);
        line(c, 60, 14, 60, 27);
      }
    } else if (method == 'nursing') {
      circle(c, 16, 9, 5);
      circle(c, 42, 20, 4);
      c.drawPath(
        Path()
          ..moveTo(10, 20)
          ..quadraticBezierTo(3, 41, 15, 56)
          ..moveTo(24, 21)
          ..lineTo(30, 29)
          ..lineTo(56, 31),
        pen(),
      );
      line(c, 30, 29, 35, 22);
      face(
        c,
        Path()
          ..moveTo(12, 35)
          ..quadraticBezierTo(34, 43, 57, 35)
          ..quadraticBezierTo(60, 52, 47, 58)
          ..quadraticBezierTo(29, 60, 18, 55)
          ..quadraticBezierTo(5, 48, 12, 35)
          ..close(),
      );
      face(
        c,
        Path()
          ..moveTo(12, 35)
          ..quadraticBezierTo(34, 43, 57, 35)
          ..quadraticBezierTo(52, 44, 22, 42)
          ..quadraticBezierTo(13, 41, 12, 35)
          ..close(),
        opacity: .16,
      );
      curveText(
        c,
        inscription,
        Path()
          ..moveTo(18, 49)
          ..quadraticBezierTo(36, 56, 51, 48),
        fontSize: 11.5,
      );
    } else if (method == 'diaper') {
      face(
        c,
        Path()
          ..moveTo(10, 22)
          ..quadraticBezierTo(30, 29, 54, 22)
          ..quadraticBezierTo(53, 42, 43, 54)
          ..quadraticBezierTo(32, 65, 20, 53)
          ..quadraticBezierTo(10, 45, 10, 22)
          ..close(),
      );
      c.drawPath(
        Path()
          ..moveTo(14, 20)
          ..quadraticBezierTo(32, 13, 50, 20),
        pen(width: 1.6),
      );
      face(
        c,
        Path()
          ..moveTo(10, 23)
          ..quadraticBezierTo(32, 36, 54, 23)
          ..quadraticBezierTo(47, 38, 33, 38)
          ..quadraticBezierTo(25, 37, 10, 23)
          ..close(),
        opacity: .15,
      );
      c.drawPath(
        Path()
          ..moveTo(6, 41)
          ..quadraticBezierTo(20, 42, 26, 59)
          ..lineTo(7, 62)
          ..close(),
        fill(ink: background),
      );
      c.drawPath(
        Path()
          ..moveTo(57, 40)
          ..quadraticBezierTo(43, 42, 37, 59)
          ..lineTo(60, 62)
          ..close(),
        fill(ink: background),
      );
      c.drawPath(
        Path()
          ..moveTo(10, 43)
          ..quadraticBezierTo(22, 41, 26, 58)
          ..moveTo(52, 40)
          ..quadraticBezierTo(40, 41, 37, 58),
        pen(width: 1.6),
      );
      text(
        c,
        value.primary,
        const Offset(33, 40),
        fontSize: 11.5,
        maxWidth: 24,
      );
      if (value.secondary.isNotEmpty) {
        text(
          c,
          value.secondary,
          const Offset(32, 51),
          fontSize: 8.5,
          maxWidth: 16,
        );
      }
    } else if (method == 'sleep') {
      c.drawPath(
        Path()
          ..moveTo(36, 6)
          ..cubicTo(8, 9, 0, 41, 18, 54)
          ..quadraticBezierTo(41, 70, 60, 37),
        pen(ink: color.withValues(alpha: .38), width: 1.6),
      );
      face(c, moon);
      line(c, 33, 5, 36, 6, width: 1.6);
      line(c, 57, 36, 60, 37, width: 1.6);
      curveText(
        c,
        inscription,
        Path()
          ..moveTo(16, 43)
          ..quadraticBezierTo(34, 54, 51, 41),
        fontSize: 12,
      );
    } else {
      utensils(c);
      c.drawOval(const Rect.fromLTWH(12, 19, 40, 16), pen(width: 1.6));
      face(
        c,
        Path()
          ..moveTo(12, 27)
          ..quadraticBezierTo(32, 43, 52, 27)
          ..lineTo(52, 34)
          ..quadraticBezierTo(32, 51, 12, 34)
          ..close(),
        opacity: .16,
      );
      curveText(
        c,
        inscription,
        Path()
          ..moveTo(17, 36)
          ..quadraticBezierTo(32, 44, 47, 36),
        fontSize: 10.5,
      );
    }
  }

  @override
  bool shouldRepaint(_StructuralPainter old) =>
      old.method != method ||
      old.value != value ||
      old.color != color ||
      old.background != background ||
      old.construction != construction ||
      old.registration != registration;
}
