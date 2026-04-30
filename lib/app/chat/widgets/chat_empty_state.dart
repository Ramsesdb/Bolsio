import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:bolsio/app/chat/theme/bolsio_ai_tokens.dart';
import 'package:bolsio/app/chat/widgets/bolsio_ai_orb.dart';
import 'package:bolsio/core/database/app_db.dart';
import 'package:bolsio/core/database/services/account/account_service.dart';
import 'package:bolsio/core/database/services/currency/currency_service.dart';
import 'package:bolsio/core/database/services/transaction/transaction_service.dart';
import 'package:bolsio/core/database/services/user-setting/hidden_mode_service.dart';
import 'package:bolsio/core/database/services/user-setting/private_mode_service.dart';
import 'package:bolsio/core/database/services/user-setting/user_setting_service.dart';
import 'package:bolsio/core/extensions/color.extensions.dart';
import 'package:bolsio/core/models/currency/currency.dart';
import 'package:bolsio/core/models/transaction/transaction_type.enum.dart';
import 'package:bolsio/core/presentation/widgets/number_ui_formatters/ui_number_formatter.dart';
import 'package:bolsio/core/presentation/widgets/transaction_filter/transaction_filter_set.dart';

class ChatEmptyState extends StatefulWidget {
  const ChatEmptyState({super.key, required this.onSuggestionTap});

  final void Function(String prompt) onSuggestionTap;

  @override
  State<ChatEmptyState> createState() => _ChatEmptyStateState();
}

class _ChatEmptyStateState extends State<ChatEmptyState> {
  String? _totalBalance;
  String? _monthExpense;
  String? _topCategory;
  String? _monthsLeft;

  StreamSubscription<List<String>>? _visibleIdsSub;
  List<String>? _lastVisibleIds;

  @override
  void initState() {
    super.initState();
    _monthsLeft = _computeMonthsLeft();
    _visibleIdsSub = HiddenModeService.instance.visibleAccountIdsStream.listen((
      ids,
    ) {
      _lastVisibleIds = ids;
      _loadPreviewValues();
    });
  }

  @override
  void dispose() {
    _visibleIdsSub?.cancel();
    super.dispose();
  }

  String _computeMonthsLeft() {
    final now = DateTime.now();
    final remaining = 12 - now.month;
    if (remaining <= 0) return 'Este mes';
    return '$remaining ${remaining == 1 ? "mes" : "meses"}';
  }

  Future<void> _loadPreviewValues() async {
    try {
      final currency = await CurrencyService.instance
          .ensureAndGetPreferredCurrency(listenToChanges: false)
          .first;

      final visibleIds = _lastVisibleIds;

      await Future.wait<void>([
        _loadTotalBalance(currency, visibleIds),
        _loadMonthStats(currency, visibleIds),
      ]);
    } catch (e, st) {
      debugPrint('ChatEmptyState preview load failed: $e\n$st');
    }
  }

  // WHY filter by visibleIds: mirrors dashboard `_visibleAccountsStream()` in
  // lib/app/home/dashboard.page.dart — when Hidden Mode is locked, saving
  // accounts are excluded from the total so the pill matches what the user
  // sees on the Saldo total indicator.
  Future<void> _loadTotalBalance(
    Currency currency,
    List<String>? visibleIds,
  ) async {
    try {
      final accountService = AccountService.instance;
      final accounts = await accountService.getAccounts().first;
      final filtered = visibleIds == null
          ? accounts
          : accounts.where((a) => visibleIds.contains(a.id)).toList();
      double total = 0.0;
      for (final account in filtered) {
        final balance = await accountService
            .getAccountMoney(
              account: account,
              convertToPreferredCurrency: true,
            )
            .first;
        total += balance;
      }
      if (!mounted) return;
      setState(() {
        _totalBalance = _formatMoney(total, currency);
      });
    } catch (e) {
      debugPrint('ChatEmptyState totalBalance failed: $e');
    }
  }

  // WHY filter by visibleIds: dashboard's income/expense cards pass the same
  // Hidden Mode filter (see dashboard.page.dart `TransactionFilterSet(accountsIDs: visibleIds)`),
  // so the month expense and top category are computed without savings-account
  // transactions while locked.
  Future<void> _loadMonthStats(
    Currency currency,
    List<String>? visibleIds,
  ) async {
    try {
      final now = DateTime.now();
      final fromDate = DateTime(now.year, now.month, 1);
      final toDate = DateTime(now.year, now.month + 1, 1);

      final transactions = await TransactionService.instance
          .getTransactions(
            filters: TransactionFilterSet(
              minDate: fromDate,
              maxDate: toDate,
              transactionTypes: const [TransactionType.expense],
              accountsIDs: visibleIds,
            ),
          )
          .first;

      final perCategory = <String, double>{};
      final categoryNames = <String, String>{};
      double total = 0.0;

      for (final tx in transactions) {
        final category = tx.category;
        if (category == null) continue;
        final amount = (tx.currentValueInPreferredCurrency ?? tx.value).abs();
        if (amount == 0) continue;
        perCategory[category.id] = (perCategory[category.id] ?? 0) + amount;
        categoryNames[category.id] = category.name;
        total += amount;
      }

      String? topName;
      double topAmount = -1;
      perCategory.forEach((id, amt) {
        if (amt > topAmount) {
          topAmount = amt;
          topName = categoryNames[id];
        }
      });

      if (!mounted) return;
      setState(() {
        _monthExpense = _formatMoney(total, currency);
        _topCategory = topName != null ? 'Top: $topName' : 'Sin datos';
      });
    } catch (e) {
      debugPrint('ChatEmptyState monthStats failed: $e');
    }
  }

  String _formatMoney(double amount, CurrencyInDB currency) {
    return UINumberFormatter.currency(
      amountToConvert: amount,
      currency: currency,
    ).getFormattedAmount();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = BolsioAiTokens.of(context);
    final accentDeep = tokens.accent.darken(0.1);

    final prompts = <_Prompt>[
      _Prompt(
        label: '¿Cuánto gasté este mes?',
        icon: Icons.trending_down,
        preview: _monthExpense,
        blurWithPrivateMode: true,
      ),
      _Prompt(
        label: '¿Dónde se fue mi dinero?',
        icon: Icons.pie_chart_outline,
        preview: _topCategory,
        blurWithPrivateMode: true,
      ),
      _Prompt(
        label: 'Proyecta diciembre',
        icon: Icons.calendar_month,
        preview: _monthsLeft,
        blurWithPrivateMode: false,
      ),
      _Prompt(
        label: 'Saldo total',
        icon: Icons.account_balance_wallet,
        preview: _totalBalance,
        blurWithPrivateMode: true,
      ),
    ];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        children: [
          const Spacer(),
          const BolsioAiOrb(size: 120, showGlow: true, animated: true),
          const SizedBox(height: 24),
          RichText(
            textAlign: TextAlign.center,
            text: TextSpan(
              style: TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.5,
                color: tokens.text,
                height: 1.15,
              ),
              children: [
                const TextSpan(text: 'Qué quieres saber\n'),
                const TextSpan(text: 'de '),
                TextSpan(
                  text: 'tu dinero hoy',
                  style: TextStyle(color: accentDeep),
                ),
                const TextSpan(text: '?'),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'Pregunta con texto o voz · Responde con datos reales',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: tokens.muted,
            ),
          ),
          const SizedBox(height: 28),
          for (int i = 0; i < prompts.length; i++) ...[
            if (i > 0) const SizedBox(height: 8),
            _PromptPill(
              prompt: prompts[i],
              onTap: widget.onSuggestionTap,
            ),
          ],
          const Spacer(),
        ],
      ),
    );
  }
}

class _Prompt {
  const _Prompt({
    required this.label,
    required this.icon,
    required this.preview,
    required this.blurWithPrivateMode,
  });

  final String label;
  final IconData icon;
  final String? preview;
  final bool blurWithPrivateMode;
}

class _PromptPill extends StatelessWidget {
  const _PromptPill({required this.prompt, required this.onTap});

  final _Prompt prompt;
  final void Function(String prompt) onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = BolsioAiTokens.of(context);
    final preview = prompt.preview;

    return Material(
      color: tokens.bubbleAi,
      borderRadius: BorderRadius.circular(BolsioAiTokens.innerCardRadius),
      child: InkWell(
        onTap: () => onTap(prompt.label),
        borderRadius: BorderRadius.circular(BolsioAiTokens.innerCardRadius),
        child: Container(
          height: 52,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(
              BolsioAiTokens.innerCardRadius,
            ),
            border: Border.all(color: tokens.border, width: 1),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 20,
                height: 20,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: tokens.accent.withValues(alpha: 0.12),
                ),
                alignment: Alignment.center,
                child: Icon(prompt.icon, size: 12, color: tokens.accent),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  prompt.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: tokens.text,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              _buildPreview(context, tokens, preview),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPreview(
    BuildContext context,
    BolsioAiTokens tokens,
    String? preview,
  ) {
    final text = Text(
      preview ?? '—',
      style: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w800,
        color: preview == null ? tokens.fainter : tokens.accent,
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
    );

    if (!prompt.blurWithPrivateMode || preview == null) return text;

    return StreamBuilder<bool>(
      stream: PrivateModeService.instance.privateModeStream,
      initialData: appStateSettings[SettingKey.privateModeAtLaunch] == '1',
      builder: (context, snapshot) {
        final sigma = (snapshot.data ?? false) ? 7.5 : 0.0;
        return ImageFiltered(
          imageFilter: ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
          child: text,
        );
      },
    );
  }
}
