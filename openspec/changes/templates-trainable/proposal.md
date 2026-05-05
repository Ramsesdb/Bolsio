# Proposal: User-Trainable Notification Templates

## Why

Today nitido parses bank notifications through a flat list of hand-coded `BankProfile`s (`BdvSmsProfile`, `BdvNotifProfile`, `BinanceApiProfile`) plus a generic LLM fallback. Anything that doesn't match a regex profile and isn't covered by `GenericLlmProfile` (LLM disabled, no API key, novel sender, or unsupported format variation) silently lands in the unparseable pile. The 200-event in-memory `CaptureEventLog` is a diagnostics tool, not a training surface, so users have no path to teach the app a new SMS format short of waiting for upstream code. This change lets a user paste one sample, mark the fields, and produce a literal-anchor template that slots into the existing pipeline between the regex profiles and the LLM — with zero LLM cost, fully offline, and stored in Drift so it travels with the existing `.db` backup.

## What Changes

- **New profile**: `TemplatesNotifProfile` (stateless, single `profileId = 'templates_user'`) implementing `BankProfile` per `lib/core/services/auto_import/profiles/bank_profile.dart:48-106`. Receives a `List<NotificationTemplate>` via constructor; the orchestrator hydrates from Drift at registry construction time.
- **New Drift table `notificationTemplates`** (migration v30): `id, senderPackage, bankName, accountMatchName, transactionType, currencyHint, anchorsJson, samplesJson, confidence (default 0.85), enabled (NOT NULL DEFAULT 1), createdAt, lastMatchedAt, version`. Multiple rows per `(senderPackage, bankName)`; orchestrator orders `confidence DESC, lastMatchedAt DESC`.
- **New Drift table `unparsedNotifs`** (same migration): `id, sender, rawText, timestamp, fingerprint, createdAt`. Written when neither regex nor LLM produces a successful parse (or LLM is disabled / no API key). Powers the new "Sin perfil" filter chip on `PendingImportsPage`.
- **Anchor schema (locked v1)**: per-field `{prefix, suffix, normalizer, required}`. Prefix/suffix are LITERAL strings (not regex), max 8 graphemes counted via `String.length` (UTF-16 code units), can be empty for boundary fields. Normalizer enum is closed and tiny — `{numeric_es, literal}` only. `required: true` means the whole template fails if the field doesn't match; default is `true` for `amount`, `false` otherwise.
- **Numeric reuse**: extract `BdvSmsProfile.parseVenezuelanNumber` (`lib/core/services/auto_import/profiles/bdv_sms_profile.dart:125-133`) into a shared util (e.g. `lib/core/utils/locale_number_parser.dart`) and reuse it as the `numeric_es` normalizer.
- **Currency cascade (no interface change)**: `TemplatesNotifProfile` constructor takes a `Map<String, String>` keyed by package → default currency, derived from `kSupportedBanks` in `lib/core/services/auto_import/supported_banks.dart`. At parse time: (1) detect from rawText (`Bs.` → VES, `$` → USD, copying the regex from `lib/core/services/auto_import/profiles/bdv_notif_profile.dart:46-55`), (2) fall back to `template.currencyHint`, (3) fall back to `kSupportedBanks` lookup by `event.sender`, (4) fail. Pure-Dart const lookup, no DB access from the parser, no breaking change to `BankProfile`.
- **Pipeline priority**: registry literal in `lib/core/services/auto_import/profiles/bank_profiles_registry.dart:10-14` becomes `[BdvSmsProfile, BdvNotifProfile, BinanceApiProfile, TemplatesNotifProfile]`. Templates run AFTER dedicated regex profiles, BEFORE the LLM fallback at `capture_orchestrator.dart:739-862`. Confidence cap 0.85; on 3 consecutive failures `confidence -= 0.10`. Diagnostics log `template_id`.
- **Toggle granularity (both)**: profile-level kill switch via new `SettingKey.userTemplatesEnabled` plus a `'templates_user'` case in `UserSettingService.isProfileEnabled` (`lib/core/database/services/user-setting/user_setting_service.dart:230-253`), mirroring the existing `'generic_llm'` precedent. Per-row `enabled` column for disabling individual misbehaving templates without nuking the feature.
- **Auto-purge**: `unparsedNotifs.purge()` deletes rows older than 30 days, called once per session from `main.dart` post-frame next to the existing `StatementBatchesService.purge()` call (`lib/main.dart:649-654`), mirroring the precedent at `lib/core/services/auto_import/statement_batches_service.dart:128-139`.
- **Training UI**: form-based field marking — user pastes raw text, taps a field button (Amount / Counterparty / Reference), then taps a value in the rendered text; UI snapshots up to 8 chars before/after as literal anchors. Triggers: (a) "Train this format" button on the existing diagnostics screen (`capture_diagnostics.page.dart`), (b) row action on the new "Sin perfil" filter chip on `PendingImportsPage`.
- **i18n**: new `templates` namespace in `lib/i18n/json/en.json` + `es.json` (minimum); regenerate via `dart run slang`. The new training UI uses slang keys (not the legacy inline `_tr(es:, en:)` pattern in `capture_diagnostics.page.dart:32-37`).

## Affected Modules

| Group | Files |
|-------|-------|
| Drift schema | `lib/core/database/sql/initial/tables.drift` (add `notificationTemplates`, `unparsedNotifs` blocks; pattern from `pendingImports` at `tables.drift:363-427`), `assets/sql/migrations/v30.sql` (new), `lib/core/database/app_db.dart:128` (`schemaVersion = 30`) |
| Drift services | `lib/core/database/services/notification_templates/` (new — builders + service), `lib/core/database/services/unparsed_notifs/` (new — builder + service with `purge()`) |
| Profile parser | `lib/core/services/auto_import/profiles/templates_notif_profile.dart` (new), `lib/core/services/auto_import/profiles/bank_profiles_registry.dart` (insert after Binance) |
| Numeric util | `lib/core/utils/locale_number_parser.dart` (new — extracted from `BdvSmsProfile.parseVenezuelanNumber`), `lib/core/services/auto_import/profiles/bdv_sms_profile.dart` (use shared util) |
| Orchestrator | `lib/core/services/auto_import/orchestrator/capture_orchestrator.dart` (write `unparsedNotifs` row when both regex and LLM fail; inject `kSupportedBanks` map into `TemplatesNotifProfile` at registry construction) |
| Setting key | `lib/core/database/services/user-setting/user_setting_service.dart` (`SettingKey.userTemplatesEnabled` + `'templates_user'` case in `isProfileEnabled`) |
| Bootstrap | `lib/main.dart:649-654` (call `unparsedNotifs.purge()` post-frame) |
| Pending imports UI | `lib/app/pending_imports/pending_imports.page.dart` (new "Sin perfil" filter chip querying `unparsedNotifs`; row action → training flow) |
| Diagnostics UI | `lib/app/diagnostics/capture_diagnostics.page.dart` ("Train this format" entry) |
| Training UI | `lib/app/auto_import/templates/` (new — form-based field marking flow, per-template toggle list) |
| Settings | `lib/app/settings/pages/auto_import/auto_import_settings.page.dart` (or equivalent) — toggle for `userTemplatesEnabled` |
| i18n | `lib/i18n/json/en.json`, `lib/i18n/json/es.json` (new `templates` namespace); regenerate via `dart run slang` |
| Tests | `test/auto_import/profile_ordering_test.dart` (new — asserts BDV always wins for BDV-package events), parser unit tests for `TemplatesNotifProfile` over BDV format variations + es-VE numeric parsing, manifest sync test that `templates_user` is registered properly |

## Drift Schema Migration

`v29 → v30` follows the standard pattern at `lib/core/database/app_db.dart:79-125` (`migrateDB` reads `assets/sql/migrations/v$i.sql`, wraps in transaction, advances `dbVersion`). `_kSkippedMigrations = {10}` (line 77) does not affect this slot. Additive only — two new tables, no DDL touching existing schema. Backup is free via the existing `.db` byte copy at `lib/core/database/backup/backup_database_service.dart:33-46`.

## Rollback Plan

1. **Kill switch**: set `SettingKey.userTemplatesEnabled = '0'` in user settings. The orchestrator skips `TemplatesNotifProfile` via the `isProfileEnabled('templates_user')` check at `capture_orchestrator.dart:469-482`.
2. **Code revert**: `git revert` of the commit that inserts `TemplatesNotifProfile()` into `bankProfilesRegistry`. Tables remain inert (read but not used).
3. **Schema**: additive migration only — no rollback DDL needed. `DELETE FROM notificationTemplates; DELETE FROM unparsedNotifs;` if cleanup is desired.
4. **30-day purge** keeps `unparsedNotifs` bounded automatically; no manual cleanup ever required.
5. **Backup compatibility**: pre-v30 backups restore cleanly — the migration runs forward on first cold start. Post-v30 backups restored on a pre-v30 build show empty tables and no behavior change (both feature toggles fall through to current behavior).

No persisted notification text leaves the device. No telemetry, no network. Rollback is safe at any tanda boundary.

## Risks

| Risk | Likelihood | Mitigation |
|------|------------|------------|
| Registry ordering — templates must run AFTER BDV and BEFORE LLM. Today's registry is a flat literal. | High | Add `test/auto_import/profile_ordering_test.dart` asserting `BdvNotifProfile` always wins for `com.bancodevenezuela.bdvdigital` events even when a templates row exists for that package. Document the registry literal as the ordering source of truth. |
| `unparsedNotifs` table growth | Med | 30-day auto-purge wired into `main.dart` post-frame, mirroring `StatementBatchesService.purge`. |
| `_isKnownBankSender` (`capture_orchestrator.dart:741-744`) gates LLM fallback. A template trained for an unsupported sender becomes the SOLE parser; if it fails, the event is unparseable. | Med | The new `unparsedNotifs` table catches this naturally. The "Sin perfil" UX surfaces "template-only sender, template failed" rows so the user can retrain. |
| 8-char anchor window slicing a surrogate pair | Low | Documented as known limit. `String.length` on UTF-16 code units is the established convention; the `characters:` package is not a direct dep and has zero usage in `lib/`. Parse fails silently and the user retrains. Revisit in v2 only if real reports surface. |
| `NotifFingerprint` dedupe (`capture_orchestrator.dart:385-440`) runs BEFORE the profile loop, so `lastMatchedAt` updates only on first sighting per fingerprint. | Low | Acceptable; documented. Dedupe is beneficial — Android repost storms don't re-fire the templates parser. |
| Template auto-categorization — when a template extracts `counterparty`, do we also run AI auto-categorization? | Low | Out of scope v1; keep current behavior (auto-categorize if AI enabled, no change needed). |

## Out of Scope (Explicit)

- **Regex inference from samples** (the rejected Option B from exploration; v1 is single-sample, literal anchors only).
- **Multi-format number parsing** beyond es-VE. v1 normalizer enum is closed: `{numeric_es, literal}`. Adding `numeric_us`, `numeric_auto`, `phone_ve`, `iso_date`, etc. is deferred to v2 only if real usage data justifies it. Building a multi-format currency parser is explicitly out of scope.
- **Community sharing** of templates (anchors JSON is portable; share UX deferred to v2).
- **Grapheme-correct anchor handling** (no `characters:` package adoption in v1).
- **LLM-assisted template suggestion** ("looks like the amount is here").
- **Voice-driven template training**.
- **Template editing post-creation** (v1 is delete + retrain).
- **Per-template Firebase sync** (rides the existing `.db` backup; no separate sync surface).
- **Changes to `BankProfile` interface** (no new parameter, no breaking change to `BdvSmsProfile`/`BdvNotifProfile`/`BinanceApiProfile`/`GenericLlmProfile`).

## Effort

**9-10 engineer-days.**

- Drift migration v30 + 2 tables (`notificationTemplates`, `unparsedNotifs`) + builders/services: 1.5d
- `TemplatesNotifProfile` parser + tests covering BDV format variations + shared `locale_number_parser` extraction: 2d
- Orchestrator wiring (registry order + `unparsedNotifs` write on no-match + currency cascade injection): 1d
- Training UI (form-based field marking, "Train this format" entry from diagnostics): 3d
- "Sin perfil" filter chip on `PendingImportsPage`: 1d
- Settings page integration + per-template toggle UI + i18n keys (en + es minimum): 1d
- Documentation + manifest sync test (templates profile registered properly): 0.5d

## Phasing Suggestion

(For `/sdd-tasks` to refine.)

1. **Schema + model**: `v30.sql`, two Drift tables, builders, services, `purge()`, `SettingKey.userTemplatesEnabled` + `isProfileEnabled('templates_user')` case.
2. **Numeric extraction**: pull `parseVenezuelanNumber` into `lib/core/utils/locale_number_parser.dart`; rewire `BdvSmsProfile`. Pure refactor, no behavior change.
3. **Parser + registry**: `TemplatesNotifProfile`, registry insert after Binance, currency cascade injection at construction time, `profile_ordering_test.dart`.
4. **Orchestrator wiring**: write `unparsedNotifs` row when both regex and LLM fail (or LLM disabled / no key); call `purge()` from `main.dart` post-frame.
5. **Training UI**: form-based field marking flow, "Train this format" entry from diagnostics, per-template toggle list.
6. **"Sin perfil" surface**: filter chip on `PendingImportsPage` querying `unparsedNotifs`; row action → training flow.
7. **Settings + i18n + polish**: `userTemplatesEnabled` toggle on auto-import settings, `templates` namespace in en/es JSONs, `dart run slang`, manifest sync test.

## Success Criteria

- [ ] User receives an SMS in a previously-unparsed format → event lands in `unparsedNotifs`, surfaces in the new "Sin perfil" filter chip on `PendingImportsPage`.
- [ ] User taps the row, marks Amount / Counterparty / Reference on the rendered text, saves the template → next SMS in the same format parses through `TemplatesNotifProfile` with confidence 0.85, populates a `pendingImports` row, and `template.lastMatchedAt` updates.
- [ ] BDV SMS in a known format continues to parse through `BdvSmsProfile` even when a templates row exists for the BDV package — verified by `profile_ordering_test.dart`.
- [ ] Setting `userTemplatesEnabled = '0'` disables `TemplatesNotifProfile` at the registry; trained templates remain in Drift, inert until re-enabled.
- [ ] Per-template `enabled = 0` disables one row without affecting others.
- [ ] After 3 consecutive failures, the template's `confidence` drops by 0.10; logged in diagnostics with `template_id`.
- [ ] `unparsedNotifs` rows older than 30 days are purged on cold start (verified post-frame call from `main.dart`).
- [ ] No regression in `BdvSmsProfile`, `BdvNotifProfile`, `BinanceApiProfile`, or `GenericLlmProfile` outputs (existing tests pass unchanged).
- [ ] `flutter analyze` passes; `dart run slang` regenerates without warnings; `.db` backup roundtrip preserves both new tables.
- [ ] No notification text leaves the device — no new network calls, no telemetry, fully offline.
