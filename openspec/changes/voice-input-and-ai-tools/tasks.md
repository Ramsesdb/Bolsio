# Tasks: Voice Input + AI Tool-Calling

## Tanda 1 — Voice Service Foundation

- [x] 1.1 Add `speech_to_text: ^7.x` to `pubspec.yaml`; run `flutter pub get`.
- [x] 1.2 Add `<uses-permission android:name="android.permission.RECORD_AUDIO"/>` to `android/app/src/main/AndroidManifest.xml`.
- [x] 1.3 Create `lib/core/services/voice/voice_service.dart` — abstract interface: `startSession(locale)`, `Stream<String> partials`, `Future<String?> stop()`, `Future<PermissionStatus> ensurePermission()`. Covers voice-input §1-3.
- [x] 1.4 Create `lib/core/services/voice/voice_service_speech_to_text.dart` — `speech_to_text` impl with es-VE locale, 2s VAD, singleton `VoiceService.instance`, `onError` → "requires internet" signal. Covers voice-input §4-6.
- [x] 1.5 Create `lib/core/services/voice/voice_service_fake.dart` — test fake emitting canned partials + final.
- [x] 1.6 MIUI permission explainer: dialog helper in same folder with `openAppSettings()` CTA on denial. Covers settings §permission-explainer.
- [x] 1.7 Run `flutter analyze`.

## Tanda 2 — AI Tool Registry & Tools

- [x] 2.1 Create `lib/core/services/ai/tools/ai_tool.dart` — `AiTool` contract + `sealed AiToolResult` (ok / proposal / error). Covers ai-tools §1.
- [x] 2.2 Create `lib/core/services/ai/tools/ai_tool_registry.dart` — register, dispatch, `toOpenAiTools()` JSON serializer. Covers ai-tools §2.
- [x] 2.3 Create `impl/get_balance_tool.dart` wrapping `AccountService.getAccountMoney`. Covers ai-tools §3.1.
- [x] 2.4 Create `impl/list_transactions_tool.dart` wrapping `TransactionService.getTransactions` with date/category filters. Covers ai-tools §3.2.
- [x] 2.5 Create `impl/get_stats_by_category_tool.dart` wrapping stats service. Covers ai-tools §3.3.
- [x] 2.6 Create `impl/get_budgets_tool.dart` wrapping `BudgetServive`. Covers ai-tools §3.4.
- [x] 2.7 Create `impl/create_transaction_tool.dart` with `execMode` flag: `propose` → `TransactionProposal`; `commit` → `insertTransaction`; `isMutating = true`. Covers ai-tools §3.5.
- [x] 2.8 Create `impl/create_transfer_tool.dart` — two-leg transfer, commit-only. Covers ai-tools §3.6.
- [x] 2.9 Add `CaptureChannel.voice` to `lib/core/models/auto_import/transaction_proposal.dart`.
- [x] 2.10 Run `flutter analyze`.

## Tanda 3 — Tool Loop in NexusAiService

- [x] 3.1 Add `completeWithTools({messages, tools, toolChoice, model, temperature})` to `lib/core/services/ai/nexus_ai_service.dart` — non-streaming POST, returns `{content, toolCalls[]}`, validates tool-call JSON, surfaces malformed-args errors. Covers ai-chat §tool-loop-transport.
- [x] 3.2 Shrink `lib/core/services/ai/financial_context_builder.dart` to ~1k chars (accounts + category list only). Covers ai-chat §context-bootstrap.
- [x] 3.3 Create `lib/core/services/ai/agents/agent_profile.dart` — immutable record + `requiresApproval(toolName)`. Covers ai-chat §agent-profile.
- [x] 3.4 Create `lib/core/services/ai/agents/quick_expense_agent.dart` — forced `create_transaction`, `maxToolLoops=1`, `run(transcript) → TransactionProposal`.
- [x] 3.5 Create `lib/core/services/ai/agents/bolsio_ai_agent.dart` — `tool_choice:auto`, `maxToolLoops=3`, `Stream<AgentEvent>` (toolCall / approval / finalText), streaming fallback when `toolCalls.isEmpty` on first iter. Covers ai-chat §loop-cap + §streaming-fallback.
- [x] 3.6 Reuse `SettingKey.nexusAiModel` for pin — no new key. Default `openai/gpt-4.1-mini`.
- [x] 3.7 Run `flutter analyze`.

## Tanda 4 — AI Chat Voice Integration (independent of Tanda 5)

- [x] 4.1 Add mic button to `lib/app/chat/bolsio_chat.page.dart` input row; hidden when `aiVoiceEnabled=0`. Covers ai-chat §mic-ui.
- [x] 4.2 Refactor `_send` → `_sendToAgent(bolsioAiAgent)` — route tool events through new handler; when no `tool_calls`, delegate to existing `streamComplete` byte-for-byte. Covers ai-chat §streaming-fallback.
- [x] 4.3 Create approval bubble widget inline in chat page — shown when `requiresApproval(toolName)` returns true, with Approve / Reject buttons feeding back into agent loop. Covers ai-chat §approval-ui.
- [x] 4.4 Wire `VoiceRecordOverlay` from Tanda 1 into mic tap → transcribe → inject as user message.
- [x] 4.5 Run `flutter analyze`.

## Tanda 5 — FAB Quick-Expense Voice (independent of Tanda 4)

- [x] 5.1 Add 4th fan action with `Icons.mic_none_rounded` to `lib/app/home/widgets/new_transaction_fl_button.dart`. Covers transaction-entry §fab-action.
- [x] 5.2 Create `lib/app/transactions/voice_input/voice_capture_flow.dart` — `static Future<void> start(ctx)` mirroring `ReceiptImportFlow.start`.
- [x] 5.3 Create `lib/app/transactions/voice_input/voice_record_overlay.dart` — bottom sheet with waveform bars, partial transcript, cancel button, auto-stop VAD. Reusable by chat. Covers transaction-entry §record-overlay.
- [x] 5.4 Create `lib/app/transactions/voice_input/voice_review_sheet.dart` — 3 editable chips (description / amount / category), 3s auto-confirm countdown, undo snackbar. Covers transaction-entry §review-chips.
- [x] 5.5 Add `TransactionFormPage.fromVoice(TransactionProposal proposal)` constructor mirroring existing `.fromReceipt(...)` — escalation path from review sheet. Covers transaction-entry §escalation.
- [x] 5.6 Wire flow to `quickExpenseAgent.run(transcript)` → `VoiceReviewSheet` → `TransactionService.insertTransaction` with `CaptureChannel.voice` + `rawText = transcript`.
- [x] 5.7 Run `flutter analyze`.

## Tanda 6 — Settings, i18n, Polish (expanded scope: also folds in chat perf fixes + polish flagged in Tandas 4-5)

- [x] 6.1 Append `SettingKey.aiVoiceEnabled` trailing case in `lib/core/database/services/user-setting/user_setting_service.dart` — no Drift migration. Covers settings §toggle-key.
- [x] 6.2 Add `SwitchListTile` in `lib/app/settings/pages/ai/ai_settings.page.dart` gated on `_aiEnabled`; default `1` when `nexusAiEnabled=1`. Covers settings §ui.
- [x] 6.3 Add i18n keys under `BOLSIO-AI` group in `lib/i18n/json/es.json` + `lib/i18n/json/en.json`. Generated as `t.bolsio_ai.*` (voice_* for capture UI, chat_* for chat UI + approval sheet, voice_settings_* for settings toggle, voice_permission_* for explainer/denial). Project uses a single `BOLSIO-AI` group (not `transaction.voice_input` / `chat.voice`) to colocate all voice + chat + approval strings for the agent feature.
- [x] 6.4 Ran `dart run slang` — translations regenerated under `lib/i18n/generated/` (0.3s).
- [x] 6.5 Permission-denied snackbar with "Abrir ajustes" action added to both voice entry points (FAB via `VoiceCaptureFlow.start`, chat via `_onMicTap`). First-run explainer was already in Tanda 1; Tanda 6 only added the denial-outcome snackbar.
- [x] 6.6 Empty-transcript snackbar + STT-unavailable / offline error messages routed in `voice_record_overlay.dart::_mapErrorMessage` (keyword-heuristic on engine error text). `loopCapReached` fallback message already landed in Tanda 4; Tanda 6 swapped it to the i18n key `t.bolsio_ai.chat_error_loop_cap`.
- [x] 6.7 Final `flutter analyze` pass — **No issues found** (29.3s). Clean.

### Tanda 6 Expanded Scope (folded-in items)

- [x] Perf Fix 1 — Localize `appStateSettings[...]` reads in `bolsio_chat.page.dart::build` into hoisted locals (`nexusAiEnabled`, `aiVoiceEnabled`, `voiceAffordance`, `avatarId`). Boot-state branch now early-returns with its own Scaffold instead of a ternary inside the main body.
- [x] Perf Fix 2 — Added dedicated `FocusNode _inputFocus` for the chat TextField; initialized implicitly on field, disposed in `dispose`. No focus listeners → no setState cascades on keyboard focus.
- [x] Perf Fix 3 — Wrapped the assistant message `MarkdownBody` in a `RepaintBoundary`. User bubbles (plain `Text`) remain unwrapped because they are cheap.
- [x] Polish 11 — Icon confirmed `Icons.mic_rounded` (filled) across overlay + review sheet + FAB + chat. Rationale documented in Tanda 5 notes — filled mic reads better at small FAB scale.
- [x] Polish 12 — `showMicPermissionDeniedSnackbar(context)` helper added in `voice_permission_dialog.dart`; wired into both voice entry points after `ensureMicPermissionWithExplainer` returns `denied`.
- [x] Approval sheet — account/category IDs now resolved to human names in `bolsio_chat.page.dart::_resolveToolArgLabels` via `AccountService.getAccountById` + `CategoryService.getCategoryById` before the sheet renders. Synthetic `__accountLabel` / `__categoryLabel` / `__fromAccountLabel` / `__toAccountLabel` keys are injected; the sheet prefers them over raw IDs. Filter skips `__`-prefixed keys in the generic-tool fallback render.
- [x] Voice feature gate — `aiVoiceEnabled` now joins `nexusAiEnabled` in the FAB + chat-mic gates. Both gates use `(nexusAiEnabled == '1') && (aiVoiceEnabled != '0')` so the sub-toggle defaults to ON when null (matches spec: default `'1'` when `nexusAiEnabled='1'`).
