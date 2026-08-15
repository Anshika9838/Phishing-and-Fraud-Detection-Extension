import 'package:flutter/material.dart';
import '../theme/theme_scope.dart';
import '../theme/typography.dart';
import '../widgets/app_button.dart';

class _Section {
  final String title;
  final String body;
  const _Section(this.title, this.body);
}

/// Updated to reflect the real Theft Alert backend's data practices
/// (see backend docs §5 "Data Management & Privacy"), scoped specifically
/// to this app's use of the URL-only `/api/scan_url` endpoint.
const _sections = [
  _Section(
    '1. Service overview',
    'Theft Alert provides real-time URL reputation and threat analysis. This app sends the URL you '
        'enter to your configured Theft Alert backend, which aggregates signals from multiple layers: '
        'external threat-intelligence feeds (including Google Safe Browsing, VirusTotal, URLhaus, '
        'OpenPhish, AbuseIPDB, AlienVault OTX, Spamhaus, Pulsedive and URLScan.io), infrastructure '
        'forensics (WHOIS and SSL/TLS certificate inspection), and heuristic URL analysis. Results are '
        'informational and reflect the state of these sources at the time of the scan.',
  ),
  _Section(
    '2. No guarantee of safety',
    'A "safe" or low-risk verdict indicates that no major database or check currently flags the URL — '
        'not that the URL is definitively trustworthy. Always exercise caution with links from '
        'unverified sources. We do not guarantee the accuracy or completeness of any scan result.',
  ),
  _Section(
    '3. What data this app sends and stores',
    'This app transmits only the URL you submit to your configured backend for analysis — no page '
        'content, personal information, contacts, or browsing history is collected or sent by this app. '
        'Your scan history (the URLs you have checked and their results) is stored exclusively on this '
        'device using local secure storage and is never transmitted to us or to any third party by this '
        'app. There is no account, login, or authentication in this app — nothing is tied to your identity.',
  ),
  _Section(
    '4. How the backend shares data',
    'To analyse a URL, the Theft Alert backend shares the minimum information necessary — typically '
        'the URL, its domain, and/or resolved IP address — with the trusted third-party threat-'
        'intelligence providers listed above, and may log requests server-side for debugging, abuse '
        'prevention, and improving detection accuracy. That sharing is governed by each provider\u2019s own '
        'privacy policy and by the policies of whoever operates your backend deployment.',
  ),
  _Section(
    '5. Acceptable use',
    'You agree to use this app to verify URLs for personal safety and awareness. You may not use it to '
        'facilitate phishing, to scan infrastructure you do not own or have permission to test, or for '
        'any unlawful purpose.',
  ),
  _Section(
    '6. Limitation of liability',
    'Theft Alert is provided "as is" without warranty of any kind. The developers are not liable for '
        'damages resulting from reliance on scan results. You are responsible for your own online safety '
        'decisions.',
  ),
  _Section(
    '7. Updates to these terms',
    'We may revise these terms periodically. Continued use of the app after an update constitutes '
        'acceptance of the revised terms.',
  ),
];

/// Direct port of the original `TermsScreen.tsx` (scroll-to-accept flow),
/// with content updated per requirement #2.
class TermsScreen extends StatefulWidget {
  final VoidCallback onAccept;
  const TermsScreen({super.key, required this.onAccept});

  @override
  State<TermsScreen> createState() => _TermsScreenState();
}

class _TermsScreenState extends State<TermsScreen> {
  final _scrollController = ScrollController();
  bool _hasScrolledToEnd = false;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    // If content already fits on-screen (no scrolling needed), unlock immediately.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients && _scrollController.position.maxScrollExtent <= 0) {
        setState(() => _hasScrolledToEnd = true);
      }
    });
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final pos = _scrollController.position;
    if (pos.pixels >= pos.maxScrollExtent - 32 && !_hasScrolledToEnd) {
      setState(() => _hasScrolledToEnd = true);
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = useAppTheme(context);
    final c = theme.colors;
    return Scaffold(
      backgroundColor: c.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Column(
            children: [
              const SizedBox(height: 12),
              Column(
                children: [
                  Container(
                    width: 56,
                    height: 56,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(color: c.primarySoft, borderRadius: BorderRadius.circular(16)),
                    child: Icon(Icons.description, size: 24, color: c.primary),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(top: 16),
                    child: Text('Terms & Conditions', style: AppTypography.h1.copyWith(color: c.text)),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      'Please read carefully before continuing.',
                      textAlign: TextAlign.center,
                      style: AppTypography.body.copyWith(color: c.textSecondary),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color: c.surface,
                    borderRadius: BorderRadius.circular(AppRadius.xl),
                    border: Border.all(color: c.border, width: 1),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(AppRadius.xl),
                    child: Stack(
                      children: [
                        ListView(
                          controller: _scrollController,
                          padding: const EdgeInsets.fromLTRB(20, 20, 20, 40),
                          children: [
                            for (final s in _sections)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 22),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(s.title,
                                        style: AppTypography.h3.copyWith(color: c.text)),
                                    const SizedBox(height: 8),
                                    Text(s.body,
                                        style: AppTypography.body.copyWith(color: c.textSecondary, height: 1.5)),
                                  ],
                                ),
                              ),
                          ],
                        ),
                        if (!_hasScrolledToEnd)
                          Positioned(
                            left: 20,
                            bottom: 12,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                              decoration: BoxDecoration(
                                color: c.primarySoft,
                                borderRadius: BorderRadius.circular(AppRadius.pill),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.arrow_downward, size: 14, color: c.primary),
                                  const SizedBox(width: 6),
                                  Text('Scroll to the end to continue',
                                      style: AppTypography.caption.copyWith(color: c.primary)),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: AppButton(
                  title: _hasScrolledToEnd ? 'I Accept & Continue' : 'Continue reading...',
                  onPressed: widget.onAccept,
                  disabled: !_hasScrolledToEnd,
                  fullWidth: true,
                  size: AppButtonSize.lg,
                  icon: Icons.check_circle,
                  colors: c,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
