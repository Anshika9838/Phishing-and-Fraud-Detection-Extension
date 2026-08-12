import 'package:flutter/material.dart';
import '../models/scan_report.dart';
import '../services/storage_service.dart';
import '../theme/colors.dart';
import '../theme/theme_scope.dart';
import '../theme/typography.dart';
import '../widgets/history_row.dart';

/// Direct port of the original `HistoryScreen.tsx`.
class HistoryScreen extends StatefulWidget {
  final ValueChanged<ScanReport> onSelectReport;
  const HistoryScreen({super.key, required this.onSelectReport});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  List<ScanReport> _reports = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final list = await StorageService.instance.getHistory();
    if (!mounted) return;
    setState(() => _reports = list);
  }

  void _handleClear() {
    if (_reports.isEmpty) return;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clear history'),
        content: const Text('Remove all scanned URLs from this device?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await StorageService.instance.clearHistory();
              setState(() => _reports = []);
            },
            child: const Text('Clear All', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = useAppTheme(context);
    final c = theme.colors;

    final total = _reports.length;
    final safe = _reports.where((r) => r.risk == RiskLevel.safe).length;
    final caution = _reports.where((r) => r.risk == RiskLevel.caution).length;
    final danger = _reports.where((r) => r.risk == RiskLevel.danger).length;

    return Scaffold(
      backgroundColor: c.background,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Your activity', style: AppTypography.caption.copyWith(color: c.textTertiary)),
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text('Scan History', style: AppTypography.h1.copyWith(color: c.text)),
                        ),
                      ],
                    ),
                  ),
                  if (_reports.isNotEmpty)
                    OutlinedButton.icon(
                      onPressed: _handleClear,
                      icon: Icon(Icons.delete_outline, size: 16, color: c.textSecondary),
                      label: Text('Clear', style: AppTypography.caption.copyWith(color: c.textSecondary)),
                      style: OutlinedButton.styleFrom(
                        backgroundColor: c.surface,
                        side: BorderSide(color: c.border),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.pill)),
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                      ),
                    ),
                ],
              ),
            ),
            if (_reports.isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  children: [
                    _StatPill(label: 'Total', value: total, color: c.text, bg: c.surface, border: c.border),
                    const SizedBox(width: 8),
                    _StatPill(label: 'Safe', value: safe, color: c.success, bg: c.successSoft, border: null),
                    const SizedBox(width: 8),
                    _StatPill(
                        label: 'Caution', value: caution, color: c.warning, bg: c.warningSoft, border: null),
                    const SizedBox(width: 8),
                    _StatPill(label: 'Risk', value: danger, color: c.danger, bg: c.dangerSoft, border: null),
                  ],
                ),
              ),
            Expanded(
              child: RefreshIndicator(
                onRefresh: _load,
                color: c.primary,
                child: _reports.isEmpty
                    ? ListView(
                        padding: const EdgeInsets.only(top: 16),
                        children: [_EmptyState(colors: c)],
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
                        itemCount: _reports.length,
                        itemBuilder: (context, i) {
                          final r = _reports[i];
                          return HistoryRow(report: r, onTap: () => widget.onSelectReport(r), colors: c);
                        },
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatPill extends StatelessWidget {
  final String label;
  final int value;
  final Color color;
  final Color bg;
  final Color? border;
  const _StatPill({required this.label, required this.value, required this.color, required this.bg, this.border});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(AppRadius.lg),
          border: border != null ? Border.all(color: border!, width: 1) : null,
        ),
        child: Column(
          children: [
            Text('$value', style: AppTypography.h2.copyWith(color: color)),
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

class _EmptyState extends StatelessWidget {
  final AppColors colors;
  const _EmptyState({required this.colors});

  @override
  Widget build(BuildContext context) {
    final c = colors;
    return Padding(
      padding: const EdgeInsets.only(top: 64),
      child: Column(
        children: [
          Container(
            width: 80,
            height: 80,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: c.primarySoft, borderRadius: BorderRadius.circular(24)),
            child: Icon(Icons.history, size: 36, color: c.primary),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 18),
            child: Text('No scans yet', textAlign: TextAlign.center, style: AppTypography.h2.copyWith(color: c.text)),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                'URLs you verify will appear here. Past scans are stored privately on your device.',
                textAlign: TextAlign.center,
                style: AppTypography.body.copyWith(color: c.textSecondary),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
