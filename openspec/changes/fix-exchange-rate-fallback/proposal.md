# Proposal: fix-exchange-rate-fallback

**Date:** 2026-04-16
**Author:** Ramses Briceno
**Status:** Draft
**Change ID:** fix-exchange-rate-fallback

---

## 1. Intent

The Monekin Finance app uses `COALESCE(excRate.exchangeRate, 1)` in 6 SQL locations to convert account balances and transaction amounts into the user's preferred currency. When no exchange rate exists for a given currency (e.g., VES with preferred currency USD), the fallback value of `1` causes the raw amount in the foreign currency to be treated as if it were already in the preferred currency.

This produces three catastrophic display errors:

1. **"Saldo por cuentas"** shows inflated per-account balances (e.g., 358,683 Bs displayed as $358,683).
2. **"Saldo final"** sums VES and USD amounts as if they were the same unit, producing a total like 1.1M "USD".
3. **Fund evolution chart** is completely distorted because historical data points almost never have stored exchange rates (the rate provider only supports today's date).

The Dart-side `ExchangeRateService.calculateExchangeRateToPreferredCurrency()` already returns `null` when no rate exists, which is the correct behavior. The SQL queries must be brought into alignment with this approach.

---

## 2. Scope

### In Scope

- All 6 SQL locations using `COALESCE(excRate.exchangeRate, 1)`
- Display logic in callers that consume converted amounts (to handle NULL/unconvertible cases)
- Aggregation logic for totals and charts when mixed currencies cannot all be converted
- Transaction filter expressions that compare amounts in preferred currency

### Out of Scope

- Adding new exchange rate providers or historical rate APIs
- Changing the exchange rate table schema
- Modifying the rate fetching lifecycle or `backfillMissingRates()` implementation
- Dashboard page (it already uses Dart-side conversion and is partially protected)
- Onboarding flow or currency selection UX

---

## 3. Approach

The fix is structured as four tiers, each building on the previous one. Tiers 1 and 2 address the data layer (SQL). Tiers 3 and 4 address the presentation layer (Flutter widgets).

### Tier 1 -- SQL Fix: NULL Propagation

**What:** Replace `COALESCE(excRate.exchangeRate, 1)` with `excRate.exchangeRate` in all 6 locations.

**Effect:** When no exchange rate exists, the multiplication `value * NULL` yields `NULL` instead of the raw foreign-currency amount. Amounts without rates become invisible in totals rather than catastrophically inflated.

**Locations:**

| # | File | Line | Expression |
|---|------|------|------------|
| 1 | `select-full-data.drift` | 49 | `t.value * excRate.exchangeRate` |
| 2 | `select-full-data.drift` | 50 | `t.valueInDestiny * excRateOfDestiny.exchangeRate` |
| 3 | `select-full-data.drift` | 102 | `SUM(t.value * excRate.exchangeRate)` |
| 4 | `select-full-data.drift` | 103 | `SUM(COALESCE(t.valueInDestiny,t.value) * excRateOfDestiny.exchangeRate)` |
| 5 | `account_service.dart` | 144 | `accounts.iniValue * excRate.exchangeRate` |
| 6-7 | `transaction_filter_set.dart` | 161, 166 | `ABS(t.value * excRate.exchangeRate)` |

**Important exception:** The outer `COALESCE(SUM(...), 0)` in locations 3-4 must be preserved -- it correctly handles the case where ALL values are NULL (returns 0 instead of NULL for the total).

**Note on preferred-currency accounts:** The original `COALESCE(..., 1)` was partly intended for accounts whose currency IS the preferred currency (no rate entry exists because rate = 1.0 implicitly). This case must be handled by ensuring that the exchange rate JOIN subquery returns 1.0 for the preferred currency, OR by adding an explicit `CASE WHEN accounts.currencyId = ? THEN 1.0 ELSE excRate.exchangeRate END` where `?` is the preferred currency code.

### Tier 2 -- Transaction Fallback: Use `exchangeRateApplied`

**What:** For individual transaction queries (locations 1-2 in `getTransactionsWithFullData`), use the rate that was stored at transaction creation time as a secondary fallback:

```sql
t.value * COALESCE(excRate.exchangeRate, t.exchangeRateApplied) AS currentValueInPreferredCurrency
```

**Rationale:** The `exchangeRateApplied` field records the BCV/paralelo/manual rate the user selected when creating the transaction. For historical transactions where the `exchangeRates` table lacks data, this provides a reasonable conversion rate.

**Limitations:**
- `exchangeRateApplied` is nullable -- older transactions or same-currency transactions will not have it.
- It represents the rate at transaction time, not the current rate. For "current value" displays this is slightly inconsistent, but far better than treating 1 VES = 1 USD.
- It does NOT help with account initial balances (`iniValue` in location 5) because initial balances have no associated transaction record.

**For aggregation queries (locations 3-4):** Also apply the same fallback:

```sql
SUM(t.value * COALESCE(excRate.exchangeRate, t.exchangeRateApplied))
```

### Tier 3 -- Display Separation: Native Currency for Unconvertible Amounts

**What:** When a converted amount is `null` (no rate available and no `exchangeRateApplied`), display the amount in its native currency instead of silently dropping it or showing it with the wrong symbol.

**Implementation:**

In callers of `CurrencyDisplayer` where converted amounts may be null:

```dart
// Before (wrong):
CurrencyDisplayer(amountToConvert: accountWithMoney.money)
// Shows "$358,683" for a VES account with no rate

// After (correct):
CurrencyDisplayer(
  amountToConvert: accountWithMoney.moneyInPreferred ?? accountWithMoney.moneyInNative,
  currency: accountWithMoney.moneyInPreferred != null ? null : account.currency,
)
// Shows "Bs 358,683" when no rate exists, "$9,684" when rate exists
```

**Affected widgets:**
- `all_accounts_balance.dart` -- per-account balance display
- `fund_evolution_info.dart` -- chart header balance

**Model changes:** `AccountWithMoney` (or equivalent data class) must carry both the preferred-currency amount (nullable) and the native-currency amount (non-null), plus a reference to `account.currency`.

### Tier 4 -- Aggregation Logic: Separated Totals for Mixed Currencies

**What:** When computing totals (Saldo final, chart data points), separate convertible amounts from unconvertible ones. Instead of silently dropping unconvertible balances from the total, present a compound display.

**Display format:**

```
$747 + Bs 380,768
```

or, if all accounts are convertible:

```
$748,415
```

**Implementation approach:**

1. `getAccountsMoney()` returns a richer type than `double`:

```dart
class MoneyBalance {
  final double convertedTotal;        // Sum of all convertible amounts in preferred currency
  final Map<String, double> unconverted; // currency code -> sum in native currency
  bool get isFullyConverted => unconverted.isEmpty;
}
```

2. A new `MoneyBalanceDisplayer` widget renders the compound format.

3. Chart data points that include unconvertible amounts are annotated (e.g., dashed line segments or a footnote indicator).

**Complexity note:** This tier has the highest implementation complexity and the widest blast radius. It changes the return type of core service methods, which ripples into every consumer. It should be implemented last and can be deferred to a follow-up change if Tiers 1-3 provide sufficient improvement.

---

## 4. Affected Modules

### SQL / Data Layer

| File | Changes |
|------|---------|
| `lib/core/database/sql/queries/select-full-data.drift` | Remove COALESCE fallback in 4 locations (lines 49, 50, 102, 103). Add `t.exchangeRateApplied` fallback for Tier 2. Handle preferred-currency identity case. |
| `lib/core/database/services/account/account_service.dart` | Remove COALESCE fallback at line 144. Add preferred-currency identity case in `_joinAccountAndRate()` helper (lines 62-78). For Tier 4: change `getAccountsMoney()` return type. |
| `lib/core/presentation/widgets/transaction_filter/transaction_filter_set.dart` | Remove COALESCE fallback at lines 161, 166. Decide behavior for filters when rate is missing (exclude transaction from filter match, or match unconverted). |

### Presentation Layer

| File | Changes |
|------|---------|
| `lib/app/accounts/all_accounts_balance.dart` | Tier 3: Pass `account.currency` to `CurrencyDisplayer` when converted amount is null. Tier 4: Update "Balance by currency" section and total display. |
| `lib/app/stats/widgets/fund_evolution_info.dart` | Tier 3: Handle null balance in chart header. Tier 4: Chart data points with unconvertible amounts. |
| `lib/core/presentation/widgets/number_ui_formatters/currency_displayer.dart` | No direct changes needed -- it already supports receiving an explicit `currency` parameter. |

### Models

| File | Changes |
|------|---------|
| `lib/core/models/transaction/transaction.dart` | `currentValueInPreferredCurrency` becomes nullable (`double?`) to reflect unconvertible state. |
| `lib/core/database/services/account/account_service.dart` | Tier 4: New `MoneyBalance` class or equivalent for compound return type. |

### Code Generation

| File | Changes |
|------|---------|
| Generated Drift files | Must be regenerated after `.drift` file changes (`dart run build_runner build`). |

---

## 5. Risks

| Risk | Severity | Mitigation |
|------|----------|------------|
| **Regression in balance calculations** -- these SQL queries feed every financial display in the app | High | Implement Tier 1 first and test thoroughly before proceeding. Write integration tests for known scenarios (VES account with rate, without rate, USD account). |
| **Drift code regeneration** -- changing `.drift` files requires `build_runner` and may surface type mismatches | Medium | Run `dart run build_runner build` immediately after SQL changes. Fix any generated-code type errors before proceeding to presentation changes. |
| **Preferred-currency identity case** -- removing COALESCE breaks accounts whose currency IS the preferred currency (they have no exchange rate entry because rate is implicitly 1.0) | High | Must add explicit handling: either inject a virtual rate of 1.0 in the JOIN subquery for the preferred currency, or use a CASE expression. This is a required part of Tier 1, not optional. |
| **Chart behavior with mixed currencies** -- fund evolution chart may show discontinuities or gaps when some data points have rates and others do not | Medium | For Tier 3, show the last known convertible value with a visual indicator. Tier 4 addresses this more completely. |
| **Nullable `currentValueInPreferredCurrency`** -- changing from `double` to `double?` in the transaction model will cause compile errors in every consumer | Medium | Use find-all-references in the IDE to locate every usage. Most consumers can use `?? 0` or conditional display. |
| **Edge case: preferred currency is VES** -- if the user sets VES as preferred, then USD accounts need rates to convert, and the same bug could affect USD accounts | Low | The fix is currency-agnostic. The NULL propagation approach works regardless of which currency is preferred. |
| **Filter behavior change** -- transaction value filters may exclude transactions without rates | Low | Acceptable behavior. A transaction that cannot be converted to preferred currency cannot be meaningfully compared to a preferred-currency threshold. Document this in filter UI if needed. |

---

## 6. Rollback Plan

All changes are local to the app's Dart/Drift source code with no backend or migration dependencies.

1. **Git revert:** Every tier will be implemented as a separate commit (or series of commits). Reverting is a `git revert <commit-range>` operation.

2. **Tier-by-tier rollback:** Because tiers build on each other incrementally:
   - Reverting Tier 4 alone restores simple totals (with NULL exclusion from Tier 1).
   - Reverting Tiers 3+4 restores the original display behavior (amounts in preferred currency only), but with NULL exclusion instead of inflation.
   - Reverting Tiers 2+3+4 restores pure NULL propagation (Tier 1 only).
   - Reverting all tiers restores the original COALESCE(1) behavior.

3. **No database migration needed:** The `exchangeRates` table schema is unchanged. No data is altered. The fix is purely in query logic and presentation.

4. **Feature flag option:** If desired, a `bool useLegacyCoalesce` flag can be added to `getAccountsMoney()` and the drift queries to toggle between old and new behavior at runtime. This adds complexity and is not recommended unless rollback frequency is expected to be high.

---

## 7. Success Criteria

### Functional

- [ ] A VES account with no exchange rate in the `exchangeRates` table does NOT show an inflated USD amount. It either shows the amount in Bs (Tier 3) or is excluded from the USD total with a separate Bs display (Tier 4).
- [ ] A VES account WITH a stored exchange rate converts correctly (e.g., 50,000 Bs * 0.027 = $1,350).
- [ ] An account in the preferred currency (e.g., USD when preferred is USD) continues to display correctly with an implicit rate of 1.0.
- [ ] "Saldo final" does not sum VES and USD raw amounts together.
- [ ] Fund evolution chart does not show spikes of 300,000+ when VES rates are missing for historical dates.
- [ ] Transaction value filters exclude or correctly handle transactions without convertible rates.
- [ ] The `exchangeRateApplied` fallback is used for individual transactions when the rate table has no entry (Tier 2).

### Non-Functional

- [ ] No performance regression in balance queries (NULL propagation is cheaper than COALESCE, not more expensive).
- [ ] Drift code regenerates cleanly with `dart run build_runner build`.
- [ ] All existing unit/widget tests pass (after updating expectations for the new behavior).
- [ ] The fix works regardless of which currency is set as preferred (USD, VES, EUR, etc.).

### Verification Method

- Manual testing with a VES + USD multi-currency setup, toggling between having and not having stored exchange rates.
- Verify each of the three original symptoms is resolved: per-account balance, total balance, and fund evolution chart.
- Test the edge case of app launch with no internet (no rates fetched) to confirm graceful degradation.

---

## Appendix: Implementation Order

| Phase | Tier | Estimated Complexity | Dependencies |
|-------|------|---------------------|--------------|
| 1 | Tier 1 (SQL NULL propagation) + preferred-currency identity fix | Low-Medium | None |
| 2 | Tier 2 (exchangeRateApplied fallback) | Low | Phase 1 |
| 3 | Tier 3 (native currency display) | Medium | Phase 2 |
| 4 | Tier 4 (compound aggregation) | High | Phase 3; can be deferred |

Tiers 1+2 alone resolve the catastrophic inflation bug. Tiers 3+4 improve the user experience when rates are unavailable but are not strictly required for correctness.
