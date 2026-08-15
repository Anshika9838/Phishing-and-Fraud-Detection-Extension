import 'package:flutter/material.dart';
import '../models/scan_report.dart';
import '../theme/colors.dart';
import '../theme/typography.dart';

/// Direct port of the original `HistoryRow.tsx`.
class HistoryRow extends StatefulWidget {
  final ScanReport report;
  final VoidCallback onTap;
  final AppColors colors;
  const HistoryRow({super.key, required this.report, required this.onTap, required this.colors});

  @override
  State<HistoryRow> createState() => _HistoryRowState();
}

class _HistoryRowState extends State<HistoryRow> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final c = widget.colors;
    final report = widget.report;
    final tint = report.risk.color(c);
    final tintSoft = report.risk.softColor(c);
    final iconData = report.risk == RiskLevel.safe
        ? Icons.verified_user
        : report.risk == RiskLevel.caution
            ? Icons.error_outline
            : Icons.warning_amber_rounded;

    final date = report.scannedAt;
    final dateStr = '${date.month}/${date.day}/${date.year}';
    final hour12 = date.hour % 12 == 0 ? 12 : date.hour % 12;
    final ampm = date.hour >= 12 ? 'PM' : 'AM';
    final timeStr = '$hour12:${date.minute.toString().padLeft(2, '0')} $ampm';

    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) => setState(() => _pressed = false),
      onTapCancel: () => setState(() => _pressed = false),
      onTap: widget.onTap,
      child: AnimatedOpacity(
        opacity: _pressed ? 0.85 : 1,
        duration: const Duration(milliseconds: 100),
        child: Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: c.surface,
            borderRadius: BorderRadius.circular(AppRadius.lg),
            border: Border.all(color: c.border, width: 1),
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                alignment: Alignment.center,
                decoration: BoxDecoration(color: tintSoft, borderRadius: BorderRadius.circular(12)),
                child: Icon(iconData, size: 22, color: tint),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(report.domain,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTypography.bodyMedium.copyWith(color: c.text)),
                    Padding(
                      padding: const EdgeInsets.only(top: 3),
                      child: Text(report.summary,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTypography.caption.copyWith(color: c.textSecondary)),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text('$dateStr · $timeStr',
                          style: AppTypography.micro.copyWith(color: c.textTertiary)),
                    ),
                  ],
                ),
              ),
              Container(
                margin: const EdgeInsets.only(left: 8),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(color: tintSoft, borderRadius: BorderRadius.circular(AppRadius.pill)),
                child: Text('${report.safetyScore}', style: AppTypography.bodyMedium.copyWith(color: tint)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
