# Archive Report: currency-modes-rework

**Change**: `currency-modes-rework`
**Archived on**: 2026-04-29
**Archiver**: sdd-archive
**Project**: bolsio
**Artifact store mode**: openspec
**Verify verdict**: **PASS** (see `verify-report.md` Section "Summary verdict")

---

## 1. Verify gate

The archive is permitted because the verify report dated 2026-04-29 reached PASS:

- 72 numbered tasks; 70 marked `[x]`. The two unchecked boxes (3.7, 8.3) are OpenSpec bookkeeping artefacts of the Phase X → Phase 10 deferral pattern — both deliverable test files exist on disk (`test/app/onboarding/persistence_test.dart`, `test/core/services/firebase_sync/currency_mode_sync_test.dart`).
- All 5 spec files' scenarios trace to a test or to a verified implementation site.
- Focused regression suite: **182 / 182 passing**, ~5s.
- `flutter analyze` reports **zero new analyzer issues**; the single info-level lint in `lib/core/utils/date_time_picker.dart:44` is the unchanged pre-existing baseline.
- All 7 orchestrator-resolved decisions verified against production code.
- Both bug fixes landed (RateSourceBadge "Auto", filter `excRate` alias).
- Rollback documentation complete (`rollback.md`, including the mandatory pre-step `auto_frankfurter` → `auto`).

---

## 2. Spec sync — delta → main

| # | Capability (domain)  | Action      | Source delta path                                                                          | Destination main spec path                                  | Conflicts |
| - | -------------------- | ----------- | ------------------------------------------------------------------------------------------ | ----------------------------------------------------------- | --------- |
| 1 | `settings`           | **CREATED** | `openspec/changes/currency-modes-rework/specs/settings/spec.md`                            | `openspec/specs/settings/spec.md`                           | None      |
| 2 | `onboarding`         | **CREATED** | `openspec/changes/currency-modes-rework/specs/onboarding/spec.md`                          | `openspec/specs/onboarding/spec.md`                         | None      |
| 3 | `currency-display`   | **CREATED** | `openspec/changes/currency-modes-rework/specs/currency-display/spec.md`                    | `openspec/specs/currency-display/spec.md`                   | None      |
| 4 | `exchange-rates`     | **CREATED** | `openspec/changes/currency-modes-rework/specs/exchange-rates/spec.md`                      | `openspec/specs/exchange-rates/spec.md`                     | None      |
| 5 | `transactions`       | **CREATED** | `openspec/changes/currency-modes-rework/specs/transactions/spec.md`                        | `openspec/specs/transactions/spec.md`                       | None      |

**Tally**: 5 main specs CREATED, 0 main specs MERGED.

### Why all five are CREATE, not MERGE

Pre-archive, `openspec/specs/` contained only its `.gitkeep` placeholder — no domain subdirectories existed. The bolsio project initialized OpenSpec for SDD purposes after the main spec corpus was empty, so this change is the first to populate `openspec/specs/`. Per the `sdd-archive` skill rule "If main spec does NOT exist → the delta spec IS a full spec; copy it directly," each of the 5 deltas was copied verbatim to its main spec path. No requirements were dropped, replaced, or reordered.

### What each new main spec covers (concise)

- **`openspec/specs/settings/spec.md`** — `currencyMode` (enum: `single_usd` | `single_bs` | `single_other` | `dual`), `secondaryCurrency` setting, the legacy → new mode migration heuristic, and Firebase sync semantics for the new keys.
- **`openspec/specs/onboarding/spec.md`** — 4-mode selection on slide 2 and the conditional gating rule for slide 3 (`s03_rate_source` shown ONLY when mode == `dual` AND the pair is the canonical USD↔VES).
- **`openspec/specs/currency-display/spec.md`** — NEW capability. Defines `CurrencyDisplayPolicy` contract, render rules per mode (`single_*`, `dual`), BCV/Paralelo chip gating to USD+VES, and multi-currency independence (creating a JPY account never depends on `currencyMode`).
- **`openspec/specs/exchange-rates/spec.md`** — `RateSource` enum normalization (lowercase `dbValue`), Frankfurter as the automatic foreign-pair source, manual override path, and the `calculateExchangeRate` null contract for missing pairs.
- **`openspec/specs/transactions/spec.md`** — Immutable per-transaction rate history (`exchangeRate` snapshot is never re-derived), and the group-by-native aggregation approach used by `countTransactions` (Phase 9 / approach B).

---

## 3. Archive folder move

| Stage  | Path                                                                  |
| ------ | --------------------------------------------------------------------- |
| Before | `openspec/changes/currency-modes-rework/`                             |
| After  | `openspec/changes/archive/2026-04-29-currency-modes-rework/`          |

**Date prefix**: `2026-04-29` (ISO-8601, today's date per env).

The entire change folder is moved as a single unit so the audit trail stays cohesive. Folder contents preserved:

- `proposal.md`
- `exploration.md`
- `design.md`
- `tasks.md`
- `specs/` (all 5 delta specs — kept inside the archived folder for lineage)
- `apply-progress.md`
- `verify-report.md`
- `rollback.md`
- `archive-report.md` (this file)

State file `state.yaml` was not present in the change folder (orchestrator did not persist one for this run); nothing to move on that front.

---

## 4. Production code scope

Per task constraints, **no production code under `lib/` was modified by the archive phase**. Archive operations are confined to:

- `openspec/specs/{settings,onboarding,currency-display,exchange-rates,transactions}/spec.md` (5 new files)
- `openspec/changes/archive/2026-04-29-currency-modes-rework/` (the moved folder, content unchanged)

`pubspec.yaml` was not touched. Per project memory rule, version/build numbers stay as-is.

---

## 5. Test count snapshot at archive time

- **182 / 182 passing** in the focused regression suite (~5s wall time).
- This matches the verify report exactly. No tests were added, removed, or re-run during the archive phase.

---

## 6. Risks / deviations / anomalies

| Item | Severity | Note |
|------|----------|------|
| Tasks 3.7 and 8.3 unchecked in `tasks.md` | Informational | Bookkeeping-only; the deliverable test files exist (Phase 10 absorbed them). Verify report explicitly accepted this and recommended an optional flip to `[x]` with back-pointers. NOT blocking. Tasks file is preserved as-is in the archive (immutable post-archive). |
| Main spec corpus was empty pre-archive | Informational | All 5 deltas became CREATE operations, not MERGE. No conflicts possible. Documented above for future archivers — this is the seed of `openspec/specs/`. |
| `EXPLAIN QUERY PLAN` task 9.6 deferred | Informational | Marked `[x]` in tasks with deferral rationale ("3 betas — perf irrelevant, document for re-check before broader release"). Re-check is a future-change concern, not an archive blocker. |

No CRITICAL issues, no merge conflicts, no destructive overwrites — clean archive.

---

## 7. Source of truth — post-archive state

`openspec/specs/` now contains the canonical specs for:

- `settings/`
- `onboarding/`
- `currency-display/` (new capability)
- `exchange-rates/`
- `transactions/`

Future SDD changes that touch any of these capabilities MUST read from `openspec/specs/{capability}/spec.md` and produce delta specs that this archive phase will then merge back in.

---

## 8. SDD cycle closure

- **Explore** → done (`exploration.md`)
- **Propose** → done (`proposal.md`)
- **Spec** → done (5 delta specs)
- **Design** → done (`design.md`)
- **Tasks** → done (`tasks.md`, 70/72 `[x]`, 2 deferred-to-Phase-10)
- **Apply** → done (`apply-progress.md`, all phases landed)
- **Verify** → done (`verify-report.md`, PASS)
- **Archive** → done (this report; specs synced; folder moved)

The `currency-modes-rework` SDD cycle is complete. Ready for the next change.
