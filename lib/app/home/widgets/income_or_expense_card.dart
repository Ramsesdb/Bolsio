import 'package:flutter/material.dart';
import 'package:skeletonizer/skeletonizer.dart';
import 'package:bolsio/core/database/services/transaction/transaction_service.dart';
import 'package:bolsio/core/models/currency/currency_display_policy.dart';
import 'package:bolsio/core/models/currency/currency_display_policy_resolver.dart';
import 'package:bolsio/core/models/date-utils/date_period_state.dart';
import 'package:bolsio/core/presentation/app_colors.dart';
import 'package:bolsio/core/presentation/widgets/number_ui_formatters/currency_displayer.dart';
import 'package:bolsio/core/presentation/widgets/transaction_filter/transaction_filter_set.dart';

import '../../../core/models/transaction/transaction_type.enum.dart';

/// Compact per-period income/expense indicator that lives at the top of the
/// dashboard header. Phase 6 of `currency-modes-rework`:
///
/// - Drops the legacy `String? rateSource` constructor argument — the BCV/
///   Paralelo source lives in the `CurrencyDisplayPolicy` (driven by the
///   resolver stream).
/// - Subscribes to [CurrencyDisplayPolicyResolver.instance.watch] so the
///   render reacts to mode toggles in Settings without a manual reload.
/// - For [SingleMode]: one line in `policy.code`. No secondary equivalence
///   and no glyph "≈".
/// - For [DualMode]: two lines — primary in `policy.primary`, secondary in
///   `policy.secondary` (visually subordinated). Both lines come from the
///   missing-aware helper [TransactionService.getTransactionsCountAndBalanceWithMissing]
///   (primary) and [TransactionService.getValueBalanceForTarget] (secondary).
///   The native-currency portion (e.g. USD when `primary='USD'`, VES when
///   `secondary='VES'`) is preserved verbatim — toggling BCV ↔ Paralelo
///   only re-converts the foreign portion (the bug the rework absorbs).
class IncomeOrExpenseCard extends StatelessWidget {
  const IncomeOrExpenseCard({
    super.key,
    required this.type,
    required this.periodState,
    required this.labelStyle,
    this.filters,
  });

  final TransactionType type;

  final DatePeriodState periodState;

  final TransactionFilterSet? filters;

  final TextStyle? labelStyle;

  TransactionFilterSet _buildFilters() {
    return TransactionFilterSet(
      accountsIDs: filters?.accountsIDs,
      categoriesIds: filters?.categoriesIds,
      minDate: periodState.startDate,
      maxDate: periodState.endDate,
      transactionTypes: [type],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
      child: StreamBuilder<CurrencyDisplayPolicy>(
        stream: CurrencyDisplayPolicyResolver.instance.watch(),
        builder: (context, policySnapshot) {
          final policy = policySnapshot.data;
          return Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: type.color(context),
                  borderRadius: BorderRadius.circular(80),
                ),
                child: Icon(
                  type.icon,
                  color: Theme.of(context).colorScheme.surface,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(type.displayName(context), style: labelStyle),
                  if (policy == null)
                    _buildSkeletonAmount(context)
                  else if (policy is DualMode)
                    _DualBalanceLines(filters: _buildFilters(), policy: policy)
                  else
                    _SingleBalanceLine(
                      filters: _buildFilters(),
                      policy: policy as SingleMode,
                    ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildSkeletonAmount(BuildContext context) {
    return Skeletonizer(
      enabled: true,
      child: CurrencyDisplayer(
        amountToConvert: 9999,
        compactView: true,
        showDecimals: false,
        integerStyle: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w300,
          color: AppColors.of(context).onHeader,
        ),
      ),
    );
  }
}

/// Single-line render for [SingleMode]. Surfaces the converted total in
/// `policy.code`. Hides the equivalence row entirely (no "≈ Bs" line).
class _SingleBalanceLine extends StatelessWidget {
  const _SingleBalanceLine({required this.filters, required this.policy});

  final TransactionFilterSet filters;
  // ignore: unused_element_parameter
  final SingleMode policy;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<TransactionQueryStatResultWithMissing>(
      stream: TransactionService.instance
          .getTransactionsCountAndBalanceWithMissing(filters: filters),
      builder: (context, snapshot) {
        final hasData = snapshot.hasData;
        final amount = snapshot.data?.valueSum.abs() ?? 9999;
        final hasMissing = snapshot.data?.hasMissingRates ?? false;
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Skeletonizer(
              enabled: !hasData,
              child: CurrencyDisplayer(
                amountToConvert: amount,
                compactView: true,
                showDecimals: false,
                integerStyle: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w300,
                  color: AppColors.of(context).onHeader,
                ),
              ),
            ),
            if (hasMissing) ...[
              const SizedBox(width: 4),
              _MissingRateHint(missing: snapshot.data!.missingRateCurrencies),
            ],
          ],
        );
      },
    );
  }
}

/// Two-line render for [DualMode]. The primary line shows the converted
/// total in `policy.primary`; the secondary line (smaller, muted) shows
/// the same set of transactions converted to `policy.secondary`. Native
/// portions (transactions whose account currency already equals the
/// target) are NEVER multiplied by a rate — only foreign portions are
/// re-converted when the user toggles BCV ↔ Paralelo.
class _DualBalanceLines extends StatelessWidget {
  const _DualBalanceLines({required this.filters, required this.policy});

  final TransactionFilterSet filters;
  final DualMode policy;

  @override
  Widget build(BuildContext context) {
    final primary$ = TransactionService.instance
        .getTransactionsCountAndBalanceWithMissing(filters: filters);
    return StreamBuilder<TransactionQueryStatResultWithMissing>(
      stream: primary$,
      builder: (context, primarySnap) {
        final hasPrimary = primarySnap.hasData;
        final primaryAmount = primarySnap.data?.valueSum.abs() ?? 9999;
        final hasMissing = primarySnap.data?.hasMissingRates ?? false;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Skeletonizer(
                  enabled: !hasPrimary,
                  child: CurrencyDisplayer(
                    amountToConvert: primaryAmount,
                    compactView: true,
                    showDecimals: false,
                    integerStyle: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w300,
                      color: AppColors.of(context).onHeader,
                    ),
                  ),
                ),
                if (hasMissing) ...[
                  const SizedBox(width: 4),
                  _MissingRateHint(
                    missing: primarySnap.data!.missingRateCurrencies,
                  ),
                ],
              ],
            ),
            // Secondary equivalence line. Only render when the primary
            // line has rendered to keep the row layout stable during the
            // cold-start frame.
            if (hasPrimary)
              _SecondaryEquivalenceLine(
                filters: filters,
                policy: policy,
              ),
          ],
        );
      },
    );
  }
}

/// Renders the secondary equivalence line for [DualMode]. Uses the
/// Phase-6 [TransactionService.getValueBalanceForTarget] entry point so
/// the secondary currency drives the per-native conversion directly —
/// the native VES portion stays at its native value when
/// `secondary='VES'`, which is the bug-fix this rework absorbs.
class _SecondaryEquivalenceLine extends StatelessWidget {
  const _SecondaryEquivalenceLine({
    required this.filters,
    required this.policy,
  });

  final TransactionFilterSet filters;
  final DualMode policy;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<double?>(
      stream: TransactionService.instance.getValueBalanceForTarget(
        filters: filters,
        targetCurrency: policy.secondary,
      ),
      builder: (context, snapshot) {
        if (!snapshot.hasData || snapshot.data == null) {
          return const SizedBox.shrink();
        }
        final amount = snapshot.data!.abs();
        final formatted = amount.toStringAsFixed(2).replaceAllMapped(
              RegExp(r'(\d)(?=(\d{3})+(?!\d))'),
              (m) => '${m[1]}.',
            );
        return BlurBasedOnPrivateMode(
          child: Text(
            '≈ $formatted ${_secondarySymbol(policy.secondary)}',
            style: TextStyle(
              fontSize: 11,
              color: AppColors.of(context).onHeaderSubtle,
            ),
          ),
        );
      },
    );
  }

  String _secondarySymbol(String code) {
    if (code == 'VES') return 'Bs';
    return code;
  }
}

/// Compact "tasa no configurada" hint icon shown next to the converted
/// amount when one or more native currencies in the period lacked a rate.
class _MissingRateHint extends StatelessWidget {
  const _MissingRateHint({required this.missing});

  final Set<String> missing;

  @override
  Widget build(BuildContext context) {
    final list = missing.join(', ');
    return Tooltip(
      message: 'Tasa no configurada para: $list',
      child: Icon(
        Icons.info_outline,
        size: 14,
        color: Colors.amber.withValues(alpha: 0.85),
      ),
    );
  }
}
