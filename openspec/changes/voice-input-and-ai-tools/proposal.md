# Proposal: Voice Input + AI Tool-Calling

## Intent

Let the user dictate transactions and ask financial questions by voice on two surfaces that share one STT + tool-calling stack:

1. Push-to-talk on the Add-Transaction FAB → single-shot `create_transaction` tool → chip-review UX (MonAi parity).
2. Push-to-talk in `WallexChatPage` → full tool registry → conversational answers grounded in live DB data.

Today `NexusAiService` has no tool-call path and zero audio packages exist. Gateway (`AI_infi`) already forwards `tools`/`tool_choice`; only the Dart client is missing.

## Scope

### In Scope
- `VoiceService` (on-device STT via `speech_to_text`, es-VE locale, partial transcripts).
- `AIToolRegistry` + 6 concrete tools: `get_balance`, `list_transactions`, `get_stats_by_category`, `get_budgets`, `create_transaction`, `create_transfer`.
- Two `AgentProfile`s: `quickExpense` (single forced tool), `wallexAssistant` (`tool_choice: auto`, max 3 loops).
- `NexusAiService.completeWithTools` (non-streaming); keep `streamComplete` for final-text path when no tool calls.
- Chat UI: mic button + `VoiceRecordOverlay` + `_sendToAgent` refactor + approval UI for mutating tools.
- FAB UI: 4th fan action + `VoiceCaptureFlow` + `VoiceReviewSheet` (3 chips, 3s auto-confirm, undo snackbar).
- `SettingKey.aiVoiceEnabled`, `AiSettingsPage` toggle, i18n keys (`t.transaction.voice_input.*`, `t.chat.voice.*`), Android `RECORD_AUDIO` permission.

### Out of Scope
- Realtime/live streaming voice (OpenAI Realtime, Gemini Live).
- TTS output (`flutter_tts`) — deferred behind future `aiVoiceTtsEnabled`.
- Cloud Whisper STT (Option B) — kept as non-breaking upgrade path.
- iOS polish beyond what `speech_to_text` provides out of the box.
- Audio file persistence (transcript stored in `TransactionProposal.rawText`; bytes discarded).

## Approach

Approach 1 from exploration: shared infra, on-device STT MVP. `VoiceService` abstracts the STT engine so a later `WhisperVoiceService` swap is non-breaking. Tool loop is **non-streaming** (OpenAI tool-call SSE deltas are gnarly); streaming is preserved only for the final plain-text assistant reply when no `tool_calls` are returned.

**Architectural decision — `FinancialContextBuilder` stays**: YES, confirmed. Keep it as bootstrap "what exists" summary (shrink to accounts + category list, ~1k chars). Tools serve on-demand fresh reads. This halves system-prompt tokens, avoids stale data, and keeps one source of truth for reads. No reason found in exploration to revisit.

## Affected Areas

| Area | Impact | Description |
|------|--------|-------------|
| `lib/core/services/voice/voice_service.dart` | New | STT abstraction (partial transcripts, permission, timeouts). |
| `lib/core/services/ai/tools/` | New | `ai_tool.dart`, `ai_tool_registry.dart`, `financial_tools.dart`. |
| `lib/core/services/ai/agent_profiles.dart` | New | `quickExpense`, `wallexAssistant`. |
| `lib/core/services/ai/nexus_ai_service.dart` | Modified | Add `completeWithTools`; existing methods untouched. |
| `lib/core/services/ai/financial_context_builder.dart` | Modified | Shrink to ~1k-char bootstrap (accounts + categories only). |
| `lib/app/chat/wallex_chat.page.dart` | Modified | Mic button, `_sendToAgent`, tool-call approval bubble. |
| `lib/app/home/widgets/new_transaction_fl_button.dart` | Modified | 4th fan action (`Icons.mic_none_rounded`). |
| `lib/app/transactions/voice_input/` | New | `voice_capture_flow.dart`, `voice_record_overlay.dart`, `voice_review_sheet.dart`. |
| `lib/core/models/auto_import/transaction_proposal.dart` | Modified | Add `CaptureChannel.voice`. |
| `lib/core/database/services/user-setting/user_setting_service.dart` | Modified | `SettingKey.aiVoiceEnabled` (trailing enum add — no Drift migration). |
| `lib/app/settings/pages/ai/ai_settings.page.dart` | Modified | One `SwitchListTile`. |
| `android/app/src/main/AndroidManifest.xml` | Modified | `<uses-permission android:name="android.permission.RECORD_AUDIO"/>`. |
| `pubspec.yaml` | Modified | Add `speech_to_text: ^7.x`. `permission_handler` already present. |
| `i18n/*.i18n.json` | Modified | New namespaces `t.transaction.voice_input.*`, `t.chat.voice.*` → `dart run slang`. |

**Drift schema migration**: none. `SettingKey` is a Dart enum stored as key-value rows; adding a case is additive.

## Risks

| Risk | Likelihood | Mitigation |
|------|------------|------------|
| Tool-call parsing complexity in Dart | Med | Non-streaming tool loop; stream only final text. |
| Agent loop runaway | Med | Hard-cap `maxToolLoops = 3` (1 for `quickExpense`); log every iteration. |
| MIUI mic permission friction | High | First-run explainer dialog + `openAppSettings()` fallback (same pattern as camera). |
| VE-dialect STT accuracy | Med | System prompt maps VE currency slang (`verdes`→USD, `bolos`→VES). Whisper upgrade kept clean. |
| Offline STT failure | Med | `onError` → "requires internet" toast; documented as online-only MVP. |
| Provider tool-call inconsistency | Low | Pin `openai/gpt-4.1-mini` or `groq/llama-3.3-70b-versatile` for agent loops. |
| Mutating-tool safety in chat | Med | Approval bubble before `create_transaction`/`create_transfer` executes. |
| Chat `_send` refactor breakage | Low | When no `tool_calls`, route to existing `streamComplete` path byte-for-byte. |

## Rollback Plan

Additive change — fully revertible via `git revert` of the feature commits. Concretely:
1. Delete new files under `lib/core/services/voice/`, `lib/core/services/ai/tools/`, `lib/app/transactions/voice_input/`, `lib/core/services/ai/agent_profiles.dart`.
2. Revert `nexus_ai_service.dart` (drop `completeWithTools`; others untouched).
3. Revert `wallex_chat.page.dart` to pre-refactor `_send` (git revert of that commit).
4. Remove `SettingKey.aiVoiceEnabled` enum case (no migration needed — stored values are ignored if key no longer resolves).
5. `pubspec.yaml`: remove `speech_to_text`, `flutter pub get`.
6. `AndroidManifest.xml`: remove `RECORD_AUDIO`.
7. `dart run slang` after removing i18n keys.

Since no DB schema, no persisted audio, and no network contract changes exist, rollback is safe at any tanda boundary.

## Dependencies

- **`wallex-ai-integration`** — landed on main. Provides `NexusAiService`, `NexusCredentialsStore`, `FinancialContextBuilder`, `SettingKey.nexusAiEnabled` + sub-toggles, `WallexChatPage`, `AiSettingsPage`. This change extends them non-breakingly.
- **`attachments-and-receipt-ocr`** — sibling, not a dependency. Shared only via `TransactionProposal` carrier (both add a `CaptureChannel` enum case, no file conflicts). Can land in any order.
- **`speech_to_text: ^7.x`** — new pubspec dep.
- **`permission_handler: ^12.0.1`** — already present.
- Gateway (`AI_infi`) already forwards `tools`/`tool_choice` (verified `index.ts:575,621`). **No backend change required** for MVP.

## Tandas Plan

Six tandas from exploration; tandas 4 and 5 are independent surface code and can land in either order or in parallel.

1. **Tanda 1 — Voice foundation**: `speech_to_text` dep, `VoiceService`, `RECORD_AUDIO` manifest, es-VE locale, minimal `VoiceRecordOverlay` proving STT pipeline end-to-end (debug screen printing partials). No AI integration.
2. **Tanda 2 — Tool registry**: `AiTool` contract, `AIToolRegistry`, 6 concrete tools wired to existing services (`AccountService`, `TransactionService`, stats, `BudgetServive`). Pure Dart unit tests.
3. **Tanda 3 — Agent loop**: `NexusAiService.completeWithTools`, `AgentProfile` with bounded tool loop + telemetry, shrink `FinancialContextBuilder` to bootstrap-only.
4. **Tanda 4 — Chat surface** (independent of Tanda 5): mic button in `WallexChatPage`, `_sendToAgent` refactor, approval UI for mutating tools, streaming preserved for no-tool responses.
5. **Tanda 5 — FAB surface** (independent of Tanda 4): 4th fan action, `VoiceCaptureFlow`, `VoiceReviewSheet` (3 chips + 3s auto-confirm + undo snackbar), `CaptureChannel.voice`.
6. **Tanda 6 — Settings + i18n + polish**: `SettingKey.aiVoiceEnabled`, `AiSettingsPage` toggle, i18n keys + `dart run slang`, first-run permission explainer, known-limitations doc.

Tandas 1–3 are plumbing; 4–5 user-visible; 6 ties it off.

## Success Criteria

- [ ] From the FAB mic action, user says *"gasté 20 dólares en almuerzo"* → `VoiceReviewSheet` shows 3 chips (description / amount / category) pre-filled → 3s countdown auto-saves → transaction appears in the list with `CaptureChannel.voice` and `rawText` = transcript; undo snackbar visible.
- [ ] In `WallexChatPage`, user taps mic and asks *"¿cuánto gasté en comida en marzo?"* → agent runs `get_stats_by_category` tool → replies with a grounded text answer in Spanish; streaming works for the final text.
- [ ] Both surfaces share a single `VoiceService` instance and a single `AIToolRegistry` (verified by grep — no duplicated STT or tool code).
- [ ] `SettingKey.aiVoiceEnabled=0` disables the mic button on both surfaces; master `nexusAiEnabled=0` disables everything including mic.
- [ ] Mutating tools (`create_transaction`/`create_transfer`) in chat show an approval bubble before execution; never auto-commit.
- [ ] `flutter analyze` passes; existing chat streaming UX unchanged for non-tool responses.
- [ ] Permission denied → friendly dialog with `openAppSettings()` CTA; no crash on MIUI.
- [ ] Gateway unchanged; `AI_infi` continues to pass `tools`/`tool_choice` through as it does today.
