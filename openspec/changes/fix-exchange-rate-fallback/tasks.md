# SDD Tasks: fix-exchange-rate-fallback

**Date:** 2026-04-16
**Status:** Draft
**Spec:** [spec.md](spec.md) | **Design:** [design.md](design.md)

---

## Phase 1: Infrastructure (SQL Layer)

### 1.1 Add `:preferredCurrency` parameter to drift query signatures

**Files:** `lib/core/database/sql/queries/select-full-data.drift`
**What to change:**
- Add `:preferredCurrency AS TEXT` as a named parameter to the `getTransactionsWithFullData` query signature
- Add `:preferredCurrency AS TEXT` as a named parameter to the `countTransactions` query signature

**Acceptance criteria:**
- Both query signatures include the new parameter
- No syntax errors in the `.drift` file
- The parameter is available for use in CASE expressions added in task 1.2

**Requirements:** R1, R2 (prerequisite for all SQL changes)
**Complexity:** Low
**Dependencies:** None

---

### 1.2 Replace COALESCE(exchangeRate, 1) in select-full-data.drift (4 locations)

**Files:** `lib/core/database/sql/queries/select-full-data.drift`
**What to change:**

**Location 1 (line ~49) -- individual transaction value:**
```sql
-- Before:
t.value * COALESCE(excRate.exchangeRate,1) as currentValueInPreferredCurrency,
-- After:
t.value * CASE
  WHEN a.currencyId = :preferredCurrency THEN 1.0
  ELSE COALESCE(excRate.exchangeRate, t.exchangeRateApplied)
END as currentValueInPreferredCurrency,
```

**Location 2 (line ~50) -- individual transaction destination value:**
```sql
-- Before:
t.valueInDestiny * COALESCE(excRateOfDestiny.exchangeRate,1) as currentValueInDestinyInPreferredCurrency,
-- After:
t.valueInDestiny * CASE
  WHEN ra.currencyId = :preferredCurrency THEN 1.0
  ELSE COALESCE(excRateOfDestiny.exchangeRate, t.exchangeRateApplied)
END as currentValueInDestinyInPreferredCurrency,
```

**Location 3 (line ~102) -- aggregated SUM of transaction values:**
```sql
-- Before:
COALESCE(SUM(t.value * COALESCE(excRate.exchangeRate,1)), 0) AS sumInPrefCurrency,
-- After:
COALESCE(SUM(t.value * CASE
  WHEN a.currencyId = :preferredCurrency THEN 1.0
  ELSE COALESCE(excRate.exchangeRate, t.exchangeRateApplied)
END), 0) AS sumInPrefCurrency,
```

**Location 4 (line ~103) -- aggregated SUM of destination values:**
```sql
-- Before:
COALESCE(SUM(COALESCE(t.valueInDestiny,t.value) * COALESCE(excRateOfDestiny.exchangeRate,1)), 0) AS sumInDestinyInPrefCurrency
-- After:
COALESCE(SUM(COALESCE(t.valueInDestiny,t.value) * CASE
  WHEN COALESCE(ra.currencyId, a.currencyId) = :preferredCurrency THEN 1.0
  ELSE COALESCE(excRateOfDestiny.exchangeRate, t.exchangeRateApplied)
END), 0) AS sumInDestinyInPrefCurrency
```

**Acceptance criteria:**
- All 4 COALESCE(exchangeRate, 1) patterns are replaced with CASE expressions
- The outer COALESCE(SUM(...), 0) is preserved on aggregation queries
- Identity case (same currency) returns 1.0
- Foreign currency with no rate AND no appliedRate returns NULL
- Foreign currency with appliedRate but no table rate uses appliedRate as fallback
- Location 4 uses `COALESCE(ra.currencyId, a.currencyId)` for non-transfer safety

**Requirements:** R1 (S1.1-S1.7), R2 (S2.1-S2.7)
**Complexity:** Medium
**Dependencies:** 1.1

---

### 1.3 Replace COALESCE in account_service.dart raw SQL

**Files:** `lib/core/database/services/account/account_service.dart`
**What to change:**
- In `getAccountsMoney()` method (line ~144), replace:
  ```dart
  ' * COALESCE(excRate.exchangeRate, 1)'
  ```
  with:
  ```dart
  ' * CASE WHEN accounts.currencyId = ? THEN 1.0 ELSE excRate.exchangeRate END'
  ```
- Add `Variable.withString(preferredCurrency)` to the `variables` list at the correct binding position (after the date variable, before any accountIds)
- Read preferred currency from settings:
  ```dart
  final preferredCurrency = appStateSettings[SettingKey.preferredCurrency] ?? 'USD';
  ```
- Add import for `user_setting_service.dart` if not already present

**Acceptance criteria:**
- No COALESCE(exchangeRate, 1) remains in account_service.dart
- The `?` placeholder is bound to the correct variable position
- Same-currency accounts get rate 1.0 (identity)
- Foreign-currency accounts with no rate get NULL (iniValue * NULL = NULL), excluded from SUM
- COALESCE(SUM(...), 0) wrapper returns 0 when all amounts are NULL
- No `exchangeRateApplied` fallback (initial balances have no transaction-level rate)

**Requirements:** R1, R3 (S3.1-S3.4)
**Complexity:** Medium
**Dependencies:** None (independent of drift changes)

---

### 1.4 Replace COALESCE in transaction_filter_set.dart

**Files:** `lib/core/database/services/transaction/transaction_filter_set.dart`
**What to change:**
- At lines ~161 and ~166, replace:
  ```dart
  '(ABS(t.value * COALESCE(excRate.exchangeRate,1)) <= $maxValue)'
  '(ABS(t.value * COALESCE(excRate.exchangeRate,1)) >= $minValue)'
  ```
  with:
  ```dart
  '(ABS(t.value * CASE WHEN a.currencyId = \'$preferredCurrency\' THEN 1.0 ELSE COALESCE(excRate.exchangeRate, t.exchangeRateApplied) END) <= $maxValue)'
  '(ABS(t.value * CASE WHEN a.currencyId = \'$preferredCurrency\' THEN 1.0 ELSE COALESCE(excRate.exchangeRate, t.exchangeRateApplied) END) >= $minValue)'
  ```
- Read preferred currency at the top of `toTransactionExpression()`:
  ```dart
  final preferredCurrency = appStateSettings[SettingKey.preferredCurrency] ?? 'USD';
  ```
- Add import for `user_setting_service.dart`

**Acceptance criteria:**
- No COALESCE(exchangeRate, 1) remains in transaction_filter_set.dart
- Same-currency transactions always evaluable (rate = 1.0)
- Unconvertible transactions (NULL rate) are excluded from filter matches (NULL comparisons are falsy in SQLite)
- Applied rate is used as fallback when table rate is missing

**Requirements:** R7 (S7.1-S7.5)
**Complexity:** Low
**Dependencies:** None (independent of drift changes)

---

### 1.5 Run dart build_runner and fix generated code

**Files:**
- `lib/core/database/sql/queries/select-full-data.drift.dart` (regenerated)
- `lib/core/database/app_db.g.dart` (regenerated)

**What to do:**
- Run `dart run build_runner build --delete-conflicting-outputs`
- Verify code generation completes without errors
- Confirm that the generated `countTransactions()` method now has a `preferredCurrency` parameter
- Confirm that the generated `getTransactionsWithFullData()` method now has a `preferredCurrency` parameter
- Confirm that `MoneyTransaction.currentValueInPreferredCurrency` is now `double?` (nullable)

**Acceptance criteria:**
- `build_runner` completes with exit code 0
- Generated `.g.dart` and `.drift.dart` files are consistent with the drift source changes
- New `preferredCurrency` parameter is present in generated method signatures

**Requirements:** NF2 (Code Generation Compatibility)
**Complexity:** Low
**Dependencies:** 1.1, 1.2

---

### 1.6 Thread preferredCurrency through TransactionService

**Files:** `lib/core/database/services/transaction/transaction_service.dart`
**What to change:**
- Add import for `user_setting_service.dart`
- In every call to `db.countTransactions()` (at least 4 invocations in `_countTransactions()`), add:
  ```dart
  preferredCurrency: appStateSettings[SettingKey.preferredCurrency] ?? 'USD',
  ```
- In every call to `db.getTransactionsWithFullData()` (in `getTransactionById`, `getTransactions`, etc.), add:
  ```dart
  preferredCurrency: appStateSettings[SettingKey.preferredCurrency] ?? 'USD',
  ```

**Acceptance criteria:**
- All calls to `countTransactions()` pass the new `preferredCurrency` parameter
- All calls to `getTransactionsWithFullData()` pass the new `preferredCurrency` parameter
- No compile errors related to missing parameters
- Value comes from `appStateSettings`, not hardcoded

**Requirements:** R1, R2 (enables all SQL changes to receive the parameter)
**Complexity:** Low
**Dependencies:** 1.5 (needs generated code with new signatures)

---

## Phase 2: Data Layer

### 2.1 Update MoneyTransaction model for nullable currentValueInPreferredCurrency

**Files:** `lib/core/models/transaction/transaction.dart` (or wherever `MoneyTransaction` is defined)
**What to change:**
- Change `currentValueInPreferredCurrency` from `double` to `double?`
- Update `getCurrentBalanceInPreferredCurrency()` to return `double?`:
  ```dart
  double? getCurrentBalanceInPreferredCurrency() {
    if (currentValueInPreferredCurrency == null) return null;
    if (type == TransactionType.transfer) {
      final destiny = currentValueInDestinyInPreferredCurrency ??
          currentValueInPreferredCurrency!;
      return destiny - currentValueInPreferredCurrency!;
    }
    return currentValueInPreferredCurrency;
  }
  ```
- Update any other methods on `MoneyTransaction` that use the field to handle null

**Acceptance criteria:**
- `currentValueInPreferredCurrency` is `double?`
- `getCurrentBalanceInPreferredCurrency()` returns `double?`
- Returns `null` when the value is null (unconvertible)
- Same-currency transactions still return correct values (never null)
- Transfer calculations handle null correctly

**Requirements:** NF3 (Type Safety), R1, R2
**Complexity:** Medium
**Dependencies:** 1.5 (generated code drives the type change)

---

### 2.2 Fix all consumers of currentValueInPreferredCurrency

**Files:** Multiple -- all files that reference `currentValueInPreferredCurrency` or `getCurrentBalanceInPreferredCurrency()`
**What to change:**
- Search codebase for all usages of `currentValueInPreferredCurrency` and `getCurrentBalanceInPreferredCurrency()`
- For each usage, add null-safety handling:
  - If displaying a single transaction: show native currency when null (per R4)
  - If summing values: skip null values or use `?? 0` where appropriate
  - If comparing values: handle null case explicitly

**Acceptance criteria:**
- No compile errors related to nullable access on `currentValueInPreferredCurrency`
- Every widget/method that consumed the old non-nullable value handles null
- `dart analyze` produces no new warnings

**Requirements:** NF3, R4
**Complexity:** High (wide blast radius, many consumers)
**Dependencies:** 2.1

---

### 2.3 Update AccountWithMoney model for dual-balance approach

**Files:** The file defining `AccountWithMoney` (likely in `lib/core/models/account/` or within `all_accounts_balance.dart`)
**What to change:**
- Add `moneyNative` field to `AccountWithMoney`:
  ```dart
  class AccountWithMoney {
    final double moneyConverted;  // renamed from money
    final double moneyNative;     // new field
    final Account account;
  }
  ```
- Add `isConverted` computed property:
  ```dart
  bool get isConverted {
    final preferredCurrency = appStateSettings[SettingKey.preferredCurrency] ?? 'USD';
    if (account.currencyId == preferredCurrency) return true;
    if (moneyConverted == 0 && moneyNative != 0) return false;
    return true;
  }
  ```
- Add `effectiveMoney` computed property for sorting/display

**Acceptance criteria:**
- `AccountWithMoney` carries both converted and native balances
- `isConverted` correctly identifies unconvertible accounts
- Same-currency accounts are always reported as converted
- Zero-balance accounts are not falsely flagged as unconverted

**Requirements:** R4 (data model for native currency display)
**Complexity:** Medium
**Dependencies:** 1.3 (SQL changes affect what moneyConverted returns)

---

### 2.4 Update getAccountsWithMoney() to fetch dual balances

**Files:** The file containing `getAccountsWithMoney()` (likely `all_accounts_balance.dart` or an accounts service file)
**What to change:**
- For each account, issue two queries:
  1. `getAccountMoney(convertToPreferredCurrency: true)` for the converted balance
  2. `getAccountMoney(convertToPreferredCurrency: false)` for the native balance
- Construct `AccountWithMoney` with both values
- Update sorting to use `effectiveMoney`

**Acceptance criteria:**
- Each account in the list has both `moneyConverted` and `moneyNative` populated
- Accounts with no exchange rate have `moneyConverted = 0` and `moneyNative` = actual native balance
- Same-currency accounts have `moneyConverted == moneyNative`
- List is sorted by `effectiveMoney`

**Requirements:** R4 (enables native currency display)
**Complexity:** Medium
**Dependencies:** 2.3

---

## Phase 3: Presentation Layer

### 3.1 Update all_accounts_balance.dart -- handle null conversion, show native currency

**Files:** `lib/app/accounts/all_accounts_balance.dart` (or equivalent)
**What to change:**
- Update `CurrencyDisplayer` calls to use `AccountWithMoney.isConverted`:
  ```dart
  CurrencyDisplayer(
    amountToConvert: accountWithMoney.isConverted
        ? accountWithMoney.moneyConverted
        : accountWithMoney.moneyNative,
    currency: accountWithMoney.isConverted
        ? null  // defaults to preferred currency
        : accountWithMoney.account.currency,
  )
  ```
- Update the "Balance by currency" section (`getCurrenciesWithMoney`) to group unconverted accounts under their native currency

**Acceptance criteria:**
- VES account with no rate displays "Bs 358,683" (not "$358,683")
- VES account with rate displays "$9,684" (converted)
- USD account (when preferred is USD) displays "$747"
- "Balance by currency" shows VES group in bolivars, USD group in dollars
- No account displays a raw foreign amount with the preferred currency symbol

**Requirements:** R4 (S4.1-S4.5), R5 (S5.5)
**Complexity:** Medium
**Dependencies:** 2.3, 2.4

---

### 3.2 Update fund_evolution_info.dart -- chart handles null data points

**Files:** `lib/app/stats/fund_evolution_info.dart` (or equivalent chart widget)
**What to change:**
- V1 approach (recommended): keep current behavior where `getAccountsMoney()` returns the convertible-only total. The chart naturally shows lower values for historical dates where VES cannot be converted, which is correct.
- Update the chart header balance to be consistent with chart data points
- (Optional) Add a warning indicator when the chart is excluding some accounts due to missing rates

**Acceptance criteria:**
- Chart does NOT show 300K+ spikes from raw VES amounts
- Chart shows smooth line representing convertible accounts only
- Historical data points where no VES rate exists show only USD account values
- Chart header matches the last data point value
- No runtime errors from null values

**Requirements:** R6 (S6.1-S6.5)
**Complexity:** Low (V1 approach requires minimal changes since SQL fix handles the core issue)
**Dependencies:** 1.2, 1.3, 1.6 (SQL layer must be correct first)

---

### 3.3 Update any other callers affected by nullable changes

**Files:** Multiple -- discovered during compilation after Phase 1/2
**What to change:**
- Fix any remaining compile errors from the nullable `currentValueInPreferredCurrency` change
- Common patterns to fix:
  - `transaction.currentValueInPreferredCurrency.abs()` -> null-safe access
  - Comparisons/sorting on the value -> handle null
  - Dashboard widgets that display transaction values -> show native currency when null
  - Budget/stats pages that aggregate transaction values -> skip null or handle gracefully

**Acceptance criteria:**
- Full app compiles with no errors (`dart analyze` clean)
- No runtime null-safety crashes
- All pages that display transaction values handle the null case

**Requirements:** NF3, R4
**Complexity:** Medium (depends on how many callers exist)
**Dependencies:** 2.1, 2.2

---

## Phase 4: Testing and Validation

### 4.1 Test happy path -- all rates available

**What to test:**
- Set preferred currency to USD
- Ensure VES exchange rate exists in rate table
- Create transactions in both USD and VES accounts
- Verify all balances display correctly in USD
- Verify total balance is correct (sum of all converted amounts)
- Verify fund evolution chart shows correct values

**Scenarios covered:** S1.2, S1.3, S2.1, S2.7, S3.1, S3.3, S5.1, S6.1
**Complexity:** Low
**Dependencies:** All Phase 1-3 tasks

---

### 4.2 Test mixed currencies -- some rates missing

**What to test:**
- Set preferred currency to USD
- Have accounts in USD, VES, and optionally EUR
- Ensure VES rate is MISSING from the rate table
- Ensure EUR rate exists (or only have USD + VES)
- Verify:
  - USD account shows "$747" (identity rate)
  - VES account shows "Bs 380,768" (native currency, NOT "$380,768")
  - Total balance shows only the convertible portion (e.g., "$747"), not inflated
  - "Balance by currency" groups correctly

**Scenarios covered:** S1.1, S1.6, S4.1, S4.3, S5.2, S5.5
**Complexity:** Medium
**Dependencies:** All Phase 1-3 tasks

---

### 4.3 Test identity case -- preferred currency accounts

**What to test:**
- Set preferred currency to USD
- Have only USD accounts
- Verify all balances display correctly (identity rate 1.0)
- Verify no NULL conversion occurs for same-currency accounts
- Change preferred currency to VES and verify VES accounts now use identity rate while USD accounts need conversion

**Scenarios covered:** S1.3, S2.7, S3.3, S4.3, S5.4, SC4
**Complexity:** Low
**Dependencies:** All Phase 1-3 tasks

---

### 4.4 Test exchangeRateApplied fallback chain

**What to test:**
- Create VES transactions WITH `exchangeRateApplied` set
- Remove all VES rates from the rate table
- Verify transactions use the applied rate for conversion (not NULL, not 1.0)
- Verify the applied rate is used in:
  - Individual transaction display
  - Aggregate sums (countTransactions)
  - Value filters (min/max)
- Test a transaction with `exchangeRateApplied = NULL` and no table rate: should be NULL/unconvertible

**Scenarios covered:** S2.2, S2.3, S2.5, S2.6, S7.3
**Complexity:** Medium
**Dependencies:** All Phase 1-3 tasks

---

### 4.5 Test chart with historical missing rates

**What to test:**
- Have a VES account with transactions dating back several months
- Only have VES exchange rates for the last 7 days
- Open the fund evolution chart with a 6-month range
- Verify:
  - No 300K+ spikes in the chart
  - Historical data points show only USD account values (VES excluded)
  - Recent data points (last 7 days) include converted VES values
  - Chart header is consistent with the last data point

**Scenarios covered:** S6.2, S6.3, S6.4, S6.5
**Complexity:** Medium
**Dependencies:** All Phase 1-3 tasks

---

### 4.6 Test value filters with mixed currencies

**What to test:**
- Set a min/max value filter (e.g., $10-$500)
- Have transactions in both USD and VES
- Have some VES transactions with `exchangeRateApplied`, some without
- Verify:
  - USD transactions are correctly filtered (identity rate)
  - VES transactions with rate (table or applied) are correctly converted and filtered
  - VES transactions with no rate at all are excluded from results (not falsely matched)

**Scenarios covered:** S7.1-S7.5
**Complexity:** Low
**Dependencies:** 1.4, 1.6

---

### 4.7 Full regression check on dashboard, stats, budgets

**What to test:**
- Navigate through all major app screens:
  - Dashboard (main balance, recent transactions)
  - Accounts page (all accounts balance, per-account balances)
  - Stats page (income/expenses, categories)
  - Budgets page
  - Transaction detail pages
  - Transfer detail pages
- Verify no crashes, no inflated amounts, no wrong currency symbols
- Verify app behaves correctly in the "fresh install, no rates" scenario

**Scenarios covered:** SC1, SC2, SC3, SC5, NF1
**Complexity:** Medium
**Dependencies:** All Phase 1-3 tasks

---

## Dependency Graph

```
Phase 1 (SQL):
  1.1 ──> 1.2 ──> 1.5 ──> 1.6
  1.3 (independent)
  1.4 (independent)

Phase 2 (Data):
  1.5 ──> 2.1 ──> 2.2
  1.3 ──> 2.3 ──> 2.4

Phase 3 (Presentation):
  2.3 + 2.4 ──> 3.1
  1.2 + 1.3 + 1.6 ──> 3.2
  2.1 + 2.2 ──> 3.3

Phase 4 (Testing):
  All Phase 1-3 ──> 4.1 through 4.7
```

## Complexity Summary

| Task | Complexity | Est. Session |
|------|-----------|-------------|
| 1.1 | Low | < 15 min |
| 1.2 | Medium | 30-45 min |
| 1.3 | Medium | 20-30 min |
| 1.4 | Low | 15-20 min |
| 1.5 | Low | 10-15 min (mostly waiting for build) |
| 1.6 | Low | 15-20 min |
| 2.1 | Medium | 20-30 min |
| 2.2 | High | 45-60 min (many consumers) |
| 2.3 | Medium | 20-30 min |
| 2.4 | Medium | 20-30 min |
| 3.1 | Medium | 30-45 min |
| 3.2 | Low | 15-20 min |
| 3.3 | Medium | 30-45 min |
| 4.1-4.7 | Medium | 60-90 min (manual testing) |

**Total estimated effort:** ~5-7 hours across sessions

## Requirements Traceability

| Requirement | Tasks |
|-------------|-------|
| R1 (SQL NULL propagation) | 1.1, 1.2, 1.3, 1.5 |
| R2 (Transaction rate fallback chain) | 1.1, 1.2, 1.6, 2.1 |
| R3 (Account initial balance conversion) | 1.3 |
| R4 (Native currency display) | 2.1, 2.2, 2.3, 2.4, 3.1, 3.3 |
| R5 (Aggregate balance display) | 3.1 (partial -- Tier 4 deferred) |
| R6 (Fund evolution chart) | 3.2 |
| R7 (Filter expressions) | 1.4 |
| NF1 (Performance) | 4.7 |
| NF2 (Code generation) | 1.5 |
| NF3 (Type safety) | 2.1, 2.2, 3.3 |
| NF4 (Currency agnosticism) | 1.1, 1.3, 1.4, 1.6 |
| NF5 (Backward compatibility) | All (no migration needed) |
