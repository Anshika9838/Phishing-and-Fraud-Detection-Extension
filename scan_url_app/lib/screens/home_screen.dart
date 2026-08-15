import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/scan_progress.dart';
import '../models/scan_report.dart';
import '../services/api_service.dart';
import '../services/storage_service.dart';
import '../theme/colors.dart';
import '../theme/theme_scope.dart';
import '../theme/typography.dart';
import '../widgets/app_button.dart';
import '../widgets/app_input.dart';
import '../widgets/markdown_view.dart';
import '../widgets/scan_progress_view.dart';
import '../widgets/score_gauge.dart';

/// Direct port of the original `HomeScreen.tsx`, with the mock scanner
/// replaced by a real call to the Theft Alert backend's
/// `POST /api/scan_url` endpoint.
class HomeScreen extends StatefulWidget {
  final VoidCallback onScanSaved;
  const HomeScreen({super.key, required this.onScanSaved});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _urlController = TextEditingController();
  String _error = '';
  bool _scanning = false;
  bool _cancelledStepAnim = false;
  ScanProgressData _progress = const ScanProgressData(step: '', percent: 0);
  ScanReport? _report;

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }

  Future<void> _handlePaste() async {
    final data = await Clipboard.getData('text/plain');
    if (data?.text != null && data!.text!.isNotEmpty) {
      setState(() {
        _urlController.text = data.text!;
        _error = '';
      });
    }
  }

  void _handleClear() {
    setState(() {
      _urlController.clear();
      _error = '';
      _report = null;
    });
  }

  Future<void> _runStepAnimation() async {
    for (final step in kScanSteps) {
      if (_cancelledStepAnim || !mounted) return;
      setState(() {
        _progress = ScanProgressData(
          step: step['label'] as String,
          source: step['source'] as String,
          percent: (((kScanSteps.indexOf(step) + 1) / kScanSteps.length) * 100).round(),
        );
      });
      await Future.delayed(Duration(milliseconds: step['duration'] as int));
    }
    if (!_cancelledStepAnim && mounted) {
      setState(() {
        _progress = const ScanProgressData(step: 'Compiling final verdict…', percent: 100);
      });
    }
  }

  Future<void> _handleScan() async {
    final trimmed = _urlController.text.trim();
    final valid = validateUrlFormat(trimmed);
    if (!valid.ok) {
      setState(() => _error = valid.reason ?? 'Invalid URL');
      return;
    }
    setState(() {
      _error = '';
      _report = null;
      _scanning = true;
      _cancelledStepAnim = false;
      _progress = const ScanProgressData(step: 'Initialising scan…', percent: 0);
    });

    _runStepAnimation();

    try {
      final result = await ApiService.instance.scanUrl(trimmed);
      _cancelledStepAnim = true;
      if (!mounted) return;
      setState(() {
        _report = result;
        _scanning = false;
      });
      await StorageService.instance.addScan(result);
      widget.onScanSaved();
    } catch (e) {
      _cancelledStepAnim = true;
      if (!mounted) return;
      setState(() => _scanning = false);
      final message = e is ApiException ? e.message : 'Unable to complete the scan. Please try again.';
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Scan failed'),
          content: Text(message),
          actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK'))],
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = useAppTheme(context);
    final c = theme.colors;
    final report = _report;
    final tint = report != null ? report.risk.color(c) : c.primary;

    return Scaffold(
      backgroundColor: c.background,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.only(bottom: 32),
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 14),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Welcome', style: AppTypography.caption.copyWith(color: c.textTertiary)),
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text('Verify a URL', style: AppTypography.h1.copyWith(color: c.text)),
                          ),
                          Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Text(
                              'Paste a link to check it against multiple threat databases.',
                              style: AppTypography.body.copyWith(color: c.textSecondary),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      width: 52,
                      height: 52,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(color: c.primarySoft, borderRadius: BorderRadius.circular(16)),
                      child: Icon(Icons.verified_user, size: 26, color: c.primary),
                    ),
                  ],
                ),
              ),

              // Scan card
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 20),
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: c.surface,
                  borderRadius: BorderRadius.circular(AppRadius.xl),
                  border: Border.all(color: c.border, width: 1),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Text('TARGET URL', style: AppTypography.micro.copyWith(color: c.textSecondary)),
                    ),
                    AppInput(
                      controller: _urlController,
                      colors: c,
                      placeholder: 'https://example.com/page',
                      leadingIcon: Icons.link,
                      enabled: !_scanning,
                      error: _error.isEmpty ? null : _error,
                      onChanged: (t) {
                        setState(() {
                          if (_error.isNotEmpty) _error = '';
                        });
                      },
                      onSubmitted: _handleScan,
                      trailing: _urlController.text.isNotEmpty
                          ? IconButton(
                              onPressed: _handleClear,
                              icon: Icon(Icons.cancel, size: 18, color: c.textTertiary),
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                              visualDensity: VisualDensity.compact,
                            )
                          : IconButton(
                              onPressed: _handlePaste,
                              icon: Icon(Icons.content_paste, size: 18, color: c.primary),
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                              visualDensity: VisualDensity.compact,
                            ),
                    ),
                    AppButton(
                      title: _scanning ? 'Scanning…' : 'Scan URL',
                      onPressed: _handleScan,
                      loading: _scanning,
                      disabled: _urlController.text.trim().isEmpty,
                      fullWidth: true,
                      size: AppButtonSize.lg,
                      icon: Icons.search,
                      colors: c,
                    ),
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Row(
                        children: [
                          Icon(Icons.info_outline, size: 14, color: c.textTertiary),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              'Scans are private — your history is stored only on this device.',
                              style: AppTypography.caption.copyWith(color: c.textTertiary),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              if (_scanning)
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
                  child: ScanProgressView(progress: _progress, colors: c),
                ),

              if (report != null && !_scanning)
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 22, 20, 0),
                  child: _ResultCard(report: report, tint: tint, colors: c),
                ),

              if (!_scanning && report == null) _HowScanningWorks(colors: c),
            ],
          ),
        ),
      ),
    );
  }
}

class _ResultCard extends StatelessWidget {
  final ScanReport report;
  final Color tint;
  final AppColors colors;
  const _ResultCard({required this.report, required this.tint, required this.colors});

  @override
  Widget build(BuildContext context) {
    final c = colors;
    final verdictLabel = report.risk == RiskLevel.safe
        ? 'Looks safe'
        : report.risk == RiskLevel.caution
            ? 'Proceed with caution'
            : 'High risk detected';

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(AppRadius.xl),
        border: Border.all(color: c.border, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              ScoreGauge(score: report.safetyScore, risk: report.risk, colors: c, size: 140),
              const SizedBox(width: 18),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('VERDICT', style: AppTypography.micro.copyWith(color: tint)),
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(verdictLabel, style: AppTypography.h2.copyWith(color: c.text)),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        report.summary,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: AppTypography.caption.copyWith(color: c.textSecondary),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          _Divider(colors: c),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('DOMAIN', style: AppTypography.micro.copyWith(color: c.textTertiary)),
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(report.domain,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTypography.bodyMedium.copyWith(color: c.text)),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text('IP ADDRESS', style: AppTypography.micro.copyWith(color: c.textTertiary)),
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(report.ip, style: AppTypography.bodyMedium.copyWith(color: c.text)),
                  ),
                ],
              ),
            ],
          ),
          if (report.categories.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 14),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final cat in report.categories)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: c.primarySoft,
                        borderRadius: BorderRadius.circular(AppRadius.pill),
                      ),
                      child: Text(cat, style: AppTypography.caption.copyWith(color: c.primary)),
                    ),
                ],
              ),
            ),
          _Divider(colors: c),
          Text('Detailed report', style: AppTypography.h3.copyWith(color: c.text)),
          const SizedBox(height: 14),
          MarkdownView(content: report.explanation, colors: c),
          _Divider(colors: c),
          Text('Checks performed', style: AppTypography.h3.copyWith(color: c.text)),
          const SizedBox(height: 14),
          for (final check in report.checks) _CheckRow(check: check, colors: c),
          if (report.checks.isEmpty)
            Text('No individual check results were returned by the backend.',
                style: AppTypography.caption.copyWith(color: c.textTertiary)),
          _Divider(colors: c),
          Text('Checks summary', style: AppTypography.h3.copyWith(color: c.text)),
          const SizedBox(height: 14),
          Row(
            children: [
              _RepStat(label: 'Sources', value: '${report.sourcesCount}', color: c.text),
              _RepStat(label: 'Clean', value: '${report.positives}', color: c.success),
              _RepStat(label: 'Caution', value: '${report.neutrals}', color: c.textSecondary),
              _RepStat(label: 'Flagged', value: '${report.negatives}', color: c.danger),
            ],
          ),
        ],
      ),
    );
  }
}

class _CheckRow extends StatelessWidget {
  final ScanCheck check;
  final AppColors colors;
  const _CheckRow({required this.check, required this.colors});

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
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: c.surfaceAlt,
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
                Text(check.name, style: AppTypography.bodyMedium.copyWith(color: c.text)),
                Padding(
                  padding: const EdgeInsets.only(top: 3),
                  child: Text(check.detail, style: AppTypography.caption.copyWith(color: c.textSecondary)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RepStat extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  const _RepStat({required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Text(value, style: AppTypography.h2.copyWith(color: color)),
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(label.toUpperCase(),
                style: AppTypography.micro.copyWith(color: color.withOpacity(0.7))),
          ),
        ],
      ),
    );
  }
}

class _Divider extends StatelessWidget {
  final AppColors colors;
  const _Divider({required this.colors});
  @override
  Widget build(BuildContext context) =>
      Container(height: 1, margin: const EdgeInsets.symmetric(vertical: 18), color: colors.border);
}

class _HowScanningWorks extends StatelessWidget {
  final AppColors colors;
  const _HowScanningWorks({required this.colors});

  @override
  Widget build(BuildContext context) {
    final c = colors;
    final items = [
      (
        Icons.search,
        'Multi-source lookup',
        'Google Safe Browsing, VirusTotal, URLhaus, OpenPhish, AbuseIPDB, OTX and more, queried in parallel.'
      ),
      (
        Icons.analytics_outlined,
        'Heuristic + AI scoring',
        'WHOIS, SSL and URL heuristics are combined with the backend\u2019s scoring engine into one 0-100 risk score.'
      ),
      (
        Icons.menu_book_outlined,
        'Plain-English summary',
        'A clear report explains the verdict, the evidence, and the recommended next steps.'
      ),
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 28, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text('How scanning works', style: AppTypography.h3.copyWith(color: c.text)),
          ),
          for (final item in items)
            Container(
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
                    width: 40,
                    height: 40,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(color: c.primarySoft, borderRadius: BorderRadius.circular(12)),
                    child: Icon(item.$1, size: 18, color: c.primary),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(item.$2, style: AppTypography.bodyMedium.copyWith(color: c.text)),
                        Padding(
                          padding: const EdgeInsets.only(top: 3),
                          child: Text(item.$3, style: AppTypography.caption.copyWith(color: c.textSecondary)),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
