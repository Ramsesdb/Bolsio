import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:wallex/core/database/services/user-setting/user_setting_service.dart';
import 'package:wallex/core/presentation/widgets/user_avatar.dart';
import 'package:wallex/core/services/ai/financial_context_builder.dart';
import 'package:wallex/core/services/ai/nexus_ai_service.dart';

class WallexChatPage extends StatefulWidget {
  const WallexChatPage({super.key});

  @override
  State<WallexChatPage> createState() => _WallexChatPageState();
}

class _WallexChatPageState extends State<WallexChatPage> {
  final _messages = <_ChatMessage>[];
  final _controller = TextEditingController();
  final _scrollController = ScrollController();

  bool _isBooting = true;
  bool _isSending = false;
  String _financialContext = '';

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    final aiEnabled = appStateSettings[SettingKey.nexusAiEnabled] == '1';
    final chatEnabled = appStateSettings[SettingKey.aiChatEnabled] == '1';

    if (!aiEnabled || !chatEnabled) {
      setState(() {
        _isBooting = false;
        _messages.add(
          const _ChatMessage(
            role: 'assistant',
            text: 'El chat de IA esta deshabilitado en configuracion.',
          ),
        );
      });
      return;
    }

    final ctx = await FinancialContextBuilder.instance.buildContext();

    if (!mounted) return;

    setState(() {
      _financialContext = ctx;
      _isBooting = false;
      _messages.add(
        const _ChatMessage(
          role: 'assistant',
          text: 'Hola! Soy **Wallex AI**, tu asistente financiero.\n\n'
              'Puedo ayudarte con:\n'
              '- Ver saldos y estado de tus cuentas\n'
              '- Analizar tus gastos por categoria\n'
              '- Revisar transacciones recientes\n'
              '- Consultar presupuestos\n\n'
              'Que deseas revisar?',
        ),
      );
    });
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _isSending) return;

    _controller.clear();

    setState(() {
      _isSending = true;
      _messages.add(_ChatMessage(role: 'user', text: text));
      _messages.add(const _ChatMessage(role: 'assistant', text: ''));
    });

    _scrollToBottom();

    var receivedAnyChunk = false;

    try {
      final history = _messages
          .where((m) => m.text.isNotEmpty)
          .take(12)
          .map((m) => {
                'role': m.role,
                'content': m.text,
              })
          .toList();

      final stream = NexusAiService.instance.streamComplete(
        temperature: 0.7,
        messages: [
          {
            'role': 'system',
            'content':
                'Eres Wallex AI, un asistente financiero personal. '
                'Respondes SIEMPRE en espanol. Se conciso y directo.\n'
                'Reglas de formato:\n'
                '- Usa **negritas** para montos de dinero (ej: **\$432.50**)\n'
                '- Usa *cursivas* para porcentajes y comparaciones (ej: *12% menos*)\n'
                '- Usa tablas con | para datos tabulares (cuentas, categorias)\n'
                '- Usa listas con - para enumerar\n'
                '- Numeros siempre con 2 decimales\n\n'
                '$_financialContext',
          },
          ...history,
        ],
      );

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
        setState(() {
          _messages.removeLast();
          _messages.add(
            const _ChatMessage(
              role: 'assistant',
              text: 'No pude procesar tu pregunta, intenta de nuevo.',
            ),
          );
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _messages.removeLast();
          _messages.add(
            const _ChatMessage(
              role: 'assistant',
              text: 'No pude procesar tu pregunta, intenta de nuevo.',
            ),
          );
        });
      }
    } finally {
      if (mounted) {
        setState(() => _isSending = false);
        _scrollToBottom();
      }
    }
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

    return Scaffold(
      appBar: AppBar(
        title: Row(
          spacing: 10,
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: cs.primaryContainer,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(Icons.auto_awesome_rounded, size: 20, color: cs.primary),
            ),
            const Text('Wallex AI'),
          ],
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: _isBooting
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      spacing: 16,
                      children: [
                        CircularProgressIndicator(color: cs.primary),
                        Text(
                          'Cargando contexto financiero...',
                          style: TextStyle(color: cs.onSurfaceVariant),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
                    itemCount: _messages.length + (_isSending && !_messages.last.text.isNotEmpty ? 0 : 0),
                    itemBuilder: (context, index) {
                      final message = _messages[index];
                      final isUser = message.role == 'user';
                      final isThinking = !isUser && message.text.isEmpty && _isSending;

                      return Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment:
                              isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
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
                                    bottomLeft: Radius.circular(isUser ? 18 : 4),
                                    bottomRight: Radius.circular(isUser ? 4 : 18),
                                  ),
                                  border: isUser
                                      ? null
                                      : Border.all(
                                          color: cs.primary.withValues(alpha: 0.1),
                                          width: 0.5,
                                        ),
                                ),
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
                                        : MarkdownBody(
                                            data: message.text,
                                            selectable: true,
                                            styleSheet: _aiMarkdownStyle(cs),
                                          ),
                              ),
                            ),
                            if (isUser) ...[
                              const SizedBox(width: 8),
                              UserAvatar(
                                avatar: appStateSettings[SettingKey.avatar] ?? 'man',
                                size: 24,
                              ),
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
              border: Border(top: BorderSide(color: cs.outlineVariant, width: 0.5)),
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
                          hintText: 'Pregunta sobre tus finanzas...',
                          hintStyle: TextStyle(color: cs.onSurfaceVariant),
                        ),
                      ),
                    ),
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
                            : Icon(Icons.send_rounded, size: 20, color: cs.onPrimary),
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
      tableCellsPadding:
          const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
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
