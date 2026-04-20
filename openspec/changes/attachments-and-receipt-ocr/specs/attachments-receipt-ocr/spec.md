# Attachments & Receipt OCR Specification

## Purpose

Define the required behavior for image attachments, receipt-assisted transaction capture, and custom avatar upload using a shared polymorphic attachment subsystem.

## Requirements

### Requirement: Generic Attachment Ownership

The system MUST persist attachments in a generic store keyed by `ownerType` and `ownerId`, and SHALL support `transaction` and `userProfile` owners in this change. The `userProfile` owner MUST use the singleton `ownerId = 'current'`.

#### Scenario: Persist receipt attachment for transaction flow

- GIVEN a user imports a receipt image from camera or gallery
- WHEN the image is accepted by the import flow and the transaction is saved
- THEN the system MUST save metadata and file path as an attachment owned by `transaction`
- AND the attachment MUST remain available after app restart

#### Scenario: Persist custom avatar attachment

- GIVEN a user selects a custom profile photo
- WHEN the user confirms the selection
- THEN the system MUST save metadata and file path as an attachment with `ownerType='userProfile'` and `ownerId='current'`
- AND the stored `role` MUST be `avatar`

### Requirement: Attachment Storage Format

The `localPath` column MUST store paths **relative** to `ApplicationDocumentsDirectory` so that attachments survive iOS documents-directory UUID changes. Images MUST be compressed to longest-side 1600px and JPEG quality 82 before being saved to the final attachments folder.

#### Scenario: Relative path survives iOS docs dir rotation

- GIVEN an attachment was saved with `localPath = 'attachments/transaction/<uuid>.jpg'`
- WHEN the OS assigns a new absolute documents directory on the next app launch
- THEN `AttachmentsService.resolveFile()` MUST return a valid absolute path by joining the current documents directory with `localPath`

#### Scenario: Large image is compressed before persistence

- GIVEN the user picks a 4000x3000 JPEG of 4.5 MB
- WHEN the image is saved via the attachments pipeline
- THEN the persisted file MUST have longest side 1600px and JPEG quality 82
- AND the persisted file size SHOULD be noticeably smaller than the source

### Requirement: Attachment Cleanup Safety

The system MUST delete owned attachments (DB row + local file) when the owner is deleted, and SHOULD provide orphan cleanup for crash/interruption cases.

#### Scenario: Delete transaction cascades attachments

- GIVEN a transaction with one or more rows in `attachments` where `ownerType='transaction'` and `ownerId=<id>`
- WHEN `TransactionService.deleteTransaction(<id>)` runs
- THEN all matching rows in `attachments` MUST be deleted
- AND their local files MUST be unlinked from disk

#### Scenario: Cancel in review page cleans temp file

- GIVEN the user reached `ReceiptReviewPage` with a pending attachment at a temp path
- WHEN the user taps cancel / back before saving the transaction
- THEN the temp attachment file MUST be deleted
- AND no orphan row or file MUST remain

#### Scenario: App crash mid-flow is recovered on next boot

- GIVEN the app process died after a temp file was written but before the transaction was persisted
- WHEN the app starts again and `AttachmentsService.purgeOrphans()` runs
- THEN any file under the attachments directory with no matching DB row MUST be removed
- AND any DB row with no backing file MUST be removed

### Requirement: Receipt Extraction Pipeline

The system MUST run OCR text recognition first, MAY enrich with Nexus multimodal AI when enabled, and MUST fall back to BDV regex parsing when AI output is invalid, times out, or is disabled.

#### Scenario: AI disabled or missing API key skips straight to regex

- GIVEN `receiptAiEnabled` is false OR no Nexus API key is configured
- WHEN extraction runs on OCR text containing BDV transfer data
- THEN the system MUST NOT call the Nexus multimodal endpoint
- AND the system MUST parse with BDV regex profiles
- AND the proposal MUST carry amount, date, counterparty, and `bankRef` when the regex matches

#### Scenario: AI enabled but malformed AI response

- GIVEN `receiptAiEnabled` is true and the multimodal AI returns invalid JSON
- WHEN extraction runs
- THEN the system MUST NOT crash
- AND the system MUST fall back to regex parsing over the OCR text

#### Scenario: Nexus multimodal times out at 15s

- GIVEN `receiptAiEnabled` is true and the Nexus request exceeds the 15-second timeout
- WHEN the timeout fires
- THEN the system MUST cancel the AI call
- AND the system MUST run the regex parser over the OCR text
- AND if the regex extracts an amount, the resulting proposal MUST carry `confidence = 0.7`

#### Scenario: OCR returns empty text

- GIVEN the image was readable but ML Kit produced no recognized text
- WHEN extraction finishes
- THEN the system MUST show a toast with key `error.ocr_empty`
- AND the transaction form MUST open empty with the image already attached as `pendingAttachmentPath`

#### Scenario: Image corrupt or decode fails

- GIVEN the picked file cannot be decoded as an image
- WHEN the pipeline attempts to load it
- THEN the system MUST show a toast with key `error.image_corrupt`
- AND NO file MUST be saved to the attachments directory
- AND the review / transaction form MUST NOT open

#### Scenario: No amount extractable from any path

- GIVEN neither Nexus nor regex can extract an amount from the OCR text
- WHEN extraction finishes
- THEN the system MUST show a toast with key `error.no_amount`
- AND the transaction form MUST open empty with the image already attached

### Requirement: Review Before Commit

The system MUST present an editable review step before transaction creation and SHOULD show confidence cues when extracted fields are uncertain.

#### Scenario: User edits uncertain currency

- GIVEN extraction returns ambiguous currency (neither `Bs.` nor `$` detected unambiguously)
- WHEN the review screen is shown
- THEN the currency field MUST default to `SettingKey.preferredCurrency`
- AND the field MUST be rendered with a "?" confidence badge
- AND the user MUST be able to edit the currency before save, and the saved transaction MUST use the confirmed value

#### Scenario: Account not identifiable requires user selection

- GIVEN extraction could not identify a `fromAccount` from the OCR or AI output
- WHEN the user reaches the form from review
- THEN `fromAccount` MUST be null on entry
- AND the form MUST block save until the user picks an account

#### Scenario: Duplicate bankRef warns but does not block

- GIVEN the extracted `bankRef` already exists per `pending_import_service`
- WHEN the review screen is shown
- THEN the system MUST display a non-blocking duplicate warning
- AND the user MUST still be able to confirm and save the transaction

### Requirement: FAB Entry Points

The dashboard FAB MUST provide manual transaction creation, gallery import, and camera import. When camera permission is denied, the system MUST offer a path to the OS app settings.

#### Scenario: Gallery import from FAB

- GIVEN the user is on the dashboard
- WHEN the user opens the FAB and selects gallery import
- THEN the system MUST start the receipt import flow with the gallery source

#### Scenario: Camera permission denied

- GIVEN the user selects camera import and camera permission is denied
- WHEN the system receives the denial
- THEN the system MUST show an explanatory dialog
- AND the dialog MUST offer a button that invokes `permission_handler.openAppSettings()`

### Requirement: Nexus AI Service Extension

The system SHALL extend the existing `NexusAiService` with a `completeMultimodal()` method without breaking the current text-only completion API.

#### Scenario: Existing text completion compatibility

- GIVEN callers use the current text-only `complete()` method
- WHEN `completeMultimodal()` is introduced
- THEN existing calls MUST continue to work without signature changes

### Requirement: Database Migration v22 to v23

The Drift migration from schemaVersion 22 to 23 MUST be purely additive: it MUST create the `attachments` table and the `idx_attachments_owner` index, and MUST NOT `ALTER` any pre-existing table.

#### Scenario: Migration applies cleanly on existing user data

- GIVEN a user device has a populated v22 database with existing transactions, accounts, and categories
- WHEN the app launches on a build with schemaVersion 23
- THEN the migration MUST create `attachments` and `idx_attachments_owner`
- AND all pre-existing rows in `transactions`, `accounts`, and every other table MUST be preserved exactly
- AND no data loss or corruption MUST occur

### Requirement: Custom Avatar Lifecycle

The system MUST render a user-uploaded avatar when present for `ownerType='userProfile'`, `ownerId='current'`, `role='avatar'`, and MUST fall back to the user's selected SVG preset otherwise. Replacing or removing the custom avatar MUST clean up the previous attachment row and file.

#### Scenario: Avatar fallback when no custom avatar exists

- GIVEN no attachment exists with `ownerType='userProfile'`, `ownerId='current'`, `role='avatar'`
- WHEN `UserAvatarDisplay` renders
- THEN the widget MUST render the SVG preset currently selected by the user

#### Scenario: Custom avatar replaces a previous custom avatar

- GIVEN a custom avatar attachment already exists for the user
- WHEN the user picks a new custom avatar and confirms
- THEN the previous attachment row AND its local file MUST be deleted BEFORE the new attachment row is inserted
- AND only one avatar attachment MUST exist afterwards

#### Scenario: Switching from custom back to preset SVG

- GIVEN the user has a custom avatar attachment
- WHEN the user taps an SVG preset in the edit-profile modal
- THEN the custom avatar attachment row AND file MUST be deleted
- AND `UserAvatarDisplay` MUST render the selected preset SVG

### Requirement: No Binary Sync in This Change

The system MUST NOT claim Firebase binary sync for attachments in this change.

#### Scenario: Reinstall after sign-in

- GIVEN a user had receipt or avatar attachments on a previous installation
- WHEN the app is reinstalled and the user signs in again
- THEN the system MAY restore structured transaction data
- AND attachment binaries MAY be missing and MUST be treated as a known limitation
