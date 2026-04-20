# Design: Voice Input + AI Tool-Calling

## Technical Approach

Extend `NexusAiService` non-breakingly with a `completeWithTools` method, add a `VoiceService` STT abstraction, and introduce an `AIToolRegistry` + `AgentProfile` layer that powers two surfaces from shared plumbing: (1) FAB voice capture with forced `create_transaction` → chip-review sheet, (2) chat voice with full tool registry + approval UI for mutations. The agent loop is non-streaming; streaming is preserved only for final plain-text replies when no tool_calls are returned (chat fallback).

## Architecture Decisions

| Decision | Choice | Alternatives | Rationale |
|---|---|---|---|
| STT engine | `speech_to_text: ^7.x` on-device (Google/MS) behind `VoiceService` interface | Cloud Whisper via new `/v1/audio/transcriptions`; Gemini audio-in; Vosk offline | Zero backend work, free, partial transcripts for UX. Interface keeps Whisper as clean future swap. |
| Tool-loop transport | Non-streaming JSON for tool phase; `streamComplete` only for final text | Parse tool_call SSE deltas in `streamComplete` | SSE tool-call deltas are fragmented; non-streaming is simpler and matches most OpenAI tool apps. |
| Context strategy | Keep `FinancialContextBuilder` shrunk (~1k chars: accounts + categories) + tools for fresh reads | Delete builder; pure tools | Halves system-prompt tokens, avoids staleness, bootstraps model with "what exists". |
| Scoped tool exec | `CreateTransactionTool` emits a `TransactionProposal` (no DB write) in `quickExpense`; writes in `wallexAssistant` after approval | Two separate tool classes | Single tool shape, `execMode` flag toggles commit; less surface. |
| Model pinning | Default `openai/gpt-4.1-mini`; allow `groq/llama-3.3-70b-versatile` fallback via existing `SettingKey.nexusAiModel` | Auto-select | Tool-call reliability varies by provider; user-level pin already exists. |
| Mutating-tool safety | Chat agent requires explicit user tap on approval bubble before `CreateTransactionTool`/`CreateTransferTool` executes | Auto-commit with undo | "Undo" for financial writes is risky; pre-approval matches UX of high-impact actions. |
| Agent loop cap | `maxToolLoops = 3` for `wallexAssistant`, `1` for `quickExpense` | Unbounded | Prevents runaway cost/latency; 3 covers nearly all realistic multi-tool questions. |

## Data Flow

```
FAB mic → VoiceCaptureFlow → VoiceService.startSession(es-VE)
   │        partials stream                    │
   │        ↓                                  │
   │   VoiceRecordOverlay (live transcript)    │
   │        final text ──────────────┐         │
   │                                 ▼         │
   │                 quickExpenseAgent.run(text)
   │                                 │
   │                                 ▼
   │      NexusAiService.completeWithTools (forced create_transaction)
   │                                 │
   │                     tool_call → CreateTransactionTool.execute(execMode=propose)
   │                                 │
   │                                 ▼
   │                        TransactionProposal
   │                                 │
   │                                 ▼
   │                   VoiceReviewSheet (3 chips + 3s countdown)
   │                                 │
   └─── user confirm / auto ─────────▶ TransactionService.insertTransaction
                                              │
                                              ▼
                                       Undo snackbar

Chat mic → VoiceService → text → wallexChatPage._sendToAgent
                                              │
                  ┌───────────────────────────┘
                  ▼
         AgentLoop (maxLoops=3):
           completeWithTools(messages + registry.toolsJson)
             ├─ has tool_calls? → for each: approval? → tool.execute → append tool msg → loop
             └─ no tool_calls?  → streamComplete(messages) for final text → UI stream
```

## File Changes

| File | Action | Description |
|------|--------|-------------|
| `pubspec.yaml` | Modify | Add `speech_to_text: ^7.x`. |
| `android/app/src/main/AndroidManifest.xml` | Modify | Add `RECORD_AUDIO` permission. |
| `lib/core/services/voice/voice_service.dart` | Create | Abstract interface: `startSession`, `partials` stream, `stop`, permission helpers. |
| `lib/core/services/voice/voice_service_speech_to_text.dart` | Create | `speech_to_text`-backed impl; singleton `VoiceService.instance`. |
| `lib/core/services/ai/tools/ai_tool.dart` | Create | `AiTool` contract (name, description, paramsSchema, execute). |
| `lib/core/services/ai/tools/ai_tool_registry.dart` | Create | Register/lookup/dispatch + `toOpenAiTools()` serializer. |
| `lib/core/services/ai/tools/impl/get_balance_tool.dart` | Create | Wraps `AccountService.getAccountMoney`. |
| `lib/core/services/ai/tools/impl/list_transactions_tool.dart` | Create | Wraps `TransactionService.getTransactions`. |
| `lib/core/services/ai/tools/impl/get_stats_by_category_tool.dart` | Create | Wraps stats service. |
| `lib/core/services/ai/tools/impl/get_budgets_tool.dart` | Create | Wraps `BudgetServive`. |
| `lib/core/services/ai/tools/impl/create_transaction_tool.dart` | Create | `execMode` flag: `propose` → `TransactionProposal`; `commit` → `insertTransaction`. |
| `lib/core/services/ai/tools/impl/create_transfer_tool.dart` | Create | Two-leg transfer; commit-only with approval. |
| `lib/core/services/ai/agents/agent_profile.dart` | Create | Immutable record: `name, systemPrompt, tools, temperature, maxToolLoops, toolChoice, requiresApproval(toolName)`. |
| `lib/core/services/ai/agents/quick_expense_agent.dart` | Create | Profile + `run(transcript) → TransactionProposal` runner, loops=1. |
| `lib/core/services/ai/agents/wallex_ai_agent.dart` | Create | Profile + `run(messages) → Stream<AgentEvent>` runner with tool/approval/final-text events. |
| `lib/core/services/ai/nexus_ai_service.dart` | Modify | Add `completeWithTools({messages, tools, toolChoice, model, temperature}) → {content, toolCalls[]}`. |
| `lib/core/services/ai/financial_context_builder.dart` | Modify | Shrink to accounts + category list (~1k chars). |
| `lib/core/models/auto_import/transaction_proposal.dart` | Modify | Add `CaptureChannel.voice`. |
| `lib/core/database/services/user-setting/user_setting_service.dart` | Modify | Trailing `SettingKey.aiVoiceEnabled` case. |
| `lib/app/settings/pages/ai/ai_settings.page.dart` | Modify | New `SwitchListTile` gated on `_aiEnabled`. |
| `lib/app/chat/wallex_chat.page.dart` | Modify | Mic button, refactor `_send` → `_sendToAgent`, approval bubble widget, stream fallback when no tool_calls. |
| `lib/app/home/widgets/new_transaction_fl_button.dart` | Modify | 4th fan action `Icons.mic_none_rounded`. |
| `lib/app/transactions/voice_input/voice_capture_flow.dart` | Create | `static Future<void> start(ctx)` — mirrors `ReceiptImportFlow.start`. |
| `lib/app/transactions/voice_input/voice_record_overlay.dart` | Create | Bottom sheet: waveform bars, partial transcript, cancel, auto-stop VAD. Reused by chat. |
| `lib/app/transactions/voice_input/voice_review_sheet.dart` | Create | 3 chips + 3s auto-confirm + undo snackbar. |
| `i18n/*.i18n.json` | Modify | Keys: `t.transaction.voice_input.{entry,listening,release_to_send,cancel,review_title,confirm,undo,empty_transcript,permission_denied,permission_explainer}`, `t.chat.voice.{tap_to_talk,listening,processing,approval_prompt,approve,reject}`. Regen via `dart run slang`. |

## Interfaces / Contracts

```dart
abstract class AiTool {
  String get name;
  String get description;
  Map<String, dynamic> get parametersSchema; // JSON Schema
  bool get isMutating;                       // drives approval UI
  Future<AiToolResult> execute(Map<String, dynamic> args);
}

sealed class AiToolResult {
  const AiToolResult();
  factory AiToolResult.ok(Object payload) = _Ok;
  factory AiToolResult.proposal(TransactionProposal p) = _Proposal; // quickExpense path
  factory AiToolResult.error(String message) = _Error;              // serialized to model
}

class AgentProfile {
  final String name;
  final String systemPrompt;
  final List<AiTool> tools;
  final Object toolChoice;       // 'auto' | {'type':'function','function':{'name':...}}
  final double temperature;
  final int maxToolLoops;
  bool requiresApproval(String toolName) => ...; // wallexAssistant: true for mutating
}

// NexusAiService addition
Future<AiCompletionResult> completeWithTools({
  required List<Map<String, dynamic>> messages,
  required List<Map<String, dynamic>> tools,
  Object toolChoice = 'auto',
  String? model,
  double temperature = 0.2,
});
// returns: { String? content, List<AiToolCall> toolCalls }
```

Tool-loop pseudocode:
```
messages = [system, ...history, user]
for i in 0..profile.maxToolLoops:
  r = nexus.completeWithTools(messages, registry.toolsJson, profile.toolChoice)
  if r.toolCalls.isEmpty:
    if i == 0 and profile == wallexAssistant:
      return streamComplete(messages)   // preserve chat streaming UX
    return r.content
  for call in r.toolCalls:
    if profile.requiresApproval(call.name) and !(await ui.approve(call)): 
      append({role:'tool', tool_call_id:id, content:'{"error":"user_rejected"}'})
      continue
    result = await registry.dispatch(call.name, jsonDecode(call.arguments))
    append({role:'tool', tool_call_id:id, content:jsonEncode(result)})
// fallthrough: ask model for a final summary with tool_choice='none'
```

## Testing Strategy

| Layer | What to Test | Approach |
|-------|--------------|----------|
| Unit | `AIToolRegistry.toOpenAiTools()` serialization | Pure Dart, golden JSON. |
| Unit | Each tool's `execute()` arg validation + error path | Mock underlying service (AccountService, etc.). |
| Unit | Agent loop: tool_calls dispatch, maxLoops cap, approval rejection path | Fake `NexusAiService` returning canned responses. |
| Unit | `completeWithTools` JSON parsing (content null, tool_calls array, malformed) | `http.Client` mock. |
| Widget | `VoiceReviewSheet` chips, auto-confirm countdown, undo snackbar | Fake `VoiceService` emitting canned partials + final. |
| Widget | Chat mic → send flow + approval bubble tap | Fake agent. |
| Manual | STT accuracy on Android + MIUI permission flow | No automation — flaky per Flutter test memory. |

## Migration / Rollout

No DB/schema migration. `SettingKey.aiVoiceEnabled` is a trailing enum add. Feature gated by `nexusAiEnabled && aiVoiceEnabled`. Default `aiVoiceEnabled = '1'` when user has `nexusAiEnabled = '1'`. Six-tanda rollout per proposal (foundation → tools → agent → chat → FAB → settings/i18n). First-run permission explainer modal runs before `Permission.microphone.request()`; denial → dialog with `openAppSettings()` CTA (camera-flow pattern).

## Open Questions

- [ ] Should approval UI remember per-tool "approve for session" to reduce taps in multi-call chats? (Propose: no for MVP — explicit every time.)
- [ ] Model pin scope: global `SettingKey.nexusAiModel` vs per-agent override? (Propose: reuse global; document recommended pins in `AiSettingsPage` helper text.)
- [ ] `VoiceRecordOverlay` VAD silence threshold: 2s vs user-configurable? (Propose: fixed 2s MVP.)
