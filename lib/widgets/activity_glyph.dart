import 'package:flutter/material.dart';

/// A consistent outline set for care activities without standard Material glyphs.
class CareGlyph extends StatelessWidget {
  const CareGlyph({
    super.key,
    required this.method,
    required this.fallback,
    this.size = 22,
    this.color,
  });
  final String method;
  final IconData fallback;
  final double size;
  final Color? color;
  @override
  Widget build(BuildContext context) =>
      ['bottle', 'diaper', 'nursing', 'pumping', 'sleep'].contains(method)
      ? Center(
          widthFactor: 1,
          heightFactor: 1,
          child: SizedBox(
            width: size,
            height: size,
            child: CustomPaint(
              painter: _CarePainter(
                method,
                color ?? IconTheme.of(context).color ?? Colors.black,
              ),
            ),
          ),
        )
      : Icon(fallback, size: size, color: color);
}

class _CarePainter extends CustomPainter {
  _CarePainter(this.method, this.color);
  final String method;
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 24, size.height / 24);
    final pen = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.7
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    if (method == 'bottle' || method == 'pumping') {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          const Rect.fromLTWH(6, 8, 12, 14),
          const Radius.circular(3),
        ),
        pen,
      );
      canvas.drawLine(const Offset(6, 8), const Offset(18, 8), pen);
      canvas.drawPath(
        Path()
          ..moveTo(8, 8)
          ..lineTo(8, 5)
          ..lineTo(10, 5)
          ..lineTo(10, 3)
          ..quadraticBezierTo(12, 0, 14, 3)
          ..lineTo(14, 5)
          ..lineTo(16, 5)
          ..lineTo(16, 8),
        pen,
      );
      for (final y in [12.0, 16.0, 19.0]) {
        canvas.drawLine(Offset(7, y), Offset(10, y), pen);
      }
      if (method == 'pumping') {
        canvas.drawPath(
          Path()
            ..moveTo(16, 4)
            ..lineTo(21, 4)
            ..lineTo(21, 11),
          pen,
        );
      }
    } else if (method == 'sleep') {
      canvas.drawPath(
        Path()
          ..moveTo(20, 15)
          ..cubicTo(12, 18, 5, 10, 9, 3)
          ..cubicTo(-2, 6, 6, 28, 20, 15)
          ..close(),
        pen,
      );
    } else if (method == 'diaper') {
      canvas.drawPath(
        Path()
          ..moveTo(2, 5)
          ..lineTo(22, 5)
          ..lineTo(21, 12)
          ..quadraticBezierTo(20, 20, 12, 21)
          ..quadraticBezierTo(4, 20, 3, 12)
          ..close(),
        pen,
      );
      canvas.drawLine(const Offset(3, 9), const Offset(21, 9), pen);
      canvas.drawPath(
        Path()
          ..moveTo(3, 11)
          ..quadraticBezierTo(9, 12, 9, 20)
          ..moveTo(21, 11)
          ..quadraticBezierTo(15, 12, 15, 20),
        pen,
      );
    } else {
      canvas.drawCircle(const Offset(8, 4), 2.5, pen);
      canvas.drawCircle(const Offset(16, 11), 2.5, pen);
      canvas.drawPath(
        Path()
          ..moveTo(5, 9)
          ..quadraticBezierTo(2, 15, 5, 21)
          ..lineTo(18, 21)
          ..moveTo(8, 9)
          ..lineTo(10, 14)
          ..lineTo(17, 17)
          ..quadraticBezierTo(12, 21, 7, 16)
          ..moveTo(10, 14)
          ..lineTo(13, 12),
        pen,
      );
    }
  }

  @override
  bool shouldRepaint(_CarePainter old) =>
      old.method != method || old.color != color;
}
