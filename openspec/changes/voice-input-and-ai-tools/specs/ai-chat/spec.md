# ai-chat Specification (new capability for this change)

## Purpose

Extends `BolsioChatPage` with a voice input affordance and a tool-enabled message flow, preserving the existing streaming UX for plain-text (no-tool) responses.

## Requirements

### Requirement: Voice Input Affordance in Chat

The system MUST render a mic button in the chat input row when both `SettingKey.nexusAiEnabled` and `SettingKey.aiVoiceEnabled` are `'1'`. Tapping it MUST open `VoiceRecordOverlay`; on stop, the final transcript SHALL be sent to `_sendToAgent(bolsioAssistant, userText: transcript)`.

#### Scenario: Voice-driven question

- GIVEN both settings are enabled and mic permission is granted
- WHEN the user taps the mic, says "cuánto gasté en comida en marzo", and releases
- THEN the transcript is sent through `_sendToAgent`
- AND the agent runs `get_stats_by_category` and responds with grounded Spanish text

#### Scenario: Voice disabled hides mic

- GIVEN `aiVoiceEnabled = '0'`
- WHEN `BolsioChatPage` renders
- THEN the mic button is absent and only the text send button is shown

### Requirement: Tool-Enabled Message Flow

The system MUST refactor `_send` into `_sendToAgent(AgentProfile profile, {String userText})` that runs the bounded tool loop via `NexusAiService.completeWithTools`. When the first response contains NO `tool_calls`, the system SHALL route to the existing `streamComplete` path for the final text so streaming UX is preserved byte-for-byte.

#### Scenario: Plain question streams as before

- GIVEN the user types "hola" and sends
- WHEN the model responds with `content` and no `tool_calls`
- THEN the message is re-requested via `streamComplete` and rendered token-by-token
- AND the existing typing indicator behavior is unchanged

#### Scenario: Tool call runs non-streaming, then final text streams

- GIVEN the user asks a question that triggers `list_transactions`
- WHEN the tool loop completes and the final model response has `content` but no more `tool_calls`
- THEN the final text is streamed via `streamComplete`

### Requirement: Approval Bubble for Mutating Tools

Mutating tool calls in chat (`create_transaction`, `create_transfer`) MUST render an approval bubble inline in the message list showing decoded arguments before `execute()` runs. (See ai-tools for gate mechanics.)

#### Scenario: User approves a chat-proposed expense

- GIVEN the assistant proposes `create_transaction({amount:45, currency:'USD', ...})`
- WHEN the user taps "Confirmar" on the bubble
- THEN `TransactionService.insertTransaction` runs
- AND the tool message with the insert result feeds back into the loop

### Requirement: Tool-Loop Cap Surfacing in Chat

When the tool loop terminates due to `maxToolLoops`, the chat MUST render a user-visible fallback ("No pude completar la consulta") instead of silently stalling.

#### Scenario: Runaway loop

- GIVEN the loop hits cap 3
- WHEN termination fires
- THEN a neutral assistant bubble shows the fallback message
- AND the input row re-enables for a new prompt
