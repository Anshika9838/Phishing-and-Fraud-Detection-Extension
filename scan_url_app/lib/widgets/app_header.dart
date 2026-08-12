import 'package:flutter/material.dart';
import '../theme/colors.dart';
import '../theme/typography.dart';

/// Direct port of the original `Header.tsx`.
class AppHeader extends StatelessWidget {
  final String title;
  final String? subtitle;
  final IconData? leftIcon;
  final VoidCallback? onLeftPressed;
  final IconData? rightIcon;
  final VoidCallback? onRightPressed;
  final AppColors colors;

  const AppHeader({
    super.key,
    required this.title,
    required this.colors,
    this.subtitle,
    this.leftIcon,
    this.onLeftPressed,
    this.rightIcon,
    this.onRightPressed,
  });

  @override
  Widget build(BuildContext context) {
    final c = colors;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 20),
      child: Row(
        children: [
          if (leftIcon != null) _IconBtn(icon: leftIcon!, onTap: onLeftPressed, colors: c),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(left: leftIcon != null ? 12 : 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(title, style: AppTypography.h2.copyWith(color: c.text)),
                  if (subtitle != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(subtitle!, style: AppTypography.caption.copyWith(color: c.textSecondary)),
                    ),
                ],
              ),
            ),
          ),
          if (rightIcon != null) _IconBtn(icon: rightIcon!, onTap: onRightPressed, colors: c),
        ],
      ),
    );
  }
}

class _IconBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;
  final AppColors colors;
  const _IconBtn({required this.icon, required this.onTap, required this.colors});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: 40,
        height: 40,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: colors.border, width: 1),
        ),
        child: Icon(icon, size: 20, color: colors.text),
      ),
    );
  }
}
