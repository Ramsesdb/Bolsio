# Exploration: voice-input-and-ai-tools

## Context

Introduce voice input to Bolsio in two surfaces that share one STT + tool-calling stack:

1. **Scoped voice on the Add-Transaction FAB** — push-to-talk, single tool `create_transaction`, chip-based review with auto-save + undo (MonAi-like UX).
2. **Conversational voice in the Bolsio AI chat** — push-to-talk next to the send button, full tool registry (`get_balance`, `list_transactions`, `get_stats_by_category`, `get_budgets`, `create_transaction`, `create_transfer`, etc.), open questions in Spanish.

Shared plumbing: one `VoiceService` (STT abstraction), one `AIToolRegistry` with Dart-callable tools, two agent profiles (`quick-expense-agent`, `bolsio-ai-agent`) that reuse the existing `NexusAiService`. Full realtime streaming ("live mode" / Gemini Live / OpenAI Realtime) is explicitly out of scope for this change.

---

## Current State

### AI layer

- `lib/core/services/ai/nexus_ai_service.dart` — OpenAI-compatible client against `https://api.ramsesdb.tech/v1/chat/completions`. Three methods today:
  - `complete(messages, temperature)` — non-streaming, text-only, returns `String?`.
  - `completeMultimodal(systemPrompt, userPrompt, imageBase64)` — vision support (used by receipt OCR).
  - `streamComplete(messages, temperature)` — SSE stream, yields `String` deltas, used by `BolsioChatPage`.
  - **No tool-call path exists today.** The body only sends `{ stream, temperature, messages }`. The gateway (`AI_infi/index.ts` + `types.ts`) already passes through `tools`, `tool_choice` on `ChatOptions` — so the backend is ready; the Dart client is not.
- `lib/core/services/ai/nexus_credentials_store.dart` — `flutter_secure_storage` with `encryptedSharedPreferences`, keys `nexus_ai_api_key` + `nexus_ai_model` (default `openai/gpt-4.1-mini`).
- `lib/core/services/ai/financial_context_builder.dart` — bakes accounts + 60 last tx + categories + budgets into a ~8k-char system-prompt blob. Used by `BolsioChatPage._bootstrap`. This is the **pre-computed context** pattern; switching to tools is an alternative architecture, not an addition.

### Chat surface

- `lib/app/chat/bolsio_chat.page.dart` — self-contained `StatefulWidget` with in-memory `_messages` list, `TextEditingController`, manual SSE aggregation in `_send()`. Input row is an inline `Row` with `TextField` + `IconButton.filled` (send). Avatar, markdown rendering, typing indicator all present. No audio/mic code anywhere.
- `lib/app/ai/ai_hub.page.dart` — entry-point hub with a card linking to `BolsioChatPage` plus insights.

### Add-transaction surface

- `lib/app/home/widgets/new_transaction_fl_button.dart` — `NewTransactionButton` already has a **3-action fan overlay** (manual / gallery / camera) built by hand (no `flutter_expandable_fab` despite the package being in `pubspec`). Actions route to `TransactionFormPage` (manual) or `ReceiptImportFlow.start(ctx, source)`. The natural expansion point for a 4th action ("voice") is `actions` list at line ~189 of this file.
- `lib/app/transactions/form/transaction_form.page.dart` — full manual form with `.fromReceipt(...)` constructor already wired (lines 60–67) that accepts a `TransactionProposal receiptPrefill` + `pendingAttachmentPath`. A voice flow could reuse this same `receiptPrefill` carrier or spawn a parallel `.fromVoice(...)` constructor with the same shape (chips UX is distinct from the full form).
- `lib/core/models/auto_import/transaction_proposal.dart` — immutable record with `amount`, `currencyId`, `date`, `type`, `counterpartyName`, `rawText`, `channel`, `confidence`, `proposedCategoryId`, etc. `CaptureChannel` enum is an extension point; receipt flow added `receiptImage`, voice would add `voice`.

### Transaction creation service

- `lib/core/database/services/transaction/transaction_service.dart` — `insertTransaction(TransactionInDB)` used across the app. Tool-call executors would call this directly, same as any other caller.

### Settings, i18n, permissions

- `SettingKey` enum (`lib/core/database/services/user-setting/user_setting_service.dart:6`) already holds `nexusAiEnabled` + sub-toggles (chat, categorization, insights, budgetPrediction, receiptAi). A new `aiVoiceEnabled` sub-toggle fits the same pattern.
- `AiSettingsPage` (`lib/app/settings/pages/ai/ai_settings.page.dart`) — one `SwitchListTile` per sub-toggle; adding voice is two lines.
- `i18n/` uses **slang** (JSON sources, generated Dart). `t.transaction.receipt_import.*` tree already exists; voice would add `t.transaction.voice_input.*` and `t.chat.voice.*` namespaces.
- Android permissions: camera + notification-listener are already handled; **microphone permission is not yet declared**. `permission_handler: ^12.0.1` is present — `Permission.microphone.request()` would be the entry point, mirroring the camera flow at `new_transaction_fl_button.dart:147`.

### Audio/STT today

- **Zero** audio packages in `pubspec.yaml`: no `speech_to_text`, `flutter_sound`, `record`, `audio_waveforms`, no on-device STT. The closest existing asset pipeline is `image_picker` + `google_mlkit_text_recognition` for receipts.
- Greps for `speech_to_text|whisper|stt|audio` across `lib/` return only matches inside the ML Kit text recognizer (Latin script, unrelated) and package `cryptography`. Nothing voice-adjacent.

### Nexus gateway (AI_infi)

- `index.ts` forwards `tools` and `tool_choice` to the provider (verified: lines 575–576, 621–622). Providers Groq (Llama 3.3/4), OpenAI (via OpenRouter), and Gemini all support OpenAI-compatible `tools` schema today. Cerebras has partial support per model.
- **No dedicated `/v1/audio/transcriptions` endpoint exists** in the gateway today. If we want cloud STT through Nexus we'd add one (Groq Whisper and OpenAI `whisper-1` are both available behind existing API keys).

---

## Affected Areas

### New packages (pubspec)

- `speech_to_text: ^7.x` — on-device STT via Android `SpeechRecognizer` / Windows hook, returns partial + final Spanish transcripts.
- **OR** (if cloud STT wins) `record: ^5.x` — captures `.m4a`/`.wav` to disk; no STT of its own. Combined with a Nexus `/v1/audio/transcriptions` proxy to Groq Whisper v3.
- Optionally `flutter_tts: ^4.x` for Phase-2 TTS of assistant replies (chat surface). NOT in MVP.

### New services

- `lib/core/services/voice/voice_service.dart` — `Future<VoiceSession> startSession({Locale locale = es_VE, Duration maxDuration = 30s})`, `Stream<String> partialTranscripts`, `Future<String> stop()`, plus permission handling.
- `lib/core/services/ai/tools/ai_tool.dart` — base contract:
  ```
  abstract class AiTool {
    String get name;
    String get description;
    Map<String, dynamic> get parametersSchema; // JSON Schema
    Future<Map<String, dynamic>> execute(Map<String, dynamic> args);
  }
  ```
- `lib/core/services/ai/tools/ai_tool_registry.dart` — holds named tool instances, serializes to OpenAI `tools[]`, dispatches `tool_calls[i].function` → `AiTool.execute(args)` → `{role:'tool', tool_call_id, content}` message.
- `lib/core/services/ai/tools/financial_tools.dart` — concrete tools:
  - `GetBalanceTool` → `AccountService.getAccountMoney(...)`.
  - `ListTransactionsTool(limit, from, to, categoryId, accountId)` → `TransactionService.getTransactions(...)`.
  - `GetStatsByCategoryTool(period)` → existing stats services.
  - `GetBudgetsTool(activeOnly)` → `BudgetServive`.
  - `CreateTransactionTool(desc, amount, currency, category, account, date?)` → `TransactionService.insertTransaction`.
  - `CreateTransferTool(fromAccount, toAccount, amount, fxRate?)` → `TransactionService.insertTransaction` × 2.
- `lib/core/services/ai/agent_profiles.dart` — `AgentProfile { name, systemPrompt, tools, temperature, maxToolLoops }`:
  - `quickExpense` → system = expense extractor in es-VE, tools = `[CreateTransactionTool]`, `tool_choice: {type:'function', function:{name:'create_transaction'}}` to force single call.
  - `bolsioAssistant` → system = full financial-assistant prompt, tools = all, `tool_choice: 'auto'`, max 3 loops.

### NexusAiService extension

- `lib/core/services/ai/nexus_ai_service.dart`:
  - Add `completeWithTools({messages, tools, toolChoice, model, temperature})` → returns parsed `{content, toolCalls[]}` record.
  - Extend `streamComplete` to buffer and emit tool-call deltas (OpenAI SSE includes `choices[0].delta.tool_calls`). Simplest MVP: **non-streaming** for the agent loop, streaming only for final assistant text. This mirrors how most OpenAI tool apps work (tools don't stream incrementally).

### UI

- **Chat surface** — `lib/app/chat/bolsio_chat.page.dart`:
  - Replace current single-send button row with `[mic] [text] [send]`.
  - New widget `VoiceRecordOverlay` — bottom sheet with waveform (simple bars from RMS), live partial transcript, cancel button, auto-stop on silence > 2s.
  - Refactor `_send` into `_sendToAgent(AgentProfile profile, {String userText, bool playTts = false})` that runs the tool loop: model call → if `tool_calls` → execute each → append tool messages → recurse (bounded).
- **Add-transaction surface** — `lib/app/home/widgets/new_transaction_fl_button.dart`:
  - Add 4th fan-overlay action: `Icons.mic_none_rounded` + `t.transaction.voice_input.entry`.
  - New flow `lib/app/transactions/voice_input/voice_capture_flow.dart` — opens `VoiceRecordOverlay`, on stop calls `quickExpense` agent, receives a single `create_transaction` tool call (not yet executed), renders `VoiceReviewSheet`.
  - New widget `lib/app/transactions/voice_input/voice_review_sheet.dart` — 3 editable chips (description / amount / category), auto-confirm countdown (3s) with tap-to-edit and "undo" snackbar after save (reuse `lib/core/presentation/helpers/snackbar.dart`).

### Settings + permissions

- `SettingKey.aiVoiceEnabled` — new enum case (default `'1'` when `nexusAiEnabled='1'`).
- `AiSettingsPage` — new `SwitchListTile` "Entrada por voz" gated on `_aiEnabled`.
- `android/app/src/main/AndroidManifest.xml` — add `<uses-permission android:name="android.permission.RECORD_AUDIO"/>`.
- Windows: `speech_to_text` uses platform-provided dictation; no manifest change needed, but the first call triggers Windows' consent UI.

### i18n (slang JSON)

- Add `t.transaction.voice_input.{entry, listening, release_to_send, cancel, review_title, confirm, undo, empty_transcript, permission_denied}`.
- Add `t.chat.voice.{tap_to_talk, listening, processing}`.
- Run `dart run slang` after edits.

---

## STT Options for Flutter (Android + Windows, Spanish-first)

| Option | Engine | Online? | Spanish VE dialect | Latency | Cost | Pros | Cons |
|--------|--------|---------|--------------------|---------|------|------|------|
| **A. `speech_to_text` (on-device, Android SpeechRecognizer + Windows dictation)** | Google on Android, Microsoft on Windows | Android: online by default, on-device only if Google app has the model downloaded. Windows: online via MS. | Good (es-VE supported by Google via `es-VE` locale tag; falls back to `es-US`). | ~300–800ms final, partial ~200ms. | **Free.** | Free, well-supported Flutter plugin, partial transcripts stream, familiar permissions. | Needs network on most Android devices (Google STT is cloud under the hood unless user downloaded offline model). No per-user privacy-by-default. Windows support is flaky on older versions. |
| **B. `record` + Nexus `/v1/audio/transcriptions` → Groq Whisper-large-v3** | OpenAI Whisper via Groq | Yes, always. | **Excellent** — Whisper is state-of-the-art for VE Spanish slang ("real" for bolívares, "verdes" for USD, etc.). | ~1–2s for a 5s clip at Groq speeds; no partials. | ~$0.04/hour at Groq — effectively free at personal-use volume. | Best transcription quality; offloads compute; no per-device model licensing; we already have a Nexus gateway. | Requires backend change (new endpoint). No partial transcripts (user sees nothing until they stop). Requires network; fails offline. |
| **C. `record` + Gemini 2.5 Flash multimodal audio** | Gemini audio-in | Yes. | Good; Gemini handles multilingual audio well. | 1–3s. | Free tier on gateway. | Single round-trip: audio → transcription + tool-call in one call (native multimodal). | Gemini audio API has quirks with tool-calling simultaneously; two-stage is safer. Same "no partials" drawback. |
| **D. `vosk_flutter` (fully offline)** | Vosk (Kaldi) | No. | OK for Castilian Spanish; VE dialect not tuned. | Fast, ~100–300ms. | Free. | True offline, private, deterministic. | Adds 40–100MB Spanish model to APK. Limited vocabulary; struggles with Spanglish ("el uber", "el delivery"). Windows build is painful. |

**Recommendation for MVP**: **Hybrid A → B**. Ship MVP with `speech_to_text` (Option A) to keep the change small, avoid a backend endpoint, and get partial transcripts for good UX. Keep the `VoiceService` behind an interface so swapping to cloud Whisper later is a one-service replacement. When users report poor VE-dialect transcription, add Option B as `WhisperVoiceService implements VoiceService` plus a gateway endpoint — non-breaking.

---

## Tool-Calling Pattern (Dart ↔ Nexus)

### Request shape

`NexusAiService.completeWithTools` sends OpenAI-compatible body:

```json
{
  "stream": false,
  "temperature": 0.2,
  "model": "openai/gpt-4.1-mini",
  "messages": [
    {"role": "system", "content": "<profile.systemPrompt>"},
    {"role": "user", "content": "<transcribed text>"}
  ],
  "tools": [
    {
      "type": "function",
      "function": {
        "name": "create_transaction",
        "description": "Create a new expense or income transaction.",
        "parameters": {
          "type": "object",
          "properties": {
            "description": {"type":"string"},
            "amount": {"type":"number"},
            "currency": {"type":"string","enum":["USD","VES"]},
            "category": {"type":"string"},
            "account": {"type":"string"},
            "date": {"type":"string","format":"date-time"}
          },
          "required": ["description","amount","currency","category","account"]
        }
      }
    }
  ],
  "tool_choice": "auto"
}
```

### Response parsing

OpenAI-compatible response:

```json
{
  "choices": [{
    "message": {
      "role": "assistant",
      "content": null,
      "tool_calls": [
        {"id":"call_1","type":"function","function":{"name":"create_transaction","arguments":"{\"amount\":45, ...}"}}
      ]
    }
  }]
}
```

Dart parses `choices[0].message.tool_calls[i]`, JSON-decodes `arguments`, looks up the tool by name in `AIToolRegistry`, calls `tool.execute(args)`, then appends a new message:

```
{"role": "tool", "tool_call_id": "call_1", "content": "<jsonEncode(result)>"}
```

And recurses (`completeWithTools` with the extended message history) up to `maxToolLoops` (3). If the next response has no `tool_calls`, its `content` is the final text shown/spoken to the user.

### Quick-expense profile specifics

- `tool_choice: {type:'function', function:{name:'create_transaction'}}` forces the model to emit that exact call; no reasoning detour.
- `execute()` for `CreateTransactionTool` in **scoped mode** does NOT insert immediately — it returns a `TransactionProposal`-like record that the review sheet binds to. Only the "Confirmar" button (or 3s countdown) triggers the real `TransactionService.insertTransaction`.
- This keeps a single abstraction: same tool shape, mode flag controls auto-commit.

### Conversational profile specifics

- `tool_choice: 'auto'`. Read-only tools execute immediately and their results feed back into the model. Mutating tools (`create_transaction`, `create_transfer`) emit an "approval required" UI bubble with a confirm button before `execute()` runs, mirroring how the model proposes actions.

---

## UI Integration Points

| File | Change | Notes |
|------|--------|-------|
| `lib/app/home/widgets/new_transaction_fl_button.dart:189` | Add 4th `_FanAction(Icons.mic_none_rounded, tooltip: t.transaction.voice_input.entry, onPressed: _startVoiceCapture)` | Local state `_VoiceCaptureState` handles permission + overlay. |
| `lib/app/chat/bolsio_chat.page.dart:316` | Insert `_MicButton(onResult: (text) => _sendWithVoice(text))` before the `TextField` in the input Row | Reuses `_send` pathway with `text` prefilled. |
| `lib/app/chat/bolsio_chat.page.dart:_send` | Refactor to `_sendToAgent(profile: AgentProfile.bolsioAssistant, userText: text)` | Agent loop handles tool calls transparently. |
| `lib/app/transactions/voice_input/voice_capture_flow.dart` (new) | Entry point: `static Future<void> start(BuildContext ctx)` | Mirrors `ReceiptImportFlow.start` signature — consistent mental model. |
| `lib/app/transactions/voice_input/voice_record_overlay.dart` (new) | Modal bottom sheet with live waveform + partial transcript + cancel | Reused by chat mic button too. |
| `lib/app/transactions/voice_input/voice_review_sheet.dart` (new) | 3 chips + auto-confirm countdown | `.fromProposal(TransactionProposal)` — reuses receipt model. |
| `lib/core/services/voice/voice_service.dart` (new) | Singleton `VoiceService.instance.startSession(...)` | Abstracts STT engine. |
| `lib/core/services/ai/tools/*.dart` (new) | Tool registry + concrete tools | 6 tools for MVP. |
| `lib/core/services/ai/agent_profiles.dart` (new) | 2 profiles | `quickExpense`, `bolsioAssistant`. |
| `lib/core/services/ai/nexus_ai_service.dart` | Add `completeWithTools`; keep `complete`/`streamComplete`/`completeMultimodal` backward-compatible | Non-breaking addition. |
| `lib/app/settings/pages/ai/ai_settings.page.dart` | New `SwitchListTile` "Entrada por voz" | One additional sub-toggle. |
| `lib/core/database/services/user-setting/user_setting_service.dart` | New `SettingKey.aiVoiceEnabled` | Trailing enum add, no migration. |
| `android/app/src/main/AndroidManifest.xml` | `RECORD_AUDIO` permission | Non-dangerous on its own but runtime-prompted. |
| `i18n/*.i18n.json` | New keys under `t.transaction.voice_input` + `t.chat.voice` | Slang regen. |

---

## Open Questions / Risks

1. **Microphone permission friction on MIUI** — same pain as camera (`project_monekin_personal` memory already flags this). Mitigate: first-run explanation dialog before `Permission.microphone.request()`, and `openAppSettings()` fallback if denied.
2. **Spanish-VE dialect handling** — Option A (`speech_to_text`) routes through Google's `es-VE` locale on Android; accuracy is acceptable for monetary nouns ("bolos" → "Bolos"/VES by prompt, "verdes" → USD by prompt). Mitigate: system prompt for `quickExpense` includes explicit VE currency slang mapping. Route to Whisper (Option B) later if quality suffers.
3. **Ambiguity in quick-expense** — "Gasté 20 en comida" omits currency AND account. Mitigate: if `CreateTransactionTool` params violate schema, the review sheet opens with the missing fields highlighted red; never silently auto-save an ambiguous transaction. Fall back to the user's `SettingKey.preferredCurrency` and default account ONLY when confidence is high (e.g. model explicitly set both) — otherwise require a chip tap.
4. **BCV vs paralelo rate for voice-entered VES** — reuse existing `SettingKey.preferredRateSource` + exchange-rate selector already in the full form. For the 3-chip scoped sheet, skip FX entirely: persist as entered in the account's native currency, leaving cross-currency edits to the full form (tap chip → opens full `TransactionFormPage.fromVoice(...)`).
5. **Cost of cloud STT** — Option A is free for users (Google's STT quota). Option B via Nexus → Groq Whisper costs ~$0.00067 per minute at Groq rates. Ramses-only personal usage: negligible. Flag for future if distributed to friends/family.
6. **Offline behavior** — Option A with Google's online STT fails gracefully (`speech_to_text` exposes `onError`; show "requires internet" toast). Fully offline requires Option D (Vosk) or a downloaded Google model; not in MVP.
7. **Background noise / environmental audio** — `speech_to_text` has VAD built in; auto-stop on silence > 2s. Add explicit "Cancelar" button and manual stop.
8. **TTS for assistant replies (Phase 2)** — `flutter_tts` works on both Android and Windows; es-VE voice available on most devices. Deferred; behind `SettingKey.aiVoiceTtsEnabled` in a later change.
9. **Gateway tool-call pass-through across providers** — Cerebras historically shaky on tools; Gemini on OpenRouter is fine; Groq Llama 3.3 70B is fine. Recommend pinning `openai/gpt-4.1-mini` (current default) or `groq/llama-3.3-70b-versatile` for tool-heavy agent loops. Document in the design phase.
10. **Agent loop runaway** — Model could keep calling tools. Mitigate: hard-cap `maxToolLoops = 3` in `bolsioAssistant` (scoped agent allows only 1). Log every loop iteration with telemetry.
11. **Conflict with in-progress `BolsioChatPage`** — the current page's `_send` handles streaming directly. Refactoring to agent-loop means the streaming UX for plain conversational replies (no tools) must be preserved. Mitigate: agent loop detects "no tool_calls" on first response → switches to `streamComplete` path for the final text.
12. **No tool_calls parsing in `NexusAiService` today** — this is the single largest net-new complexity. Gateway pass-through is verified (`AI_infi/index.ts:575,621`) so only the Dart side needs work.

---

## Relation to Other Open SDD Changes

### `bolsio-ai-integration` — FOUNDATIONAL DEPENDENCY (already landed per current code)

- This change **extends** `NexusAiService` with `completeWithTools`. The credentials store, settings keys, master toggle, and `FinancialContextBuilder` already exist on main.
- **Trade-off**: we're moving from "pre-computed context dump" (current `FinancialContextBuilder`) to "on-demand tool calls" for the conversational surface. Keep the context builder as the **bootstrap system prompt** (user's accounts + category list, ~1k chars) so the model knows what to ask for, then let tools fetch fresh data on demand. This halves system-prompt tokens, avoids stale data, and keeps a single source of truth for reads.

### `attachments-and-receipt-ocr` — SIBLING, NOT A DEPENDENCY

- Receipt OCR added `CaptureChannel.receiptImage` and `TransactionFormPage.fromReceipt(receiptPrefill, pendingAttachmentPath)`. Voice input adds a parallel `CaptureChannel.voice` enum case and reuses the **same** `TransactionProposal` model as the carrier between the agent and the review sheet.
- No shared plumbing with attachments (no audio file is persisted — we store the final transcript in `TransactionProposal.rawText` and discard the audio bytes). If we later want "audio receipts", that's a future change using the `attachments` subsystem.
- No file conflicts; can develop in parallel.

### `firebase-always-on` — UNRELATED

- Auth/sync domain. No overlap.

### `fix-exchange-rate-fallback` — UNRELATED

- Display/SQL fix in exchange-rate layer. No overlap.

---

## Approaches

### 1. Two surfaces, shared infrastructure — MVP with on-device STT (RECOMMENDED)

Single `VoiceService` backed by `speech_to_text`; single `AIToolRegistry`; two `AgentProfile`s. Ship scoped quick-expense + chat voice in one change.

- **Pros**: One net-new dependency (`speech_to_text`), no backend work, shared code between surfaces, incremental (can land in tandas). Free at any personal-use scale. VE-dialect quality acceptable for common transactions; upgrade path to Whisper is clean.
- **Cons**: Relies on Google's online STT for Android; fails offline. Tool-call parsing in Dart is net-new code with real parsing risk (OpenAI SSE tool-call deltas are gnarly — mitigated by non-streaming tool loop).
- **Effort**: Medium — 1 service + 1 registry + 6 tools + 2 screens + 1 chat refactor + 1 pubspec dep + 1 permission + i18n.

### 2. Cloud-only (Whisper via Nexus endpoint)

Add `/v1/audio/transcriptions` to Nexus, use `record` in Flutter to capture audio, POST to gateway.

- **Pros**: Best transcription quality; no client-side engine inconsistency across Android versions; same auth/rate-limit path as existing AI calls.
- **Cons**: Requires backend change to `AI_infi` (out of this repo, coordination cost); no live partial transcripts (worse UX until final); always requires network.
- **Effort**: Medium-High (two repos).

### 3. Two separate features, ship serially

Ship scoped quick-expense voice first (no chat surface), then chat voice later.

- **Pros**: Lower blast radius per change; first change is tiny and high-value (MonAi parity).
- **Cons**: Duplicated `VoiceService` + `AIToolRegistry` thinking across two changes, higher cumulative effort. Chat voice would sit unused until its own change lands.
- **Effort**: Low per change, High cumulative.

### 4. Voice-only in chat, skip scoped surface

Only add mic to `BolsioChatPage`; users dictate "créame un gasto de 45 en uber" through the chat agent.

- **Pros**: Smallest code change; chat already exists.
- **Cons**: Loses MonAi-like single-tap ergonomics from the FAB; every quick-expense takes 3+ round trips (open chat → dictate → wait → confirm). Defeats the value prop.
- **Effort**: Low.

---

## Recommendation

**Approach 1** — ship both surfaces with on-device STT in one change, split across tandas:

1. **Tanda 1** — `VoiceService` + `speech_to_text` dep + permission + manifest + es-VE locale + minimal `VoiceRecordOverlay`. No AI integration yet; proves STT pipeline end-to-end with a debug screen printing transcripts.
2. **Tanda 2** — `AiTool` contract + `AIToolRegistry` + 6 concrete tools + unit tests (pure Dart).
3. **Tanda 3** — `NexusAiService.completeWithTools` + agent loop in `AgentProfile` + telemetry.
4. **Tanda 4** — Chat surface wiring: mic button, `_sendToAgent` refactor, tool-call approval UI for mutating tools. Falls back to streaming text when no tool calls.
5. **Tanda 5** — Add-transaction surface: 4th FAB action, `VoiceCaptureFlow`, `VoiceReviewSheet` with 3 chips + 3s auto-confirm + undo snackbar.
6. **Tanda 6** — Settings toggle, i18n, end-to-end polish, known-limitations doc.

Tandas 1–3 are backend-ish; Tandas 4–5 are user-visible. Can land Tanda 5 (scoped quick-expense) without Tanda 4 (chat voice) if we want to ship incrementally — they're independent surface code.

Keep `FinancialContextBuilder` alive as the bootstrap system prompt; don't delete it. Tools replace **read-time** context fetching, not the cold-start context.

---

## Risks (consolidated)

- **Permission friction on MIUI** — runtime-prompt + `openAppSettings()` fallback.
- **Tool-call parsing complexity in Dart** — non-streaming tool loop; streaming only for final text.
- **Agent-loop runaway** — hard-cap `maxToolLoops = 3` (1 for scoped profile).
- **VE dialect STT accuracy** — Google on-device STT is acceptable; Whisper is a clean upgrade path.
- **Offline behavior** — graceful fallback toast; documented as online-only for MVP.
- **Cost of cloud STT (if we escalate)** — negligible at personal scale; flag for future.
- **Mutating-tool safety** — approval UI for `create_transaction` / `create_transfer` in conversational profile.
- **Chat `_send` refactor breakage** — keep a dedicated path for "no tool_calls" response that routes to `streamComplete` so existing chat UX is preserved byte-for-byte when the agent answers a plain question.
- **Provider inconsistency on tool calls** — pin `openai/gpt-4.1-mini` (current default) or `groq/llama-3.3-70b-versatile` for agent loops; document in design.

---

## Ready for Proposal

**Yes.**

The orchestrator should tell the user:

> Exploration confirms both voice surfaces can share one `VoiceService` + one `AIToolRegistry` + two `AgentProfile`s, extending the existing `NexusAiService` non-breakingly. MVP uses on-device STT (`speech_to_text`, free, Spanish-VE capable) with a clean upgrade path to Whisper-via-Nexus if dialect accuracy suffers. Gateway already passes `tools` through — only the Dart client needs new code.
>
> One architectural decision for the proposal phase: do we keep `FinancialContextBuilder` as bootstrap context (recommended) or remove it in favor of pure tool-call-based reads? Recommendation: keep, but shrink its output to accounts + category list (~1k chars), letting tools fetch transactions/budgets on demand. This halves token cost and avoids stale data.
>
> No conflict with `attachments-and-receipt-ocr` (parallel sibling, both add a `CaptureChannel` case on `TransactionProposal`). Depends on `bolsio-ai-integration` (already landed). Ready to run `/sdd-propose`.
