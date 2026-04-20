import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:wallex/app/common/widgets/user_avatar_display.dart';
import 'package:wallex/app/transactions/voice_input/voice_record_overlay.dart';
import 'package:wallex/core/database/services/account/account_service.dart';
import 'package:wallex/core/database/services/category/category_service.dart';
import 'package:wallex/core/database/services/user-setting/user_setting_service.dart';
import 'package:wallex/core/services/ai/agents/agent_run_result.dart';
import 'package:wallex/core/services/ai/agents/wallex_ai_agent.dart';
import 'package:wallex/core/services/ai/nexus_ai_service.dart';
import 'package:wallex/core/services/voice/voice_permission_dialog.dart';
import 'package:wallex/i18n/generated/translations.g.dart';

class WallexChatPage extends StatefulWidget {
  const WallexChatPage({super.key});

  @override
  State<WallexChatPage> createState() => _WallexChatPageState();
}

class _WallexChatPageState extends State<WallexChatPage> {
  final _messages = <_ChatMessage>[];
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  final _inputFocus = FocusNode();
  final _agent = WallexAiAgent();

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
    final t = Translations.of(context).wallex_ai;

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
      _messages.add(
        _ChatMessage(role: 'assistant', text: t.chat_welcome_message),
      );
    });
  }

  Future<void> _onMicTap() async {
    if (_isSending) return;
    final t = Translations.of(context).wallex_ai;

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

      final result = await _agent.run(history: history);

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

  Future<void> _handleAgentResult(AgentRunResult result) async {
    if (!mounted) return;
    final t = Translations.of(context).wallex_ai;

    switch (result.status) {
      case AgentRunStatus.streamFinalText:
        // Preserve byte-for-byte streaming UX for the plain text-only path.
        await _streamFinalText(result.messages);
      case AgentRunStatus.finalText:
        _replaceLastAssistant(
          result.finalText?.isNotEmpty == true
              ? result.finalText!
              : t.chat_error_generic,
        );
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
        _replaceLastAssistantWithError();
    }
  }

  Future<void> _streamFinalText(List<Map<String, dynamic>> messages) async {
    final streamMessages = messages
        .map((m) => <String, String>{
              'role': (m['role'] ?? '').toString(),
              'content': (m['content'] ?? '').toString(),
            })
        .where((m) => m['role']!.isNotEmpty)
        .toList();

    final stream = NexusAiService.instance.streamComplete(
      temperature: 0.3,
      messages: streamMessages,
    );

    var receivedAnyChunk = false;
    await for (final chunk in stream) {
      if (!mounted) return;
      setState(() {
        final last = _messages.removeLast();
        final newText = receivedAnyChunk ? '${last.text}$chunk' : chunk;
        _messages.add(_ChatMessage(role: last.role, text: newText));
      });
      receivedAnyChunk = true;
      _scrollToBottom();
    }

    if (!receivedAnyChunk && mounted) {
      _replaceLastAssistantWithError();
    }
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
    final resumed = await _agent.resume(messages: messages);
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
    final t = Translations.of(context).wallex_ai;
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
    final t = Translations.of(context).wallex_ai;

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
        appBar: _buildAppBar(cs, t),
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

    return Scaffold(
      appBar: _buildAppBar(cs, t),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
              itemCount: _messages.length,
              itemBuilder: (context, index) {
                final message = _messages[index];
                final isUser = message.role == 'user';
                final isThinking =
                    !isUser && message.text.isEmpty && _isSending;

                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: isUser
                        ? MainAxisAlignment.end
                        : MainAxisAlignment.start,
                    children: [
                      if (!isUser) ...[
                        _buildAiAvatar(cs),
                        const SizedBox(width: 8),
                      ],
                      Flexible(
                        child: Container(
                          padding: EdgeInsets.symmetric(
                            horizontal: isUser ? 14 : 16,
                            vertical: isUser ? 10 : 14,
                          ),
                          decoration: BoxDecoration(
                            color: isUser
                                ? cs.primary
                                : cs.surfaceContainerHighest,
                            borderRadius: BorderRadius.only(
                              topLeft: const Radius.circular(18),
                              topRight: const Radius.circular(18),
                              bottomLeft: Radius.circular(
                                isUser ? 18 : 4,
                              ),
                              bottomRight: Radius.circular(
                                isUser ? 4 : 18,
                              ),
                            ),
                            border: isUser
                                ? null
                                : Border.all(
                                    color: cs.primary.withValues(
                                      alpha: 0.1,
                                    ),
                                    width: 0.5,
                                  ),
                          ),
                          // Perf-fix #3: wrap only the assistant markdown bubble
                          // in a RepaintBoundary so parent-driven rebuilds do
                          // not force MarkdownBody to re-parse on every keystroke.
                          child: isThinking
                              ? _buildTypingIndicator(cs)
                              : isUser
                              ? Text(
                                  message.text,
                                  style: TextStyle(
                                    color: cs.onPrimary,
                                    fontSize: 15,
                                  ),
                                )
                              : RepaintBoundary(
                                  child: MarkdownBody(
                                    data: message.text,
                                    selectable: true,
                                    styleSheet: _aiMarkdownStyle(cs),
                                  ),
                                ),
                        ),
                      ),
                      if (isUser) ...[
                        const SizedBox(width: 8),
                        UserAvatarDisplay(avatar: avatarId, size: 24),
                      ],
                    ],
                  ),
                );
              },
            ),
          ),
          DecoratedBox(
            decoration: BoxDecoration(
              color: cs.surfaceContainer,
              border: Border(
                top: BorderSide(color: cs.outlineVariant, width: 0.5),
              ),
            ),
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _controller,
                        focusNode: _inputFocus,
                        minLines: 1,
                        maxLines: 4,
                        textInputAction: TextInputAction.send,
                        onSubmitted: (_) => _send(),
                        style: const TextStyle(fontSize: 15),
                        decoration: InputDecoration(
                          filled: true,
                          fillColor: cs.surfaceContainerHighest,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(24),
                            borderSide: BorderSide.none,
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 10,
                          ),
                          hintText: _isUsingTools
                              ? t.chat_input_hint_using_tools
                              : t.chat_input_hint_default,
                          hintStyle: TextStyle(color: cs.onSurfaceVariant),
                        ),
                      ),
                    ),
                    if (voiceAffordance) ...[
                      const SizedBox(width: 6),
                      Container(
                        margin: const EdgeInsets.only(bottom: 2),
                        child: IconButton(
                          onPressed: _isSending ? null : _onMicTap,
                          style: IconButton.styleFrom(
                            backgroundColor: cs.surfaceContainerHighest,
                            shape: const CircleBorder(),
                            padding: const EdgeInsets.all(10),
                          ),
                          icon: Icon(
                            Icons.mic_rounded,
                            size: 20,
                            color: cs.primary,
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(width: 6),
                    Container(
                      margin: const EdgeInsets.only(bottom: 2),
                      child: IconButton.filled(
                        onPressed: _isSending ? null : _send,
                        style: IconButton.styleFrom(
                          backgroundColor: cs.primary,
                          disabledBackgroundColor: cs.surfaceContainerHighest,
                          shape: const CircleBorder(),
                          padding: const EdgeInsets.all(10),
                        ),
                        icon: _isSending
                            ? SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: cs.onSurfaceVariant,
                                ),
                              )
                            : Icon(
                                Icons.send_rounded,
                                size: 20,
                                color: cs.onPrimary,
                              ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  PreferredSizeWidget _buildAppBar(
    ColorScheme cs,
    TranslationsWallexAiEn t,
  ) {
    return AppBar(
      title: Row(
        spacing: 10,
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: cs.primaryContainer,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              Icons.auto_awesome_rounded,
              size: 20,
              color: cs.primary,
            ),
          ),
          Text(t.chat_header),
        ],
      ),
    );
  }

  MarkdownStyleSheet _aiMarkdownStyle(ColorScheme cs) {
    return MarkdownStyleSheet(
      p: TextStyle(color: cs.onSurface, fontSize: 15, height: 1.5),
      strong: TextStyle(
        color: cs.primary,
        fontWeight: FontWeight.w700,
        fontSize: 15,
      ),
      em: TextStyle(
        color: cs.tertiary,
        fontStyle: FontStyle.normal,
        fontWeight: FontWeight.w600,
        fontSize: 15,
      ),
      tableHead: TextStyle(
        color: cs.onSurface,
        fontWeight: FontWeight.w600,
        fontSize: 13,
      ),
      tableBody: TextStyle(color: cs.onSurfaceVariant, fontSize: 13),
      tableBorder: TableBorder.all(
        color: cs.outlineVariant.withValues(alpha: 0.5),
        width: 0.5,
      ),
      tableColumnWidth: const IntrinsicColumnWidth(),
      tableCellsPadding: const EdgeInsets.symmetric(
        horizontal: 10,
        vertical: 5,
      ),
      listBullet: TextStyle(color: cs.primary, fontSize: 15),
      h1: TextStyle(
        color: cs.onSurface,
        fontSize: 18,
        fontWeight: FontWeight.w700,
      ),
      h2: TextStyle(
        color: cs.onSurface,
        fontSize: 16,
        fontWeight: FontWeight.w600,
      ),
      h3: TextStyle(
        color: cs.onSurface,
        fontSize: 15,
        fontWeight: FontWeight.w600,
      ),
      code: TextStyle(
        color: cs.primary,
        backgroundColor: cs.primary.withValues(alpha: 0.1),
        fontSize: 13,
      ),
      blockSpacing: 10,
    );
  }

  Widget _buildAiAvatar(ColorScheme cs) {
    return Container(
      clipBehavior: Clip.hardEdge,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: cs.primaryContainer,
      ),
      child: SvgPicture.asset(
        'assets/icons/avatars/executive_woman.svg',
        height: 26,
        width: 26,
      ),
    );
  }

  Widget _buildTypingIndicator(ColorScheme cs) {
    return SizedBox(
      width: 48,
      height: 24,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        spacing: 4,
        children: List.generate(3, (i) {
          return TweenAnimationBuilder<double>(
            tween: Tween(begin: 0.0, end: 1.0),
            duration: Duration(milliseconds: 600 + i * 200),
            builder: (context, value, child) {
              return Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: cs.primary.withValues(alpha: 0.3 + 0.5 * value),
                  shape: BoxShape.circle,
                ),
              );
            },
          );
        }),
      ),
    );
  }
}

class _ChatMessage {
  final String role;
  final String text;

  const _ChatMessage({required this.role, required this.text});
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

  String _titleFor(TranslationsWallexAiEn t) {
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

  List<_Summary> _summaryLines(TranslationsWallexAiEn t) {
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
    final t = Translations.of(context).wallex_ai;
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
