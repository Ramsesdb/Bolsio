# Tasks: Attachments Subsystem + Receipt OCR Import

Six tandas, each independently landable. Within each tanda: Implementation -> Tests -> Verification.

## Tanda 1: Infraestructura `attachments` genérica (DB + service, no UI)

### Implementation

- [x] 1.1 Add `attachments` table + `idx_attachments_owner` to `lib/core/database/sql/initial/tables.drift` (cols: id TEXT PK, ownerType TEXT, ownerId TEXT, localPath TEXT, mimeType TEXT, sizeBytes INT, role TEXT NULL, createdAt INT).
- [x] 1.2 Create `assets/sql/migrations/v23.sql` with additive `CREATE TABLE attachments` + `CREATE INDEX` — zero `ALTER` on existing tables.
- [x] 1.3 Bump `schemaVersion` 22 -> 23 in `lib/core/database/app_db.dart` and register the v23 migration in the migration strategy.
- [x] 1.4 Run `dart run build_runner build -d` to regenerate Drift code.
- [x] 1.5 Create `lib/core/services/attachments/attachment_model.dart` with `Attachment` class + `AttachmentOwnerType` enum (`transaction, userProfile, account, budget`).
- [x] 1.6 Create `lib/core/services/attachments/attachments_service.dart` implementing `attach`, `listByOwner`, `firstByOwner`, `deleteById`, `deleteByOwner`, `purgeOrphans`, `resolveFile` per design contract.
- [x] 1.7 Compression helper: `attach` routes images through `image` package (longest side 1600px, JPEG q82) before persisting under `<docs>/attachments/<ownerType>/<uuid>.<ext>`; store `localPath` **relative** to docs dir.
- [x] 1.8 Modify `lib/core/database/services/transaction/transaction_service.dart` — `deleteTransaction(id)` MUST call `AttachmentsService.deleteByOwner(transaction, id)` BEFORE the transaction row delete.
- [x] 1.9 Add `CaptureChannel.receiptImage` enum value in `lib/core/models/auto_import/transaction_proposal.dart`.
- [x] 1.10 Add to `pubspec.yaml`: `image_picker`, `google_mlkit_text_recognition`, `image`; **activate** the already-declared `flutter_expandable_fab` (no UI wiring yet, just keep entry).
- [x] 1.11 Android: add `<uses-permission android:name="android.permission.CAMERA" />` + non-required camera feature in `android/app/src/main/AndroidManifest.xml`.
- [ ] 1.12 iOS: add `NSCameraUsageDescription` + `NSPhotoLibraryUsageDescription` in `ios/Runner/Info.plist`. (Blocked: this repository currently has no `ios/` directory)

### Tests

- [x] 1.13 Unit: `AttachmentsService.attach -> listByOwner -> deleteById` leaves zero rows and unlinks file.
- [x] 1.14 Unit: `deleteByOwner('transaction', id)` removes every row + file for that owner and no others.
- [x] 1.15 Unit: `purgeOrphans()` with tmpdir + in-memory DB — seeds row-without-file and file-without-row; both cleaned.
- [x] 1.16 Unit: `resolveFile()` rebuilds absolute path from relative `localPath` against a mocked documents dir (iOS rotation case).
- [x] 1.17 Unit: large-image compression — 4000x3000 JPEG source -> persisted file has longest side 1600 and smaller byte size.
- [x] 1.18 Unit sweep: `TransactionService.deleteTransaction()` invokes `AttachmentsService.deleteByOwner('transaction', id)` (mock verify).
- [x] 1.19 Integration: open a v22 fixture DB, run migration, assert `attachments` + index exist and all pre-existing rows unchanged.

### Verification

- [x] 1.20 `flutter pub get && dart run build_runner build -d` finishes clean.
- [ ] 1.21 App boots on an existing v22 DB, migration applies, prior transactions intact.
- [x] 1.22 `flutter test` green for all unit + migration tests above.

## Tanda 2: OCR + extractor regex-only (functional without AI)

### Implementation

- [x] 2.1 Create `lib/core/services/receipt_ocr/ocr_service.dart` wrapping `google_mlkit_text_recognition` Latin recognizer; exposes `Future<String> recognize(File image)`.
- [x] 2.2 Create `lib/core/services/receipt_ocr/receipt_image_service.dart` — `pickAndCompress({source: camera|gallery})` using `image_picker` + compression pipeline from tanda 1, saves to a **temp** path (not the final attachments dir).
- [x] 2.3 Create `lib/core/services/receipt_ocr/receipt_extractor_service.dart` with **regex-only** path: wraps OCR text in a synthetic `RawCaptureEvent` and calls `BdvNotifProfile.tryParse(...)` to produce a `TransactionProposal` carrying `CaptureChannel.receiptImage`.
- [x] 2.4 Error paths: empty OCR -> `ExtractionResult.empty`; no amount extractable -> `ExtractionResult.noAmount` (no crash).
- [x] 2.5 Ambiguous currency heuristic: when neither `Bs.` nor `$` / `USD` unambiguous -> currency = null, flagged for review badge.

### Tests

- [x] 2.6 Fixture: real BDV Pago Movil screenshot OCR text -> extractor returns proposal with correct `amount`, `bankRef`, `date`, `type=E`, `counterpartyName`.
- [x] 2.7 Fixture: empty OCR string -> returns `empty` result, no exception.
- [x] 2.8 Fixture: OCR text without an amount anywhere -> returns `noAmount` result.
- [x] 2.9 Unit: `receipt_image_service` compresses a 4K source to <= 1600px longest side and JPEG q82.

### Verification

- [x] 2.10 Run `flutter test` — all fixture tests green.
- [ ] 2.11 Manual: on device, pick a real BDV screenshot via a temporary dev entry-point; log proves extractor returns the expected proposal using only regex (no network calls).

## Tanda 3: Nexus multimodal (AI layer on top of tanda 2)

### Implementation

- [x] 3.1 Extend `lib/core/services/ai/nexus_ai_service.dart` with `completeMultimodal({systemPrompt, userPrompt, imageBase64, temperature=0.1})` — existing text `complete()` signature unchanged.
- [x] 3.2 Implement multimodal HTTP payload exactly per `design.md` wire contract: `messages[1].content` as array of `{type:'text'}` + `{type:'image_url', image_url:{url: 'data:image/jpeg;base64,...'}}`.
- [x] 3.3 Add `SettingKey.receiptAiEnabled` (default `true`) and wire a toggle in `lib/app/settings/pages/ai/ai_settings.page.dart` under the existing AI section, gated by the master Nexus toggle.
- [x] 3.4 Integrate Nexus call in `receipt_extractor_service.dart` **before** the regex fallback: 15s timeout, strict JSON parse of the expected schema (amount, currencyCode, date, type, counterpartyName, bankRef, bankName, confidence).
- [x] 3.5 Failure handling: HTTP non-2xx, timeout, JSON parse error, or schema-validation error -> log + fall through to regex path. NEVER bubble exceptions to UI.
- [x] 3.6 On regex-after-AI-timeout success, stamp `proposal.confidence = 0.7`.
- [x] 3.7 Link a comment in `receipt_extractor_service.dart` to `openspec/changes/attachments-and-receipt-ocr/design.md#nexusaiservicecompletemultimodal--wire-contract` for the payload contract.

### Tests

- [x] 3.8 Unit: stub `completeMultimodal` returning valid JSON -> extractor returns proposal with AI confidence; no regex call executed.
- [x] 3.9 Unit: stub returning prose / truncated JSON -> regex fallback kicks in, no exception.
- [x] 3.10 Unit: stub delaying > 15s -> timeout path fires, regex runs, resulting proposal (if amount found) carries `confidence = 0.7`.
- [x] 3.11 Unit: `receiptAiEnabled = false` -> multimodal NEVER called (verify via mock call count == 0), extractor uses regex directly.
- [x] 3.12 Unit: capture outgoing HTTP body and assert `messages[1].content` has both `text` and `image_url` parts and the `data:image/jpeg;base64,` prefix.

### Verification

- [ ] 3.13 With `receiptAiEnabled = true` + valid Nexus key: invoice (non-BDV) image where regex fails -> Nexus returns structured JSON and proposal is populated.
- [ ] 3.14 Airplane mode: same flow falls back to regex without crash.
- [x] 3.15 `flutter test` green.

## Tanda 4: UI review + prefill form

### Implementation

- [x] 4.1 Create `lib/app/transactions/receipt_import/receipt_review_page.dart` — image preview + editable fields (amount, currency, date, type, counterparty, reference); ambiguous-currency field rendered with a **"?" confidence badge**.
- [x] 4.2 Create `lib/app/transactions/receipt_import/receipt_import_flow.dart` — static entry `ReceiptImportFlow.start(context, source)`: pick -> loader with 3 steps (`processing_ocr`, `processing_ai`, `processing_done`) -> push review page.
- [x] 4.3 Modify `lib/app/transactions/form/transaction_form.page.dart` — add `TransactionFormPage.fromReceipt({prefill, pendingAttachmentPath})` constructor; holds `pendingAttachmentPath` in state.
- [x] 4.4 On successful `_submit()` in the receipt branch, call `AttachmentsService.attach(ownerType: transaction, ownerId: newTxId, sourceFile: File(pendingAttachmentPath), role: 'receipt')` AFTER the transaction row is written.
- [x] 4.5 If user cancels/backs out of review: delete the temp attachment file; no orphan left.
- [x] 4.6 Create `lib/app/common/widgets/attachment_viewer.dart` — reusable fullscreen pinch-zoom viewer with an "eliminar" action that calls `AttachmentsService.deleteById`.
- [x] 4.7 Add i18n keys in `i18n/en.i18n.json` and `i18n/es.i18n.json`:
  - `t.transaction.receipt_import.entry_gallery/entry_camera/processing_ocr/processing_ai/processing_done/review_title/review_subtitle/review_cta_continue/review_cta_retry`
  - `t.transaction.receipt_import.error.{ocr_empty|ai_failed|image_corrupt|no_amount|ambiguous_currency}`
  - `t.transaction.receipt_import.field.{amount|currency|date|counterparty|reference}`
  - `t.attachments.{view|remove|replace|upload_from_gallery|upload_from_camera|empty_state}`
  - `t.transaction.{receipt_attached|view_receipt}`
- [x] 4.8 Run `dart run slang` to regenerate i18n Dart bindings.

### Tests

- [x] 4.9 Widget: review page renders ambiguous-currency "?" badge when extractor returned null currency; editing the field saves the edited value.
- [x] 4.10 Widget: review page cancel removes the temp file (fake FS verify).
- [x] 4.11 Widget: account not identifiable -> form opens with `fromAccount=null` and save button disabled until an account is picked.
- [x] 4.12 Widget: user-edited values on review override extractor output in the saved transaction.
- [x] 4.13 Integration: end-to-end pick (mocked) -> review -> save -> assert `transactions` row + `attachments` row both exist and file present on disk.

### Verification

- [ ] 4.14 Manual: gallery pick -> review -> form pre-filled -> save; dashboard shows the new transaction.
- [ ] 4.15 Cancel in review -> no temp file left (checked with `purgeOrphans()` reporting zero).
- [ ] 4.16 `flutter test` green.

## Tanda 5: FAB integracion + detalle transaccion + polish

### Implementation

- [x] 5.1 Migrate `lib/app/home/widgets/new_transaction_fl_button.dart` from the single FAB to `ExpandableFab` (from `flutter_expandable_fab`) with 3 children: "Nueva transaccion", "Desde comprobante (galeria)", "Desde comprobante (camara)". **Preserve** the existing `AnimatedFloatingButtonBasedOnScroll` wrapper (hide-on-scroll).
- [x] 5.2 Camera denied path: on permission denial, show explanatory dialog with a button that calls `permission_handler.openAppSettings()`.
- [x] 5.3 Transaction detail page: add a "Ver comprobante" chip visible only when an attachment with `role='receipt'` exists for that transaction; tap opens `AttachmentViewer`.
- [x] 5.4 Wire dedupe: in receipt import flow, after extraction, check `pending_import_service` for an existing record by `bankRef`; if hit, display a non-blocking "duplicate" warning on the review page (does not disable save).
- [x] 5.5 `purgeOrphans()` boot hook: call it in **debug-only** app init path (no release cost); also expose "Limpieza de adjuntos huerfanos" action under Settings -> Storage.
- [x] 5.6 Assets: receipt chip icon + any minor polish (copy, spacing) using existing design tokens.

### Tests

- [ ] 5.7 Widget: FAB expands into 3 children and each routes to the expected action.
- [ ] 5.8 Widget: transaction detail renders "Ver comprobante" chip only when attachment exists.
- [ ] 5.9 Unit: dedupe warning appears when `pending_import_service` already knows the `bankRef`; flag does NOT disable save.
- [ ] 5.10 Unit: Settings "Limpieza de adjuntos huerfanos" action invokes `purgeOrphans()` and reports the count removed.

### Verification

- [ ] 5.11 Manual on Xiaomi device: (a) FAB -> camera capture real photo, (b) blurry image path shows `error.no_amount` toast cleanly, (c) airplane mode falls back to regex, (d) migration v22 -> v23 runs cleanly against a populated fixture DB copy.
- [ ] 5.12 Manual: delete a transaction with a receipt -> chip gone, file under `attachments/transaction/` gone, row gone.
- [ ] 5.13 `flutter test` green.

## Tanda 6: Avatar custom de usuario (reuse del subsistema)

### Implementation

- [x] 6.1 Locate the real edit-profile modal path (`lib/app/settings/widgets/edit_profile_modal.dart` or closest match) and extend it: add a "Subir foto" button **above** the SVG preset grid.
- [x] 6.2 "Subir foto" -> `ReceiptImageService.pickAndCompress()` -> if prior avatar exists (`firstByOwner(userProfile, 'current', role: 'avatar')`), `deleteById(old.id)` FIRST, THEN `AttachmentsService.attach(userProfile, 'current', role: 'avatar', file)`.
- [x] 6.3 Create `lib/app/common/widgets/user_avatar_display.dart` — renders custom avatar when `firstByOwner(userProfile, 'current', role:'avatar')` is non-null; otherwise falls back to the user's selected SVG preset.
- [x] 6.4 Replace every existing avatar render call-site with `UserAvatarDisplay` (dashboard header, edit-profile preview, any drawer header).
- [x] 6.5 Add "Usar avatar predeterminado" action in the edit-profile modal -> deletes the custom avatar attachment (row + file); UI falls back to SVG preset.
- [x] 6.6 Add i18n keys `t.profile.upload_custom_avatar` + `t.profile.use_preset_avatar`; run `dart run slang`.

### Tests

- [ ] 6.7 Integration: upload avatar A -> upload avatar B -> assert exactly one row + one file remain (B); A's row + file deleted.
- [ ] 6.8 Widget: `UserAvatarDisplay` renders custom image when attachment exists; renders SVG preset when absent.
- [ ] 6.9 Integration: "Usar avatar predeterminado" deletes the attachment and UserAvatarDisplay switches back to SVG.
- [ ] 6.10 Regression: unit sweep ensures no orphan file is left after any avatar replace path (same assertion style as tanda 1).

### Verification

- [ ] 6.11 Manual: Editar perfil -> Subir foto (galeria) -> avatar custom aparece en el header del dashboard y sobrevive a cerrar/reabrir la app.
- [ ] 6.12 Manual: Editar perfil -> seleccionar SVG preset -> custom desaparece, vuelve el SVG.
- [ ] 6.13 Manual: Subir foto (camara) en Xiaomi -> avatar aparece igual que via galeria.
- [ ] 6.14 `flutter test` green.

## Implementation Order

Tanda 1 (infra, no UI) must land first — everything else depends on the `AttachmentsService` primitive and the v23 migration. Tanda 2 delivers the regex-only OCR MVP that's fully functional without AI. Tanda 3 adds Nexus on top behind a setting. Tanda 4 brings the user-facing review + prefill. Tanda 5 wires the FAB and adds polish. Tanda 6 reuses the primitive for avatars. Each tanda is individually shippable; no cross-tanda collapse.
