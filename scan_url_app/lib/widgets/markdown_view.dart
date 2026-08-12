import 'package:flutter/material.dart';
import '../theme/colors.dart';
import '../theme/typography.dart';

/// Lightweight markdown renderer — handles headings, bullets, bold, line
/// breaks. Direct port of the original `MarkdownView.tsx`.
class MarkdownView extends StatelessWidget {
  final String content;
  final AppColors colors;
  const MarkdownView({super.key, required this.content, required this.colors});

  @override
  Widget build(BuildContext context) {
    final lines = content.split('\n');
    final children = <Widget>[];

    for (var idx = 0; idx < lines.length; idx++) {
      final line = lines[idx];
      final trimmed = line.trim();

      if (trimmed.isEmpty) {
        children.add(const SizedBox(height: 10));
        continue;
      }

      if (trimmed.startsWith('## ')) {
        children.add(Padding(
          padding: EdgeInsets.only(top: idx == 0 ? 0 : 14, bottom: 8),
          child: Text(
            trimmed.replaceFirst(RegExp(r'^##\s+'), ''),
            style: AppTypography.h3.copyWith(color: colors.text),
          ),
        ));
        continue;
      }

      if (trimmed.startsWith('### ')) {
        children.add(Padding(
          padding: const EdgeInsets.only(top: 10, bottom: 4),
          child: Text(
            trimmed.replaceFirst(RegExp(r'^###\s+'), ''),
            style: AppTypography.bodyMedium.copyWith(color: colors.primary),
          ),
        ));
        continue;
      }

      if (trimmed.startsWith('- ') || trimmed.startsWith('* ')) {
        final text = trimmed.replaceFirst(RegExp(r'^[-*]\s+'), '');
        children.add(Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 8, right: 10),
                child: Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(color: colors.primary, shape: BoxShape.circle),
                ),
              ),
              Expanded(
                child: Text.rich(
                  _renderInline(text, colors),
                  style: AppTypography.body.copyWith(color: colors.text),
                ),
              ),
            ],
          ),
        ));
        continue;
      }

      children.add(Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Text.rich(
          _renderInline(trimmed, colors),
          style: AppTypography.body.copyWith(color: colors.text),
        ),
      ));
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: children);
  }

  /// Parses `**bold**` inline spans.
  TextSpan _renderInline(String text, AppColors colors) {
    final spans = <InlineSpan>[];
    final regex = RegExp(r'\*\*(.+?)\*\*');
    var lastIdx = 0;
    for (final match in regex.allMatches(text)) {
      if (match.start > lastIdx) {
        spans.add(TextSpan(text: text.substring(lastIdx, match.start)));
      }
      spans.add(TextSpan(
        text: match.group(1),
        style: TextStyle(fontWeight: FontWeight.w700, color: colors.text),
      ));
      lastIdx = match.end;
    }
    if (lastIdx < text.length) {
      spans.add(TextSpan(text: text.substring(lastIdx)));
    }
    return TextSpan(children: spans);
  }
}
