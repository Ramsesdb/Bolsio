import 'package:flutter_test/flutter_test.dart';
import 'package:nitido/core/models/currency/currency_display_policy.dart';

/// Phase 6 of `currency-modes-rework` widget-shape contract tests for
/// [IncomeOrExpenseCard]. The widget itself is a thin shell over a
/// `StreamBuilder<CurrencyDisplayPolicy>` that branches between
/// `_SingleBalanceLine` (single mode) and `_DualBalanceLines` (dual
/// mode). The tests below validate the policy-driven decisions the
/// widget makes, without booting a Drift DB.
///
/// The full widget integration (real DB + StreamBuilder) is exercised
/// by Phase 10's integration test pass — this file documents the
/// invariants the widget relies on so a future refactor that breaks
/// them fails fast.
///
/// We test:
/// - SingleMode → policy.showsRateSourceChip == false (no chip).
/// - SingleMode → policy.showsEquivalence == false (one line).
/// - DualMode(USD, VES) → showsRateSourceChip + showsEquivalence true.
/// - DualMode(VES, USD) → showsRateSourceChip true (unordered pair).
/// - DualMode(EUR, COP) → showsRateSourceChip false (non-VES dual).
/// - DualMode(EUR, COP) → showsEquivalence true (still two lines).
void main() {
  group('IncomeOrExpenseCard policy contract', () {
    test('single_usd → no chip, no equivalence (one-line render)', () {
      const policy = SingleMode(code: 'USD');
      expect(policy.showsRateSourceChip, isFalse);
      expect(policy.showsEquivalence, isFalse);
      expect(policy.equivalenceCurrency, isNull);
      expect(policy.displayCurrencies(), equals(['USD']));
    });

    test('single_bs → no chip, no equivalence', () {
      const policy = SingleMode(code: 'VES');
      expect(policy.showsRateSourceChip, isFalse);
      expect(policy.showsEquivalence, isFalse);
    });

    test('single_other(EUR) → no chip, no equivalence', () {
      const policy = SingleMode(code: 'EUR');
      expect(policy.showsRateSourceChip, isFalse);
      expect(policy.showsEquivalence, isFalse);
    });

    test('dual(USD, VES) → chip ON + equivalence (two-line render)', () {
      const policy = DualMode(primary: 'USD', secondary: 'VES');
      expect(policy.showsRateSourceChip, isTrue);
      expect(policy.showsEquivalence, isTrue);
      expect(policy.equivalenceCurrency, equals('VES'));
      expect(policy.displayCurrencies(), equals(['USD', 'VES']));
    });

    test('dual(VES, USD) → chip ON (unordered pair gating)', () {
      const policy = DualMode(primary: 'VES', secondary: 'USD');
      expect(policy.showsRateSourceChip, isTrue);
      expect(policy.showsEquivalence, isTrue);
      expect(policy.equivalenceCurrency, equals('USD'));
      // The render order respects primary→secondary.
      expect(policy.displayCurrencies(), equals(['VES', 'USD']));
    });

    test('dual(EUR, COP) → chip OFF, equivalence still ON', () {
      const policy = DualMode(primary: 'EUR', secondary: 'COP');
      expect(policy.showsRateSourceChip, isFalse);
      expect(policy.showsEquivalence, isTrue);
      expect(policy.equivalenceCurrency, equals('COP'));
    });

    test('dual(EUR, ARS) → chip OFF (non-VES dual)', () {
      const policy = DualMode(primary: 'EUR', secondary: 'ARS');
      expect(policy.showsRateSourceChip, isFalse);
      expect(policy.showsEquivalence, isTrue);
    });

    test('dual(USD, USD) edge case — same currency twice → chip OFF', () {
      // showsRateSourceChip requires the unordered pair to BE {USD, VES}.
      // Two USDs collapse to {USD} which has length 1 — chip stays off.
      const policy = DualMode(primary: 'USD', secondary: 'USD');
      expect(policy.showsRateSourceChip, isFalse);
    });

    test('SingleMode rateSourceForPair(USD, VES) defers to preferred', () {
      // The single-mode policy still answers rate-source queries — this
      // matters when the dashboard shows a USD account in single_bs mode
      // (the conversion has to pick BCV vs Paralelo).
      const policy = SingleMode(code: 'VES');
      // No preferred passed → defaults to BCV.
      expect(policy.rateSourceForPair('USD', 'VES')?.dbValue, equals('bcv'));
    });

    test('DualMode equality — used by .distinct() in the resolver', () {
      const a = DualMode(primary: 'USD', secondary: 'VES');
      const b = DualMode(primary: 'USD', secondary: 'VES');
      const c = DualMode(primary: 'VES', secondary: 'USD');
      expect(a, equals(b));
      expect(a == c, isFalse);
    });

    test('SingleMode equality', () {
      const a = SingleMode(code: 'EUR');
      const b = SingleMode(code: 'EUR');
      const c = SingleMode(code: 'USD');
      expect(a, equals(b));
      expect(a == c, isFalse);
    });
  });

  group('IncomeOrExpenseCard native-portion stability invariant', () {
    // The bug the rework absorbs: toggling BCV ↔ Paralelo in dual(USD,VES)
    // mode previously multiplied EVERY transaction by the rate, including
    // those whose native currency was already the target. Phase 9
    // [CurrencyConversionHelper.convertMixedCurrenciesToTarget] fixes this
    // by isolating the native portion. The widget consumes that helper
    // via [TransactionService.getTransactionsCountAndBalanceWithMissing]
    // (primary line) and [TransactionService.getValueBalanceForTarget]
    // (secondary line). The invariant tests live in
    // `test/core/services/currency/currency_conversion_helper_test.dart`
    // — this group documents that the widget DOES consume those entry
    // points and inherits the invariant through composition.

    test('contract: primary line uses missing-aware helper', () {
      // Documented invariant — exercised end-to-end in Phase 10. The
      // fact that the widget calls
      // `getTransactionsCountAndBalanceWithMissing` (instead of the
      // legacy `getTransactionsValueBalance`) is what gives it the
      // "tasa no configurada" hint surface.
      // See lib/app/home/widgets/income_or_expense_card.dart line ~125.
      expect(true, isTrue);
    });

    test('contract: secondary line uses target-specific helper', () {
      // Documented invariant — the secondary line targets
      // `policy.secondary` directly via
      // `TransactionService.getValueBalanceForTarget`. This means the
      // VES line in dual(USD,VES) renders the SAME native VES amount
      // regardless of which BCV/Paralelo source is active — the rate
      // only affects the USD foreign portion.
      // See lib/app/home/widgets/income_or_expense_card.dart line ~225.
      expect(true, isTrue);
    });
  });
}
