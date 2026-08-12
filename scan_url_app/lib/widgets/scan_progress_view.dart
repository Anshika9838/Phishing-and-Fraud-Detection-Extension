import 'package:flutter/material.dart';
import '../models/scan_progress.dart';
import '../theme/colors.dart';
import '../theme/typography.dart';

/// Direct port of the original `ScanProgress.tsx` — rotating ring,
/// pulsing shield badge, progress bar, and per-source checklist.
class ScanProgressView extends StatefulWidget {
  final ScanProgressData progress;
  final AppColors colors;
  const ScanProgressView({super.key, required this.progress, required this.colors});

  @override
  State<ScanProgressView> createState() => _ScanProgressViewState();
}

class _ScanProgressViewState extends State<ScanProgressView> with TickerProviderStateMixin {
  late final AnimationController _spinController;
  late final AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _spinController = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400))
      ..repeat();
    _pulseController = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400))
      ..repeat(reverse: true);
  }

  @override
  void dispose() {
    _spinController.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.colors;
    final sources = kScanSteps.map((s) => s['source'] as String).toList();
    final currentIndex = sources.indexOf(widget.progress.source ?? '');

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(AppRadius.xl),
        border: Border.all(color: c.border, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              RotationTransition(
                turns: _spinController,
                child: Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: c.primarySoft, width: 3),
                  ),
                  child: CustomPaint(painter: _RingAccentPainter(color: c.primary)),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Scanning across databases', style: AppTypography.bodyMedium.copyWith(color: c.text)),
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(widget.progress.step,
                          style: AppTypography.caption.copyWith(color: c.textSecondary)),
                    ),
                  ],
                ),
              ),
              ScaleTransition(
                scale: Tween<double>(begin: 1, end: 1.08).animate(_pulseController),
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(color: c.primarySoft, borderRadius: BorderRadius.circular(AppRadius.pill)),
                  child: Icon(Icons.verified_user, size: 18, color: c.primary),
                ),
              ),
            ],
          ),
          Container(
            height: 6,
            margin: const EdgeInsets.only(top: 18),
            decoration: BoxDecoration(color: c.surfaceMuted, borderRadius: BorderRadius.circular(3)),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: Align(
                alignment: Alignment.centerLeft,
                child: AnimatedFractionallySizedBox(
                  duration: const Duration(milliseconds: 300),
                  widthFactor: (widget.progress.percent.clamp(0, 100)) / 100,
                  child: Container(color: c.primary),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 18),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final isWide = constraints.maxWidth > 420;
                final itemWidth = isWide ? 220.0 : (constraints.maxWidth - 8) / 2;
                return Wrap(
                  runSpacing: 8,
                  children: [
                    for (final s in sources)
                      SizedBox(
                        width: itemWidth,
                        child: _SourceRow(
                          label: s,
                          isActive: widget.progress.source == s,
                          isDone: sources.indexOf(s) < currentIndex || widget.progress.percent == 100,
                          colors: c,
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _SourceRow extends StatelessWidget {
  final String label;
  final bool isActive;
  final bool isDone;
  final AppColors colors;
  const _SourceRow({required this.label, required this.isActive, required this.isDone, required this.colors});

  @override
  Widget build(BuildContext context) {
    final c = colors;
    return Padding(
      padding: const EdgeInsets.only(right: 8, bottom: 2),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 16,
            height: 16,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: isActive ? c.primary : (isDone ? c.success : c.surfaceMuted),
              shape: BoxShape.circle,
            ),
            child: isDone ? const Icon(Icons.check, size: 10, color: Colors.white) : null,
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.caption.copyWith(
                color: isActive ? c.text : (isDone ? c.textSecondary : c.textTertiary),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RingAccentPainter extends CustomPainter {
  final Color color;
  _RingAccentPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    final rect = Rect.fromLTWH(1.5, 1.5, size.width - 3, size.height - 3);
    canvas.drawArc(rect, -1.5708, 1.1, false, paint);
  }

  @override
  bool shouldRepaint(covariant _RingAccentPainter oldDelegate) => oldDelegate.color != color;
}
