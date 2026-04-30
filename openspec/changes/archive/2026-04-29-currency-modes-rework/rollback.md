# Rollback Plan: currency-modes-rework

> Companion to [`proposal.md` §Rollback Plan](proposal.md), [`design.md`](design.md), and [`apply-progress.md`](apply-progress.md).
> Phase 11 deliverable. **This document describes the rollback path; it is NOT executed.**
>
> Scope reminder: 3 beta users. The rollback is a "break-glass" plan, not a routine operation.

## TL;DR

The rollback is **mostly safe** but has **two irrecoverable data points**:

1. The **lowercase normalization** of `exchangeRates.source` rows (cosmetic — old code happened to do `.toLowerCase()` defensively in most read paths, so reverting is a one-line `UPDATE` if needed).
2. Any `transactions` row whose `exchangeRateSource` was migrated from legacy `'auto'` → **`'auto_frankfurter'`**, OR any new row written by the new build with `'auto_frankfurter'`. The OLD CHECK constraint (`('bcv','paralelo','manual','auto')`) will **reject** these rows. They MUST be `UPDATE`d to `'auto'` (the legacy alias) before restoring the OLD CHECK constraint, otherwise the reverse-migration aborts.

Everything else (Phase 2-9 code, Phase 1 settings rows, Frankfurter / manual `exchangeRates` rows) reverts cleanly.

---

## 1. What the migration changed (recap)

Per [`apply-progress.md` Run 1](apply-progress.md) and [`v28.sql`](../../../assets/sql/migrations/v28.sql), Phase 1 produced:

| Effect | Reversible? | Notes |
|--------|-------------|-------|
| `userSettings`: insert `currencyMode` row | YES | `DELETE` row |
| `userSettings`: insert `secondaryCurrency` row | YES | `DELETE` row |
| `transactions.exchangeRateSource` CHECK widened to include `'auto_frankfurter'` | YES, with caveat | Must `UPDATE` `'auto_frankfurter'` rows back to `'auto'` first |
| `transactions.exchangeRateSource`: legacy `'auto'` rows remapped to `'auto_frankfurter'` | YES | Reverse `UPDATE` |
| `transactions.exchangeRateSource`: rogue uppercase rows lowercased during recreate | NO (lossy) | Cosmetic only — old enum `RateSource.fromDb` already tolerated mixed case in code paths. Casing is not a referential identity. |
| `exchangeRates.source`: lowercased via `UPDATE … LOWER(source)` | NO (lossy) | Same as above — cosmetic. The OLD codebase already mixed case (see migration comment "rogue uppercase rows"). Going back is a per-source `UPDATE` if a true byte-identical revert is required. |
| `exchangeRates`: new rows written by `FrankfurterRateProvider` (`source='auto_frankfurter'`) | YES | `DELETE` by source |
| `exchangeRates`: new rows written by `ManualOverrideProvider` (`source='manual'`) | YES (caveat) | `'manual'` is also a legacy value — see "Selective delete" below |
| `app_db.dart::schemaVersion` bumped 27 → 28 | N/A | Reverting the code reverts this |
| Phase 2-9 Dart code (~30 files) | YES | Plain `git revert` of the merge commit |

---

## 2. Reverse SQL (forward → backward)

This SQL is **not** auto-run; it's a manual recovery script if the rollback is ever needed. It must be applied AFTER the binary downgrade (otherwise the new code would re-run v28 on the next cold-start).

> Apply order matters: prep `transactions` first, then drop the new settings, then optionally clean rate rows.

### Step A — prep `transactions` for the OLD CHECK

```sql
-- Map new 'auto_frankfurter' rows back to the legacy 'auto' alias so
-- they pass the OLD CHECK constraint ('bcv','paralelo','manual','auto').
UPDATE transactions
   SET exchangeRateSource = 'auto'
 WHERE exchangeRateSource = 'auto_frankfurter';
```

### Step B — restore the OLD CHECK constraint on `transactions.exchangeRateSource`

> SQLite does not support `ALTER TABLE … DROP CONSTRAINT`. The reverse uses the same recreate-table dance as v28.sql.

```sql
PRAGMA foreign_keys = OFF;

CREATE TABLE IF NOT EXISTS transactions_rollback (
  id TEXT NOT NULL PRIMARY KEY,
  date DATETIME NOT NULL,
  accountID TEXT NOT NULL REFERENCES accounts(id) ON DELETE CASCADE ON UPDATE CASCADE,
  value REAL NOT NULL,
  title TEXT,
  notes TEXT,
  type TEXT NOT NULL CHECK(type IN ('E', 'I', 'T')),
  status TEXT CHECK(status IN ('V', 'P', 'R', 'U')),
  categoryID TEXT REFERENCES categories(id) ON DELETE CASCADE ON UPDATE CASCADE,
  debtId TEXT REFERENCES debts(id) ON DELETE SET NULL ON UPDATE CASCADE,
  valueInDestiny REAL,
  receivingAccountID TEXT REFERENCES accounts(id) ON DELETE CASCADE ON UPDATE CASCADE,
  isHidden BOOLEAN NOT NULL DEFAULT 0,
  exchangeRateApplied REAL,
  -- OLD CHECK literal, restored:
  exchangeRateSource TEXT CHECK(exchangeRateSource IN ('bcv','paralelo','manual','auto')),
  createdBy TEXT REFERENCES users(id) ON DELETE SET NULL ON UPDATE CASCADE,
  modifiedBy TEXT REFERENCES users(id) ON DELETE SET NULL ON UPDATE CASCADE,
  createdAt DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  modifiedAt DATETIME,
  locLatitude REAL,
  locLongitude REAL,
  locAddress TEXT,
  intervalPeriod TEXT CHECK(intervalPeriod IN ('day','week','month','year')),
  intervalEach INTEGER,
  endDate DATETIME,
  remainingTransactions INTEGER,

  CHECK ((receivingAccountID IS NULL) != (categoryID IS NULL)),
  CHECK ((intervalPeriod IS NULL) == (intervalEach IS NULL)),
  CHECK ((intervalPeriod IS NOT NULL) OR (endDate IS NULL)),
  CHECK ((intervalPeriod IS NOT NULL) OR (remainingTransactions IS NULL)),
  CHECK ((locLongitude IS NULL AND locLatitude IS NULL) OR (locLongitude IS NOT NULL AND locLatitude IS NOT NULL)),
  CHECK ((locAddress IS NULL) OR (locLatitude IS NOT NULL AND locLongitude IS NOT NULL)),
  CHECK (categoryID IS NULL OR valueInDestiny IS NULL)
);

INSERT INTO transactions_rollback SELECT * FROM transactions;
DROP TABLE transactions;
ALTER TABLE transactions_rollback RENAME TO transactions;

PRAGMA foreign_keys = ON;
```

### Step C — drop the new `userSettings` keys

```sql
DELETE FROM userSettings
 WHERE settingKey IN ('currencyMode', 'secondaryCurrency');
```

### Step D (optional) — clean Frankfurter / manual rate rows

```sql
-- Drop rows written by the new providers. 'manual' was also a pre-existing
-- legacy value, so this DELETE may also remove pre-Phase-1 manual rows
-- if the user ever set one. For the 3 betas, the legacy app did not expose
-- a manual-override UI, so this should be safe.
DELETE FROM exchangeRates WHERE source = 'auto_frankfurter';
-- ONLY if the user did not have legacy manual rows (verify per-DB):
-- DELETE FROM exchangeRates WHERE source = 'manual';
```

### Step E (optional) — re-uppercase `exchangeRates.source` if a byte-identical revert is required

```sql
-- The OLD codebase's RateSource readers tolerated mixed casing, so this is
-- cosmetic. Skip unless the reverted binary has a strict-case-sensitive
-- comparison somewhere we missed.
UPDATE exchangeRates SET source = 'BCV'      WHERE source = 'bcv';
UPDATE exchangeRates SET source = 'PARALELO' WHERE source = 'paralelo';
UPDATE exchangeRates SET source = 'AUTO'     WHERE source = 'auto';
-- 'manual' was lowercase in the legacy code; do not touch.
```

> **Recommendation**: SKIP step E. The legacy code already lowercased on read in most paths (see Task 4.8 — "Remove all defensive `.toLowerCase()` reads" — those calls existed precisely because legacy data was inconsistent). Re-uppercasing risks breaking other paths that expected lowercase.

---

## 3. Code rollback

The Dart-side changes (Phases 2-9, ~30 files) are pure code. There is no migration that mutates data based on these changes — they only consume settings and database rows.

**Path**: `git revert <merge commit>` of the `currency-modes-rework` branch, then re-tag and ship.

The `schemaVersion` field in `lib/core/database/app_db.dart` reverts from 28 → 27 automatically as part of the code revert. This stops the new build's `migrateDB()` from re-running v28.sql on cold-start of the older binary (the older binary doesn't even know v28.sql exists — its `schemaVersion` is 27, so `migrateDB` only runs migrations up to v27).

> ⚠️ **Do NOT delete `assets/sql/migrations/v28.sql`** from the rolled-back binary's source tree. Leave it as historical evidence (per OpenSpec archive convention). The file is only invoked when `schemaVersion >= 28`, which the rolled-back binary will not satisfy.

---

## 4. Forward-compatibility on rollback (old binary reading new data)

Per the original Phase 1 risk note ([`apply-progress.md` Run 1, line 96–104](apply-progress.md)):

| Data point | Old binary behavior |
|------------|---------------------|
| Extra `userSettings` rows (`currencyMode`, `secondaryCurrency`) | IGNORED. The legacy `SettingKey` enum doesn't include them — `SettingKey.values.firstWhereOrNull` returns `null` and the row is silently skipped. ✅ |
| `exchangeRates` rows with `source='auto_frankfurter'` | Old code reads via `RateSource.fromDb(...)` (which the rollback removes) — but the legacy code path that reads `source` typically does a `.toLowerCase()` and then a substring/equality check. An `'auto_frankfurter'` value would NOT match `'bcv'`/`'paralelo'`/`'auto'`/`'manual'`, so the legacy `RateProviderManager` selection logic would skip the row. The user sees stale rates until the legacy DolarApi refresh writes new BCV/Paralelo rows. ✅ |
| `transactions` rows with `exchangeRateSource='auto_frankfurter'` | **PROBLEM** — the OLD CHECK constraint rejects this. **Step A above is mandatory.** ⚠️ |
| `exchangeRates` rows with new lowercase `source` | Old code already tolerated lowercase via defensive `.toLowerCase()` reads (the very reads Task 4.8 removed). ✅ |

---

## 5. Validation checklist

After applying the rollback, verify:

### Schema
- [ ] `PRAGMA user_version;` returns ≤ 27 (or whatever the legacy `schemaVersion` was).
- [ ] `SELECT sql FROM sqlite_master WHERE name='transactions';` shows the OLD CHECK literal: `CHECK(exchangeRateSource IN ('bcv','paralelo','manual','auto'))` — no `'auto_frankfurter'`.
- [ ] `SELECT COUNT(*) FROM userSettings WHERE settingKey IN ('currencyMode','secondaryCurrency');` returns 0.

### Data
- [ ] `SELECT COUNT(*) FROM transactions WHERE exchangeRateSource = 'auto_frankfurter';` returns 0 (Step A succeeded).
- [ ] `SELECT COUNT(*) FROM exchangeRates WHERE source = 'auto_frankfurter';` returns 0 (Step D succeeded).
- [ ] All BCV / Paralelo `exchangeRates` rows still present: `SELECT source, COUNT(*) FROM exchangeRates GROUP BY source;`

### Application
- [ ] App boots without the `currencyMode` / `secondaryCurrency` keys (legacy code ignores them).
- [ ] Dashboard shows the legacy "USD primary + Bs equivalence" two-line layout for users who had `preferredRateSource` set.
- [ ] Onboarding (if reset) shows the legacy 3-tile flow (Solo USD / Solo Bs / Dual collapsed-to-USD), not the new 4-tile flow.
- [ ] BCV/Paralelo chip on dashboard works (legacy behavior).
- [ ] No "tasa no configurada" hint anywhere (that's a new-code-only UI string).
- [ ] Calculator opens normally — Phase 7 verified zero coupling, so no rollback concern there.

### Firebase sync
- [ ] An old client pulling a sync blob that contains `currencyMode` / `secondaryCurrency` ignores them silently (verified per [`tasks.md` 8.2](tasks.md) — `firstWhereOrNull` returns `null` for unknown enum values).
- [ ] An old client pushing a sync blob does NOT contain `currencyMode` / `secondaryCurrency` keys (because its `SettingKey` enum doesn't include them) — a still-on-new-build peer device receiving this push will **preserve** its local values per the field-by-field merge guarantee (`_pullUserSettings` only overwrites keys present in the remote blob).

---

## 6. Phase-by-phase rollback feasibility

Walked through conceptually (not executed — per Phase 11 constraint):

| Phase | Output | Reversible? | Mechanism |
|-------|--------|-------------|-----------|
| 1 — Schema, settings keys, enums, migrations | `v28.sql`, schema bump, new settings rows | YES (with Step A caveat) | Reverse SQL above |
| 2 — `CurrencyDisplayPolicy` abstraction + resolver | New Dart files, no DB writes | YES | `git revert` |
| 3 — Onboarding rework | Onboarding Dart changes; first-cold-start writes the right `currencyMode` value to `userSettings` | YES | `git revert` removes the new flow; the persisted `currencyMode` row is removed by Step C |
| 4 — Rate provider chain (Frankfurter, manual, fallback fix) | New providers + scheduler; new `exchangeRates` rows written with `source='auto_frankfurter'` | YES | `git revert` + Step D |
| 5 — Settings post-onboarding (CurrencyManagerPage) | UI tile changes; can write `currencyMode`/`secondaryCurrency` mid-session | YES | `git revert` + Step C |
| 6 — Dashboard widgets refactored to consume policy | Pure widget refactor | YES | `git revert` |
| 7 — Calculator FX widget audit | Verification only, zero code change | N/A | Nothing to revert |
| 8 — Firebase sync verification | Verification only, zero code change | N/A | Nothing to revert |
| 9 — `countTransactions` group-by-native | Drift query + service refactor + new helper | YES | `git revert`; the Drift query reverts to the `latestRates` CTE shape |
| 10 — Testing | Test files only | YES | `git revert` (test files are non-load-bearing for rollback) |
| 11 — This document | Documentation only | N/A | — |

**Conclusion**: every phase is revertable via `git revert` of the merge commit + the reverse SQL in §2. The only operational gotcha is Step A (the `'auto_frankfurter'` → `'auto'` UPDATE before restoring the OLD CHECK constraint).

---

## 7. Residual / irrecoverable data

These are mutations the migration applied that the rollback **cannot byte-identically restore**:

1. **`exchangeRates.source` lowercase normalization** (Phase 1.6 / `v28.sql` line 130).
   - **Recoverable**: yes, via Step E (per-source UPPER UPDATEs).
   - **Recommendation**: don't restore. The legacy code's defensive `.toLowerCase()` reads (the ones Task 4.8 deleted) tolerated lowercase. Restoring uppercase is risk for zero benefit.
   - **Risk on rollback**: NONE.

2. **`transactions.exchangeRateSource` rogue uppercase rows lowercased during recreate** (`v28.sql` lines 103–106).
   - **Recoverable**: in theory, only if the original casing was logged. It was not. The legacy data had inconsistent casing for the same logical value — there's no source of truth to restore from.
   - **Risk on rollback**: NONE — the OLD CHECK constraint accepts lowercase values (`'bcv'`, `'paralelo'`, `'manual'`, `'auto'`) verbatim. Drift's reads in the legacy code path didn't rely on case sensitivity beyond the CHECK.

3. **Phase 1 heuristic seeds for `currencyMode` / `secondaryCurrency`**.
   - **"Recoverable"**: the heuristic seeds DON'T need recovery. They're additive `INSERT OR IGNORE` rows that simply disappear when Step C runs. The legacy code never reads these keys, so dropping them is a no-op for the legacy binary's behavior.
   - **Risk on rollback**: NONE.

4. **Any user-driven mutations made on the new build before rollback** (e.g., the user explicitly changed mode from `dual` to `single_usd` via `CurrencyManagerPage`).
   - **Recoverable**: no — the migration heuristic only runs on first cold-start with `INSERT OR IGNORE`. Re-running it after the rollback would NOT undo a user mutation, but the rollback drops the row entirely (Step C), so the legacy binary boots as if `currencyMode` was never set.
   - **Risk on rollback**: NONE — the legacy binary doesn't know `currencyMode` exists.

5. **New `exchangeRates` rows written by Frankfurter (`source='auto_frankfurter'`) or manual (`source='manual'` written via the new `ManualOverrideProvider`)**.
   - **Recoverable**: yes, via Step D (`DELETE` by source).
   - **Caveat for `'manual'`**: the legacy code MAY have written `'manual'` rows in some path we didn't audit. If a beta user has legacy `'manual'` rows, Step D will erase them. **Mitigation**: before running `DELETE … WHERE source = 'manual'`, verify per-DB: `SELECT date, currency, exchangeRate FROM exchangeRates WHERE source = 'manual' ORDER BY date;` — if the rows pre-date the new build's release tag, KEEP them. Otherwise, delete.
   - **Risk on rollback**: LOW (manual case requires per-DB triage; auto_frankfurter is unambiguous).

---

## 8. Final answer to "is the rollback genuinely safe?"

**YES, with two caveats:**

- **Caveat 1**: Step A (UPDATE `transactions.exchangeRateSource = 'auto_frankfurter'` → `'auto'`) is **mandatory** before restoring the OLD CHECK constraint. Skipping it makes the recreate-table dance fail because the OLD CHECK rejects `'auto_frankfurter'`.

- **Caveat 2**: Step D's `DELETE FROM exchangeRates WHERE source = 'manual'` requires per-DB triage if the user has any legacy manual rows. For the 3 betas, the legacy app did NOT expose a manual-override UI (verified per `proposal.md` "Out of Scope"), so this is theoretically safe — but worth checking.

The lowercase normalization (residual #1, #2) is **not lost** in any meaningful sense — it's a one-way cosmetic change that the legacy code already tolerated.

No customer-visible data (transactions, accounts, categories, debts, recurrent transactions, attachments, statement imports) is touched by the migration in any way that requires reversal.

---

## 9. Tag-and-release rollback notes (for the 3 beta users' release notes)

When tagging the rollback build, include this in release notes:

> **Rollback note**: This release reverts the "currency modes" rework. If you customized your currency mode (Solo USD / Solo Bs / Solo otra moneda), your selection is reset to the legacy defaults. If you had foreign-fiat balances (EUR, GBP, etc.) showing on the dashboard, they will revert to the legacy "USD primary + Bs equivalence" layout. Manually-set rates and Frankfurter-fetched rates are removed; BCV and Paralelo rates are preserved. To restore your settings, install the rolled-back release and re-run onboarding (Settings → Currencies).

---

## Sign-off

This document satisfies Phase 11 of `currency-modes-rework`:
- [x] Reverse SQL documented for v28 (this file, §2).
- [x] Step-by-step code revert path documented (§3).
- [x] Validation checklist (§5).
- [x] Phase-by-phase feasibility walked through (§6).
- [x] Residual / irrecoverable data documented (§7).
- [x] Final safety verdict (§8).
- [x] Release notes copy (§9).

**No rollback was executed.** This is documentation only.
