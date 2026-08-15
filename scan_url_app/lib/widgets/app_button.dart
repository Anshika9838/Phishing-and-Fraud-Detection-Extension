import 'package:flutter/material.dart';
import '../theme/colors.dart';
import '../theme/typography.dart';

enum AppButtonVariant { primary, secondary, ghost, danger }

enum AppButtonSize { md, lg }

/// Direct port of the original `Button.tsx`.
class AppButton extends StatefulWidget {
  final String title;
  final VoidCallback? onPressed;
  final AppButtonVariant variant;
  final IconData? icon;
  final IconData? iconRight;
  final bool loading;
  final bool disabled;
  final bool fullWidth;
  final AppButtonSize size;
  final AppColors colors;

  const AppButton({
    super.key,
    required this.title,
    required this.onPressed,
    required this.colors,
    this.variant = AppButtonVariant.primary,
    this.icon,
    this.iconRight,
    this.loading = false,
    this.disabled = false,
    this.fullWidth = false,
    this.size = AppButtonSize.md,
  });

  @override
  State<AppButton> createState() => _AppButtonState();
}

class _AppButtonState extends State<AppButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final c = widget.colors;
    final disabled = widget.disabled || widget.loading;

    Color bg, fg, border;
    if (widget.disabled) {
      bg = c.surfaceMuted;
      fg = c.textTertiary;
      border = Colors.transparent;
    } else {
      switch (widget.variant) {
        case AppButtonVariant.primary:
          bg = c.primary;
          fg = Colors.white;
          border = Colors.transparent;
          break;
        case AppButtonVariant.secondary:
          bg = c.surface;
          fg = c.primary;
          border = c.border;
          break;
        case AppButtonVariant.ghost:
          bg = Colors.transparent;
          fg = c.primary;
          border = Colors.transparent;
          break;
        case AppButtonVariant.danger:
          bg = c.danger;
          fg = Colors.white;
          border = Colors.transparent;
          break;
      }
    }

    final padV = widget.size == AppButtonSize.lg ? 16.0 : 13.0;
    final padH = widget.size == AppButtonSize.lg ? 24.0 : 18.0;

    return GestureDetector(
      onTapDown: disabled ? null : (_) => setState(() => _pressed = true),
      onTapUp: disabled ? null : (_) => setState(() => _pressed = false),
      onTapCancel: disabled ? null : () => setState(() => _pressed = false),
      onTap: disabled ? null : widget.onPressed,
      child: AnimatedOpacity(
        opacity: _pressed ? 0.85 : 1,
        duration: const Duration(milliseconds: 100),
        child: Container(
          width: widget.fullWidth ? double.infinity : null,
          padding: EdgeInsets.symmetric(vertical: padV, horizontal: padH),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(AppRadius.lg),
            border: Border.all(color: border, width: 1),
          ),
          child: Center(
            child: widget.loading
                ? SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: fg),
                  )
                : Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (widget.icon != null) ...[
                        Icon(widget.icon, size: 18, color: fg),
                        const SizedBox(width: 8),
                      ],
                      Flexible(
                        child: Text(
                          widget.title,
                          style: AppTypography.bodyMedium.copyWith(color: fg),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (widget.iconRight != null) ...[
                        const SizedBox(width: 8),
                        Icon(widget.iconRight, size: 18, color: fg),
                      ],
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}
