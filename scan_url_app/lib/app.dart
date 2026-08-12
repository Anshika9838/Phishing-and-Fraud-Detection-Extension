import 'package:flutter/material.dart';
import 'screens/root_navigator.dart';
import 'theme/colors.dart';

/// Direct port of the original `App.tsx`. Follows system light/dark mode
/// automatically, exactly like the original `ThemeContext`
/// (`useColorScheme()` with no manual toggle).
class TheftAlertApp extends StatelessWidget {
  const TheftAlertApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ShieldURL',
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.system,
      theme: _buildThemeData(AppColors.light, Brightness.light),
      darkTheme: _buildThemeData(AppColors.dark, Brightness.dark),
      home: const RootNavigator(),
    );
  }

  ThemeData _buildThemeData(AppColors c, Brightness brightness) {
    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      scaffoldBackgroundColor: c.background,
      colorScheme: ColorScheme.fromSeed(seedColor: c.primary, brightness: brightness),
    );
  }
}
