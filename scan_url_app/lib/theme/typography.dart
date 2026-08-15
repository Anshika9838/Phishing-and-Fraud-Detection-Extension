import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

/// Ported 1:1 from the original React Native `theme/typography.ts`.
class AppTypography {
  static const TextStyle display = TextStyle(
    fontSize: 34,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.8,
    height: 40 / 34,
  );

  static const TextStyle h1 = TextStyle(
    fontSize: 28,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.6,
    height: 34 / 28,
  );

  static const TextStyle h2 = TextStyle(
    fontSize: 22,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.4,
    height: 28 / 22,
  );

  static const TextStyle h3 = TextStyle(
    fontSize: 18,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.2,
    height: 24 / 18,
  );

  static const TextStyle body = TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.w400,
    height: 24 / 16,
  );

  static const TextStyle bodyMedium = TextStyle(
    fontSize: 15,
    fontWeight: FontWeight.w500,
    height: 22 / 15,
  );

  static const TextStyle bodySmall = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w400,
    height: 20 / 14,
  );

  static const TextStyle caption = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w500,
    letterSpacing: 0.3,
    height: 16 / 12,
  );

  static const TextStyle micro = TextStyle(
    fontSize: 11,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.6,
    height: 14 / 11,
  );

  static TextStyle get mono => TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w500,
        letterSpacing: 0.1,
        fontFamily: (!kIsWeb && Platform.isIOS) ? 'Menlo' : 'monospace',
      );
}

class AppSpacing {
  static const double xxs = 4;
  static const double xs = 8;
  static const double sm = 12;
  static const double md = 16;
  static const double lg = 20;
  static const double xl = 24;
  static const double xxl = 32;
  static const double xxxl = 48;
}

class AppRadius {
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 22;
  static const double xxl = 28;
  static const double pill = 999;
}
