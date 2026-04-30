import 'package:flutter/material.dart';
import 'package:bolsio/app/chat/theme/bolsio_ai_tokens.dart';

class SuggestChips extends StatelessWidget {
  const SuggestChips({
    super.key,
    required this.suggestions,
    required this.onTap,
    this.padding,
  });

  final List<String> suggestions;
  final void Function(String suggestion) onTap;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    if (suggestions.isEmpty) return const SizedBox.shrink();

    final tokens = BolsioAiTokens.of(context);
    final bg = tokens.accent.withValues(alpha: 0.08);
    final border = tokens.accent.withValues(alpha: 0.44);

    return Padding(
      padding: padding ?? EdgeInsets.zero,
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: suggestions
            .map(
              (label) => Material(
                color: bg,
                shape: StadiumBorder(
                  side: BorderSide(color: border, width: 1),
                ),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: () => onTap(label),
                  customBorder: const StadiumBorder(),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 8,
                    ),
                    child: Text(
                      label,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0,
                        color: tokens.accent,
                      ),
                    ),
                  ),
                ),
              ),
            )
            .toList(),
      ),
    );
  }
}
