import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import '../theme/colors.dart';

/// Direct port of the original `ShieldLogo.tsx` SVG (shield + checkmark,
/// diagonal gradient from primary to primaryDark).
class ShieldLogo extends StatelessWidget {
  final double size;
  final AppColors colors;
  const ShieldLogo({super.key, this.size = 64, required this.colors});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _ShieldPainter(colors: colors),
      ),
    );
  }
}

class _ShieldPainter extends CustomPainter {
  final AppColors colors;
  _ShieldPainter({required this.colors});

  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.width / 64;
    canvas.save();
    canvas.scale(scale, scale);

    final shieldPath = Path()
      ..moveTo(32, 4)
      ..lineTo(56, 14)
      ..lineTo(56, 30)
      ..cubicTo(56, 44, 45.4, 55.2, 32, 60)
      ..cubicTo(18.6, 55.2, 8, 44, 8, 30)
      ..lineTo(8, 14)
      ..close();

    final gradient = ui.Gradient.linear(
      const Offset(0, 0),
      const Offset(64, 64),
      [colors.primary, colors.primaryDark],
    );
    final shieldPaint = Paint()..shader = gradient;
    canvas.drawPath(shieldPath, shieldPaint);

    final checkPath = Path()
      ..moveTo(22, 32)
      ..lineTo(29, 39)
      ..lineTo(43, 25);
    final checkPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(checkPath, checkPaint);

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _ShieldPainter oldDelegate) =>
      oldDelegate.colors.primary != colors.primary || oldDelegate.colors.primaryDark != colors.primaryDark;
}
