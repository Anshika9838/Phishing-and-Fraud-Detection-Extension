import 'package:flutter/material.dart';
import '../models/scan_report.dart';
import '../theme/colors.dart';
import '../theme/theme_scope.dart';
import '../theme/typography.dart';
import 'detail_screen.dart';
import 'history_screen.dart';
import 'home_screen.dart';
import 'settings_screen.dart';

/// Direct port of the original `MainTabs.tsx`. The `onSignOut` callback
/// and auth wiring have been removed along with the login screen.
class MainTabsScreen extends StatefulWidget {
  const MainTabsScreen({super.key});

  @override
  State<MainTabsScreen> createState() => _MainTabsScreenState();
}

class _MainTabsScreenState extends State<MainTabsScreen> {
  int _tabIndex = 0;
  int _historyTick = 0;
  ScanReport? _activeReport;

  void _refreshHistory() => setState(() => _historyTick++);

  @override
  Widget build(BuildContext context) {
    final theme = useAppTheme(context);
    final c = theme.colors;

    if (_activeReport != null) {
      return DetailScreen(
        report: _activeReport!,
        onBack: () => setState(() => _activeReport = null),
        onDeleted: () => setState(() {
          _activeReport = null;
          _historyTick++;
        }),
      );
    }

    final pages = [
      HomeScreen(onScanSaved: _refreshHistory),
      HistoryScreen(
        key: ValueKey('history_$_historyTick'),
        onSelectReport: (r) => setState(() => _activeReport = r),
      ),
      const SettingsScreen(),
    ];

    return Scaffold(
      backgroundColor: c.background,
      body: IndexedStack(index: _tabIndex, children: pages),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: c.surface,
          border: Border(top: BorderSide(color: c.border, width: 1)),
        ),
        child: SafeArea(
          top: false,
          child: SizedBox(
            height: 64,
            child: Row(
              children: [
                _TabItem(
                  label: 'Scan',
                  activeIcon: Icons.verified_user,
                  inactiveIcon: Icons.verified_user_outlined,
                  selected: _tabIndex == 0,
                  colors: c,
                  onTap: () => setState(() => _tabIndex = 0),
                ),
                _TabItem(
                  label: 'History',
                  activeIcon: Icons.access_time_filled,
                  inactiveIcon: Icons.access_time,
                  selected: _tabIndex == 1,
                  colors: c,
                  onTap: () => setState(() => _tabIndex = 1),
                ),
                _TabItem(
                  label: 'Settings',
                  activeIcon: Icons.settings,
                  inactiveIcon: Icons.settings_outlined,
                  selected: _tabIndex == 2,
                  colors: c,
                  onTap: () => setState(() => _tabIndex = 2),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TabItem extends StatelessWidget {
  final String label;
  final IconData activeIcon;
  final IconData inactiveIcon;
  final bool selected;
  final VoidCallback onTap;
  final AppColors colors;
  const _TabItem({
    required this.label,
    required this.activeIcon,
    required this.inactiveIcon,
    required this.selected,
    required this.onTap,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    final color = selected ? colors.primary : colors.textTertiary;
    return Expanded(
      child: InkWell(
        onTap: onTap,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(selected ? activeIcon : inactiveIcon, size: 22, color: color),
            const SizedBox(height: 2),
            Text(label, style: AppTypography.caption.copyWith(color: color, fontSize: 11)),
          ],
        ),
      ),
    );
  }
}
