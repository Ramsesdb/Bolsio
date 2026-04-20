# voice-input Specification

## Purpose

Defines STT capture behavior shared by the FAB quick-expense flow and the chat voice affordance. Wraps the STT engine behind `VoiceService` so on-device (`speech_to_text`) can be swapped for cloud Whisper without breaking callers.

## Requirements

### Requirement: Voice Session Capture

The system MUST expose `VoiceService.startSession(locale, maxDuration)` returning partial transcripts as a stream and a final transcript on stop. Default locale SHALL be `es-VE`; `maxDuration` default SHALL be 30s with auto-stop on 2s silence.

#### Scenario: Happy path Spanish-VE capture

- GIVEN microphone permission is granted and device is online
- WHEN the user holds the mic and says "gasté veinte dólares en almuerzo"
- THEN `partialTranscripts` emits interim strings during speech
- AND `stop()` returns the final transcript with non-empty text

#### Scenario: Auto-stop on silence

- GIVEN an active session
- WHEN the user stops speaking for more than 2 seconds
- THEN the session auto-finalizes and emits the last transcript

### Requirement: Microphone Permission Handling

The system MUST request `Permission.microphone` before first capture and MUST show a first-run explainer dialog before the OS prompt. If denied, the system SHALL surface an `openAppSettings()` CTA and MUST NOT crash.

#### Scenario: Permission granted

- GIVEN permission status is `denied` (never asked)
- WHEN the user triggers the mic
- THEN the explainer dialog appears, user accepts, OS prompt is shown, permission becomes `granted`
- AND the session starts

#### Scenario: Permission permanently denied (MIUI)

- GIVEN permission status is `permanentlyDenied`
- WHEN the user triggers the mic
- THEN a dialog with "Abrir ajustes" CTA appears that invokes `openAppSettings()`
- AND no session starts

### Requirement: STT Unavailable / Offline

The system MUST surface a user-friendly toast when the STT engine errors (no network, no model, hardware fault) and MUST NOT leak exceptions to the UI layer.

#### Scenario: Offline failure

- GIVEN device has no internet and no on-device model
- WHEN the user starts a session
- THEN `VoiceService` emits an error event "requires internet"
- AND the overlay closes with a snackbar showing the message

### Requirement: Low-Confidence Transcript

The system SHOULD return the transcript even at low STT confidence, leaving downstream flows (review sheet / chat) to let the user edit before save.

#### Scenario: Noisy input still yields editable text

- GIVEN heavy background noise
- WHEN the user stops recording
- THEN `stop()` returns whatever partial was captured (may be empty string)
- AND the caller flow is responsible for the empty-transcript edge case (see transaction-entry and ai-chat specs)
