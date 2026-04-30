import 'package:flutter/material.dart';
import 'package:kilatex/core/services/rate_providers/rate_source.dart';

/// Compact pill-style badge that surfaces the on-disk `source` value for
/// an exchange-rate row. Phase 5 task 5.5 — adds visibility into the
/// rate's provenance directly in the "Tasas de cambio" list so the user
/// can tell at a glance whether a row was set by BCV/Paralelo/Frankfurter
/// auto-fetch or by their own manual override.
///
/// Pure presentation — no interactivity. The list-tile that renders the
/// badge owns the tap-to-edit affordance.
class RateSourceBadge extends StatelessWidget {
  const RateSourceBadge({super.key, required this.rawSource});

  /// The raw `source` string from `exchangeRates.source`. May be `null`
  /// for very old rows; we treat null as "Auto" (legacy fallback) per the
  /// design spec — older readers used to write `null` for the BCV path.
  final String? rawSource;

  @override
  Widget build(BuildContext context) {
    final raw = rawSource;
    final (label, color) = _resolveLabelAndColor(context, raw);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: color,
          letterSpacing: 0.2,
        ),
      ),
    );
  }

  (String, Color) _resolveLabelAndColor(BuildContext context, String? raw) {
    final scheme = Theme.of(context).colorScheme;

    if (raw == null) {
      // Legacy rows (pre-source-tagging) — treat as Auto for clarity.
      return ('Auto', scheme.primary);
    }
    final source = RateSource.fromDb(raw);
    switch (source) {
      case RateSource.bcv:
        return ('BCV', Colors.green);
      case RateSource.paralelo:
        return ('Paralelo', Colors.orange);
      case RateSource.autoFrankfurter:
        return ('Auto', scheme.primary);
      case RateSource.manual:
        return ('Manual', Colors.blueGrey);
    }
  }
}
