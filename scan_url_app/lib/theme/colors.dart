import 'package:flutter/material.dart';

/// Soft, smoky colour palette — minimalist professional aesthetic.
/// Ported 1:1 from the original React Native `theme/colors.ts`.
class AppColors {
  final Color background;
  final Color surface;
  final Color surfaceAlt;
  final Color surfaceMuted;
  final Color primary;
  final Color primaryDark;
  final Color primarySoft;
  final Color accent;
  final Color success;
  final Color successSoft;
  final Color warning;
  final Color warningSoft;
  final Color danger;
  final Color dangerSoft;
  final Color text;
  final Color textSecondary;
  final Color textTertiary;
  final Color border;
  final Color borderStrong;
  final Color muted;
  final Color overlay;
  final Color shadow;

  const AppColors({
    required this.background,
    required this.surface,
    required this.surfaceAlt,
    required this.surfaceMuted,
    required this.primary,
    required this.primaryDark,
    required this.primarySoft,
    required this.accent,
    required this.success,
    required this.successSoft,
    required this.warning,
    required this.warningSoft,
    required this.danger,
    required this.dangerSoft,
    required this.text,
    required this.textSecondary,
    required this.textTertiary,
    required this.border,
    required this.borderStrong,
    required this.muted,
    required this.overlay,
    required this.shadow,
  });

  static const light = AppColors(
    background: Color(0xFFF5F2F8),
    surface: Color(0xFFFFFFFF),
    surfaceAlt: Color(0xFFFAF8FC),
    surfaceMuted: Color(0xFFEFEAF4),
    primary: Color(0xFF7C6F9C),
    primaryDark: Color(0xFF5E527C),
    primarySoft: Color(0xFFEBE5F4),
    accent: Color(0xFFA899C4),
    success: Color(0xFF7FA88B),
    successSoft: Color(0xFFE2EEE5),
    warning: Color(0xFFD4A574),
    warningSoft: Color(0xFFF4E8D8),
    danger: Color(0xFFC58691),
    dangerSoft: Color(0xFFF0DDE0),
    text: Color(0xFF1F1B2E),
    textSecondary: Color(0xFF6B6478),
    textTertiary: Color(0xFF9B95A8),
    border: Color(0xFFECE8F2),
    borderStrong: Color(0xFFD9D3E2),
    muted: Color(0xFFB5AEC4),
    overlay: Color(0x731F1B2E),
    shadow: Color(0x1A5E527C),
  );

  static const dark = AppColors(
    background: Color(0xFF15131C),
    surface: Color(0xFF1F1C28),
    surfaceAlt: Color(0xFF28243A),
    surfaceMuted: Color(0xFF2A2638),
    primary: Color(0xFF9F92BD),
    primaryDark: Color(0xFF7C6F9C),
    primarySoft: Color(0xFF2F2A40),
    accent: Color(0xFFC7B9DE),
    success: Color(0xFF95C2A2),
    successSoft: Color(0xFF1F3329),
    warning: Color(0xFFE0BC8E),
    warningSoft: Color(0xFF3A2E1F),
    danger: Color(0xFFD89BA4),
    dangerSoft: Color(0xFF3A262B),
    text: Color(0xFFECE8F2),
    textSecondary: Color(0xFFA099B0),
    textTertiary: Color(0xFF6B6478),
    border: Color(0xFF2F2A40),
    borderStrong: Color(0xFF3F3854),
    muted: Color(0xFF5E5773),
    overlay: Color(0xA60F0D14),
    shadow: Color(0x59000000),
  );
}

enum RiskLevel { safe, caution, danger }

extension RiskColor on RiskLevel {
  Color color(AppColors c) {
    switch (this) {
      case RiskLevel.safe:
        return c.success;
      case RiskLevel.caution:
        return c.warning;
      case RiskLevel.danger:
        return c.danger;
    }
  }

  Color softColor(AppColors c) {
    switch (this) {
      case RiskLevel.safe:
        return c.successSoft;
      case RiskLevel.caution:
        return c.warningSoft;
      case RiskLevel.danger:
        return c.dangerSoft;
    }
  }
}
