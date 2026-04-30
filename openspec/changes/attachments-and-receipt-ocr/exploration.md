# Exploration: attachments-and-receipt-ocr

## Context

Bolsio currently forces manual transcription of transactions from Pago Móvil BDV screenshots, bank transfer confirmations, and invoice photos — error-prone work compounded by dual-currency (USD/VES) and BCV/paralelo rates. User avatars are also limited to SVG presets with no custom-image support. The same storage primitive (local attachments with DB metadata) solves both gaps.

Goal: from the dashboard FAB, pick an image (gallery or camera), extract transaction fields via a hybrid OCR + multimodal-AI + regex-fallback pipeline, pre-fill the transaction form, and persist the image as a permanent attachment — reusing a generic `attachments` subsystem that later powers custom avatars (and future: budgets, accounts, multi-image).

A detailed plan is already approved at `C:\Users\ramse\.claude\plans\como-puedo-hacer-para-linked-blum.md`; this exploration condenses it into the SDD format and flags dependencies with concurrent active changes.

---

## Current State

### Transaction capture pipeline

- `CaptureOrchestrator` consumes `RawCaptureEvent`s, matches them against `BankProfile`s, runs `DedupeChecker`, and persists via `PendingImportService.insertProposal()`.
- `TransactionProposal` already carries structured fields (`amount`, `currencyId`, `date`, `type`, `counterpartyName`, `bankRef`, `bankName`) but lacks a `receiptImage` channel.
- `BdvNotifProfile` (`lib/core/services/auto_import/profiles/bdv_notif_profile.dart`) owns the regex library for BDV Pago Móvil / transfers — currently invoked only from the notification-listener flow but fully reusable over arbitrary text.

### AI layer (from active change `bolsio-ai-integration`)

- `NexusAiService` (`lib/core/services/ai/nexus_ai_service.dart`) proxies to `api.ramsesdb.tech` (multi-provider gateway: Cerebras, Groq, Gemini, OpenRouter). Today it exposes `complete()` (non-streaming) and SSE streaming for chat, both text-only.
- `NexusCredentialsStore` with `flutter_secure_storage` encrypted prefs. Master toggle `nexusAiEnabled` in settings.
- No multimodal (vision) path exists.

### Transaction form / FAB

- `TransactionFormPage` (`lib/app/transactions/form/transaction_form.page.dart:44`) has one constructor today — no "pre-fill from proposal" path beyond the auto-import modal.
- Dashboard FAB is `NewTransactionButton` (`lib/app/home/widgets/new_transaction_fl_button.dart`), wrapped in `AnimatedFloatingButtonBasedOnScroll` for hide-on-scroll.
- `flutter_expandable_fab` is declared in `pubspec.yaml` but unused — ready to activate.

### Database

- Drift schema at version 22. Tables defined in `lib/core/database/sql/initial/tables.drift`. Migrations under `assets/sql/migrations/vN.sql`, registered in `lib/core/database/app_db.dart`.
- No `attachments` table. The `transactions` table has no image column.

### Avatar

- SVG presets only, selected through the edit-profile modal under settings. No storage path exists for user-supplied images.

### Packages available / missing

- Present: `http`, `flutter_secure_storage`, `path_provider`, `flutter_expandable_fab` (unused), `permission_handler`, `image_picker` in other contexts verified in pubspec.
- Missing: `google_mlkit_text_recognition`, `image` (compression), `image_picker` if not already present — plan calls them out to add.

---

## Affected Areas

### DB & models
- `lib/core/database/sql/initial/tables.drift` — add `attachments` table + `idx_attachments_owner` index.
- `lib/core/database/app_db.dart` — bump schemaVersion 22 → 23; register migration.
- `assets/sql/migrations/v23.sql` — new file, `CREATE TABLE` + index.
- `lib/core/models/auto_import/transaction_proposal.dart` — add `CaptureChannel.receiptImage` enum case.

### New services
- `lib/core/services/attachments/attachment_model.dart` — `Attachment`, `AttachmentOwnerType` enum (`transaction | userProfile | account | budget`).
- `lib/core/services/attachments/attachments_service.dart` — `attach`, `listByOwner`, `firstByOwner`, `deleteById`, `deleteByOwner`, `purgeOrphans`, `resolveFile`.
- `lib/core/services/receipt_ocr/receipt_image_service.dart` — gallery/camera pick, compression (`image` pkg, 1600px longest side, JPEG q=82), temp save.
- `lib/core/services/receipt_ocr/ocr_service.dart` — ML Kit Latin recognizer wrapper.
- `lib/core/services/receipt_ocr/receipt_extractor_service.dart` — orchestrates OCR → Nexus multimodal → regex fallback → `TransactionProposal`.

### AI extension
- `lib/core/services/ai/nexus_ai_service.dart` — add `completeMultimodal({systemPrompt, userPrompt, imageBase64, temperature})`. **This extends the service introduced by `bolsio-ai-integration`** (see overlap section).

### UI
- `lib/app/transactions/receipt_import/receipt_import_flow.dart` (new) — entry point from FAB.
- `lib/app/transactions/receipt_import/receipt_review_page.dart` (new) — preview + editable fields + confidence indicator.
- `lib/app/common/widgets/attachment_viewer.dart` (new) — fullscreen pinch-zoom viewer, reusable.
- `lib/app/transactions/form/transaction_form.page.dart` — new `TransactionFormPage.fromReceipt(...)` constructor accepting pre-filled fields + `pendingAttachmentPath`.
- `lib/app/home/widgets/new_transaction_fl_button.dart` — migrate to `ExpandableFab` with 3 actions (manual, gallery, camera).
- Edit-profile modal (path TBD; plan notes `edit_profile_modal.dart`) — add "Subir foto" above SVG grid for avatar.

### Settings / i18n
- `lib/app/settings/pages/ai/ai_settings.page.dart` — add `SettingKey.receiptAiEnabled` toggle (default true).
- `i18n/*.i18n.json` — new keys under `t.transaction.receipt_import.*`, `t.attachments.*`, `t.profile.*`.

### Cleanup integration
- `lib/core/database/services/transaction/transaction_service.dart` — `deleteTransaction()` calls `AttachmentsService.deleteByOwner(transaction, id)`.
- `lib/core/services/auto_import/pending_import_service.dart` — reuse for `bankRef` dedupe on receipt imports.

### Platform config
- `android/app/src/main/AndroidManifest.xml` — `CAMERA` permission + non-required camera feature.
- `ios/Runner/Info.plist` — `NSCameraUsageDescription`, `NSPhotoLibraryUsageDescription`.
- `pubspec.yaml` — add `image_picker`, `google_mlkit_text_recognition`, `image`.

---

## Overlap With Active Changes

| Change | Overlap type | Notes |
|--------|--------------|-------|
| `bolsio-ai-integration` | **EXTENDS** | Owns `NexusAiService` and settings scaffolding. This change adds a `completeMultimodal()` method on that service and a `receiptAiEnabled` sub-toggle beside the master `nexusAiEnabled`. We MUST sequence after (or coordinate with) `bolsio-ai-integration`'s foundation phase. Backward-compatible addition — no breaking change to existing text-only `complete()`. |
| `firebase-always-on` | **NONE (indirect note)** | Unrelated domain (auth/sync). Worth noting only that attached files are **not** synced to Firebase in this change's scope — backup/sync of binary attachments is out of scope and deferred. If Ramses relies on Firebase restore post-reinstall, receipts will be lost. Flag as known limitation. |
| `fix-exchange-rate-fallback` | **NONE** | Pure display/SQL fix in exchange-rate layer. No surface contact with transaction capture, DB schema beyond its own queries, or attachments. Safe to develop in parallel. |

---

## Approaches

### 1. Generic `attachments` table + service (RECOMMENDED)

Single table `attachments(id, ownerType, ownerId, localPath, mimeType, sizeBytes, role, createdAt)` with polymorphic `ownerType` discriminator and no hard FK. One `AttachmentsService` owns file I/O, DB CRUD, and orphan cleanup.

- Pros:
  - One subsystem powers receipts, avatars, and future budget/account attachments.
  - No schema churn per new owner; only a new enum case.
  - Supports multiple attachments per entity out of the gate (receipts + future invoice + supplementary image).
  - `purgeOrphans()` handles app crashes mid-flow uniformly.
  - Avoids bloating `transactions` (or `userProfiles`) with binary/path metadata.
- Cons:
  - Requires cleanup discipline: every entity-delete site must call `deleteByOwner`. Miss one → orphans (mitigated by `purgeOrphans`).
  - Polymorphic design lacks hard referential integrity — ownership is a convention, not a constraint.
  - Slightly more indirection for simple "one receipt per transaction" reads vs. a direct column.
- Effort: **Medium** (DB migration + service + 5 callers; designed for reuse).

### 2. Direct column per entity (`transactions.receiptPath`, `userProfiles.avatarPath`)

Add a nullable `TEXT` column on each entity that needs an image.

- Pros:
  - Simplest possible shape; one migration per entity.
  - Hard referential coupling — deleting the row deletes the reference automatically.
  - Zero indirection on reads.
- Cons:
  - Duplicates file-lifecycle logic across entities (compress, move, cleanup, orphan detection).
  - One image per entity cap — hostile to future "multiple invoices per purchase" or audit-photo-plus-receipt scenarios.
  - Every new owner type (budget, goal, account) = another migration + another ad-hoc service.
  - Avatar work lives in a totally different code path than receipt work despite identical I/O.
- Effort: **Low** for receipts alone; **High** cumulatively across all owners (avatar work re-implements 80% of receipt work).

### 3. Filesystem-only (no DB table; derive from conventional paths)

Store files at `attachments/transaction/<txId>.jpg` and check existence on read.

- Pros:
  - Zero schema changes.
  - Trivially simple.
- Cons:
  - No metadata (size, mime, role, createdAt) — can't differentiate multiple images or roles.
  - Listing is an `ls` + parse, slow and fragile.
  - No referential cleanup — deleting a transaction relies on someone remembering to delete the file.
  - No way to support multi-attachment without re-inventing a sidecar index.
- Effort: **Low** short-term, **High** long-term.

---

## Recommendation

**Approach 1 (generic `attachments` table + service).** The user already approved this. The second-order payoff — enabling custom avatar support in the same change with no extra DB work — converts a single-feature change into a platform primitive. The cleanup-discipline risk is real but bounded: `purgeOrphans()` is the safety net, and there are only a handful of delete sites to instrument.

Sequencing (from the approved plan):

1. Infrastructure — `attachments` table, service, package adds, permissions.
2. OCR + regex-only extractor — proves local pipeline without touching Nexus.
3. Nexus multimodal — `completeMultimodal()` + `receiptAiEnabled` toggle + integration.
4. UI — review page, form `.fromReceipt` constructor, `AttachmentViewer`.
5. FAB + transaction detail + polish — `ExpandableFab`, receipt chip, dedupe.
6. Avatar custom — edit-profile modal extension + `UserAvatarDisplay` widget.

Tandas 1–3 are backend-ish and testable without UI. Tanda 4 is the user-visible MVP. Tandas 5–6 are polish and the avatar payoff.

---

## Risks

- **Sequencing dependency on `bolsio-ai-integration`.** `completeMultimodal()` assumes `NexusAiService` and credentials store exist. Mitigate: implement tanda 2 (regex-only) first so the receipt feature is functional without Nexus; gate tanda 3 on `bolsio-ai-integration`'s foundation phase landing.
- **DB migration v22 → v23 on live data.** Ramses has real balances on device. Mitigate: additive-only migration (no `ALTER TABLE` on `transactions`); test on a DB copy before pushing.
- **ML Kit binary size.** `google_mlkit_text_recognition` adds ~15–25 MB to APK. Acceptable for a personal app; document for awareness.
- **Camera permission friction on MIUI.** Xiaomi aggressively revokes permissions. Mitigate: `permission_handler.openAppSettings()` with explanatory dialog when denied.
- **Orphan files on crash mid-import.** Mitigate: run `purgeOrphans()` on app startup in debug, and after successful/cancelled import flows. Temp files use `.tmp` extension or live in a `pending/` subfolder until committed.
- **No Firebase sync of attachments.** On fresh reinstall + sign-in, user loses receipts even if `firebase-always-on` lands. Document as known limitation; do not silently implement half-sync.
- **Multimodal JSON robustness.** Nexus could return malformed JSON. Mitigate: strict JSON schema parse with try/catch → fall through to regex. Never crash the import flow.
- **Ambiguous VES/USD currency detection.** Mitigate: default to `SettingKey.preferredCurrency`, badge the currency field as "?", let user correct in review page.
- **Cleanup discipline regressions.** Future entity-delete code might forget `deleteByOwner`. Mitigate: add a unit test that sweeps all entity-delete services for the call, and rely on `purgeOrphans()` as safety net.

---

## Ready for Proposal

**Yes, with one sequencing condition.**

The orchestrator should tell the user:

> The exploration condenses the approved plan and confirms the generic `attachments` approach over direct columns. One dependency to decide: `attachments-and-receipt-ocr` **extends** `bolsio-ai-integration` (it adds `completeMultimodal()` on top of `NexusAiService`). Options:
> (a) Land `bolsio-ai-integration`'s foundation phase first, then start this change's tandas in order.
> (b) Start this change now but restrict to tandas 1, 2, 4–6 (regex-only, no Nexus) and stitch in tanda 3 after the AI foundation lands.
>
> No conflict with `firebase-always-on` or `fix-exchange-rate-fallback`. Known limitation: receipts are NOT Firebase-synced — call this out in the proposal and success criteria. Ready to run `/sdd-propose` once the sequencing option is chosen.
