## Exploration: currency-modes-rework

### Current State

**No `currencyMode` enum exists.** The onboarding stores only:
- `SettingKey.preferredCurrency` (`'USD' | 'VES' | <any code>`) — note that `'DUAL'` is selected in the UI but is collapsed to `'USD'` before persistence (`onboarding.dart:233-234`). There is **no** persisted distinction today between "USD only" and "DUAL USD/VES".
- `SettingKey.preferredRateSource` (`'bcv' | 'paralelo'`) — the only rate-source toggle.

Dashboard widgets infer "dual" implicitly: every total-line widget hardcodes a "≈ X Bs" / "= X Bs" secondary line (`total_balance_summary_widget.dart:199-211, 367-390`; `income_or_expense_card.dart:84-114`). There is no opt-out for users who picked `VES` only or any other single currency.

**Rates infrastructure already supports per-source rows.** `exchangeRates.source TEXT NULL` already exists (`tables.drift:44-50`). `ExchangeRateService.insertOrUpdateExchangeRateWithSource` upserts by `(currencyCode, date, source)`. `_getRateWithFallback` falls back to "any source" when the requested one is missing (`exchange_rate_service.dart:177-194`). Rate refresh is hardcoded to `['bcv', 'paralelo']` for USD + EUR (`rate_refresh_service.dart:40, 130-239`); the only active provider is `DolarApiProvider`, no Frankfurter integration exists.

**Dashboard "convert everything via tooltip rate" bug.** The `countTransactions` Drift query (`select-full-data.drift:93-135`) multiplies *every* transaction's `t.value` by the latest-rate CTE row for the account currency, regardless of whether that account is already in `:preferredCurrency`. The CASE branch `WHEN a.currencyId = :preferredCurrency THEN 1.0` IS present (line 113), so when `preferredCurrency='USD'` and account is USD, value is unchanged — but the CTE `latestRates` partitions only by `currencyCode` and is biased to the active `:rateSource`. So when the user switches BCV↔Paralelo on the dashboard, `_rateSource` propagates into `appStateSettings[SettingKey.preferredRateSource]` and into this query, recomputing the USD-equivalent of *every* non-preferred-currency tx with the new rate. A native-VES tx aggregated alongside a USD-preferred dashboard sees its value re-converted; that is the reported "Bs amounts vary when toggling BCV↔Paralelo". Same shape applies in reverse for VES-preferred users.

**Settings page for preferred currency exists** (`currency_manager.dart:63-79, 119-181`). Today, changing the preferred currency calls `ExchangeRateService.deleteExchangeRates()` (wipes ALL rates) and then re-fetches via the cold-start path. Reuses `CurrencySelectorModal` (full 151-currency picker, `currency_selector_modal.dart`).

### Affected Areas

| File | Why |
|------|-----|
| `lib/core/database/services/user-setting/user_setting_service.dart:7-176` | Add new `SettingKey.currencyMode` (and `secondaryCurrency` for dual) |
| `lib/app/onboarding/onboarding.dart:53, 181-261, 328-354` | Replace single `_selectedCurrency` string with mode + (optional) secondary; persist new keys; remove `'DUAL' → 'USD'` collapse |
| `lib/app/onboarding/slides/s02_currency.dart:1-70` | Reflow to 4 modes; add picker step for "Solo otra" + dual-pair config |
| `lib/app/onboarding/widgets/v3_currency_tile.dart:1-86` | Generalize tile (or add 2nd variant for "Otra moneda" → opens `CurrencySelectorModal`) |
| `lib/app/onboarding/slides/s03_rate_source.dart` | Show ONLY when active mode resolves to USD+VES dual; otherwise skip slide |
| `lib/app/home/dashboard.page.dart:64-65, 79-84, 250-262, 290, 451-545` | `_rateSource` becomes mode-driven; tooltip chip visibility tied to "is dual USD+VES"; `IncomeOrExpenseCard.rateSource` becomes nullable / mode-aware |
| `lib/app/home/dashboard_widgets/widgets/total_balance_summary_widget.dart:199-211, 264-410` | Hardcoded VES line + BCV/Par chip must become mode-driven (single-line for single modes; secondary line for dual; chip only for USD+VES) |
| `lib/app/home/widgets/income_or_expense_card.dart:56-114` | Same: only render "≈ Bs" line in dual-USD-VES mode |
| `lib/core/database/services/transaction/transaction_service.dart:200-226` | **Bug fix**: aggregate by native `currencyId`, then convert only non-display currencies. Stop multiplying everything via single CTE rate |
| `lib/core/database/sql/queries/select-full-data.drift:93-135` | Query needs reshape — likely add a `GROUP BY a.currencyId` variant or compute conversion at Dart level (see Approaches) |
| `lib/core/database/services/account/account_service.dart:158-249, 320-340` | Pattern is correct — keep, but extend to use `displayCurrency` and `displayMode` rather than always preferred |
| `lib/core/services/rate_providers/rate_refresh_service.dart:40, 130-239` | Generalize: dynamic source list (`bcv`, `paralelo`, `frankfurter`, `manual`) per currency pair derived from active mode |
| `lib/core/services/rate_providers/rate_provider_manager.dart:1-57` | Add `FrankfurterProvider` + `ManualOverrideProvider`; current `dolar_api_provider` becomes BCV/Paralelo-only |
| `lib/core/database/sql/initial/tables.drift:44-50` | `exchangeRates.source` already nullable TEXT — no schema change needed; just widen accepted values to `'BCV' \| 'PARALELO' \| 'AUTO_FRANKFURTER' \| 'MANUAL'` (currently lowercase `bcv`/`paralelo` — migration?) |
| `lib/core/database/services/exchange-rate/exchange_rate_service.dart:177-229` | `_getRateWithFallback` + `calculateExchangeRate` — extend `source` semantics to include `MANUAL` precedence (manual overrides always win) |
| `lib/app/currencies/currency_manager.dart:63-79, 119-181` | This screen becomes the "change mode" entry point post-onboarding (mode picker + secondary currency + force-manual override toggles) |
| `lib/app/accounts/all_accounts_balance.dart:33, 113-114` | "Tasas de cambio" / "Saldo total" totals need the new `displayMode` resolver |
| `lib/app/stats/widgets/fund_evolution_info.dart:109` | Stats widgets read preferredCurrency directly — must respect mode |
| `lib/core/presentation/widgets/transaction_filter/transaction_filter_set.dart:179` | Same |
| `lib/main.dart:669` | Bootstrap fallback default `'USD'` — extend to seed `currencyMode` |
| `lib/core/database/sql/initial/seed.dart:35` | Seed `currencyMode` row alongside `preferredCurrency` |
| `lib/core/services/firebase_sync_service.dart:1341, 1424` | Sync exclusion list may need `currencyMode` + `secondaryCurrency` (default: SYNC) |

### Approaches

**A — Minimal: add `currencyMode` enum + adapt widgets one-by-one**

Add `SettingKey.currencyMode` (`single | dual`) + `SettingKey.secondaryCurrency` (nullable). Each widget reads both keys and conditionally renders the equivalence line. Keep the bug fix isolated to `transaction_service` + the Drift query.

- Pros: Smallest diff. No new abstraction. Easy to ship per-widget.
- Cons: Display logic gets duplicated across 5+ widgets. Future "what's my display currency?" lookups stay scattered. The bug fix lives apart from the mode change but they're conceptually one feature.
- Effort: **Medium**.

**B — Introduce a `CurrencyDisplayPolicy` that all widgets consume**

Create a single domain object:
```dart
sealed class CurrencyDisplayPolicy {
  const factory CurrencyDisplayPolicy.single({required String code}) = _SingleMode;
  const factory CurrencyDisplayPolicy.dual({required String primary, required String secondary}) = _DualMode;
}
```
Resolver service reads `currencyMode` + `preferredCurrency` + `secondaryCurrency` and emits a `Stream<CurrencyDisplayPolicy>`. Every widget subscribes; layout becomes:
- `single`: render one line in policy.code.
- `dual`: render primary above + secondary below; expose `rateSource` chip only when `(primary, secondary) == ('USD', 'VES')`.

The income/expense bug fix becomes a method on the policy: `Stream<double> sumInDisplayCurrency(List<TxByNativeCurrency>)` — group by native, convert only non-display amounts via `ExchangeRateService.calculateExchangeRate`. Reuses the correct pattern already in `total_balance_summary_widget._perAccountConvertedStream` (`total_balance_summary_widget.dart:139-163`).

- Pros: Single source of truth. Widgets stop re-deriving "should I show 2 lines?". Bug fix lives next to mode logic. Future modes (e.g. triple, watch face) plug in via new policy variants. Pairs naturally with `CurrencySelectorModal` reuse.
- Cons: Touches more files. Slight learning cost ("policy object" vs "two settings keys"). Risk of over-engineering if no future modes ever land.
- Effort: **Medium-High**.

### Recommendation

**Approach B (`CurrencyDisplayPolicy`)**, justified by:

1. The bug fix in `transaction_service` is structurally identical to "what should I display?" — it's a per-currency aggregate, not a per-row conversion. Wrapping both behind a policy stream collapses two refactors into one.
2. The mode rework already touches 5+ widgets; without a shared abstraction each one re-implements the same `if (mode == dual && pair == USD/VES) showChip()` ladder.
3. Leverages the existing correct pattern from `total_balance_summary_widget._perAccountConvertedStream` (lines 139-163) — it's effectively a per-account preview of what we want for transactions.
4. The settings page reuses `CurrencySelectorModal` cleanly — modes are just policy constructors.
5. `exchangeRates.source` is already `TEXT` nullable; no schema migration needed if we widen accepted values + write a one-time normalize-existing-rows migration.

### Risks

- **Drift query reshape (`countTransactions`)**: validated. The current query joins `latestRates` once per row with `:rateSource` bias; a `GROUP BY a.currencyId` variant returning `(currencyId, sum(value))` rows lets Dart-side conversion use the same `ExchangeRateService.calculateExchangeRate` already battle-tested in `total_balance_summary_widget`. Risk: query plan regression on large datasets — mitigation: index already exists on `transactions.accountID` via FK; `accounts.currencyId` is a small-cardinality column. Acceptable for 3 beta users.
- **Rate fallback when frankfurter doesn't cover a currency**: the existing `_getRateWithFallback` (line 177) already falls back to "any source" — extending to FRANKFURTER → MANUAL → null is a 1-line change; null result MUST surface a "tasa no configurada" UI hint instead of silently using 1.0 (current `calculateExchangeRate` defaults to `1.0` at lines 222-224 — that's a hidden bug we should at least gate behind `displayMode == dual` so single-mode users never see misconverted totals).
- **Compatibility with existing 3 beta users**: validated. Migration is trivial — read existing `preferredCurrency`; if it equals `'USD'` AND `preferredRateSource` is present, write `currencyMode=dual`, `secondaryCurrency='VES'`. Otherwise `currencyMode=single`. One-shot SQL on first cold start of new build.
- **`exchangeRates.source` value casing** — current writes lowercase (`'bcv'`, `'paralelo'`), spec calls for uppercase enum (`'BCV'`, `'PARALELO'`, `'AUTO_FRANKFURTER'`, `'MANUAL'`). Either keep lowercase + add new lowercase values, or write a one-shot UPDATE to normalize. Lowercase is less disruptive — recommend keeping it.
- **NEW — Tooltip chip visibility flicker**: when user changes mode in settings, the dashboard's `_rateSource` `State` survives the rebuild but the chip-builder must hide. Mitigation: `dashboard.page.dart::_rateSource` should be derived from the policy stream rather than `initState`-cached.
- **NEW — Calculator FX page** (`lib/app/calculator/widgets/currency_amount_pane.dart`) — out of immediate scope but currently coupled to `preferredCurrency`. Verify in /sdd-design phase whether mode flips break it.
- **NEW — `firebase_sync_service` exclusion list** — `currencyMode` + `secondaryCurrency` MUST sync (otherwise multi-device users get split-brain modes). Verify in /sdd-spec.

### Ready for Proposal

**Yes.** Tell the orchestrator: scope is well-defined, all 4 closed decisions map cleanly to Approach B, no schema migration required, dashboard bug folds into the same refactor. Recommend `/sdd-propose currency-modes-rework` next.
