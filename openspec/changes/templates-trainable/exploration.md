# Exploration: templates-trainable

User-trainable notification parsing templates that slot into the existing `BankProfile` pipeline. Most design work was done before this exploration; this document is **validation + risk surfacing**, not greenfield.

## Locked Design (baseline — not under re-debate)

**Option A — form-based, anchor-based templates.** Effort: 9–11 engineer-days.

- **Storage:** new Drift table `notificationTemplates` (migration v30). Columns: `id, senderPackage, bankName, accountMatchName, transactionType, currencyHint, anchorsJson, samplesJson, confidence (default 0.85), enabled, createdAt, lastMatchedAt, version`.
- **Field marking:** form-based. User pastes raw text, taps a field button (Amount / Counterparty / Reference), then taps a value in the rendered text; UI snapshots 8 chars before/after as literal anchors.
- **Generalization:** single-sample, literal anchors, NO regex inference. Per-field normalizer (numeric for amount, etc.). Fuzzy whitespace + accent matching at parse time.
- **Granularity:** multiple templates per `(senderPackage, bankName)`; orchestrator orders them `confidence DESC, lastMatchedAt DESC`. Each tagged credit/debit/transfer/auto.
- **Pipeline priority:** templates run AFTER dedicated regex profiles, BEFORE GenericLlmProfile. Confidence cap 0.85.
- **Training trigger:** (a) "Train this format" button on diagnostics screen; (b) new "Sin perfil" filter chip on `PendingImportsPage` that surfaces unparseable events from `CaptureEventLog`.
- **Failure path:** silent fallback to LLM/unparseable pile; after 3 consecutive failures, drop `confidence` by 0.10. Diagnostics log `template_id`.
- **Backup:** free — Drift table travels with the existing `.db` byte copy (`backup_database_service.dart:33`–`46`).
- **Community sharing:** out of scope v1. JSON anchors format is portable.

**Hard constraints:** stateless `BankProfile` impl (no Drift inside parsing); orchestrator loads templates from Drift and passes them to the parser; matches via `channel + knownSenders.contains(sender)`; fully offline (no LLM, no network); MUST NOT regress BDV/Binance/GenericLlmProfile; NO telemetry of notification text.

## Codebase Validation

### Critical files exist and shape matches assumptions

- `lib/core/services/auto_import/profiles/bank_profile.dart:48–106` — abstract `BankProfile` with `profileId`, `bankName`, `accountMatchName`, `channel`, `knownSenders`, `profileVersion`, `tryParse`, `tryParseWithDetails`. **The interface is exactly what the design memo assumed.** A `TemplatesNotifProfile` can implement this without subclassing tricks; the trainable side passes a `List<NotificationTemplate>` into the constructor (loaded by the orchestrator from Drift), keeping the parser stateless.
- `lib/core/services/auto_import/profiles/bank_profiles_registry.dart:10–14` — current registry is a flat `final List<BankProfile> bankProfilesRegistry = [BdvSmsProfile(), BdvNotifProfile(), BinanceApiProfile()]`. **A trainable profile cannot simply be appended** — it must run AFTER dedicated regex profiles and BEFORE the LLM fallback. See "Integration Risks" §1 below.
- `lib/core/services/auto_import/orchestrator/capture_orchestrator.dart:443–732` — dispatch: filter `bankProfilesRegistry` by `channel + knownSenders`, then iterate `matchingProfiles` and break on first success (`createdTransactionId ??= ...`). LLM fallback at lines `739–862` runs only when `!anyProfileSucceeded`. Confirmed: a templates profile inserted into the same registry inherits ordering automatically — provided we control the order, which we do (registry literal).
- `lib/core/database/app_db.dart:128` — `int get schemaVersion => 29;` (most recent migration: `assets/sql/migrations/v29.sql`, partial UNIQUE index on `pendingImports`). **v29 → v30 is the correct path.** `_kSkippedMigrations = {10}` (line 77) is a hard rule for the renumber.
- `lib/core/database/app_db.dart:79–125` — `migrateDB` loops `from+1..to` reading `assets/sql/migrations/v$i.sql`, wraps each in a `transaction(...)`, then advances `AppDataKey.dbVersion`. **Pattern: drop a `v30.sql` next to `v29.sql` and we are done.**
- `lib/core/database/sql/initial/tables.drift:363–427` — the `pendingImports` table block is the precedent for adding `notificationTemplates`. The drift file uses `AS PendingImportInDB;` suffix for the generated row class.
- `lib/core/database/backup/backup_database_service.dart:33–46` — confirmed `.db` byte copy via `getDbFileInBytes`. **Drift table travels for free.**

### i18n confirmed

- `build.yaml:24–37` configures `slang_build_runner` with `base_locale: en`, `key_case: snake`, `fallback_strategy: base_locale`.
- 10 locale JSONs live in `lib/i18n/json/`. Adding a `templates` namespace block to `en.json` + `es.json` and regenerating via `dart run slang` is the established path.
- The `capture_diagnostics.page.dart:32–37` uses an inline `_tr(es:, en:)` shortcut (legacy pattern) — the new training UI should use slang keys instead for consistency.

## Integration Risks Surfaced (NOT in the locked memo)

### Risk 1 — Registry ordering must be enforced (HIGH)

The orchestrator iterates `bankProfilesRegistry` in registration order; first match wins. Today's registry is hand-ordered (`BdvSmsProfile, BdvNotifProfile, BinanceApiProfile`). **Inserting `TemplatesNotifProfile` AFTER BDV but BEFORE the LLM fallback means the registry literal must be edited surgically**, and we need a regression test asserting that BDV always parses first when a BDV-package event arrives. Otherwise a buggy template tagged for `com.bancodevenezuela.bdvdigital` could shadow `BdvNotifProfile`. Mitigate: add a `priority` field on `BankProfile` OR keep the literal ordering and document it. Recommend the latter (less surface change). Add a `test/auto_import/profile_ordering_test.dart`.

### Risk 2 — `CaptureEventLog` is NOT a Drift table (HIGH)

`lib/core/services/auto_import/capture/capture_event_log.dart:39–52` is an **in-memory ring buffer (200 entries) persisted via SharedPreferences (last 100 only)**. The locked memo's "Sin perfil" filter chip on `PendingImportsPage` assumed it could query unparseable events alongside `pendingImports` rows. **It cannot — they are different stores.**

Two paths forward (must-answer-before-spec):

- **2a.** Surface unparseable events via `CaptureEventLog.instance.listenable` (in-memory + SP), filtered to `parsedFailed` and `filteredOut` statuses. Pros: no schema change. Cons: only the last 200 events; `parsedFailed` ≠ "no profile available" exactly (it includes profile exceptions).
- **2b.** Persist a new minimal "unparseable" Drift row whenever no profile matches. Pros: queryable, durable, dedupable. Cons: extra schema surface.

Recommend **2a for v1** (the diagnostics page already hydrates it). Document the 200-event window as a known limit.

### Risk 3 — `RawCaptureEvent.rawText` fidelity (MEDIUM)

`lib/core/models/auto_import/raw_capture_event.dart:11–12`: `rawText` is the verbatim bundle of `title + '\n' + body` produced by `NotificationCaptureSource`. The orchestrator's `_buildDiagnosticBase` (`capture_orchestrator.dart:888–929`) splits on the first `\n` for display. **Anchor extraction must operate on the same combined string the user sees in the training UI**, otherwise an anchor captured against "title\nbody" will not match a stored event whose `rawText` is "title body". Confirm the training UI reads `event.rawText` directly (not the split title/body) and the parser does the same.

Edge: BDV notifications occasionally carry non-breaking space U+00A0 and right-to-left marks — fuzzy whitespace matching in the parser must normalize Unicode whitespace classes, not just ASCII space.

### Risk 4 — Fingerprint dedupe runs BEFORE templates (LOW)

`capture_orchestrator.dart:385–440` dedupes by `NotifFingerprint` BEFORE the profile loop. **Beneficial** for templates: a known-content notification will not re-fire the templates parser on every Android repost. No change needed; just be aware that template `lastMatchedAt` updates only on the first sighting per fingerprint.

### Risk 5 — `_isKnownBankSender` gates the LLM fallback (MEDIUM)

`capture_orchestrator.dart:741–744`: LLM only fires when `BankDetectionService.kPackageToProfileId.containsKey(sender)`. **A template trained against an unsupported sender (e.g. a regional bank not yet in `kPackageToProfileId`) would be the ONLY parser for that package** — neither dedicated profile nor LLM fallback will run. That is desirable, but the user must understand: if their template breaks, the event becomes unparseable. The "Sin perfil" UX (Risk 2) needs to also surface "template-only sender, template failed" rows.

### Risk 6 — Per-template toggle and drift in `UserSettingService.isProfileEnabled` (LOW)

The orchestrator at `capture_orchestrator.dart:469–482` calls `UserSettingService.instance.isProfileEnabled(profile.profileId)`. Each `BankProfile` exposes a single `profileId`. A trainable profile carries N templates internally; do they share a single `profileId` (e.g. `'templates_v1'`) or one toggle per template? The locked memo says "templates parser MUST be a stateless `BankProfile` implementation" implying a single profileId. **Recommend** one toggle (`templates_user`) at the profile level; per-template `enabled` flag lives in the Drift row. Confirm before spec.

## Open Questions

### Must-answer-before-spec

1. **Risk 2 resolution:** "Sin perfil" chip — go with `CaptureEventLog` filter (2a) or new Drift row (2b)?
2. **Risk 6 resolution:** profile-level toggle vs per-template toggle?
3. **Anchor format final shape:** `anchorsJson = { "amount": {"prefix":"Bs. ", "suffix":" en", "normalizer":"numeric_es"}, ... }` — confirm this exact schema before spec, since it locks Drift content.
4. **Multi-currency:** does `currencyHint` accept null (parser inspects rawText for `Bs.`/`$`) or is it required at training time?

### Can-defer-to-implementation

- Exact UI gesture for "tap a value in rendered text" (text selection vs interactive tokens).
- Whether to expose anchor previews in the diagnostics tile.
- Whether `samplesJson` keeps a single sample (training pivot) or up to N (audit trail).

## Conflict Check with In-Flight Changes

- **`onboarding-v2-auto-import`**: I scanned its `proposal.md:1–60` and `tasks.md:1–40`. It owns the `intro` namespace in `lib/i18n/json/*.json` and adds the `bank_detection_service.dart` (already present at `lib/core/services/bank_detection/bank_detection_service.dart`). **No collision** — templates introduces a new `templates` namespace and reuses `BankDetectionService` read-only. Both can land in any order; only the i18n JSON merge needs care if both PRs touch `es.json` simultaneously.
- No other active change touches `bank_profiles_registry.dart`, the orchestrator, or `notificationTemplates`.

## Recommendation

Proceed to `sdd-propose`. Locked design is sound and codebase-compatible. Resolve the 4 must-answer questions during proposal drafting; the 6 risks above belong in the proposal's "Risks" section.

## Ready for Proposal

**Yes** — the orchestrator can take the new profile, the schema bump path is clean (v29 → v30, no skipped slot), the backup pattern preserves data for free, and the two genuine integration risks (`CaptureEventLog` is not Drift; registry ordering must be enforced) are tractable design choices, not blockers.
