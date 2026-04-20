import 'package:flutter/material.dart';

class StatementImportCounter extends StatelessWidget {
  const StatementImportCounter({
    super.key,
    required this.filtered,
    required this.total,
    this.modeLabel,
  });

  final int filtered;
  final int total;
  final String? modeLabel;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: cs.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: cs.primary.withValues(alpha: 0.25),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                RichText(
                  text: TextSpan(
                    style: tt.headlineMedium?.copyWith(
                      color: cs.primary,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.6,
                    ),
                    children: [
                      TextSpan(text: '$filtered'),
                      TextSpan(
                        text: ' de $total',
                        style: tt.titleMedium?.copyWith(
                          color: cs.onSurfaceVariant,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  modeLabel == null
                      ? 'filas se importarán'
                      : 'filas se importarán · $modeLabel',
                  style: tt.bodySmall?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: cs.primary,
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: Icon(
              Icons.south_rounded,
              color: cs.onPrimary,
              size: 22,
            ),
          ),
        ],
      ),
    );
  }
}
