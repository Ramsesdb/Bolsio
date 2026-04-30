# Exploration: bolsio-ai-integration

## Context

Integrate 4 AI-powered features into Bolsio using the existing Nexus AI Gateway (multi-provider proxy: Cerebras, Groq, Gemini, OpenRouter). Features: Smart Auto-Categorization, Financial Chat, Spending Pattern Analysis, Budget Prediction.

## Findings

### Current Architecture

**Service Pattern**: Singleton services (`ServiceName._(this.db)` / `static final instance`), Drift ORM on SQLite, RxDart streams for reactive UI.

**Auto-Import Pipeline**: `CaptureOrchestrator` → `BankProfile` matching → `DedupeChecker` → `PendingImportService.insertProposal()`. The `TransactionProposal.proposedCategoryId` field already exists but is only set by UI heuristics.

**HTTP**: `http` package (^1.5.0) already in deps, used by `DolarApiService`.

**Secure Storage**: `BinanceCredentialsStore` pattern with `flutter_secure_storage` + `AndroidOptions(encryptedSharedPreferences: true)`.

**UI**: `PageFramework` scaffold, `PageSwitcher` with `FadeIndexedStack`, bottom nav (Dashboard, Budgets, Transactions, Stats, Settings). i18n via `slang`.

### Integration Points

| Feature | Hook Point | Method |
|---------|-----------|--------|
| Auto-Categorization | `CaptureOrchestrator._handleEvent()` after proposal parse, before persist | Non-streaming (`stream: false`) |
| Financial Chat | New screen (push route from Dashboard/Settings) | Streaming SSE |
| Spending Patterns | Dashboard card or Stats page section | Non-streaming |
| Budget Prediction | Budget detail/list widget | Non-streaming |

### Nexus API Contract

- **Endpoint**: `POST /v1/chat/completions`
- **Auth**: `Authorization: Bearer {NEXUS_MASTER_KEY}`
- **Request**: `{ messages: ChatMessage[], stream?: boolean, temperature?: number }`
- **Streaming**: SSE `data: {json}\n\n` with `data: [DONE]` terminator
- **Non-streaming**: Standard OpenAI completion JSON response

### Technical Considerations

- **No DB migration needed**: `proposedCategoryId` exists, chat history in-memory, insights cached in memory.
- **Latency**: Auto-categorization adds ~500ms-2s but pipeline is async (user doesn't wait). Chat uses streaming for perceived speed.
- **Offline**: All AI features fail gracefully — master toggle `nexusAiEnabled`.
- **Credentials**: Follow `BinanceCredentialsStore` pattern → `NexusCredentialsStore`.
- **Language**: System prompts specify Spanish output.

### Open Questions

1. **Nexus URL**: Production URL accessible from phone? (api.ramsesdb.tech or custom?)
2. **Category suggestion UX**: Auto-populate or show AI suggestion with accept/reject?
3. **Insight frequency**: On every dashboard load, once/day, or on-demand button?
4. **Budget prediction scope**: All budgets or only warning-status ones?
5. **Rate limiting**: Daily AI call quota?
6. **Feature gating**: Behind premium wall? (in_app_purchase already in deps)

## Recommendation

4-phase incremental implementation:
1. **Foundation + Auto-Categorization** — NexusCredentialsStore, NexusAiService, settings, orchestrator hook
2. **Financial Chat** — SSE streaming, FinancialContextBuilder, chat screen, in-memory history
3. **Spending Pattern Analysis** — Period comparison service, dashboard insight card, TTL cache
4. **Budget Prediction** — Historical data extraction, prediction widget, structured JSON responses
