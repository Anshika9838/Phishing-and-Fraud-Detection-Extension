import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../theme/colors.dart';
import '../theme/typography.dart';

/// Animated circular safety gauge — direct port of the original
/// `ScoreGauge.tsx` (SVG circle + reanimated strokeDashoffset tween).
class ScoreGauge extends StatefulWidget {
  final int score; // 0-100, higher = safer
  final RiskLevel risk;
  final double size;
  final bool showLabel;
  final AppColors colors;

  const ScoreGauge({
    super.key,
    required this.score,
    required this.risk,
    required this.colors,
    this.size = 160,
    this.showLabel = true,
  });

  @override
  State<ScoreGauge> createState() => _ScoreGaugeState();
}

class _ScoreGaugeState extends State<ScoreGauge> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 1200));
    _animation = Tween<double>(begin: 0, end: widget.score.toDouble())
        .animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));
    _controller.forward();
  }

  @override
  void didUpdateWidget(covariant ScoreGauge oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.score != widget.score) {
      _animation = Tween<double>(begin: _animation.value, end: widget.score.toDouble())
          .animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));
      _controller.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  String get _label {
    switch (widget.risk) {
      case RiskLevel.safe:
        return 'Trusted';
      case RiskLevel.caution:
        return 'Caution';
      case RiskLevel.danger:
        return 'High Risk';
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.risk.color(widget.colors);
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          AnimatedBuilder(
            animation: _animation,
            builder: (context, _) {
              return CustomPaint(
                size: Size(widget.size, widget.size),
                painter: _GaugePainter(
                  progress: _animation.value,
                  trackColor: widget.colors.surfaceMuted,
                  color: color,
                ),
              );
            },
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedBuilder(
                animation: _animation,
                builder: (context, _) => Text(
                  _animation.value.round().toString(),
                  style: AppTypography.display.copyWith(color: widget.colors.text),
                ),
              ),
              if (widget.showLabel)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    _label.toUpperCase(),
                    style: AppTypography.micro.copyWith(color: color),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _GaugePainter extends CustomPainter {
  final double progress; // 0-100
  final Color trackColor;
  final Color color;

  _GaugePainter({required this.progress, required this.trackColor, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 12.0;
    final radius = (size.width - stroke) / 2;
    final center = Offset(size.width / 2, size.height / 2);

    final trackPaint = Paint()
      ..color = trackColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke;
    canvas.drawCircle(center, radius, trackPaint);

    final rect = Rect.fromCircle(center: center, radius: radius);
    final sweep = (progress.clamp(0, 100) / 100) * 2 * math.pi;

    final gradient = SweepGradient(
      startAngle: 0,
      endAngle: 2 * math.pi,
      transform: GradientRotation(-math.pi / 2),
      colors: [color, color.withOpacity(0.55)],
      stops: const [0.0, 1.0],
    );
    final fgPaint = Paint()
      ..shader = gradient.createShader(rect)
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;

    canvas.drawArc(rect, -math.pi / 2, sweep, false, fgPaint);
  }

  @override
  bool shouldRepaint(covariant _GaugePainter oldDelegate) =>
      oldDelegate.progress != progress || oldDelegate.color != color || oldDelegate.trackColor != trackColor;
}
