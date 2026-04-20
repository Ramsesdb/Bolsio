# ai-tools Specification

## Purpose

Defines the tool-calling contract used by agent profiles: a registry of named `AiTool` instances, an OpenAI-compatible serialization, a bounded invocation loop, and approval gates for mutating tools.

## Requirements

### Requirement: Tool Registry and Schema Serialization

The system MUST expose `AIToolRegistry` that holds `AiTool` instances keyed by `name` and SHALL serialize to the OpenAI `tools[]` JSON shape (`{type:'function', function:{name, description, parameters}}`).

#### Scenario: Registry emits valid OpenAI tools array

- GIVEN the registry holds 6 tools (`get_balance`, `list_transactions`, `get_stats_by_category`, `get_budgets`, `create_transaction`, `create_transfer`)
- WHEN `registry.toOpenAiTools()` is called
- THEN output is a JSON-serializable list with one entry per tool
- AND each entry has non-empty `function.name`, `description`, and a valid JSON Schema under `parameters`

### Requirement: Tool Invocation Dispatch

The system MUST dispatch a single `tool_calls[i]` by looking up `function.name` in the registry, JSON-decoding `function.arguments`, calling `AiTool.execute(args)`, and producing a `{role:'tool', tool_call_id, content: jsonEncode(result)}` message.

#### Scenario: Read-only tool dispatch

- GIVEN the model emits one `tool_call` for `get_balance` with `{accountId: 'a1'}`
- WHEN the loop dispatches it
- THEN `GetBalanceTool.execute({accountId:'a1'})` runs
- AND a `tool` message is appended with the JSON-encoded balance result

#### Scenario: Unknown tool name

- GIVEN the model emits a `tool_call` for an unregistered name
- WHEN the loop dispatches it
- THEN the tool message content is a JSON error `{error:'unknown_tool', name:<n>}`
- AND the loop continues (model may correct itself)

### Requirement: Tool Loop Cap

The system MUST enforce an `AgentProfile.maxToolLoops` cap on the number of model-to-tool round trips. When the cap is reached, the loop SHALL terminate and surface the last assistant `content` (or a fallback message) to the user.

#### Scenario: Cap reached

- GIVEN `wallexAssistant.maxToolLoops = 3` and the model emits a tool call on every iteration
- WHEN the 3rd loop completes and the 4th response still contains `tool_calls`
- THEN the loop stops without executing the 4th batch
- AND the UI shows a fallback message indicating the assistant could not complete the task

### Requirement: Mutating Tool Approval Gate

The system MUST require explicit user approval before executing `create_transaction` or `create_transfer` in the `wallexAssistant` profile. Read-only tools MUST execute without approval.

#### Scenario: Approval required for create_transaction

- GIVEN the model returns a `create_transaction` tool call in chat
- WHEN the loop reaches that call
- THEN an approval UI bubble renders with the proposed arguments
- AND `execute()` is NOT invoked until the user taps "Confirmar"

#### Scenario: User rejects mutation

- GIVEN an approval bubble is visible
- WHEN the user taps "Cancelar"
- THEN a tool message with `{status:'user_rejected'}` is appended
- AND the loop continues so the model can respond textually

### Requirement: Agent Profile Isolation

The system MUST expose at least two profiles: `quickExpense` (tools = `[CreateTransactionTool]`, `tool_choice` forced to that function, `maxToolLoops = 1`) and `wallexAssistant` (tools = all six, `tool_choice: 'auto'`, `maxToolLoops = 3`). A profile MUST NOT be able to invoke tools outside its declared set.

#### Scenario: quickExpense cannot call non-transaction tools

- GIVEN `quickExpense` is active
- WHEN the model hallucinates a `get_balance` tool call
- THEN the registry lookup scoped to the profile returns "unknown_tool"
- AND no `GetBalanceTool.execute` is invoked

### Requirement: Quick-Expense Non-Commit Semantics

In the `quickExpense` profile, `CreateTransactionTool.execute` MUST return a `TransactionProposal`-shaped record WITHOUT persisting. Commit SHALL happen only from the review sheet (see transaction-entry).

#### Scenario: Proposal returned, not persisted

- GIVEN `quickExpense` runs with transcript "gasté 20 en uber"
- WHEN the tool call is dispatched
- THEN `TransactionService.insertTransaction` is NOT called
- AND the result is a `TransactionProposal` carrier consumed by `VoiceReviewSheet`
