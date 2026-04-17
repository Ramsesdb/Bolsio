# SDD Explore: fix-exchange-rate-fallback

**Date:** 2026-04-16
**Change:** Fix COALESCE(exchangeRate, 1) fallback causing VES accounts to appear as USD

---

## 1. Exchange Rate Table Schema

**File:** `lib/core/database/sql/initial/tables.drift` (lines 44-50)

```sql
CREATE TABLE IF NOT EXISTS exchangeRates (
    id TEXT NOT NULL PRIMARY KEY,
    date DATETIME NOT NULL,
    currencyCode TEXT NOT NULL REFERENCES currencies(code),
    exchangeRate REAL NOT NULL,
    source TEXT
) AS ExchangeRateInDB;
```

### Key findings:

- **Rates are stored as a single number per currency per date.** The `exchangeRate` field is the conversion factor FROM that currency TO the user's preferred currency (or more precisely, it represents how much 1 unit of `currencyCode` is worth in the "base" context).
- **The `source` field** can be `NULL` or contain values like `'bcv'`, `'paralelo'`, `'manual'`, `'auto'` -- indicating the rate origin.
- **There is NO explicit "toCurrency" column.** All rates are implicitly relative to the user's preferred currency. The system assumes: `amount_in_preferred = amount_in_currency * exchangeRate`.
- **VES relationship to USD:** If the preferred currency is USD, then the `exchangeRates` table would have rows like `currencyCode='VES', exchangeRate=0.027` (1 VES = 0.027 USD). If the preferred currency is VES, then `currencyCode='USD', exchangeRate=36.5` (1 USD = 36.5 VES). The rates are fetched from ve.dolarapi.com which returns BCV and paralelo rates.

### How rates are fetched:

**File:** `lib/core/services/rate_providers/dolar_api_provider.dart`

- Uses `https://ve.dolarapi.com/v1/{dolares|euros}/{oficial|paralelo}` endpoint
- Returns `promedio` (average) field from the JSON response
- **Only supports today's rate** -- no historical data endpoint works
- Historical rates are built up by accumulation: each app launch fetches today's rate and stores it

**File:** `lib/core/services/rate_providers/rate_provider_manager.dart`

- Single provider chain with only `DolarApiProvider`
- Returns `null` immediately for non-today dates
- `backfillMissingRates()` in `ExchangeRateService` is effectively a no-op for past dates

---

## 2. The 6 COALESCE Locations (Full Context Analysis)

### Location 1: `select-full-data.drift` line 49

```sql
t.value * COALESCE(excRate.exchangeRate,1) as currentValueInPreferredCurrency,
```

**Context (lines 35-96):** This is inside `getTransactionsWithFullData()` query. It LEFT JOINs the most recent exchange rate for the account's currency. The COALESCE means: if no exchange rate is found for this account's currency, treat the rate as 1.0 (i.e., treat the currency as if it IS the preferred currency).

**Impact:** A VES transaction of 1000 Bs would show as $1000 if no VES exchange rate exists. This is the primary bug vector for individual transaction display.

### Location 2: `select-full-data.drift` line 50

```sql
t.valueInDestiny * COALESCE(excRateOfDestiny.exchangeRate,1) as currentValueInDestinyInPreferredCurrency,
```

**Context:** Same query, for the receiving account in transfers. LEFT JOINs exchange rate for the destination account's currency.

**Impact:** Same as Location 1 but for the receiving side of transfers.

### Location 3: `select-full-data.drift` line 102

```sql
COALESCE(SUM(t.value * COALESCE(excRate.exchangeRate,1)), 0) AS sumInPrefCurrency,
```

**Context (lines 98-145):** This is inside `countTransactions()` query. It sums transaction values converted to preferred currency. Used by `TransactionService._countTransactions()` which feeds into `getTransactionsValueBalance()`.

**Impact:** This is the MOST DAMAGING location. Every VES transaction without an exchange rate gets its raw bolivar amount added directly to the USD sum. A grocery purchase of 50 Bs becomes +$50 in the total balance.

### Location 4: `select-full-data.drift` line 103

```sql
COALESCE(SUM(COALESCE(t.valueInDestiny,t.value) * COALESCE(excRateOfDestiny.exchangeRate,1)), 0) AS sumInDestinyInPrefCurrency
```

**Context:** Same `countTransactions()` query, for destination side of transfers.

**Impact:** Same inflation issue for transfer destinations.

### Location 5: `account_service.dart` line 144

```sql
accounts.iniValue * COALESCE(excRate.exchangeRate, 1)
```

**Context (lines 137-172):** Inside `getAccountsMoney()` custom SQL query. This computes the initial balance of accounts converted to preferred currency. The `_joinAccountAndRate()` helper (lines 62-78) LEFT JOINs the exchange rate.

**Impact:** The initial balance of a VES account (e.g., 500 Bs initial value) would appear as $500. This corrupts the starting point of all balance calculations.

### Location 6 & 7: `transaction_filter_set.dart` lines 161 and 166

```dart
'(ABS(t.value * COALESCE(excRate.exchangeRate,1)) <= $maxValue)',
'(ABS(t.value * COALESCE(excRate.exchangeRate,1)) >= $minValue)',
```

**Context (lines 153-211):** These are filter expressions for min/max value filters on transactions. They convert transaction values to preferred currency for comparison.

**Impact:** Less critical for display, but means value filters would incorrectly match VES transactions (a 50 Bs transaction would be compared as if it were $50).

### What happens if we just remove COALESCE?

If we change `COALESCE(excRate.exchangeRate, 1)` to just `excRate.exchangeRate`:
- **NULL propagation:** `value * NULL = NULL`, `SUM(NULL) = NULL` (not 0)
- Transactions/accounts with no rate would simply **disappear from totals** instead of being inflated
- The outer `COALESCE(SUM(...), 0)` in locations 3-4 would still return 0 if ALL transactions are NULL
- This is **better than inflation** but still incorrect -- it silently drops data

---

## 3. `exchangeRateApplied` Field

**File:** `lib/core/database/sql/initial/tables.drift` (lines 159-163)

```sql
-- The exchange rate that was applied when this transaction was created (for audit/traceability)
exchangeRateApplied REAL,

-- The source of the exchange rate applied to this transaction
exchangeRateSource TEXT CHECK(exchangeRateSource IN ('bcv','paralelo','manual','auto')),
```

### When is it populated?

**File:** `lib/app/transactions/form/widgets/exchange_rate_selector.dart`

The `ExchangeRateSelector` widget provides BCV/Paralelo/Manual rate selection during transaction creation. The selected rate and source are stored in `exchangeRateApplied` and `exchangeRateSource`.

**File:** `lib/core/database/sql/queries/select-full-data.drift` (line 51-52)

```sql
t.exchangeRateApplied as exchangeRateApplied,
t.exchangeRateSource as exchangeRateSource
```

These are selected in `getTransactionsWithFullData` but **NOT used in the currency conversion calculation** (lines 49-50 use the exchange rate table instead).

### Could it serve as a fallback?

**Partially.** It records what rate was applied at transaction creation time, so for historical transactions where the `exchangeRates` table lacks data, `exchangeRateApplied` could provide a reasonable conversion rate. However:

- It is **nullable** -- older transactions or transactions in the same currency as preferred won't have it
- It represents the rate at **transaction time**, not the current rate -- for balance displays this may be more accurate for historical analysis but inconsistent with "current value" semantics
- It would need to be integrated into the SQL queries as a secondary fallback: `COALESCE(excRate.exchangeRate, t.exchangeRateApplied, <something_else>)`

**Verdict:** Useful as a tier-2 fallback for individual transactions, but cannot solve the initial balance problem (account `iniValue` has no per-transaction exchange rate).

---

## 4. CurrencyDisplayer Widget

**File:** `lib/core/presentation/widgets/number_ui_formatters/currency_displayer.dart` (full file, 137 lines)

### How it works:

1. Accepts an `amountToConvert` (double) and an optional `currency` (CurrencyInDB)
2. If `currency` is provided, it renders immediately using that currency's symbol and decimal places
3. If `currency` is NULL, it **streams the user's preferred currency** via `CurrencyService.instance.ensureAndGetPreferredCurrency()` and uses that
4. Delegates actual formatting to `UINumberFormatter.currency()`

### Key observation:

The widget does NOT do any conversion -- it is purely a **display formatter**. It shows whatever `amountToConvert` is, using the symbol of the provided (or preferred) currency. This means:

- When `all_accounts_balance.dart` calls `CurrencyDisplayer(amountToConvert: accountWithMoney.money)` with no currency parameter, it displays the money using the **preferred currency symbol** (e.g., "$")
- If the money value is wrong (inflated VES amount), it shows "$50,000" instead of "Bs 50,000"
- The widget CAN accept a specific currency -- e.g., `CurrencyDisplayer(amountToConvert: x, currency: account.currency)` would show "Bs" instead of "$"

---

## 5. Account Model

**File:** `lib/core/models/account/account.dart` (full file, 129 lines)

```dart
class Account extends AccountInDB {
  CurrencyInDB currency;  // <-- The full currency object

  Account({
    ...
    required this.currency,
    ...
  }) : super(currencyId: currency.code);
}
```

### Key findings:

- `Account.currency` is a `CurrencyInDB` object with `code`, `symbol`, `name`, `decimalPlaces`, `isDefault`, `type`
- `Account.currencyId` (inherited from `AccountInDB`) is the string code like `'VES'` or `'USD'`
- The currency is populated via `Account.fromDB(account, currency)` factory and is always available when you have an `Account` instance
- In `getAccountsWithFullData()` (select-full-data.drift line 17-24), the currency is JOINed:
  ```sql
  INNER JOIN currencies currency ON a.currencyId = currency.code
  ```
- **Yes, `account.currency` is always available** in contexts where accounts are fetched with full data

---

## 6. Balance Calculation Flow

### `getAccountsMoney()` -- `lib/core/database/services/account/account_service.dart` (lines 128-197)

**Step 1: Initial balance query (lines 137-172)**

```sql
SELECT COALESCE(
  SUM(
    CASE WHEN accounts.date > ? THEN 0
    ELSE accounts.iniValue * COALESCE(excRate.exchangeRate, 1)   -- BUG HERE
    END
  )
, 0) AS balance
FROM accounts
  LEFT JOIN (...) AS excRate ON accounts.currencyId = excRate.currencyCode
  WHERE accounts.id IN (...)
```

- Gets the initial balance of each account
- If `convertToPreferredCurrency` is true, multiplies by the exchange rate (with COALESCE fallback)
- The `_joinAccountAndRate()` helper builds the LEFT JOIN subquery that fetches the latest rate for each currency

**Step 2: Transaction sum (lines 175-196)**

Calls `TransactionService.instance.getTransactionsValueBalance()` which uses the `countTransactions` drift query.

**Step 3: Combine with RxDart**

```dart
return Rx.combineLatest2(
  initialBalanceQuery,
  transactionBalance,
  (double initial, double tx) => initial + tx,
);
```

### `getAccountMoney()` -- (lines 104-116)

Wrapper around `getAccountsMoney()` for a single account. Rounds the result.

### Full flow for "Saldo por cuentas" (all_accounts_balance.dart):

1. `getAccountsWithMoney()` iterates over accounts
2. For each account, calls `getAccountMoney(account: account, convertToPreferredCurrency: true)`
3. This calls `getAccountsMoney(accountIds: [account.id], convertToPreferredCurrency: true)`
4. Which runs the initial balance SQL + `getTransactionsValueBalance()`
5. Both use `COALESCE(excRate.exchangeRate, 1)` -- the bug

### Dashboard flow (dashboard.page.dart):

The dashboard does NOT use `getAccountsMoney(convertToPreferredCurrency: true)`. Instead (lines 86-144):

1. Gets each account's balance in its own currency (`convertToPreferredCurrency: false`)
2. Manually converts using `ExchangeRateService.instance.calculateExchangeRate()`
3. Maps null results to 0: `.map((v) => v ?? 0)`

This means the **dashboard is partially protected** from the COALESCE bug because it uses the Dart-side exchange rate service. However, it still maps null rates to 0 (account disappears from total rather than inflating).

---

## 7. Fund Evolution Chart

**File:** `lib/app/stats/widgets/fund_evolution_info.dart` (full file, 443 lines)

### How it builds chart data points:

**`getEvolutionData()` method (lines 226-262):**

1. Takes a time range and divides it into ~100 sample points
2. For each sample point (date):
   ```dart
   balance.add(
     AccountService.instance.getAccountsMoney(
       trFilters: widget.filters,
       date: currentDay,
     ),
   );
   ```
3. `getAccountsMoney()` defaults `convertToPreferredCurrency: true`
4. Combines all streams into a `LineChartDataItem`

**Impact:** Every data point in the fund evolution chart hits the COALESCE bug. If VES exchange rates are missing for historical dates, the chart will show wildly inflated values. Since `DolarApiProvider` only supports today's rate, historical chart points will almost certainly lack rates, making the chart useless for VES accounts.

### Balance header (lines 80-98):

```dart
accountService.getAccountsMoney(
  accountIds: accounts.map((e) => e.id),
  trFilters: filters,
  date: dateRange.endDate,
),
```

Also uses `convertToPreferredCurrency: true` (default), so the header amount is also affected.

---

## 8. "Saldo por cuentas" List

**File:** `lib/app/accounts/all_accounts_balance.dart` (full file, 283 lines)

### How accounts are listed:

1. `getAccountsWithMoney()` (lines 50-77) fetches all non-closed accounts
2. For each account, calls:
   ```dart
   AccountService.instance.getAccountMoney(
     account: account,
     trFilters: filters,
     convertToPreferredCurrency: true,  // <-- HERE
     date: date,
   )
   ```
3. Sorts by money descending
4. Displays each account with `CurrencyDisplayer(amountToConvert: accountWithMoney.money)` -- **no currency param**, so it shows the preferred currency symbol

### Where `convertToPreferredCurrency` is used:

- Line 65: `convertToPreferredCurrency: true` -- converts every account balance to preferred currency
- The `CurrencyDisplayer` at line 166 shows the amount with no explicit currency, defaulting to preferred currency symbol

### "Balance by currency" section (lines 79-103):

Groups accounts by `account.account.currency.code` and sums their (already-converted) money values. Since all values are already in preferred currency, the per-currency grouping shows preferred-currency amounts, NOT native currency amounts.

**Bug impact:** A VES account with 50,000 Bs and no exchange rate shows as $50,000 in the list. The currency grouping would also show VES: $50,000.

---

## 9. Exchange Rate Service

**File:** `lib/core/database/services/exchange-rate/exchange_rate_service.dart` (full file, 295 lines)

### Core methods:

| Method | Purpose |
|--------|---------|
| `insertOrUpdateExchangeRate()` | Upserts a rate, deduplicating by currency+date |
| `insertOrUpdateExchangeRateWithSource()` | Upserts with currency+date+source dedup |
| `getExchangeRates()` | Gets latest rates for all currencies |
| `getExchangeRatesOf()` | Gets all historical rates for a currency |
| `getLastExchangeRateOf()` | Gets most recent rate <= date for a currency, optionally filtered by source |
| `calculateExchangeRateToPreferredCurrency()` | Returns `null` when rate unavailable (correct!) |
| `calculateExchangeRateToPreferredCurrencyOrZero()` | Returns `0` when unavailable (for display widgets) |
| `calculateExchangeRate()` | Cross-currency conversion using two rates |
| `backfillMissingRates()` | Attempts to fill gaps -- currently no-op for past dates |
| `_getRateWithFallback()` | Tries specific source first, falls back to any source |

### Key insight:

The **Dart-side service** (`calculateExchangeRateToPreferredCurrency`) correctly returns `null` when no rate exists. The **SQL-side queries** use `COALESCE(..., 1)` which is the bug. There is a mismatch between the two approaches:

- Dashboard uses Dart-side: null -> 0 (account vanishes from total) -- suboptimal but not catastrophic
- Stats/balances/charts use SQL-side: null -> 1 (VES treated as USD) -- catastrophic

### Rate fetching lifecycle:

1. On app start, `DolarApiService` fetches today's BCV and paralelo rates
2. Rates are stored in `exchangeRates` table via `insertOrUpdateExchangeRateWithSource()`
3. The LEFT JOIN subquery finds the latest rate for each currency by date
4. If no rate has ever been stored for a currency, the LEFT JOIN returns NULL
5. COALESCE converts NULL to 1.0 -- the bug

---

## 10. The preferredCurrency Setting

**File:** `lib/core/database/services/user-setting/user_setting_service.dart` (lines 7, 99)

```dart
enum SettingKey {
  preferredCurrency,  // First enum value
  ...
}

final Map<SettingKey, String?> appStateSettings = {};
```

### How it is determined:

**File:** `lib/core/database/services/currency/currency_service.dart` (lines 65-89)

```dart
Stream<Currency> ensureAndGetPreferredCurrency() {
  final currencyCode = appStateSettings[SettingKey.preferredCurrency];
  // If not set, detects device locale and picks the matching currency
  // Falls back to 'USD' if no match
}
```

### Where it is read:

1. **`appStateSettings[SettingKey.preferredCurrency]`** -- in-memory map, used throughout the app:
   - `dashboard.page.dart:102` -- `?? 'USD'`
   - `demo_app_seeders.dart:18` -- `?? 'USD'`
   - `debt_service.dart:55,94` -- for debt calculations
   - `exchange_rate_details.dart:351` -- display

2. **`CurrencyService.instance.ensureAndGetPreferredCurrency()`** -- stream-based, used by:
   - `CurrencyDisplayer` when no explicit currency is provided
   - `FundEvolutionLineChart` for chart tooltip formatting

### Where it is set:

- **Onboarding:** `onboarding.dart:327` -- user picks during setup
- **Currency manager:** `currency_manager.dart:41` -- user changes in settings
- **Auto-detect:** `CurrencyService.getDeviceDefaultCurrencyCode()` uses device locale

### Important:

The preferred currency is what the exchange rates are relative to. If preferred currency is USD, then `exchangeRates` stores how much 1 unit of other currencies is worth in USD. The SQL queries multiply `value * exchangeRate` to convert to USD. **The preferred currency itself never has an exchange rate entry** (it is the implicit base with rate = 1.0), which is why COALESCE(..., 1) was originally written -- to handle the "same currency" case where no rate is needed.

---

## Summary of the Bug Mechanism

1. User has preferred currency = USD
2. User has a VES account with transactions in bolivares
3. The `exchangeRates` table stores VES rates (e.g., `currencyCode='VES', exchangeRate=0.027`)
4. SQL queries LEFT JOIN on `accounts.currencyId = excRate.currencyCode`
5. If VES has a rate: `50000 Bs * 0.027 = $1,350` (correct)
6. If VES has NO rate (LEFT JOIN returns NULL): `COALESCE(NULL, 1) = 1`, so `50000 Bs * 1 = $50,000` (catastrophic)

### When rates are missing:

- Fresh install before first API fetch
- Historical dates where no rate was accumulated
- API failure / no internet
- Currency not supported by ve.dolarapi.com (e.g., EUR before that support was added)

### The correct behavior should be:

- **Option A (exclude):** Treat missing rate as "unconvertible" -- exclude from totals, show in native currency
- **Option B (zero):** Treat missing rate as 0 -- account doesn't contribute to total (matches dashboard behavior)
- **Option C (fallback chain):** Use `exchangeRateApplied` from transactions as fallback, then exclude

**Option A is the most honest** and matches what the Dart-side service already does (returns null).

---

## Files Inventory

| File | Lines of Interest | Role |
|------|-------------------|------|
| `lib/core/database/sql/initial/tables.drift` | 44-50, 129-219 | Schema: exchangeRates, transactions tables |
| `lib/core/database/sql/queries/select-full-data.drift` | 49, 50, 102, 103 | COALESCE bugs in SQL queries |
| `lib/core/database/services/account/account_service.dart` | 62-78, 128-197 | Balance calculation with COALESCE bug at line 144 |
| `lib/core/presentation/widgets/transaction_filter/transaction_filter_set.dart` | 159-166 | Filter expressions with COALESCE at lines 161, 166 |
| `lib/core/presentation/widgets/number_ui_formatters/currency_displayer.dart` | 1-137 | Display widget, accepts optional currency |
| `lib/core/models/account/account.dart` | 52-128 | Account model with `currency` field |
| `lib/core/database/services/transaction/transaction_service.dart` | 177-309 | Transaction balance aggregation using drift queries |
| `lib/core/database/services/exchange-rate/exchange_rate_service.dart` | 1-295 | Rate management, correctly returns null for missing |
| `lib/core/database/services/currency/currency_service.dart` | 65-89 | Preferred currency resolution |
| `lib/core/database/services/user-setting/user_setting_service.dart` | 1-123 | Settings storage including preferredCurrency |
| `lib/core/models/transaction/transaction.dart` | 17-82, 102-110 | MoneyTransaction model with currentValueInPreferredCurrency |
| `lib/app/stats/widgets/fund_evolution_info.dart` | 226-262, 80-98 | Chart data generation using getAccountsMoney |
| `lib/app/accounts/all_accounts_balance.dart` | 50-77, 165-166 | Account balance list with convertToPreferredCurrency |
| `lib/app/home/dashboard.page.dart` | 86-144, 147-185 | Dashboard (uses Dart-side conversion, partially protected) |
| `lib/app/transactions/form/widgets/exchange_rate_selector.dart` | 1-354 | Rate selector UI for transaction form |
| `lib/core/services/rate_providers/rate_provider_manager.dart` | 1-57 | Rate provider chain (DolarApi only) |
| `lib/core/services/rate_providers/dolar_api_provider.dart` | 1-77 | ve.dolarapi.com integration, today-only |
| `lib/core/models/exchange-rate/exchange_rate.dart` | 1-12 | ExchangeRate model |
