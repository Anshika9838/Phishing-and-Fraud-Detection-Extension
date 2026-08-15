import 'package:flutter/material.dart';
import 'colors.dart';

/// Exposes the correct [AppColors] palette for the current system
/// brightness, mirroring the original `ThemeContext.tsx` which followed
/// `useColorScheme()` automatically (no manual toggle).
class AppTheme {
  final AppColors colors;
  final bool isDark;
  const AppTheme({required this.colors, required this.isDark});
}

AppTheme useAppTheme(BuildContext context) {
  final brightness = MediaQuery.platformBrightnessOf(context);
  final isDark = brightness == Brightness.dark;
  return AppTheme(colors: isDark ? AppColors.dark : AppColors.light, isDark: isDark);
}
