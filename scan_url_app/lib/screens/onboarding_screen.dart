import 'package:flutter/material.dart';
import '../theme/theme_scope.dart';
import '../theme/typography.dart';

class _Slide {
  final IconData icon;
  final String title;
  final String body;
  const _Slide({required this.icon, required this.title, required this.body});
}

const _slides = [
  _Slide(
    icon: Icons.public,
    title: 'Scan any URL instantly',
    body: 'Paste a link and we will check it against community-driven threat databases in seconds.',
  ),
  _Slide(
    icon: Icons.verified_user_outlined,
    title: 'Multi-source reputation',
    body: 'Google Safe Browsing, VirusTotal, URLhaus, OpenPhish, WHOIS and SSL inspection combined.',
  ),
  _Slide(
    icon: Icons.history_outlined,
    title: 'Keep your scan history',
    body: 'Every URL you verify is saved privately on your device so you can revisit results anytime.',
  ),
];

/// Direct port of the original `OnboardingScreen.tsx`.
class OnboardingScreen extends StatefulWidget {
  final VoidCallback onFinish;
  const OnboardingScreen({super.key, required this.onFinish});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  int _index = 0;

  void _next() {
    if (_index < _slides.length - 1) {
      setState(() => _index++);
    } else {
      widget.onFinish();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = useAppTheme(context);
    final c = theme.colors;
    final slide = _slides[_index];
    final width = MediaQuery.of(context).size.width;

    return Scaffold(
      backgroundColor: c.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            children: [
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: widget.onFinish,
                    child: Text('Skip', style: AppTypography.bodyMedium.copyWith(color: c.textSecondary)),
                  ),
                ],
              ),
              Expanded(
                child: Center(
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 250),
                    child: Column(
                      key: ValueKey(_index),
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: width * 0.45,
                          height: width * 0.45,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(color: c.primarySoft, shape: BoxShape.circle),
                          child: Icon(slide.icon, size: 64, color: c.primary),
                        ),
                        Padding(
                          padding: const EdgeInsets.only(top: 36),
                          child: Text(
                            slide.title,
                            textAlign: TextAlign.center,
                            style: AppTypography.h1.copyWith(color: c.text),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.only(top: 14),
                          child: Text(
                            slide.body,
                            textAlign: TextAlign.center,
                            style: AppTypography.body.copyWith(color: c.textSecondary),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(bottom: 32),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        for (var i = 0; i < _slides.length; i++)
                          AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            margin: const EdgeInsets.symmetric(horizontal: 4),
                            width: i == _index ? 22 : 8,
                            height: 8,
                            decoration: BoxDecoration(
                              color: i == _index ? c.primary : c.border,
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _next,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: c.primary,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.lg)),
                          elevation: 0,
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              _index == _slides.length - 1 ? 'Get Started' : 'Next',
                              style: AppTypography.bodyMedium.copyWith(color: Colors.white),
                            ),
                            const SizedBox(width: 8),
                            const Icon(Icons.arrow_forward, size: 18, color: Colors.white),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
