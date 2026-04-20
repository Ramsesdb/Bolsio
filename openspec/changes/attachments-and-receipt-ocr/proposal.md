# Proposal: Attachments subsystem + Receipt OCR import

## Intent

Eliminate manual transcription of BDV Pago Móvil / transfer screenshots and invoice photos. From the dashboard FAB, a user picks (camera/gallery) a receipt image, gets fields auto-extracted (OCR + Nexus multimodal + regex fallback), reviews, and saves a transaction with the image permanently attached. The same attachments primitive unlocks custom user avatars.

## Scope

### In Scope
- Generic polymorphic `attachments` table + `AttachmentsService` (file I/O, CRUD, orphan purge).
- Drift migration v22 → v23 (additive: new table + index only).
- Receipt OCR pipeline: `google_mlkit_text_recognition` + `image` compression + `BdvNotifProfile` regex reuse.
- `NexusAiService.completeMultimodal()` extension (text-only API unchanged).
- Receipt import flow from FAB (`ExpandableFab` with manual / gallery / camera) + review page + `TransactionFormPage.fromReceipt(...)`.
- Reusable `AttachmentViewer` (pinch-zoom) + receipt chip on transaction detail.
- Custom user avatar upload (tanda 6) reusing the same subsystem.
- `receiptAiEnabled` sub-toggle + i18n keys under `t.transaction.receipt_import.*`, `t.attachments.*`, `t.profile.*`.

### Out of Scope
- Firebase sync of attachment binaries (receipts lost on reinstall).
- PDF attachments, multi-page OCR, non-Latin script OCR.
- Attachments for budgets / goals / accounts (enum is ready; UIs deferred).

## Approach

Implement in 6 tandas per approved plan: (1) infra, (2) regex-only extractor, (3) Nexus multimodal, (4) UI MVP, (5) FAB + detail polish + dedupe, (6) avatar. Tandas 1–2 and 4–6 are independent of AI; tanda 3 depends on the existing `NexusAiService`.

## Affected Areas

| Area | Impact | Description |
|------|--------|-------------|
| `lib/core/database/sql/initial/tables.drift`, `assets/sql/migrations/v23.sql`, `app_db.dart` | Modified | `attachments` table + index; schemaVersion 22→23 |
| `lib/core/services/attachments/` | New | Model + service |
| `lib/core/services/receipt_ocr/` | New | Image, OCR, extractor services |
| `lib/core/services/ai/nexus_ai_service.dart` | Modified | `completeMultimodal()` added |
| `lib/app/transactions/receipt_import/`, `form/transaction_form.page.dart` | New / Modified | Flow, review page, `.fromReceipt` ctor |
| `lib/app/home/widgets/new_transaction_fl_button.dart`, edit-profile modal | Modified | `ExpandableFab`; avatar upload |
| `android/.../AndroidManifest.xml`, `ios/.../Info.plist`, `pubspec.yaml` | Modified | Camera perms + 3 new packages |

## Risks

| Risk | Likelihood | Mitigation |
|------|------------|------------|
| Attachments not Firebase-synced | High | Document as known limitation; scope explicit |
| ML Kit +15–25 MB APK | High | Acceptable for personal app; documented |
| Polymorphic FK-less ownership → orphans | Med | `deleteByOwner` at each delete site + `purgeOrphans()` safety net + unit test sweep |
| MIUI camera permission revocation | Med | `permission_handler.openAppSettings()` fallback + explanatory dialog |
| Drift v22→v23 on live data | Low | Purely additive — no `ALTER` on existing tables |
| Nexus malformed JSON | Med | Strict parse → fall through to regex, never crash flow |

## Rollback Plan

Migration is additive: rollback = drop `attachments` table, revert UI patches, delete `receipts/` directory. No existing transaction data is mutated. Each tanda is independently revertible via git.

## Dependencies

Depends on `NexusAiService` (already implemented on `main`, tracked under inactive `wallex-ai-integration` change — see `lib/core/services/ai/nexus_ai_service.dart`, `nexus_credentials_store.dart`, recent commits `541c50e`, `ab38970`). This proposal EXTENDS it with a new `completeMultimodal()` method; existing text-only `complete()` stays backward-compatible. New pubspec entries: `image_picker`, `google_mlkit_text_recognition`, `image`.

## Success Criteria

- [ ] End-to-end: FAB → pick image → review → saved transaction with attached receipt visible on detail page.
- [ ] Custom avatar upload works; appears in home header and settings.
- [ ] All 6 tandas' verification checks from the approved plan pass.
- [ ] `flutter test` green; migration applies cleanly to a v22 DB copy.
- [ ] Deleting a transaction removes its attachment file and row.
