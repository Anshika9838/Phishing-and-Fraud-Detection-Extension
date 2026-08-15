import 'package:flutter/material.dart';
import '../theme/colors.dart';
import '../theme/typography.dart';

/// Direct port of the original `Input.tsx`.
class AppInput extends StatelessWidget {
  final TextEditingController controller;
  final String? placeholder;
  final String? error;
  final IconData? leadingIcon;
  final Widget? trailing;
  final bool enabled;
  final TextInputType keyboardType;
  final TextInputAction textInputAction;
  final ValueChanged<String>? onChanged;
  final VoidCallback? onSubmitted;
  final AppColors colors;

  const AppInput({
    super.key,
    required this.controller,
    required this.colors,
    this.placeholder,
    this.error,
    this.leadingIcon,
    this.trailing,
    this.enabled = true,
    this.keyboardType = TextInputType.url,
    this.textInputAction = TextInputAction.search,
    this.onChanged,
    this.onSubmitted,
  });

  @override
  Widget build(BuildContext context) {
    final c = colors;
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            constraints: const BoxConstraints(minHeight: 50),
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              color: c.surface,
              borderRadius: BorderRadius.circular(AppRadius.lg),
              border: Border.all(color: error != null ? c.danger : c.border, width: 1),
            ),
            child: Row(
              children: [
                if (leadingIcon != null) ...[
                  Icon(leadingIcon, size: 18, color: c.textTertiary),
                  const SizedBox(width: 10),
                ],
                Expanded(
                  child: TextField(
                    controller: controller,
                    enabled: enabled,
                    keyboardType: keyboardType,
                    textInputAction: textInputAction,
                    autocorrect: false,
                    style: AppTypography.body.copyWith(color: c.text),
                    decoration: InputDecoration(
                      isDense: true,
                      border: InputBorder.none,
                      hintText: placeholder,
                      hintStyle: AppTypography.body.copyWith(color: c.textTertiary),
                      contentPadding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    onChanged: onChanged,
                    onSubmitted: (_) => onSubmitted?.call(),
                  ),
                ),
                if (trailing != null) trailing!,
              ],
            ),
          ),
          if (error != null)
            Padding(
              padding: const EdgeInsets.only(top: 6, left: 4),
              child: Text(error!, style: AppTypography.caption.copyWith(color: c.danger)),
            ),
        ],
      ),
    );
  }
}
