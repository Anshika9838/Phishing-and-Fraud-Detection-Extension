import 'package:flutter/material.dart';
import '../services/storage_service.dart';
import 'main_tabs_screen.dart';
import 'onboarding_screen.dart';
import 'splash_screen.dart';
import 'terms_screen.dart';

enum _Stage { splash, onboarding, terms, main }

/// Direct port of the original `RootNavigator.tsx`, with the `auth` stage
/// and login screen removed entirely per product requirement #2. The
/// flow is now: splash -> onboarding -> terms -> main.
class RootNavigator extends StatefulWidget {
  const RootNavigator({super.key});

  @override
  State<RootNavigator> createState() => _RootNavigatorState();
}

class _RootNavigatorState extends State<RootNavigator> {
  _Stage _stage = _Stage.splash;
  bool _onboardingDone = false;
  bool _termsAccepted = false;
  late final Future<void> _bootstrapFuture;

  @override
  void initState() {
    super.initState();
    _bootstrapFuture = _bootstrap();
  }

  Future<void> _bootstrap() async {
    final onboardingDone = await StorageService.instance.isOnboardingDone();
    final termsAccepted = await StorageService.instance.isTermsAccepted();
    if (!mounted) return;
    setState(() {
      _onboardingDone = onboardingDone;
      _termsAccepted = termsAccepted;
    });
  }

  /// Waits for storage to finish loading (in case the splash timer fires
  /// first) then advances to the correct next stage.
  Future<void> _resolveNextStage() async {
    await _bootstrapFuture;
    if (!mounted) return;
    setState(() {
      if (!_onboardingDone) {
        _stage = _Stage.onboarding;
      } else if (!_termsAccepted) {
        _stage = _Stage.terms;
      } else {
        _stage = _Stage.main;
      }
    });
  }

  Future<void> _completeOnboarding() async {
    await StorageService.instance.setOnboardingDone();
    if (!mounted) return;
    setState(() {
      _onboardingDone = true;
      _stage = _termsAccepted ? _Stage.main : _Stage.terms;
    });
  }

  Future<void> _acceptTerms() async {
    await StorageService.instance.acceptTerms();
    if (!mounted) return;
    setState(() {
      _termsAccepted = true;
      _stage = _Stage.main;
    });
  }

  @override
  Widget build(BuildContext context) {
    switch (_stage) {
      case _Stage.splash:
        return SplashScreen(onFinish: _resolveNextStage);
      case _Stage.onboarding:
        return OnboardingScreen(onFinish: _completeOnboarding);
      case _Stage.terms:
        return TermsScreen(onAccept: _acceptTerms);
      case _Stage.main:
        return const MainTabsScreen();
    }
  }
}
