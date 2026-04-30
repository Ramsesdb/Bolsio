import 'package:flutter/material.dart';
import 'package:bolsio/core/models/account/account.dart';

class SiHeader extends StatelessWidget {
  const SiHeader({super.key, required this.account});

  final Account account;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    final tail = _tailDigits(account.iban);

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
      decoration: BoxDecoration(
        color: cs.surface,
        border: Border(
          bottom: BorderSide(color: Theme.of(context).dividerColor),
        ),
      ),
      child: Row(
        children: [
          account.displayIcon(context, size: 36),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Cuenta destino'.toUpperCase(),
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: cs.onSurfaceVariant,
                    letterSpacing: 0.4,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  tail != null ? '${account.name}  ·· $tail' : account.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String? _tailDigits(String? iban) {
    if (iban == null) return null;
    final cleaned = iban.replaceAll(RegExp(r'\s+'), '');
    if (cleaned.length < 4) return null;
    return cleaned.substring(cleaned.length - 4);
  }
}
