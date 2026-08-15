import 'package:flutter/material.dart';
import '../theme/theme_scope.dart';
import '../theme/typography.dart';
import '../widgets/shield_logo.dart';

/// Direct port of the original `SplashScreen.tsx`: logo fades/scales in,
/// title+subtitle fade/slide in after a short delay, then auto-advances
/// after 2 seconds.
class SplashScreen extends StatefulWidget {
  final VoidCallback onFinish;
  const SplashScreen({super.key, required this.onFinish});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with TickerProviderStateMixin {
  late final AnimationController _logoController;
  late final AnimationController _textController;
  late final Animation<double> _logoOpacity;
  late final Animation<double> _logoScale;
  late final Animation<double> _textOpacity;
  late final Animation<Offset> _textOffset;

  @override
  void initState() {
    super.initState();
    _logoController = AnimationController(vsync: this, duration: const Duration(milliseconds: 900));
    _textController = AnimationController(vsync: this, duration: const Duration(milliseconds: 600));

    _logoOpacity = CurvedAnimation(
      parent: _logoController,
      curve: const Interval(0, 700 / 900, curve: Curves.linear),
    );
    _logoScale = Tween<double>(begin: 0.85, end: 1).animate(
      CurvedAnimation(parent: _logoController, curve: Curves.easeOutCubic),
    );
    _textOpacity = CurvedAnimation(parent: _textController, curve: Curves.linear);
    _textOffset = Tween<Offset>(begin: const Offset(0, 0.15), end: Offset.zero).animate(
      CurvedAnimation(parent: _textController, curve: Curves.easeOut),
    );

    _logoController.forward();
    Future.delayed(const Duration(milliseconds: 450), () {
      if (mounted) _textController.forward();
    });
    Future.delayed(const Duration(milliseconds: 2000), () {
      if (mounted) widget.onFinish();
    });
  }

  @override
  void dispose() {
    _logoController.dispose();
    _textController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = useAppTheme(context);
    final c = theme.colors;
    return Scaffold(
      backgroundColor: c.background,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            FadeTransition(
              opacity: _logoOpacity,
              child: ScaleTransition(scale: _logoScale, child: ShieldLogo(size: 88, colors: c)),
            ),
            const SizedBox(height: 24),
            FadeTransition(
              opacity: _textOpacity,
              child: SlideTransition(
                position: _textOffset,
                child: Column(
                  children: [
                    Text('ShieldURL',
                        style: AppTypography.h1.copyWith(color: c.text, letterSpacing: -0.5)),
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        'Verify before you click.',
                        textAlign: TextAlign.center,
                        style: AppTypography.body.copyWith(color: c.textSecondary),
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
}
