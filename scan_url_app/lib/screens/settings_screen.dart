import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../services/storage_service.dart';
import '../theme/colors.dart';
import '../theme/theme_scope.dart';
import '../theme/typography.dart';
import '../widgets/app_button.dart';

/// Direct port of the original `SettingsScreen.tsx`, minus every
/// account/session-related row (avatar, name/email, Sign Out) since the
/// login screen has been removed. Adds a Backend Server section so the
/// Theft Alert FastAPI base URL is configurable, since it isn't fixed.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _urlController = TextEditingController();
  bool _testing = false;
  String? _testResult;
  bool _testOk = false;

  @override
  void initState() {
    super.initState();
    StorageService.instance.getBackendUrl().then((v) {
      if (mounted) setState(() => _urlController.text = v);
    });
  }

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }

  Future<void> _saveAndTest() async {
    await StorageService.instance.setBackendUrl(_urlController.text);
    setState(() {
      _testing = true;
      _testResult = null;
    });
    try {
      await ApiService.instance.healthCheck();
      setState(() {
        _testOk = true;
        _testResult = 'Connected successfully.';
      });
    } catch (e) {
      setState(() {
        _testOk = false;
        _testResult = e is ApiException ? e.message : 'Could not connect to the backend.';
      });
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  void _showTerms() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Terms of Service'),
        content: const SingleChildScrollView(
          child: Text(
            'Theft Alert sends only the URL you submit to your configured backend for analysis. '
            'No page content, personal data, or browsing history is collected by this app. Scan '
            'history is stored only on this device. See the Terms & Conditions shown at first launch '
            'for the full text.',
          ),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close'))],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = useAppTheme(context);
    final c = theme.colors;

    return Scaffold(
      backgroundColor: c.background,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Configuration', style: AppTypography.caption.copyWith(color: c.textTertiary)),
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text('Settings', style: AppTypography.h1.copyWith(color: c.text)),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
                children: [
                  // Backend server card
                  Container(
                    padding: const EdgeInsets.all(16),
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
                            Container(
                              width: 40,
                              height: 40,
                              alignment: Alignment.center,
                              decoration:
                                  BoxDecoration(color: c.primarySoft, borderRadius: BorderRadius.circular(12)),
                              child: Icon(Icons.dns_outlined, size: 18, color: c.primary),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('Backend server', style: AppTypography.bodyMedium.copyWith(color: c.text)),
                                  Text('Your Theft Alert FastAPI URL',
                                      style: AppTypography.caption.copyWith(color: c.textSecondary)),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14),
                          decoration: BoxDecoration(
                            color: c.surfaceAlt,
                            borderRadius: BorderRadius.circular(AppRadius.lg),
                            border: Border.all(color: c.border, width: 1),
                          ),
                          child: TextField(
                            controller: _urlController,
                            keyboardType: TextInputType.url,
                            style: AppTypography.bodySmall.copyWith(color: c.text),
                            decoration: InputDecoration(
                              isDense: true,
                              border: InputBorder.none,
                              hintText: 'http://your-server-ip:8000',
                              hintStyle: AppTypography.bodySmall.copyWith(color: c.textTertiary),
                              contentPadding: const EdgeInsets.symmetric(vertical: 12),
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        AppButton(
                          title: _testing ? 'Testing…' : 'Save & Test Connection',
                          onPressed: _saveAndTest,
                          loading: _testing,
                          fullWidth: true,
                          icon: Icons.wifi_tethering,
                          colors: c,
                        ),
                        if (_testResult != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 10),
                            child: Row(
                              children: [
                                Icon(_testOk ? Icons.check_circle : Icons.error_outline,
                                    size: 14, color: _testOk ? c.success : c.danger),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(_testResult!,
                                      style: AppTypography.caption
                                          .copyWith(color: _testOk ? c.success : c.danger)),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),

                  _SectionLabel(title: 'Preferences', colors: c),
                  _SettingRow(
                    icon: Icons.notifications_none,
                    title: 'Scan alerts',
                    subtitle: 'Notify when a new community report arrives',
                    colors: c,
                    trailing: Switch(value: false, onChanged: null, activeColor: c.primary),
                  ),
                  _SettingRow(
                    icon: Icons.dark_mode_outlined,
                    title: 'Use system theme',
                    subtitle: 'Match your device appearance',
                    colors: c,
                    trailing: Switch(value: true, onChanged: null, activeColor: c.primary),
                  ),

                  _SectionLabel(title: 'Data', colors: c),
                  _SettingRow(
                    icon: Icons.delete_outline,
                    title: 'Clear scan history',
                    subtitle: 'Remove all saved URLs from this device',
                    colors: c,
                    onTap: () {
                      showDialog(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          title: const Text('Clear history'),
                          content: const Text('This will remove all your saved scans.'),
                          actions: [
                            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
                            TextButton(
                              onPressed: () async {
                                await StorageService.instance.clearHistory();
                                if (ctx.mounted) Navigator.pop(ctx);
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(content: Text('Your scan history has been cleared.')),
                                  );
                                }
                              },
                              child: const Text('Clear', style: TextStyle(color: Colors.red)),
                            ),
                          ],
                        ),
                      );
                    },
                  ),

                  _SectionLabel(title: 'About', colors: c),
                  _SettingRow(
                    icon: Icons.info_outline,
                    title: 'Version',
                    colors: c,
                    trailing: Text('1.0.0', style: AppTypography.caption.copyWith(color: c.textTertiary)),
                  ),
                  _SettingRow(
                    icon: Icons.description_outlined,
                    title: 'Terms of Service',
                    colors: c,
                    onTap: _showTerms,
                  ),
                  _SettingRow(
                    icon: Icons.verified_user_outlined,
                    title: 'Privacy Policy',
                    colors: c,
                    onTap: _showTerms,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String title;
  final AppColors colors;
  const _SectionLabel({required this.title, required this.colors});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 24, bottom: 10, left: 4),
      child: Text(title.toUpperCase(), style: AppTypography.micro.copyWith(color: colors.textTertiary)),
    );
  }
}

class _SettingRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final AppColors colors;
  final Widget? trailing;
  final VoidCallback? onTap;
  const _SettingRow({
    required this.icon,
    required this.title,
    required this.colors,
    this.subtitle,
    this.trailing,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = colors;
    final content = Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: c.border, width: 1),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: c.primarySoft, borderRadius: BorderRadius.circular(10)),
            child: Icon(icon, size: 18, color: c.primary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: AppTypography.bodyMedium.copyWith(color: c.text)),
                if (subtitle != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 3),
                    child: Text(subtitle!, style: AppTypography.caption.copyWith(color: c.textSecondary)),
                  ),
              ],
            ),
          ),
          trailing ?? (onTap != null ? Icon(Icons.chevron_right, size: 18, color: c.textTertiary) : const SizedBox()),
        ],
      ),
    );

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: onTap != null ? InkWell(onTap: onTap, borderRadius: BorderRadius.circular(AppRadius.lg), child: content) : content,
    );
  }
}
