# transaction-entry Specification (new capability for this change)

## Purpose

Adds a voice capture channel to the Add-Transaction flow: FAB 4th action → `VoiceCaptureFlow` → `quickExpense` agent → `VoiceReviewSheet` (3 chips + 3s auto-confirm + undo). Reuses the `TransactionProposal` carrier shared with the receipt-OCR path.

## Requirements

### Requirement: Voice Capture Channel

The system MUST add `CaptureChannel.voice` to `TransactionProposal.channel`. Transactions persisted via this path MUST have `channel = voice` and `rawText = final transcript`. No audio bytes SHALL be persisted.

#### Scenario: Voice transaction saved

- GIVEN the user completes a voice capture "gasté 20 dólares en almuerzo"
- WHEN the review sheet auto-confirms
- THEN a `TransactionInDB` is inserted with `channel = voice` and `rawText` equal to the transcript
- AND no file exists in attachments storage for this transaction

### Requirement: FAB Fourth Action

The system MUST add a 4th fan-overlay action (mic icon, label `t.transaction.voice_input.entry`) to `NewTransactionButton`. Tapping it MUST start `VoiceCaptureFlow.start(ctx)` only when `SettingKey.aiVoiceEnabled == '1'` and `nexusAiEnabled == '1'`.

#### Scenario: Disabled voice hides FAB action

- GIVEN `aiVoiceEnabled = '0'`
- WHEN the FAB expands
- THEN the mic action is not rendered and the fan shows only 3 actions

### Requirement: Voice Review Sheet (3 chips + auto-confirm)

The system MUST render `VoiceReviewSheet` with three editable chips (description, amount, category) pre-filled from the `quickExpense` tool-call arguments, a 3-second auto-confirm countdown, and an undo snackbar visible for at least 5 seconds after insert.

#### Scenario: Auto-confirm happy path

- GIVEN the review sheet opens with all 3 chips populated and confidence is high
- WHEN no chip is tapped for 3 seconds
- THEN the transaction is inserted
- AND an undo snackbar appears with a working "Deshacer" action that deletes the inserted row

#### Scenario: User edits before confirm

- GIVEN the review sheet is counting down
- WHEN the user taps a chip
- THEN the countdown pauses
- AND the edited value is used on subsequent confirm

#### Scenario: Low-confidence / missing field blocks auto-confirm

- GIVEN the tool returned arguments missing `category` or with empty `amount`
- WHEN the sheet opens
- THEN the missing chip is highlighted and the auto-confirm countdown does NOT start
- AND the user MUST tap to fill before the "Confirmar" button enables

### Requirement: Multi-Currency Handling in Voice Path

The system MUST respect the user's `SettingKey.preferredCurrency` as default when the transcript omits currency. For VES amounts in the 3-chip sheet the system SHALL NOT apply FX conversion; escalating to full FX editing MUST open `TransactionFormPage.fromVoice(...)`.

#### Scenario: USD omitted → falls back to preferred currency

- GIVEN preferredCurrency is `USD` and transcript is "gasté 20 en almuerzo"
- WHEN the tool returns `currency: 'USD'` (inferred)
- THEN the amount chip shows `$20.00`
- AND the inserted transaction has currency USD

#### Scenario: Escalate to full form for FX edits

- GIVEN the user long-taps the amount chip
- WHEN the escalation action is chosen
- THEN `TransactionFormPage.fromVoice(proposal)` opens with the prefill intact

### Requirement: Empty Transcript Handling

If the final transcript is empty or only whitespace, the system MUST NOT call the agent and SHALL show a retry toast.

#### Scenario: Empty transcript

- GIVEN `VoiceService.stop()` returns ""
- WHEN `VoiceCaptureFlow` receives it
- THEN a toast `t.transaction.voice_input.empty_transcript` appears
- AND no network call is made
