import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:bolsio/app/chat/models/chat_card_dispatcher.dart';
import 'package:bolsio/app/chat/models/chat_card_payload.dart';
import 'package:bolsio/app/chat/models/chat_text_sanitizer.dart';
import 'package:bolsio/app/chat/theme/bolsio_ai_tokens.dart';
import 'package:bolsio/app/chat/widgets/ai_bubble.dart';
import 'package:bolsio/app/chat/widgets/cards/account_pick_card.dart';
import 'package:bolsio/app/chat/widgets/cards/balance_card.dart';
import 'package:bolsio/app/chat/widgets/cards/expense_card.dart';
import 'package:bolsio/app/chat/widgets/chat_empty_state.dart';
import 'package:bolsio/app/chat/widgets/chat_input_bar.dart';
import 'package:bolsio/app/chat/widgets/suggest_chips.dart';
import 'package:bolsio/app/chat/widgets/typing_dots.dart';
import 'package:bolsio/app/chat/widgets/user_bubble.dart';
import 'package:bolsio/app/chat/widgets/bolsio_ai_markdown.dart';
import 'package:bolsio/app/chat/widgets/bolsio_ai_orb.dart';
import 'package:bolsio/app/common/widgets/user_avatar_display.dart';
import 'package:bolsio/app/transactions/voice_input/voice_record_overlay.dart';
import 'package:bolsio/core/database/services/account/account_service.dart';
import 'package:bolsio/core/database/services/category/category_service.dart';
import 'package:bolsio/core/database/services/user-setting/user_setting_service.dart';
import 'package:bolsio/core/services/ai/agents/agent_run_result.dart';
import 'package:bolsio/core/services/ai/agents/bolsio_ai_agent.dart';
import 'package:bolsio/core/services/voice/voice_permission_dialog.dart';
import 'package:bolsio/i18n/generated/translations.g.dart';

class BolsioChatPage extends StatefulWidget {
  const BolsioChatPage({super.key});

  @override
  State<BolsioChatPage> createState() => _BolsioChatPageState();
}

class _BolsioChatPageState extends State<BolsioChatPage> {
  final _messages = <_ChatMessage>[];
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  final _inputFocus = FocusNode();
  final _agent = BolsioAiAgent();
  final _cardDispatcher = const ChatCardDispatcher();

  bool _isBooting = true;
  bool _isSending = false;
  bool _isUsingTools = false;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    _inputFocus.dispose();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    final aiEnabled = appStateSettings[SettingKey.nexusAiEnabled] == '1';
    final chatEnabled = appStateSettings[SettingKey.aiChatEnabled] == '1';

    if (!mounted) return;
    final t = Translations.of(context).bolsio_ai;

    if (!aiEnabled || !chatEnabled) {
      setState(() {
        _isBooting = false;
        _messages.add(
          _ChatMessage(role: 'assistant', text: t.chat_disabled),
        );
      });
      return;
    }

    setState(() {
      _isBooting = false;
    });
  }

  Future<void> _onMicTap() async {
    if (_isSending) return;
    final t = Translations.of(context).bolsio_ai;

    final outcome = await ensureMicPermissionWithExplainer(context);
    if (outcome != VoicePermissionOutcome.granted) {
      if (outcome == VoicePermissionOutcome.denied && mounted) {
        showMicPermissionDeniedSnackbar(context);
      }
      return;
    }
    if (!mounted) return;

    final transcript = await showVoiceRecordOverlay(context, locale: 'es_VE');
    if (!mounted) return;
    if (transcript == null) return;

    final trimmed = transcript.trim();
    if (trimmed.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(t.voice_empty_transcript)),
      );
      return;
    }

    _controller.text = trimmed;
    await _sendToAgent(userText: trimmed);
  }

  Future<void> _send() {
    final text = _controller.text.trim();
    if (text.isEmpty || _isSending) return Future.value();
    return _sendToAgent(userText: text);
  }

  Future<void> _sendToAgent({required String userText}) async {
    _controller.clear();

    setState(() {
      _isSending = true;
      _isUsingTools = false;
      _messages.add(_ChatMessage(role: 'user', text: userText));
      _messages.add(const _ChatMessage(role: 'assistant', text: ''));
    });
    _scrollToBottom();

    try {
      final history = _messages
          .where((m) =>
              m.text.isNotEmpty &&
              (m.role == 'user' || m.role == 'assistant'))
          .take(12)
          .map((m) => <String, dynamic>{'role': m.role, 'content': m.text})
          .toList();

      final result = await _agent.run(
        history: history,
        onTextChunk: _appendChunkToLastAssistant,
      );

      await _handleAgentResult(result);
    } catch (_) {
      _replaceLastAssistantWithError();
    } finally {
      if (mounted) {
        setState(() {
          _isSending = false;
          _isUsingTools = false;
        });
        _scrollToBottom();
      }
    }
  }

  /// Live token-by-token append for the last assistant bubble. Wired into
  /// the agent's `onTextChunk` so the UI renders the model's reply as it
  /// arrives — no second HTTP roundtrip needed.
  void _appendChunkToLastAssistant(String chunk) {
    if (!mounted || chunk.isEmpty) return;
    setState(() {
      if (_messages.isEmpty || _messages.last.role != 'assistant') {
        _messages.add(_ChatMessage(role: 'assistant', text: chunk));
        return;
      }
      final last = _messages.removeLast();
      _messages.add(_ChatMessage(
        role: last.role,
        text: '${last.text}$chunk',
        kind: last.kind,
        card: last.card,
      ));
    });
    _scrollToBottom();
  }

  Future<void> _handleAgentResult(AgentRunResult result) async {
    if (!mounted) return;
    final t = Translations.of(context).bolsio_ai;

    switch (result.status) {
      case AgentRunStatus.finalText:
        // The text was streamed live via `onTextChunk` while the request was
        // in flight. The placeholder bubble already holds the full answer; we
        // just need to (a) cover the edge case where the model returned no
        // content, and (b) try to append a structured card if a tool ran in
        // a previous loop iteration.
        final liveText =
            (_messages.isNotEmpty && _messages.last.role == 'assistant')
                ? _messages.last.text
                : '';
        final fallbackText = result.finalText?.isNotEmpty == true
            ? result.finalText!
            : t.chat_error_generic;
        if (liveText.isEmpty) {
          _replaceLastAssistant(fallbackText);
        }
        await _maybeAppendCardFromMessages(result.messages);
      case AgentRunStatus.needsApproval:
        await _handleApprovals(result);
      case AgentRunStatus.loopCapReached:
        _replaceLastAssistant(t.chat_error_loop_cap);
      case AgentRunStatus.proposal:
        _replaceLastAssistant(
          result.finalText?.isNotEmpty == true
              ? result.finalText!
              : t.voice_save_success_manual,
        );
      case AgentRunStatus.error:
        // Log the diagnostic code so we can correlate stuck-bubble reports
        // with provider hiccups (invalid tool args, dispatch crash, empty
        // stream) without surfacing the raw code to the user.
        debugPrint(
          '[BOLSIO_CHAT] agent run returned error code='
          '${result.error ?? 'unknown'}',
        );
        // If the placeholder bubble was never filled by streaming, either
        // replace it (if it exists and is empty) or insert a fresh bubble so
        // the user always sees something instead of a muted screen.
        final hasEmptyAssistantBubble = _messages.isNotEmpty &&
            _messages.last.role == 'assistant' &&
            _messages.last.text.isEmpty;
        final hasFilledAssistantBubble = _messages.isNotEmpty &&
            _messages.last.role == 'assistant' &&
            _messages.last.text.isNotEmpty;
        if (hasFilledAssistantBubble) {
          // Partial text leaked before the error — keep it and append a new
          // assistant bubble with the error so context isn't lost.
          if (mounted) {
            setState(() {
              _messages.add(_ChatMessage(
                role: 'assistant',
                text: t.chat_error_generic,
              ));
            });
            _scrollToBottom();
          }
        } else if (hasEmptyAssistantBubble) {
          _replaceLastAssistantWithError();
        } else {
          // Defensive fallback: no assistant bubble exists at all.
          if (mounted) {
            setState(() {
              _messages.add(_ChatMessage(
                role: 'assistant',
                text: t.chat_error_generic,
              ));
            });
            _scrollToBottom();
          }
        }
    }
  }

  Future<void> _maybeAppendCardFromMessages(
    List<Map<String, dynamic>> messages,
  ) async {
    try {
      final toolRoles = messages.where((m) => m['role'] == 'tool').toList();
      final assistantToolCalls = messages
          .where((m) =>
              m['role'] == 'assistant' &&
              m['tool_calls'] is List &&
              (m['tool_calls'] as List).isNotEmpty)
          .toList();
      debugPrint(
        '[BOLSIO_CHAT_CARDS] scan: total=${messages.length} '
        'toolMsgs=${toolRoles.length} assistantWithCalls=${assistantToolCalls.length}',
      );

      Map<String, dynamic>? lastAssistantWithCalls;
      Map<String, dynamic>? lastToolMsg;
      for (final m in messages.reversed) {
        if (lastToolMsg == null && m['role'] == 'tool') {
          lastToolMsg = m;
          continue;
        }
        if (lastToolMsg != null &&
            m['role'] == 'assistant' &&
            m['tool_calls'] is List &&
            (m['tool_calls'] as List).isNotEmpty) {
          lastAssistantWithCalls = m;
          break;
        }
      }

      if (lastToolMsg == null || lastAssistantWithCalls == null) {
        debugPrint(
          '[BOLSIO_CHAT_CARDS] no tool/assistant pair found — agent did not '
          'call tools this turn',
        );
        return;
      }

      final callId = lastToolMsg['tool_call_id']?.toString();
      final calls = lastAssistantWithCalls['tool_calls'] as List;
      Map<String, dynamic>? matchedCall;
      for (final c in calls.cast<Map<String, dynamic>>()) {
        if (c['id']?.toString() == callId) {
          matchedCall = c;
          break;
        }
      }
      matchedCall ??= calls.first as Map<String, dynamic>;

      final fn = matchedCall['function'] as Map<String, dynamic>?;
      final toolName = (fn?['name'] as String?) ?? '';
      if (toolName.isEmpty) {
        debugPrint('[BOLSIO_CHAT_CARDS] abort: empty toolName');
        return;
      }

      Map<String, dynamic> args = <String, dynamic>{};
      final argsJson = fn?['arguments']?.toString();
      if (argsJson != null && argsJson.isNotEmpty) {
        try {
          final decoded = jsonDecode(argsJson);
          if (decoded is Map<String, dynamic>) args = decoded;
        } catch (_) {}
      }

      final rawJson = lastToolMsg['content']?.toString() ?? '';
      final rawPreview = rawJson.length > 180
          ? '${rawJson.substring(0, 180)}…'
          : rawJson;
      final payload = await _cardDispatcher.fromToolResult(
        toolName: toolName,
        args: args,
        rawJson: rawJson,
      );
      debugPrint(
        '[BOLSIO_CHAT_CARDS] dispatch tool=$toolName '
        'argKeys=${args.keys.toList()} cardProduced=${payload != null} '
        'rawPreview=$rawPreview',
      );
      if (payload == null || !mounted) return;

      setState(() {
        String? intro;
        if (_messages.isNotEmpty &&
            _messages.last.role == 'assistant' &&
            _messages.last.kind == ChatMessageKind.text) {
          final prev = _messages.removeLast();
          final sanitized = stripRedundantStructuredText(prev.text);
          if (sanitized.isNotEmpty && sanitized.length <= 200) {
            intro = sanitized;
          }
        }
        _messages.add(_ChatMessage(
          role: 'assistant',
          text: intro ?? '',
          kind: ChatMessageKind.card,
          card: payload,
        ));
      });
      _scrollToBottom();
    } catch (e, st) {
      debugPrint('[BOLSIO_CHAT_CARDS] dispatch failed: $e\n$st');
    }
  }

  void _onAccountPickTap(String accountId) {
    // Reuse the standard send path so the agent sees a normal user turn.
    _sendToAgent(userText: 'Usa la cuenta $accountId');
  }

  // Chips after data cards auto-send (vs empty-state cards which pre-fill):
  // data-card chips are terse follow-ups; pre-fill would add friction.
  void _onChipTap(String prompt) {
    if (_isSending) return;
    _sendToAgent(userText: prompt);
  }

  List<String> _chipsFor(ChatCardPayload payload) {
    return switch (payload) {
      ExpensePayload() => const [
          'Compara con mes pasado',
          '¿Dónde puedo recortar?',
          'Top 3 categorías',
        ],
      BalancePayload() => const [
          'Detalle por cuenta',
          'Proyección a fin de mes',
          '¿Cuánto puedo ahorrar?',
        ],
      AccountPickPayload() => const <String>[],
    };
  }

  Widget _buildCard(ChatCardPayload payload) {
    return switch (payload) {
      ExpensePayload() => ExpenseCard(payload),
      BalancePayload() => BalanceCard(payload),
      AccountPickPayload() => AccountPickCard(
          payload,
          onTap: _onAccountPickTap,
        ),
    };
  }

  Future<void> _handleApprovals(AgentRunResult result) async {
    // Render the "consultando tus datos" indicator while tools are pending.
    if (mounted) setState(() => _isUsingTools = true);

    final messages = List<Map<String, dynamic>>.from(result.messages);

    for (final pending in result.pendingApprovals) {
      if (!mounted) return;
      // Resolve human labels for account/category ids before rendering the
      // sheet so the user sees "Cuenta principal" instead of raw UUIDs.
      final resolvedArgs = await _resolveToolArgLabels(
        pending.toolName,
        pending.arguments,
      );
      if (!mounted) return;
      final approved = await showToolApprovalSheet(
        context,
        toolName: pending.toolName,
        arguments: resolvedArgs,
      );
      if (!mounted) return;

      if (approved == true) {
        final dispatchResult = await _agent.profile.toolRegistry.dispatch(
          pending.toolName,
          pending.arguments,
        );
        messages.add(<String, dynamic>{
          'role': 'tool',
          'tool_call_id': pending.toolCallId,
          'name': pending.toolName,
          'content': dispatchResult.toModelJson(),
        });
      } else {
        messages.add(<String, dynamic>{
          'role': 'tool',
          'tool_call_id': pending.toolCallId,
          'name': pending.toolName,
          'content': jsonEncode(<String, dynamic>{'error': 'user_rejected'}),
        });
      }
    }

    if (!mounted) return;
    // Make sure there's a placeholder bubble for the post-approval reply so
    // the live token stream has a target to append into.
    if (_messages.isEmpty || _messages.last.role != 'assistant') {
      setState(() {
        _messages.add(const _ChatMessage(role: 'assistant', text: ''));
      });
    } else if (_messages.last.text.isNotEmpty) {
      setState(() {
        _messages.add(const _ChatMessage(role: 'assistant', text: ''));
      });
    }
    final resumed = await _agent.resume(
      messages: messages,
      onTextChunk: _appendChunkToLastAssistant,
    );
    await _handleAgentResult(resumed);
  }

  Future<Map<String, dynamic>> _resolveToolArgLabels(
    String toolName,
    Map<String, dynamic> args,
  ) async {
    final resolved = Map<String, dynamic>.from(args);

    Future<String?> accountName(Object? id) async {
      if (id == null) return null;
      final acc =
          await AccountService.instance.getAccountById(id.toString()).first;
      return acc?.name;
    }

    Future<String?> categoryName(Object? id) async {
      if (id == null) return null;
      final cat =
          await CategoryService.instance.getCategoryById(id.toString()).first;
      return cat?.name;
    }

    if (toolName == 'create_transaction') {
      final accName = await accountName(args['accountId']);
      if (accName != null) resolved['__accountLabel'] = accName;
      final catName = await categoryName(args['categoryId']);
      if (catName != null) resolved['__categoryLabel'] = catName;
    } else if (toolName == 'create_transfer') {
      final fromName = await accountName(args['fromAccountId']);
      if (fromName != null) resolved['__fromAccountLabel'] = fromName;
      final toName = await accountName(args['toAccountId']);
      if (toName != null) resolved['__toAccountLabel'] = toName;
    }
    return resolved;
  }

  void _replaceLastAssistant(String text) {
    if (!mounted) return;
    setState(() {
      if (_messages.isNotEmpty && _messages.last.role == 'assistant') {
        _messages.removeLast();
      }
      _messages.add(_ChatMessage(role: 'assistant', text: text));
    });
  }

  void _replaceLastAssistantWithError() {
    if (!mounted) return;
    final t = Translations.of(context).bolsio_ai;
    _replaceLastAssistant(t.chat_error_generic);
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final t = Translations.of(context).bolsio_ai;

    // Perf-fix #1: hoist every appStateSettings read out of the widget tree so
    // rebuilds do not re-hash the settings map repeatedly mid-frame. The
    // avatar id is read once per build and passed down as a plain String.
    final nexusAiEnabled =
        appStateSettings[SettingKey.nexusAiEnabled] == '1';
    final aiVoiceEnabled =
        appStateSettings[SettingKey.aiVoiceEnabled] != '0';
    final voiceAffordance = nexusAiEnabled && aiVoiceEnabled;
    final avatarId = appStateSettings[SettingKey.avatar] ?? 'man';

    if (_isBooting) {
      return Scaffold(
        appBar: _buildAppBar(t),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            spacing: 16,
            children: [
              CircularProgressIndicator(color: cs.primary),
              Text(
                t.chat_boot_loading,
                style: TextStyle(color: cs.onSurfaceVariant),
              ),
            ],
          ),
        ),
      );
    }

    final typingLabel = _isUsingTools ? 'Ejecutando…' : 'Pensando…';

    return Scaffold(
      appBar: _buildAppBar(t),
      body: Column(
        children: [
          Expanded(
            child: _messages.isEmpty
                ? ChatEmptyState(
                    onSuggestionTap: (p) => _sendToAgent(userText: p),
                  )
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
                    itemCount: _messages.length,
                    itemBuilder: (context, index) {
                      final message = _messages[index];
                      final isUser = message.role == 'user';
                      final isThinking =
                          !isUser &&
                              message.kind == ChatMessageKind.text &&
                              message.text.isEmpty &&
                              _isSending;

                      if (message.kind == ChatMessageKind.card &&
                          message.card != null) {
                        final chips = _chipsFor(message.card!);
                        return Padding(
                          padding: const EdgeInsets.only(
                            bottom: BolsioAiTokens.bubbleGap,
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (message.text.isNotEmpty) ...[
                                Align(
                                  alignment: Alignment.centerLeft,
                                  child: AiBubble(
                                    child: RepaintBoundary(
                                      child: BolsioAiMarkdown(
                                        data: message.text,
                                        onUser: false,
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(
                                  height: BolsioAiTokens.bubbleGap,
                                ),
                              ],
                              Align(
                                alignment: Alignment.centerLeft,
                                child: _buildCard(message.card!),
                              ),
                              if (chips.isNotEmpty)
                                SuggestChips(
                                  suggestions: chips,
                                  onTap: _onChipTap,
                                  padding: const EdgeInsets.only(
                                    top: BolsioAiTokens.bubbleGap,
                                    left: 4,
                                  ),
                                ),
                            ],
                          ),
                        );
                      }

                      return Padding(
                        padding: const EdgeInsets.only(
                          bottom: BolsioAiTokens.bubbleGap,
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: isUser
                              ? MainAxisAlignment.end
                              : MainAxisAlignment.start,
                          children: [
                            Flexible(
                              child: isThinking
                                  ? Align(
                                      alignment: Alignment.centerLeft,
                                      child: TypingDots(label: typingLabel),
                                    )
                                  : isUser
                                  ? Align(
                                      alignment: Alignment.centerRight,
                                      child: UserBubble(text: message.text),
                                    )
                                  : Align(
                                      alignment: Alignment.centerLeft,
                                      child: AiBubble(
                                        child: RepaintBoundary(
                                          child: BolsioAiMarkdown(
                                            data: message.text,
                                            onUser: false,
                                          ),
                                        ),
                                      ),
                                    ),
                            ),
                            if (isUser) ...[
                              const SizedBox(width: BolsioAiTokens.bubbleGap / 1.5),
                              UserAvatarDisplay(avatar: avatarId, size: 24),
                            ],
                          ],
                        ),
                      );
                    },
                  ),
          ),
          ChatInputBar(
            controller: _controller,
            focusNode: _inputFocus,
            hint: _isUsingTools
                ? t.chat_input_hint_using_tools
                : t.chat_input_hint_default,
            isSending: _isSending,
            isUsingTools: _isUsingTools,
            voiceAffordance: voiceAffordance,
            onSend: () => _send(),
            onMicTap: voiceAffordance ? () => _onMicTap() : null,
          ),
        ],
      ),
    );
  }

  PreferredSizeWidget _buildAppBar(TranslationsBolsioAiEn t) {
    return AppBar(
      title: Row(
        spacing: 10,
        children: [
          const BolsioAiOrb(size: 28, showGlow: false),
          Text(t.chat_header),
        ],
      ),
    );
  }

}

enum ChatMessageKind { text, card }

class _ChatMessage {
  final String role;
  final String text;
  final ChatMessageKind kind;
  final ChatCardPayload? card;

  const _ChatMessage({
    required this.role,
    required this.text,
    this.kind = ChatMessageKind.text,
    this.card,
  });
}

/// Bottom sheet asking the user to approve a mutating tool call emitted by the
/// chat agent. Returns `true` on approve, `false` on reject, `null` if the
/// sheet was dismissed (treated as reject upstream).
///
/// [arguments] may contain the following synthetic keys injected by the chat
/// page, which take precedence over raw ids in the summary rows:
///  - `__accountLabel`, `__categoryLabel`
///  - `__fromAccountLabel`, `__toAccountLabel`
Future<bool?> showToolApprovalSheet(
  BuildContext context, {
  required String toolName,
  required Map<String, dynamic> arguments,
}) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) => _ToolApprovalSheet(
      toolName: toolName,
      arguments: arguments,
    ),
  );
}

class _ToolApprovalSheet extends StatelessWidget {
  const _ToolApprovalSheet({
    required this.toolName,
    required this.arguments,
  });

  final String toolName;
  final Map<String, dynamic> arguments;

  String _titleFor(TranslationsBolsioAiEn t) {
    switch (toolName) {
      case 'create_transaction':
        final type = arguments['type'] as String?;
        return type == 'income'
            ? t.chat_tool_create_transaction_income
            : t.chat_tool_create_transaction_expense;
      case 'create_transfer':
        return t.chat_tool_create_transfer;
      default:
        return t.chat_tool_generic_confirm;
    }
  }

  IconData get _icon {
    switch (toolName) {
      case 'create_transaction':
        final type = arguments['type'] as String?;
        return type == 'income'
            ? Icons.trending_up_rounded
            : Icons.shopping_bag_rounded;
      case 'create_transfer':
        return Icons.swap_horiz_rounded;
      default:
        return Icons.auto_awesome_rounded;
    }
  }

  List<_Summary> _summaryLines(TranslationsBolsioAiEn t) {
    switch (toolName) {
      case 'create_transaction':
        final categoryLabel = arguments['__categoryLabel']?.toString() ??
            arguments['categoryId']?.toString();
        final accountLabel = arguments['__accountLabel']?.toString() ??
            arguments['accountId']?.toString();
        return [
          if (arguments['amount'] != null)
            _Summary(t.chat_tool_field_amount, _fmtAmount(arguments['amount'])),
          if (arguments['type'] != null)
            _Summary(
              t.chat_tool_field_type,
              arguments['type'] == 'income'
                  ? t.chat_tool_field_type_income
                  : t.chat_tool_field_type_expense,
            ),
          if (arguments['title'] != null &&
              (arguments['title'] as String).isNotEmpty)
            _Summary(
              t.chat_tool_field_description,
              arguments['title'].toString(),
            ),
          if (categoryLabel != null)
            _Summary(t.chat_tool_field_category, categoryLabel),
          if (accountLabel != null)
            _Summary(t.chat_tool_field_account, accountLabel),
          if (arguments['date'] != null)
            _Summary(t.chat_tool_field_date, arguments['date'].toString()),
        ];
      case 'create_transfer':
        final fromLabel = arguments['__fromAccountLabel']?.toString() ??
            arguments['fromAccountId']?.toString();
        final toLabel = arguments['__toAccountLabel']?.toString() ??
            arguments['toAccountId']?.toString();
        return [
          if (arguments['amount'] != null)
            _Summary(t.chat_tool_field_amount, _fmtAmount(arguments['amount'])),
          if (fromLabel != null)
            _Summary(t.chat_tool_field_from_account, fromLabel),
          if (toLabel != null)
            _Summary(t.chat_tool_field_to_account, toLabel),
          if (arguments['valueInDestiny'] != null)
            _Summary(
              t.chat_tool_field_value_in_destiny,
              _fmtAmount(arguments['valueInDestiny']),
            ),
          if (arguments['title'] != null &&
              (arguments['title'] as String).isNotEmpty)
            _Summary(
              t.chat_tool_field_description,
              arguments['title'].toString(),
            ),
        ];
      default:
        return arguments.entries
            .where((e) => !e.key.startsWith('__'))
            .map((e) => _Summary(e.key, e.value.toString()))
            .toList();
    }
  }

  static String _fmtAmount(Object? raw) {
    if (raw is num) return raw.toStringAsFixed(2);
    return raw?.toString() ?? '';
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final t = Translations.of(context).bolsio_ai;
    final lines = _summaryLines(t);

    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 4,
          bottom: 20 + MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: cs.primaryContainer,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(_icon, color: cs.primary, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    _titleFor(t),
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              t.chat_tool_review_subtitle,
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: cs.onSurfaceVariant),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: cs.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: lines.isEmpty
                    ? [
                        Text(
                          t.chat_tool_no_details,
                          style: TextStyle(color: cs.onSurfaceVariant),
                        ),
                      ]
                    : lines
                        .map((l) => Padding(
                              padding: const EdgeInsets.symmetric(vertical: 4),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  SizedBox(
                                    width: 110,
                                    child: Text(
                                      l.label,
                                      style: TextStyle(
                                        color: cs.onSurfaceVariant,
                                        fontSize: 13,
                                      ),
                                    ),
                                  ),
                                  Expanded(
                                    child: Text(
                                      l.value,
                                      style: TextStyle(
                                        color: cs.onSurface,
                                        fontSize: 14,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ))
                        .toList(),
              ),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(false),
                    child: Text(t.chat_tool_cta_cancel),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () => Navigator.of(context).pop(true),
                    icon: const Icon(Icons.check_rounded),
                    label: Text(t.chat_tool_cta_approve),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Summary {
  final String label;
  final String value;
  const _Summary(this.label, this.value);
}
