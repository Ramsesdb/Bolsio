# SDD Spec: fix-exchange-rate-fallback

**Date:** 2026-04-16
**Change:** Fix COALESCE(exchangeRate, 1) fallback causing VES accounts to appear as USD
**Status:** Draft

---

## Terminology

| Term | Definition |
|------|-----------|
| Preferred currency | The user's chosen base currency (e.g., USD). All exchange rates are relative to it. |
| Native currency | The currency assigned to a specific account (e.g., VES for a bolivar account). |
| Same-currency account | An account whose native currency equals the preferred currency. |
| Foreign-currency account | An account whose native currency differs from the preferred currency. |
| Convertible amount | An amount for which a valid exchange rate exists, enabling conversion to preferred currency. |
| Unconvertible amount | An amount for which no exchange rate exists and no fallback rate is available. |
| Rate table | The `exchangeRates` SQL table storing historical rates per currency per date. |
| Applied rate | The `exchangeRateApplied` field on a transaction, recording the rate used at creation time. |

---

## R1: SQL Exchange Rate Resolution

### Requirement

The system MUST NOT use a fallback multiplier of 1.0 for missing exchange rates. When no exchange rate exists in the rate table for a foreign currency, the conversion result MUST be NULL, not the raw unconverted amount.

**Exception:** When the account's currency equals the user's preferred currency (same-currency account), the system MUST treat the effective rate as 1.0 (identity conversion). This SHALL be implemented either via a `CASE WHEN accounts.currencyId = :preferredCurrencyCode THEN 1.0 ELSE excRate.exchangeRate END` expression or by ensuring the JOIN subquery returns 1.0 for the preferred currency.

The system MUST NOT use `COALESCE(excRate.exchangeRate, 1)` in any SQL query.

### Affected Locations

All 6 SQL locations identified in the proposal:
1. `select-full-data.drift` line 49 -- individual transaction value
2. `select-full-data.drift` line 50 -- individual transaction destination value
3. `select-full-data.drift` line 102 -- aggregated SUM of transaction values
4. `select-full-data.drift` line 103 -- aggregated SUM of destination values
5. `account_service.dart` line 144 -- account initial balance
6. `transaction_filter_set.dart` lines 161, 166 -- filter expressions

### Scenarios

#### S1.1: Foreign-currency account with no exchange rate

```
Given the user's preferred currency is USD
  And the user has an account "Banesco" with native currency VES
  And the exchangeRates table contains NO entries for currencyCode = 'VES'
When the system computes the converted balance for account "Banesco"
Then the conversion result MUST be NULL
  And the raw VES amount MUST NOT appear as a USD value
```

#### S1.2: Foreign-currency account with a valid exchange rate

```
Given the user's preferred currency is USD
  And the user has an account "Banesco" with native currency VES
  And the exchangeRates table contains an entry (currencyCode='VES', exchangeRate=0.027, date=2026-04-16)
  And the account has a balance of 50,000 Bs
When the system computes the converted balance for account "Banesco"
Then the conversion result MUST be 50000 * 0.027 = 1350.00
```

#### S1.3: Same-currency account (identity conversion)

```
Given the user's preferred currency is USD
  And the user has an account "Chase" with native currency USD
  And the exchangeRates table contains NO entry for currencyCode = 'USD'
When the system computes the converted balance for account "Chase"
Then the effective rate MUST be 1.0
  And the conversion result MUST equal the raw balance (e.g., 500.00 -> 500.00)
  And the result MUST NOT be NULL
```

#### S1.4: Preferred currency is VES, foreign account is USD

```
Given the user's preferred currency is VES
  And the user has an account "Zelle" with native currency USD
  And the exchangeRates table contains an entry (currencyCode='USD', exchangeRate=36.5)
  And the account has a balance of $200
When the system computes the converted balance for account "Zelle"
Then the conversion result MUST be 200 * 36.5 = 7300.00 Bs
```

#### S1.5: Preferred currency is VES, USD account with no rate

```
Given the user's preferred currency is VES
  And the user has an account "Zelle" with native currency USD
  And the exchangeRates table contains NO entries for currencyCode = 'USD'
When the system computes the converted balance for account "Zelle"
Then the conversion result MUST be NULL
  And the raw USD amount MUST NOT appear as a VES value
```

#### S1.6: Multiple currencies, partial rates available

```
Given the user's preferred currency is USD
  And the user has accounts in VES, EUR, and USD
  And the exchangeRates table contains a rate for EUR (exchangeRate=1.08) but NOT for VES
When the system computes converted balances
Then the EUR account balance MUST be correctly converted (amount * 1.08)
  And the USD account balance MUST use identity rate 1.0
  And the VES account conversion result MUST be NULL
```

#### S1.7: Outer COALESCE for aggregate sums is preserved

```
Given the user's preferred currency is USD
  And ALL transactions in the query have NULL conversion results (no rates available)
When the system computes SUM of converted transaction values
Then the inner SUM MUST evaluate to NULL (not 0)
  And the outer COALESCE(SUM(...), 0) MUST return 0
  And the result MUST NOT include any raw foreign-currency amounts
```

---

## R2: Transaction Rate Fallback Chain

### Requirement

For individual transaction queries, the conversion rate resolution order MUST be:

1. **Latest rate from the `exchangeRates` table** for the account's currency on or before the query date
2. **`exchangeRateApplied`** stored on the transaction itself (the rate recorded at transaction creation time)
3. **NULL** (unconvertible)

The SQL expression MUST be equivalent to:
```sql
t.value * CASE
  WHEN a.currencyId = :preferredCurrencyCode THEN 1.0
  ELSE COALESCE(excRate.exchangeRate, t.exchangeRateApplied)
END
```

For aggregate queries (SUM), the same fallback chain MUST apply:
```sql
SUM(t.value * CASE
  WHEN a.currencyId = :preferredCurrencyCode THEN 1.0
  ELSE COALESCE(excRate.exchangeRate, t.exchangeRateApplied)
END)
```

The `exchangeRateApplied` field is nullable. When both the rate table and `exchangeRateApplied` are NULL, the final result MUST be NULL.

### Scenarios

#### S2.1: Rate table has entry -- use rate table

```
Given the user's preferred currency is USD
  And a VES transaction of -50,000 Bs exists with exchangeRateApplied = 0.025
  And the exchangeRates table has (currencyCode='VES', exchangeRate=0.027, date=2026-04-16)
When the system converts this transaction to preferred currency
Then it MUST use the rate table value: -50000 * 0.027 = -1350.00
  And it MUST NOT use the applied rate of 0.025
```

#### S2.2: Rate table empty, transaction has applied rate -- use applied rate

```
Given the user's preferred currency is USD
  And a VES transaction of -50,000 Bs exists with exchangeRateApplied = 0.025
  And the exchangeRates table has NO entries for currencyCode = 'VES'
When the system converts this transaction to preferred currency
Then it MUST use the applied rate: -50000 * 0.025 = -1250.00
```

#### S2.3: Rate table empty, transaction has no applied rate -- NULL

```
Given the user's preferred currency is USD
  And a VES transaction of -50,000 Bs exists with exchangeRateApplied = NULL
  And the exchangeRates table has NO entries for currencyCode = 'VES'
When the system converts this transaction to preferred currency
Then the conversion result MUST be NULL
```

#### S2.4: Historical transaction with outdated applied rate

```
Given the user's preferred currency is USD
  And a VES transaction from 2026-01-15 exists with exchangeRateApplied = 0.020
  And the exchangeRates table has a rate for VES from 2026-04-16 (exchangeRate=0.027)
  And no rate exists for 2026-01-15 specifically
When the system converts this transaction to preferred currency
Then it MUST use the latest available rate from the table (<= query date)
  And it SHOULD use 0.027 (the most recent rate available)
```

#### S2.5: Transfer transaction -- both sides use fallback chain

```
Given the user's preferred currency is USD
  And a transfer exists: -50,000 Bs from VES account, +$1,350 to USD account
  And the VES transaction has exchangeRateApplied = 0.027
  And the exchangeRates table has NO entry for VES
When the system converts the source side (t.value)
Then it MUST use the applied rate: -50000 * 0.027 = -1350.00
When the system converts the destination side (t.valueInDestiny)
Then the USD account uses identity rate 1.0: 1350 * 1.0 = 1350.00
```

#### S2.6: Aggregate SUM with mixed fallback sources

```
Given the user's preferred currency is USD
  And three VES transactions exist:
    | value    | exchangeRateApplied | rateTableAvailable |
    | -50,000  | 0.025               | yes (0.027)        |
    | -30,000  | 0.024               | no                 |
    | -10,000  | NULL                 | no                 |
When the system computes SUM of converted values
Then the SUM MUST include:
    -50000 * 0.027 (rate table) = -1350
    -30000 * 0.024 (applied rate) = -720
    -10000 * NULL = NULL (excluded from SUM by SQL)
  And the total MUST be -2070.00
  And the -10,000 Bs transaction MUST be silently excluded from the SUM
```

#### S2.7: Same-currency transaction -- bypass fallback chain

```
Given the user's preferred currency is USD
  And a USD transaction of -$100 exists with exchangeRateApplied = NULL
When the system converts this transaction to preferred currency
Then the CASE expression MUST resolve to 1.0 (identity)
  And the result MUST be -100.00
  And the fallback chain (COALESCE) MUST NOT be evaluated
```

---

## R3: Account Initial Balance Conversion

### Requirement

For account initial balances (`iniValue`), the conversion rate resolution MUST be:

1. **Latest rate from the `exchangeRates` table** for the account's currency
2. **NULL** (unconvertible)

There is no per-transaction `exchangeRateApplied` fallback available for initial balances because initial balances are not transaction records.

**Exception:** When the account's currency equals the preferred currency, the rate MUST be 1.0 (identity).

### Scenarios

#### S3.1: Foreign-currency initial balance with rate available

```
Given the user's preferred currency is USD
  And a VES account has iniValue = 500 Bs
  And the exchangeRates table has (currencyCode='VES', exchangeRate=0.027)
When the system computes the converted initial balance
Then the result MUST be 500 * 0.027 = 13.50
```

#### S3.2: Foreign-currency initial balance with no rate

```
Given the user's preferred currency is USD
  And a VES account has iniValue = 500 Bs
  And the exchangeRates table has NO entries for currencyCode = 'VES'
When the system computes the converted initial balance
Then the result MUST be NULL
  And the result MUST NOT be 500 (the raw VES amount)
```

#### S3.3: Same-currency initial balance

```
Given the user's preferred currency is USD
  And a USD account has iniValue = 1000
When the system computes the converted initial balance
Then the effective rate MUST be 1.0
  And the result MUST be 1000.00
```

#### S3.4: Initial balance with date filter

```
Given the user's preferred currency is USD
  And a VES account was created on 2026-01-01 with iniValue = 500 Bs
  And the query date is 2025-12-01 (before account creation)
When the system computes the converted initial balance
Then the CASE WHEN accounts.date > :queryDate condition MUST yield 0
  And the exchange rate resolution is irrelevant for this account
```

---

## R4: Native Currency Display

### Requirement

When a conversion to preferred currency returns NULL, the system MUST display the amount in the account's native currency with the correct currency symbol.

The system MUST NOT:
- Display the raw foreign amount with the preferred currency symbol (e.g., "$50,000" for 50,000 Bs)
- Silently hide the account or show 0
- Show an error or empty state

The system SHOULD use the existing `CurrencyDisplayer` widget with an explicit `currency` parameter set to the account's native currency.

### Model Requirements

The data model feeding display widgets MUST carry:
- `moneyInPreferred` (double?) -- the converted amount, or NULL if unconvertible
- `moneyInNative` (double) -- the raw amount in the account's native currency (always available)
- `currency` (CurrencyInDB) -- the account's native currency object

### Scenarios

#### S4.1: Account with no rate displays in native currency

```
Given the user's preferred currency is USD
  And a VES account "Banesco" has balance 358,683 Bs
  And no VES exchange rate exists in the rate table
When the system renders the balance for "Banesco" in the accounts list
Then it MUST display "Bs 358,683" (or equivalent locale-formatted VES amount)
  And it MUST NOT display "$358,683"
  And it MUST use the VES currency symbol
```

#### S4.2: Account with rate displays in preferred currency

```
Given the user's preferred currency is USD
  And a VES account "Banesco" has balance 358,683 Bs
  And a VES exchange rate of 0.027 exists
When the system renders the balance for "Banesco" in the accounts list
Then it MUST display "$9,684" (or equivalent locale-formatted USD amount)
  And it MUST use the USD currency symbol
```

#### S4.3: Same-currency account always displays in preferred currency

```
Given the user's preferred currency is USD
  And a USD account "Chase" has balance $747
When the system renders the balance for "Chase" in the accounts list
Then it MUST display "$747"
  And this case MUST always succeed (identity rate = 1.0, never NULL)
```

#### S4.4: Preferred currency is VES, USD account with no rate

```
Given the user's preferred currency is VES
  And a USD account "Zelle" has balance $200
  And no USD exchange rate exists
When the system renders the balance for "Zelle" in the accounts list
Then it MUST display "$200" (in native USD currency)
  And it MUST NOT display "Bs 200"
```

#### S4.5: Fresh install with no rates fetched yet

```
Given the user has just installed the app
  And the preferred currency is USD
  And a VES account exists with balance 100,000 Bs
  And the exchangeRates table is empty (first launch, no API call yet)
When the system renders the accounts list
Then the VES account MUST display "Bs 100,000" (native currency)
  And the USD accounts MUST display with "$" symbol (identity rate)
  And no account MUST show an inflated amount with the wrong currency symbol
```

#### S4.6: Fund evolution chart header with unconvertible balance

```
Given the user's preferred currency is USD
  And the fund evolution chart header shows total balance
  And some accounts have NULL conversion results
When the system renders the chart header
Then it MUST handle the NULL gracefully
  And it SHOULD display the convertible portion or a compound format (see R5)
  And it MUST NOT display the raw sum of mixed currencies as a single USD amount
```

---

## R5: Aggregate Balance Display

### Requirement

Totals (Saldo final, chart header, balance summaries) MUST NOT mix converted and unconverted amounts into a single number.

When all accounts are fully convertible, the system MUST display the total in the preferred currency as a single amount (e.g., "$748,415").

When some accounts are unconvertible, the system MUST use one of the following approaches:
- **Option A (compound format):** Display convertible total plus unconverted amounts separately (e.g., "$747 + Bs 380,768")
- **Option B (convertible-only with disclaimer):** Display only the convertible portion with a visual indicator that the total is incomplete

The system MUST NOT silently drop unconvertible amounts from the total without any indication.

### Data Model

The service layer SHOULD return a richer type than `double` for balance totals:

```dart
class MoneyBalance {
  final double convertedTotal;           // Sum of convertible amounts in preferred currency
  final Map<String, double> unconverted; // currencyCode -> sum in native currency
  bool get isFullyConverted => unconverted.isEmpty;
}
```

### Scenarios

#### S5.1: All accounts convertible (happy path)

```
Given the user's preferred currency is USD
  And account "Chase" (USD) has balance $500
  And account "Banesco" (VES) has balance 50,000 Bs
  And a VES exchange rate of 0.027 exists
When the system computes and displays the total balance
Then the total MUST be 500 + (50000 * 0.027) = $1,850
  And it MUST be displayed as a single amount: "$1,850"
  And no disclaimer or compound format is needed
```

#### S5.2: Mixed convertible and unconvertible accounts

```
Given the user's preferred currency is USD
  And account "Chase" (USD) has balance $747
  And account "Banesco" (VES) has balance 380,768 Bs
  And NO VES exchange rate exists
When the system displays the total balance
Then it MUST NOT display "$381,515" (raw sum of $747 + 380,768)
  And it MUST display either:
    - Compound: "$747 + Bs 380,768"
    - Or partial: "$747" with an indicator that VES balances are excluded
```

#### S5.3: No accounts convertible (all foreign, no rates)

```
Given the user's preferred currency is USD
  And only VES and EUR accounts exist
  And NO exchange rates exist for either VES or EUR
When the system displays the total balance
Then it MUST NOT display "$0"
  And it MUST display the unconverted amounts (e.g., "Bs 380,768 + EUR 1,200")
  Or it MAY display "$0" with a clear indicator that balances could not be converted
```

#### S5.4: Only same-currency accounts

```
Given the user's preferred currency is USD
  And all accounts are in USD
When the system displays the total balance
Then the total MUST be the simple sum of all account balances
  And it MUST be displayed as a single USD amount
  And no compound format is needed
```

#### S5.5: Balance by currency section in accounts page

```
Given the user's preferred currency is USD
  And VES accounts have total balance 500,000 Bs with no rate available
  And USD accounts have total balance $747
When the system renders "Balance by currency"
Then the VES group MUST show "Bs 500,000" (native currency)
  And the VES group MUST NOT show "$500,000"
  And the USD group MUST show "$747"
```

---

## R6: Fund Evolution Chart

### Requirement

The fund evolution chart MUST handle NULL conversion gracefully across all data points.

Data points where some accounts are unconvertible SHOULD show only the convertible portion. The chart SHOULD indicate when data is incomplete due to missing rates.

The chart MUST NOT:
- Plot raw foreign-currency amounts as if they were in the preferred currency
- Show sudden spikes or drops caused by exchange rate availability changes across time
- Silently mix converted and unconverted amounts

### Scenarios

#### S6.1: All rates available for all dates (happy path)

```
Given the user's preferred currency is USD
  And the user has VES and USD accounts
  And VES exchange rates exist for all dates in the chart range
When the chart renders fund evolution
Then all data points MUST show correct converted totals
  And the chart line MUST be continuous and accurate
```

#### S6.2: VES rates missing for historical dates

```
Given the user's preferred currency is USD
  And the user has a VES account with transactions dating back 6 months
  And VES exchange rates only exist for the last 7 days (accumulated since last install)
When the chart renders fund evolution over 6 months
Then data points before 7 days ago MUST NOT include the VES balance as USD
  And the chart SHOULD show only the convertible portion (USD accounts) for those dates
  And the chart SHOULD visually indicate that historical data is incomplete
```

#### S6.3: Rate becomes available mid-chart

```
Given the chart range is 2026-01-01 to 2026-04-16
  And VES exchange rates exist only from 2026-04-10 onward
When the chart renders
Then data points before 2026-04-10 MUST exclude VES balances (NULL conversion)
  And data points from 2026-04-10 onward MUST include converted VES balances
  And the transition SHOULD be smooth or visually indicated (not an unexplained spike)
```

#### S6.4: No internet, no rates at all

```
Given the user launched the app with no internet connection
  And the exchangeRates table is empty
  And the user has both VES and USD accounts
When the chart renders fund evolution
Then the chart MUST show only USD account balances (identity rate)
  And VES accounts MUST be excluded from chart data points
  And the chart SHOULD indicate data incompleteness
  And the chart MUST NOT show a wildly inflated line
```

#### S6.5: Chart header balance matches data

```
Given the chart shows a balance header for the end date
  And some accounts are unconvertible at the end date
When the header renders
Then the header value MUST be consistent with the last data point in the chart
  And the header MUST follow the same display rules as R5 (compound format or partial with indicator)
```

---

## R7: Filter Expressions

### Requirement

Transaction value filters (min/max) MUST use the same fallback chain as R2 for converting transaction amounts to preferred currency before comparison.

When a transaction's converted value is NULL (no rate and no applied rate), the transaction MUST be excluded from the filter match. A transaction that cannot be converted to the preferred currency cannot be meaningfully compared to a preferred-currency threshold.

**Exception:** Same-currency transactions MUST always be evaluable against the filter (identity rate = 1.0).

### Scenarios

#### S7.1: Filter with rate available

```
Given the user's preferred currency is USD
  And a min value filter of $10 is set
  And a VES transaction of -50,000 Bs exists
  And the VES exchange rate is 0.027
When the filter evaluates this transaction
Then the converted value is ABS(-50000 * 0.027) = 1350
  And 1350 >= 10, so the transaction MUST be included in results
```

#### S7.2: Filter with no rate and no applied rate

```
Given the user's preferred currency is USD
  And a min value filter of $10 is set
  And a VES transaction of -50,000 Bs exists with exchangeRateApplied = NULL
  And NO VES exchange rate exists
When the filter evaluates this transaction
Then the converted value is ABS(-50000 * NULL) = NULL
  And the transaction MUST be excluded from filter results
  And it MUST NOT be treated as ABS(-50000 * 1) = 50000 (would incorrectly match)
```

#### S7.3: Filter with applied rate fallback

```
Given the user's preferred currency is USD
  And a max value filter of $2000 is set
  And a VES transaction of -50,000 Bs exists with exchangeRateApplied = 0.025
  And NO VES exchange rate exists in the rate table
When the filter evaluates this transaction
Then the converted value is ABS(-50000 * 0.025) = 1250
  And 1250 <= 2000, so the transaction MUST be included in results
```

#### S7.4: Filter on same-currency transactions

```
Given the user's preferred currency is USD
  And a min value filter of $100 is set
  And a USD transaction of -$50 exists
When the filter evaluates this transaction
Then the converted value is ABS(-50 * 1.0) = 50
  And 50 < 100, so the transaction MUST be excluded from results
  And the identity rate MUST always be available (never NULL)
```

#### S7.5: Filter with both min and max, mixed currencies

```
Given the user's preferred currency is USD
  And a min value filter of $10 and max value filter of $500 are set
  And the following transactions exist:
    | currency | value    | appliedRate | tableRate | converted | matches? |
    | USD      | -$100    | NULL        | N/A       | $100      | yes      |
    | VES      | -20,000  | 0.025       | NULL      | $500      | yes      |
    | VES      | -50,000  | NULL        | NULL      | NULL      | excluded |
    | VES      | -1,000   | NULL        | 0.027     | $27       | yes      |
    | USD      | -$5      | NULL        | N/A       | $5        | no (< min) |
When the filter evaluates all transactions
Then 3 transactions MUST be included (the ones matching $10-$500 range)
  And 1 transaction MUST be excluded due to NULL conversion
  And 1 transaction MUST be excluded due to being below min
```

---

## Cross-Cutting Scenarios

### SC1: Fresh install -- no rates, no transactions

```
Given the user just completed onboarding
  And the preferred currency is USD
  And a single VES account was created with iniValue = 0
  And the exchangeRates table is empty
When the system renders the accounts page
Then the VES account MUST display "Bs 0" (native currency, no rate)
  And the total balance MUST display "$0" or "Bs 0" (zero is zero in any currency)
  And no inflation or error MUST occur
```

### SC2: App launched offline after previous use

```
Given the user has previously used the app with VES rates available
  And rates from 2026-04-15 exist in the table
  And the user launches the app offline on 2026-04-16
When the system queries for rates on 2026-04-16
Then it MUST use the latest available rate (<= 2026-04-16), which is 2026-04-15
  And balances MUST convert correctly using the 2026-04-15 rate
  And no fallback to 1.0 MUST occur
```

### SC3: Transfer between VES and USD accounts

```
Given the user's preferred currency is USD
  And a transfer of 50,000 Bs from "Banesco" (VES) to "Chase" (USD) was recorded
  And t.value = -50000, t.valueInDestiny = 1350
  And t.exchangeRateApplied = 0.027
  And no VES rate exists in the rate table
When the system converts both sides of the transfer
Then the source side MUST use applied rate: -50000 * 0.027 = -1350.00
  And the destination side MUST use identity rate: 1350 * 1.0 = 1350.00
  And the transfer MUST appear as a net-zero movement in the preferred currency total
```

### SC4: Currency changed from USD to VES

```
Given the user previously had preferred currency = USD
  And the exchangeRates table has VES rates (relative to USD)
  And the user changes preferred currency to VES
When rates are re-fetched relative to VES
Then USD accounts become the "foreign" currency needing conversion
  And VES accounts become same-currency (identity rate 1.0)
  And all SQL queries MUST correctly detect the new preferred currency
  And the CASE expression MUST use the updated preferred currency code
```

### SC5: EUR account with no supported rate provider

```
Given the user's preferred currency is USD
  And the user has a EUR account with balance EUR 1,200
  And ve.dolarapi.com does not provide EUR/USD rates
  And no EUR rate has ever been stored
When the system renders the EUR account
Then the balance MUST display "EUR 1,200" (native currency)
  And the total MUST exclude the EUR amount (or show compound format)
  And the EUR amount MUST NOT appear as "$1,200"
```

---

## Non-Functional Requirements

### NF1: Performance

The removal of `COALESCE(excRate.exchangeRate, 1)` and replacement with CASE expressions MUST NOT cause measurable performance regression. NULL propagation and CASE evaluation are standard SQL operations with negligible overhead.

### NF2: Code Generation Compatibility

After modifying `.drift` files, the system MUST successfully regenerate Drift code via `dart run build_runner build` without errors.

### NF3: Type Safety

The `currentValueInPreferredCurrency` field in the transaction model MUST become `double?` (nullable) to reflect the possibility of unconvertible transactions. All consumers of this field MUST handle the null case.

### NF4: Currency Agnosticism

The fix MUST work regardless of which currency is set as preferred. The implementation MUST NOT hardcode any currency codes (e.g., 'USD', 'VES'). The preferred currency code MUST be passed as a parameter to all queries.

### NF5: Backward Compatibility

- No database migration is required. The `exchangeRates` table schema is unchanged.
- No data is altered. The fix is purely in query logic and presentation.
- Existing exchange rate entries remain valid and are used as before.

---

## Implementation Tiers (Priority Order)

| Tier | Requirements | Severity if Skipped |
|------|-------------|-------------------|
| Tier 1 | R1 (SQL NULL propagation + identity case) | Critical -- inflation bug persists |
| Tier 2 | R2 (exchangeRateApplied fallback), R7 (filters) | High -- historical transactions show as unconvertible |
| Tier 3 | R3 (initial balance), R4 (native currency display) | High -- wrong symbols, hidden amounts |
| Tier 4 | R5 (aggregate display), R6 (chart handling) | Medium -- totals incomplete without indication |

Tiers 1+2 resolve the catastrophic inflation bug. Tiers 3+4 improve user experience for missing-rate scenarios.
