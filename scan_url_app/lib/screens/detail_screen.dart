import 'package:flutter/material.dart';
import '../models/scan_report.dart';
import '../services/storage_service.dart';
import '../theme/colors.dart';
import '../theme/theme_scope.dart';
import '../theme/typography.dart';
import '../widgets/app_header.dart';
import '../widgets/markdown_view.dart';
import '../widgets/score_gauge.dart';

/// Direct port of the original `DetailScreen.tsx`.
class DetailScreen extends StatelessWidget {
  final ScanReport report;
  final VoidCallback onBack;
  final VoidCallback onDeleted;
  const DetailScreen({super.key, required this.report, required this.onBack, required this.onDeleted});

  @override
  Widget build(BuildContext context) {
    final theme = useAppTheme(context);
    final c = theme.colors;
    final tint = report.risk.color(c);
    final heroLabel = report.risk == RiskLevel.safe
        ? 'Safe to visit'
        : report.risk == RiskLevel.caution
            ? 'Proceed with caution'
            : 'High risk URL';

    return Scaffold(
      backgroundColor: c.background,
      body: SafeArea(
        child: Column(
          children: [
            AppHeader(
              title: 'Scan Result',
              colors: c,
              leftIcon: Icons.chevron_left,
              onLeftPressed: onBack,
              rightIcon: Icons.delete_outline,
              onRightPressed: () async {
                await StorageService.instance.deleteScan(report.id);
                onDeleted();
              },
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Column(
                        children: [
                          ScoreGauge(score: report.safetyScore, risk: report.risk, colors: c, size: 180),
                          Padding(
                            padding: const EdgeInsets.only(top: 18),
                            child: Text(heroLabel,
                                textAlign: TextAlign.center, style: AppTypography.h1.copyWith(color: c.text)),
                          ),
                          Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Text(report.summary,
                                textAlign: TextAlign.center,
                                style: AppTypography.body.copyWith(color: c.textSecondary)),
                          ),
                          Container(
                            width: double.infinity,
                            margin: const EdgeInsets.only(top: 18),
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            decoration: BoxDecoration(
                              color: c.surfaceAlt,
                              borderRadius: BorderRadius.circular(AppRadius.pill),
                              border: Border.all(color: c.border, width: 1),
                            ),
                            child: Row(
                              children: [
                                Icon(Icons.link, size: 14, color: c.primary),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(report.url,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: AppTypography.mono.copyWith(color: c.text)),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    _Section(
                      title: 'Detailed report',
                      colors: c,
                      child: MarkdownView(content: report.explanation, colors: c),
                    ),
                    _Section(
                      title: 'All checks',
                      colors: c,
                      child: Column(
                        children: [
                          for (final check in report.checks) _CheckDetailRow(check: check, colors: c),
                          if (report.checks.isEmpty)
                            Align(
                              alignment: Alignment.centerLeft,
                              child: Text('No individual check results were returned by the backend.',
                                  style: AppTypography.caption.copyWith(color: c.textTertiary)),
                            ),
                        ],
                      ),
                    ),
                    _Section(
                      title: 'Scan details',
                      colors: c,
                      child: Column(
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(child: _WhoisField(label: 'Domain', value: report.domain, colors: c)),
                              const SizedBox(width: 12),
                              Expanded(child: _WhoisField(label: 'IP address', value: report.ip, colors: c)),
                            ],
                          ),
                          const SizedBox(height: 14),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: _WhoisField(
                                  label: 'Threat type',
                                  value: report.threatType.isEmpty ? 'Unknown' : report.threatType,
                                  colors: c,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: _WhoisField(
                                  label: 'Raw risk score',
                                  value: report.riskScore.toStringAsFixed(0),
                                  colors: c,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    _Section(
                      title: 'Checks summary',
                      colors: c,
                      child: Column(
                        children: [
                          Row(
                            children: [
                              _RepStat(label: 'Sources', value: '${report.sourcesCount}', color: c.text, colors: c),
                              _RepStat(label: 'Clean', value: '${report.positives}', color: c.success, colors: c),
                              _RepStat(
                                  label: 'Caution', value: '${report.neutrals}', color: c.textSecondary, colors: c),
                              _RepStat(label: 'Flagged', value: '${report.negatives}', color: c.danger, colors: c),
                            ],
                          ),
                        ],
                      ),
                    ),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: c.surfaceAlt,
                        borderRadius: BorderRadius.circular(AppRadius.md),
                        border: Border.all(color: c.border, width: 1),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.calendar_today_outlined, size: 14, color: c.textTertiary),
                          const SizedBox(width: 6),
                          Text('Scanned on ${_formatDateTime(report.scannedAt)}',
                              style: AppTypography.caption.copyWith(color: c.textTertiary)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _formatDateTime(DateTime d) {
    final hour12 = d.hour % 12 == 0 ? 12 : d.hour % 12;
    final ampm = d.hour >= 12 ? 'PM' : 'AM';
    return '${d.month}/${d.day}/${d.year}, $hour12:${d.minute.toString().padLeft(2, '0')} $ampm';
  }
}

class _Section extends StatelessWidget {
  final String title;
  final Widget child;
  final AppColors colors;
  const _Section({required this.title, required this.child, required this.colors});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(AppRadius.xl),
        border: Border.all(color: colors.border, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: Text(title, style: AppTypography.h3.copyWith(color: colors.text)),
          ),
          child,
        ],
      ),
    );
  }
}

class _CheckDetailRow extends StatelessWidget {
  final ScanCheck check;
  final AppColors colors;
  const _CheckDetailRow({required this.check, required this.colors});

  @override
  Widget build(BuildContext context) {
    final c = colors;
    final status = check.status;
    final cTint = status == CheckStatus.pass ? c.success : (status == CheckStatus.warn ? c.warning : c.danger);
    final cSoft =
        status == CheckStatus.pass ? c.successSoft : (status == CheckStatus.warn ? c.warningSoft : c.dangerSoft);
    final icon = status == CheckStatus.pass
        ? Icons.check_circle
        : (status == CheckStatus.warn ? Icons.error_outline : Icons.cancel);

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: c.border, width: 1),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: cSoft, borderRadius: BorderRadius.circular(10)),
            child: Icon(icon, size: 18, color: cTint),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(child: Text(check.name, style: AppTypography.bodyMedium.copyWith(color: c.text))),
                    Text(status.name.toUpperCase(), style: AppTypography.micro.copyWith(color: cTint)),
                  ],
                ),
                if (check.description.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(check.description, style: AppTypography.caption.copyWith(color: c.textSecondary)),
                  ),
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(check.detail, style: AppTypography.bodySmall.copyWith(color: c.text)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _WhoisField extends StatelessWidget {
  final String label;
  final String value;
  final AppColors colors;
  const _WhoisField({required this.label, required this.value, required this.colors});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label.toUpperCase(), style: AppTypography.micro.copyWith(color: colors.textTertiary)),
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(value, style: AppTypography.bodySmall.copyWith(color: colors.text)),
        ),
      ],
    );
  }
}

class _RepStat extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  final AppColors colors;
  const _RepStat({required this.label, required this.value, required this.color, required this.colors});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 4),
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
        decoration: BoxDecoration(color: colors.surfaceAlt, borderRadius: BorderRadius.circular(AppRadius.md)),
        child: Column(
          children: [
            Text(value, style: AppTypography.h2.copyWith(color: color)),
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(label.toUpperCase(), style: AppTypography.micro.copyWith(color: color.withOpacity(0.7))),
            ),
          ],
        ),
      ),
    );
  }
}
