# Proposal: Currency Modes Rework

## Why

Today wallex has no real concept of "currency mode". The dashboard hardcodes a "USD primary + Bs equivalence" two-line layout for everyone, even users who picked VES-only or another single currency in onboarding. The `'DUAL'` selection in onboarding is silently collapsed to `'USD'` before persistence, so the app cannot tell a single-USD user from a dual-USD/VES user. The same conflation feeds a bug where toggling BCV/Paralelo on the dashboard re-converts every native-currency transaction through the active rate, producing wrong totals. This rework introduces a real, persisted currency mode (4 variants), generalizes rate sources beyond Bs, and absorbs the related dashboard conversion bug.

## What Changes

- **Onboarding:** 4 explicit modes — Solo USD, Solo Bs, Solo otra moneda (151-currency picker), Dual (default USD+Bs, configurable).
- **Persistence:** new settings `currencyMode` (`single | dual`) and `secondaryCurrency` (nullable); remove the `'DUAL' → 'USD'` collapse.
- **Display abstraction:** introduce `CurrencyDisplayPolicy` (sealed: `single` / `dual`); all total/income/expense widgets consume a `Stream<CurrencyDisplayPolicy>` instead of re-deriving layout from raw setting keys.
- **Dashboard layout:** single mode renders one line; dual renders two (primary above, equivalence below). BCV/Paralelo tooltip chip appears only when dual pair is exactly USD+VES.
- **Rate sources:** Bs keeps BCV/Paralelo via existing `DolarApiProvider`. Other fiat pairs use a new Frankfurter provider (no API key, manual fallback). Crypto stays manual-only. User can force manual override per pair. Lowercase `source` values: existing `'bcv'`, `'paralelo'` plus new `'auto_frankfurter'`, `'manual'`.
- **Settings:** mode is changeable post-onboarding from the existing currency manager screen; accounts and transactions are untouched on mode change.
- **Bug fix (Gasto/Ingreso):** group transactions by native `currencyId`, convert only foreign portions via `ExchangeRateService.calculateExchangeRate`. Drop the per-row CTE multiplication.
- **Bug gate:** `calculateExchangeRate`'s silent `1.0` fallback fails loudly (or returns a "rate-missing" sentinel surfaced in UI) for non-VES pairs.
- **Sync:** `currencyMode` and `secondaryCurrency` ride existing Firebase settings sync (no exclusion).

## Affected Modules

| Group | Files |
|-------|-------|
| Onboarding | `lib/app/onboarding/onboarding.dart`, `slides/s02_currency.dart`, `slides/s03_rate_source.dart` (conditional on dual USD+VES), `widgets/v3_currency_tile.dart` |
| Settings | `lib/app/currencies/currency_manager.dart`, `lib/main.dart:669`, `lib/core/database/sql/initial/seed.dart:35` |
| Settings keys | `lib/core/database/services/user-setting/user_setting_service.dart` (new `currencyMode`, `secondaryCurrency`) |
| Display policy (NEW) | `lib/core/models/currency/currency_display_policy.dart`, resolver service streaming from settings |
| Dashboard widgets | `lib/app/home/dashboard.page.dart`, `dashboard_widgets/widgets/total_balance_summary_widget.dart`, `widgets/income_or_expense_card.dart`, `lib/app/accounts/all_accounts_balance.dart`, `lib/app/stats/widgets/fund_evolution_info.dart`, `lib/core/presentation/widgets/transaction_filter/transaction_filter_set.dart` |
| Transaction aggregation (bug fix) | `lib/core/database/services/transaction/transaction_service.dart:200-226`, `lib/core/database/sql/queries/select-full-data.drift:93-135` |
| Exchange rate | `lib/core/database/services/exchange-rate/exchange_rate_service.dart:177-229`, `lib/core/services/rate_providers/rate_refresh_service.dart`, `rate_provider_manager.dart`, new `frankfurter_provider.dart`, new `manual_override_provider.dart` |
| Calculator | `lib/app/calculator/widgets/currency_amount_pane.dart` (audit only — confirm no break) |
| Firebase sync | `lib/core/services/firebase_sync_service.dart` (verify new keys NOT in exclusion list) |

## Drift Schema Migrations

`exchangeRates.source` already nullable TEXT — no DDL change. Settings live in the key/value `userSettings` table — also no DDL change for the new keys.

**Migration heuristic** (one-shot on first cold start of new build, idempotent):

```sql
-- Seed currencyMode if missing, using preferredRateSource as the dual signal.
INSERT OR IGNORE INTO userSettings (settingKey, settingValue)
SELECT 'currencyMode',
       CASE WHEN EXISTS (SELECT 1 FROM userSettings WHERE settingKey = 'preferredRateSource')
            THEN 'dual' ELSE 'single' END;

INSERT OR IGNORE INTO userSettings (settingKey, settingValue)
SELECT 'secondaryCurrency',
       CASE WHEN EXISTS (SELECT 1 FROM userSettings WHERE settingKey = 'preferredRateSource')
            THEN 'VES' ELSE NULL END;
```

If a future Drift schema bump becomes desirable for type-safe columns, defer to a follow-up — the key/value approach matches existing setting conventions.

## Rollback Plan

Scope: 3 beta users. Risk surface limited.

1. **Code rollback:** revert the release tag; previous build ignores `currencyMode` / `secondaryCurrency` rows (forward-compat — extra setting rows don't break older code).
2. **Data rollback:** the migration is purely additive (two new `userSettings` rows). No destructive DDL. `DELETE FROM userSettings WHERE settingKey IN ('currencyMode','secondaryCurrency');` restores pre-rework state.
3. **Rate rows:** Frankfurter / manual rows live in `exchangeRates` with new `source` values. They do not collide with `'bcv'`/`'paralelo'` rows; ignore or delete by source if needed.
4. **Firebase:** new keys are sync-eligible. On rollback, older clients ignore them — no split-brain risk for the rolled-back-direction. (The forward direction split-brain is covered in Risks.)

## Risks

| Risk | Mitigation |
|------|------------|
| `calculateExchangeRate` silently returns `1.0` for missing rates — widening to non-VES pairs amplifies blast radius | Gate the `1.0` default behind explicit `displayMode == single` OR remove and surface a "tasa no configurada" UI hint; require explicit fallback path |
| `exchangeRates.source` casing — existing rows are lowercase, new values must match | Keep lowercase across the board; document the enum as lowercase strings |
| Firebase sync split-brain if old client and new client share an account during rollout | Sync the keys (default behavior). Old client tolerates unknown keys. Document that mid-rollout, an old-client write does not erase new keys |
| Drift query reshape for `countTransactions` may regress on larger datasets | `accounts.currencyId` is small-cardinality and `transactions.accountID` is FK-indexed; for 3 beta users acceptable. Validate with explain-plan in design phase |
| Conditional `s03_rate_source` slide must not break onboarding navigation indices | Slide list becomes mode-derived; cover with onboarding flow tests in tasks phase |
| Calculator FX widget (`currency_amount_pane.dart`) is coupled to `preferredCurrency` directly | Audit during design; if broken, add to scope. Otherwise ship as-is and revisit |
| Dashboard `_rateSource` `State` survives mode change | Derive from policy stream rather than `initState` cache |

## Out of Scope

- CoinGecko or any crypto auto-rate provider (manual only).
- Editable rate history UI (per-tx history already on `transactions.exchangeRateApplied`).
- Retroactive recalculation of historical transactions on mode/rate changes.
- Account-currency conversion (accounts remain multi-currency, untouched).
- Triple-display or watch-face modes (policy is designed to admit them later, but not built).

## Phasing Suggestion

(For `/sdd-tasks` to refine.)

1. **Schema + model:** new setting keys, migration, `CurrencyDisplayPolicy` sealed class + resolver service, lowercase `source` enum constants.
2. **Onboarding update:** 4-mode flow, dual-pair config, conditional `s03_rate_source`, persistence (drop `'DUAL'→'USD'` collapse).
3. **Display policy + widget refactor:** wire dashboard, total balance, income/expense card, all-accounts balance, stats widgets, transaction filters to consume the policy stream. Tooltip chip gated on dual USD+VES.
4. **Rates infra:** Frankfurter provider, manual override provider, generalize `rate_refresh_service` source list per active mode, gate `calculateExchangeRate` `1.0` fallback.
5. **Settings post-onboarding:** mode + secondary currency + force-manual toggles in `currency_manager.dart`.
6. **Dashboard bug absorption:** reshape `countTransactions` (Drift) + `transaction_service` aggregation to group-by-native, convert-foreign-only.
7. **Testing:** onboarding-flow tests, mode-change tests, dual-pair non-USD/VES (no chip) tests, Frankfurter provider unit tests, migration idempotency test, regression test for the BCV/Paralelo toggle bug, Firebase sync round-trip for new keys.
