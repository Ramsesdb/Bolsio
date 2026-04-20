import 'dart:async';
import 'dart:ui';

// ignore: unused_import
import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:wallex/app/accounts/account_selector.dart';
import 'package:wallex/app/chat/widgets/voice_action_buttons.dart';
import 'package:wallex/app/categories/selectors/category_picker.dart';
import 'package:wallex/app/transactions/form/dialogs/amount_selector.dart';
import 'package:wallex/app/transactions/form/transaction_form.page.dart';
import 'package:wallex/core/database/services/account/account_service.dart';
import 'package:wallex/core/database/services/category/category_service.dart';
import 'package:wallex/core/database/services/currency/currency_service.dart';
import 'package:wallex/core/database/services/transaction/transaction_service.dart';
import 'package:wallex/core/database/utils/drift_utils.dart';
import 'package:wallex/core/extensions/color.extensions.dart';
import 'package:wallex/core/models/account/account.dart';
import 'package:wallex/core/models/auto_import/transaction_proposal.dart';
import 'package:wallex/core/models/category/category.dart';
import 'package:wallex/core/models/currency/currency.dart';
import 'package:wallex/core/models/supported-icon/icon_displayer.dart';
import 'package:wallex/core/models/transaction/transaction_status.enum.dart';
import 'package:wallex/core/models/transaction/transaction_type.enum.dart';
import 'package:wallex/core/database/app_db.dart';
import 'package:wallex/core/presentation/helpers/snackbar.dart';
import 'package:wallex/core/presentation/widgets/number_ui_formatters/currency_displayer.dart';
import 'package:wallex/core/routes/route_utils.dart';
import 'package:wallex/core/utils/date_time_picker.dart';
import 'package:wallex/core/utils/uuid.dart';
import 'package:wallex/i18n/generated/translations.g.dart';

/// Review + auto-confirm sheet shown after the quick-expense agent returns a
/// [TransactionProposal] from a voice transcript.
///
/// Visual skin: Wallex Liquid Glass voice review sheet — blurred 62% sheet
/// with drag handle, auto-save pill (top-right), three glass edit chips
/// (descripción / monto / categoría), account row, "Editar más" + "Guardar"
/// actions. Business logic (auto-confirm countdown, picker delegation, DB
/// insert, undo snackbar, form escalation) is preserved from the previous
/// implementation.
Future<void> showVoiceReviewSheet(
  BuildContext context, {
  required TransactionProposal proposal,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useRootNavigator: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.35),
    // We draw our own drag handle inside the glass panel.
    showDragHandle: false,
    builder: (_) => _VoiceReviewSheet(proposal: proposal),
  );
}

String _formatReviewDate(BuildContext context, DateTime date) {
  final t = Translations.of(context).wallex_ai;
  final now = DateTime.now();
  final isSameDay =
      date.year == now.year && date.month == now.month && date.day == now.day;
  final timeLabel = DateFormat('HH:mm', 'es').format(date);
  if (isSameDay) {
    return '${t.voice_review_date_today} $timeLabel';
  }
  final dateFormat = date.year == now.year
      ? DateFormat('d MMM', 'es')
      : DateFormat('d MMM yyyy', 'es');
  return '${dateFormat.format(date)} · $timeLabel';
}

// Wallex palette tokens — neutral-only. The accent is resolved per-build
// from Theme.of(context).colorScheme.primary so the sheet follows the user's
// selected accent (or Material You dynamic color) instead of the legacy
// hardcoded mustard. See [_kAccentOf].
const Color _kExpenseRed = Color(0xFFF75959);
const Color _kIncomeGreen = Color(0xFF4CAF50);
const Color _kSheetTint = Color.fromRGBO(22, 22, 22, 0.62);
const Color _kHairline = Color.fromRGBO(255, 255, 255, 0.08);
const Color _kChipTint = Color.fromRGBO(255, 255, 255, 0.05);
const Color _kRowTint = Color.fromRGBO(255, 255, 255, 0.04);

Color _kAccentOf(BuildContext context) =>
    Theme.of(context).colorScheme.primary;
Color _kChipBorderOf(BuildContext context) =>
    _kAccentOf(context).withValues(alpha: 0.30);

class _VoiceReviewSheet extends StatefulWidget {
  const _VoiceReviewSheet({required this.proposal});

  final TransactionProposal proposal;

  @override
  State<_VoiceReviewSheet> createState() => _VoiceReviewSheetState();
}

class _VoiceReviewSheetState extends State<_VoiceReviewSheet> {
  static const _autoConfirmDelay = Duration(seconds: 20);
  static const _undoDuration = Duration(seconds: 6);

  late double _amount;
  late TransactionType _type;
  String? _description;
  Account? _account;
  Category? _category;
  DateTime _date = DateTime.now();
  // Currency extracted by the LLM from the transcript (e.g. "$10" -> USD).
  // The amount chip displays this currency, not the account's, so the user
  // sees what they voiced. A hint appears below when it differs from the
  // account currency.
  Currency? _proposalCurrency;

  Timer? _autoConfirmTimer;
  double _autoSecondsLeft = 0; // fractional so the ring progress is smooth
  Timer? _tickTimer;
  DateTime? _tickStart;
  bool _autoConfirmPaused = false;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    final p = widget.proposal;
    _amount = p.amount.abs();
    _type = p.type;
    _description = (p.counterpartyName != null &&
            p.counterpartyName!.trim().isNotEmpty)
        ? p.counterpartyName
        : null;
    // Defense-in-depth: if the LLM slipped through a clearly stale date
    // (older than 7 days) despite the tool's own guard, fall back to now.
    // Voice capture is always about "right now" unless the user overrode
    // the date explicitly in the review sheet.
    final now = DateTime.now();
    _date = p.date.isBefore(now.subtract(const Duration(days: 7)))
        ? now
        : p.date;

    unawaited(_hydrateReferences());
  }

  Future<void> _hydrateReferences() async {
    final p = widget.proposal;
    Account? account;
    if (p.accountId != null) {
      account = await AccountService.instance.getAccountById(p.accountId!).first;
      debugPrint(
        'VoiceReviewSheet account path: proposal.accountId="${p.accountId}" '
        '-> resolved="${account?.name}" (${account?.id})',
      );
    }
    if (account == null) {
      account = await _firstUsableAccount();
      debugPrint(
        'VoiceReviewSheet account path: fallback firstUsableAccount '
        '(displayOrder asc, non-saving, open) -> "${account?.name}" '
        '(${account?.id})',
      );
    }

    Category? category;
    if (p.proposedCategoryId != null && _type.isIncomeOrExpense) {
      category = await CategoryService.instance
          .getCategoryById(p.proposedCategoryId!)
          .first;
    }

    Currency? proposalCurrency;
    if (p.currencyId.trim().isNotEmpty) {
      proposalCurrency =
          await CurrencyService.instance.getCurrencyByCode(p.currencyId).first;
    }

    if (!mounted) return;
    setState(() {
      _account = account;
      _category = category;
      _proposalCurrency = proposalCurrency;
    });
    _maybeStartAutoConfirm();
  }

  Future<Account?> _firstUsableAccount() async {
    final accounts = await AccountService.instance
        .getAccounts(
          predicate: (acc, _) => buildDriftExpr([
            acc.type.equalsValue(AccountType.saving).not(),
            acc.closingDate.isNull(),
          ]),
          limit: 1,
        )
        .first;
    return accounts.isNotEmpty ? accounts.first : null;
  }

  bool get _canAutoConfirm {
    if (_autoConfirmPaused) return false;
    if (_amount <= 0) return false;
    if (_account == null) return false;
    if (_type.isIncomeOrExpense && _category == null) return false;
    return true;
  }

  void _maybeStartAutoConfirm() {
    _autoConfirmTimer?.cancel();
    _tickTimer?.cancel();
    if (!_canAutoConfirm) {
      setState(() => _autoSecondsLeft = 0);
      return;
    }
    _tickStart = DateTime.now();
    setState(
      () => _autoSecondsLeft = _autoConfirmDelay.inSeconds.toDouble(),
    );
    // Sub-second ticker so the circular progress animates smoothly.
    _tickTimer = Timer.periodic(const Duration(milliseconds: 60), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      final elapsed = DateTime.now().difference(_tickStart!).inMilliseconds;
      final left = (_autoConfirmDelay.inMilliseconds - elapsed) / 1000.0;
      setState(() {
        _autoSecondsLeft = left.clamp(0.0, 999.0);
      });
      if (_autoSecondsLeft <= 0) timer.cancel();
    });
    _autoConfirmTimer = Timer(_autoConfirmDelay, () {
      if (!mounted) return;
      unawaited(_save(auto: true));
    });
  }

  void _pauseAutoConfirm() {
    _autoConfirmTimer?.cancel();
    _tickTimer?.cancel();
    if (!_autoConfirmPaused) {
      setState(() {
        _autoConfirmPaused = true;
        _autoSecondsLeft = 0;
      });
    } else {
      setState(() => _autoSecondsLeft = 0);
    }
  }

  Future<void> _editAmount() async {
    _pauseAutoConfirm();
    final t = Translations.of(context).wallex_ai;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => AmountSelector(
        title: t.chat_tool_field_amount,
        initialAmount: _amount,
        enableSignToggleButton: _type.isIncomeOrExpense,
        currency: _proposalCurrency ?? _account?.currency,
        onSubmit: (value) {
          if (mounted) {
            setState(() => _amount = value.abs());
          }
          RouteUtils.popRoute();
        },
      ),
    );
  }

  Future<void> _editCategory() async {
    _pauseAutoConfirm();
    final picked = await showCategoryPickerModal(
      context,
      modal: CategoryPicker(
        selectedCategory: _category,
        categoryType: _type == TransactionType.income
            ? [CategoryType.I, CategoryType.B]
            : [CategoryType.E, CategoryType.B],
      ),
    );
    if (picked != null && mounted) {
      setState(() => _category = picked);
    }
  }

  Future<void> _editDescription() async {
    _pauseAutoConfirm();
    final t = Translations.of(context).wallex_ai;
    final controller = TextEditingController(text: _description ?? '');
    final result = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.fromLTRB(
            20,
            8,
            20,
            20 + MediaQuery.of(ctx).viewInsets.bottom,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                t.voice_review_description_placeholder,
                style: Theme.of(ctx).textTheme.titleMedium,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                autofocus: true,
                decoration: InputDecoration(
                  border: const OutlineInputBorder(),
                  hintText: t.voice_review_description_hint,
                ),
                onSubmitted: (v) => Navigator.of(ctx).pop(v.trim()),
              ),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: () =>
                    Navigator.of(ctx).pop(controller.text.trim()),
                child: Text(t.voice_done),
              ),
            ],
          ),
        );
      },
    );
    if (result != null && mounted) {
      setState(() => _description = result.isEmpty ? null : result);
    }
  }

  Future<void> _editDate() async {
    _pauseAutoConfirm();
    final picked = await openDateTimePicker(
      context,
      initialDate: _date,
      showTimePickerAfterDate: true,
    );
    if (picked != null && mounted) {
      setState(() => _date = picked);
    }
  }

  Future<void> _editAccount() async {
    _pauseAutoConfirm();
    List<Account>? picked;
    try {
      picked = await showAccountSelectorBottomSheet(
        context,
        AccountSelectorModal(
          allowMultiSelection: false,
          filterSavingAccounts: _type.isIncomeOrExpense,
          includeArchivedAccounts: false,
          selectedAccounts: _account != null ? [_account!] : const [],
        ),
      );
      debugPrint(
        'VoiceReviewSheet._editAccount: picker returned '
        '${picked?.map((a) => '${a.name}(${a.id})').toList()}',
      );
    } catch (e, st) {
      debugPrint('VoiceReviewSheet._editAccount: picker threw $e\n$st');
      if (!mounted) return;
      final t = Translations.of(context).wallex_ai;
      WallexSnackbar.error(SnackbarParams(t.voice_validation_account_missing));
      return;
    }
    if (!mounted) return;
    if (picked == null || picked.isEmpty) return;
    final newAccount = picked.first;
    // Belt-and-suspenders: tapping a freshly picked account can rebuild the
    // sheet with a different currency. Any surprise (missing currency field,
    // FX-lookup failure inside a descendant, stream still in flight) would
    // otherwise bubble up as an "Unhandled Exception" and crash the root
    // navigator. Swallow the exception, log, and warn — the user can try
    // again or fall back to the full form via "Editar más".
    try {
      // User picked this account manually: chip should show its currency.
      // Amount value stays, currency label follows the account (no FX).
      setState(() => _account = newAccount);
      final newCurrency = await CurrencyService.instance
          .getCurrencyByCode(newAccount.currency.code)
          .first;
      if (!mounted) return;
      setState(() => _proposalCurrency = newCurrency);
    } catch (e, st) {
      debugPrint(
        'VoiceReviewSheet._editAccount: setState failed $e\n$st',
      );
      if (!mounted) return;
      final t = Translations.of(context).wallex_ai;
      WallexSnackbar.error(
        SnackbarParams(t.voice_validation_account_missing, message: '$e'),
      );
    }
  }

  Future<void> _save({bool auto = false}) async {
    if (_isSaving) return;
    _autoConfirmTimer?.cancel();
    _tickTimer?.cancel();
    final t = Translations.of(context).wallex_ai;

    if (_amount <= 0) {
      WallexSnackbar.warning(
        SnackbarParams(t.voice_validation_amount_zero),
      );
      return;
    }
    if (_account == null) {
      WallexSnackbar.warning(
        SnackbarParams(t.voice_validation_account_missing),
      );
      return;
    }
    if (_type.isIncomeOrExpense && _category == null) {
      WallexSnackbar.warning(
        SnackbarParams(t.voice_validation_category_missing),
      );
      return;
    }

    setState(() => _isSaving = true);

    final newId = generateUUID();
    final signedValue =
        _type == TransactionType.expense ? -_amount : _amount;
    final title = _description?.trim();
    final rawTranscript = widget.proposal.rawText.trim().isEmpty
        ? null
        : widget.proposal.rawText.trim();

    final tx = TransactionInDB(
      id: newId,
      date: _date,
      value: signedValue,
      isHidden: false,
      type: _type,
      accountID: _account!.id,
      categoryID: _type.isIncomeOrExpense ? _category?.id : null,
      status: _date.isAfter(DateTime.now())
          ? TransactionStatus.pending
          : TransactionStatus.reconciled,
      title: (title != null && title.isNotEmpty) ? title : null,
      notes: rawTranscript,
      createdAt: DateTime.now(),
    );

    try {
      await TransactionService.instance.insertTransaction(tx);
    } catch (e) {
      if (!mounted) return;
      setState(() => _isSaving = false);
      WallexSnackbar.error(SnackbarParams.fromError(e));
      return;
    }

    if (!mounted) return;
    Navigator.of(context).pop();

    WallexSnackbar.success(
      SnackbarParams(
        auto ? t.voice_save_success_auto : t.voice_save_success_manual,
        duration: _undoDuration,
        actions: [
          WallexSnackbarAction(
            label: t.voice_save_undo_label,
            onPressed: () async {
              await TransactionService.instance.deleteTransaction(newId);
              WallexSnackbar.info(
                SnackbarParams(
                  t.voice_save_undo_success,
                  duration: const Duration(seconds: 2),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Future<void> _escalateToForm() async {
    _autoConfirmTimer?.cancel();
    _tickTimer?.cancel();

    final updated = widget.proposal.copyWith(
      amount: _amount,
      currencyId: _proposalCurrency?.code ??
          _account?.currency.code ??
          widget.proposal.currencyId,
      date: _date,
      type: _type,
      accountId: _account?.id,
      counterpartyName: _description,
      proposedCategoryId: _category?.id,
    );

    if (!mounted) return;
    Navigator.of(context).pop();
    await RouteUtils.pushRoute(
      TransactionFormPage.fromVoice(voicePrefill: updated),
    );
  }

  @override
  void dispose() {
    _autoConfirmTimer?.cancel();
    _tickTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = Translations.of(context).wallex_ai;
    final mq = MediaQuery.of(context);
    // Min height so we still fit content when keyboard is closed.
    final sheetHeight = (mq.size.height * 0.62).clamp(500.0, 780.0).toDouble();
    final showAuto = !_autoConfirmPaused && _autoSecondsLeft > 0;

    return Padding(
      padding: EdgeInsets.only(bottom: mq.viewInsets.bottom),
      child: SizedBox(
        height: sheetHeight,
        width: double.infinity,
        child: ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
            child: DecoratedBox(
              decoration: const BoxDecoration(
                color: _kSheetTint,
                border: Border(
                  top: BorderSide(color: _kHairline, width: 0.5),
                  left: BorderSide(color: _kHairline, width: 0.5),
                  right: BorderSide(color: _kHairline, width: 0.5),
                ),
                borderRadius:
                    BorderRadius.vertical(top: Radius.circular(28)),
              ),
              child: Stack(
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const SizedBox(height: 10),
                      Center(
                        child: Container(
                          width: 40,
                          height: 5,
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.22),
                            borderRadius: BorderRadius.circular(3),
                          ),
                        ),
                      ),
                      // Header
                      Padding(
                        padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              t.voice_review_title,
                              style: const TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
                                letterSpacing: -0.4,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              t.voice_review_tap_to_edit,
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.white.withValues(alpha: 0.5),
                                letterSpacing: -0.1,
                              ),
                            ),
                          ],
                        ),
                      ),
                      // Transcript quote (if present)
                      if (widget.proposal.rawText.trim().isNotEmpty)
                        Padding(
                          padding:
                              const EdgeInsets.fromLTRB(24, 10, 24, 0),
                          child: Text(
                            '"${widget.proposal.rawText.trim()}"',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 13,
                              fontStyle: FontStyle.italic,
                              color: Colors.white.withValues(alpha: 0.45),
                            ),
                          ),
                        ),
                      // Horizontal scroll of edit chips (Monto, Categoria,
                      // Fecha, Descripcion). A right-edge fade hints at the
                      // scrollability while keeping the sheet compact.
                      Padding(
                        padding: const EdgeInsets.fromLTRB(0, 16, 0, 4),
                        child: Builder(
                          builder: (context) {
                            const chipWidth = 168.0;
                            const chipHeight = 110.0;
                            const gap = 12.0;
                            final displayCurrency =
                                _proposalCurrency ?? _account?.currency;
                            final amountValue = _amount > 0
                                ? FittedBox(
                                    fit: BoxFit.scaleDown,
                                    alignment: Alignment.centerLeft,
                                    child: DefaultTextStyle(
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 22,
                                        fontWeight: FontWeight.w600,
                                        letterSpacing: -0.5,
                                        height: 1.1,
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        crossAxisAlignment:
                                            CrossAxisAlignment.baseline,
                                        textBaseline:
                                            TextBaseline.alphabetic,
                                        children: [
                                          CurrencyDisplayer(
                                            amountToConvert: _amount,
                                            currency: displayCurrency,
                                            followPrivateMode: false,
                                            integerStyle: const TextStyle(
                                              color: Colors.white,
                                              fontSize: 22,
                                              fontWeight: FontWeight.w600,
                                              letterSpacing: -0.5,
                                            ),
                                          ),
                                          if (displayCurrency?.code != null &&
                                              displayCurrency!
                                                  .code.isNotEmpty)
                                            Padding(
                                              padding: const EdgeInsets
                                                  .only(left: 6),
                                              child: Text(
                                                displayCurrency.code,
                                                style: TextStyle(
                                                  fontSize: 12,
                                                  fontWeight: FontWeight.w500,
                                                  color: Colors.white
                                                      .withValues(
                                                          alpha: 0.45),
                                                ),
                                              ),
                                            ),
                                        ],
                                      ),
                                    ),
                                  )
                                : Text(
                                    t.voice_review_amount_placeholder,
                                    style: TextStyle(
                                      color: Colors.white
                                          .withValues(alpha: 0.6),
                                      fontSize: 22,
                                      fontWeight: FontWeight.w600,
                                      letterSpacing: -0.5,
                                      height: 1.1,
                                    ),
                                  );
                            final categoryValue = Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  width: 6,
                                  height: 6,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: _category != null
                                        ? ColorHex.get(_category!.color)
                                        : _kExpenseRed,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Flexible(
                                  child: FittedBox(
                                    fit: BoxFit.scaleDown,
                                    alignment: Alignment.centerLeft,
                                    child: Text(
                                      _category?.name ??
                                          t.voice_review_category_none,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 22,
                                        fontWeight: FontWeight.w600,
                                        letterSpacing: -0.5,
                                        height: 1.1,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            );
                            final dateValue = FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: Alignment.centerLeft,
                              child: Text(
                                _formatReviewDate(context, _date),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 22,
                                  fontWeight: FontWeight.w600,
                                  letterSpacing: -0.5,
                                  height: 1.1,
                                ),
                              ),
                            );
                            final descriptionValue = FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: Alignment.centerLeft,
                              child: Text(
                                _description ??
                                    t.voice_review_description_placeholder,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 22,
                                  fontWeight: FontWeight.w600,
                                  letterSpacing: -0.5,
                                  height: 1.1,
                                ),
                              ),
                            );
                            final chips = <Widget>[
                              SizedBox(
                                width: chipWidth,
                                height: chipHeight,
                                child: _EditChip(
                                  icon: _AmountTypeBadge(type: _type),
                                  label:
                                      t.voice_review_amount_placeholder,
                                  valueWidget: amountValue,
                                  active: _amount > 0,
                                  onTap: _editAmount,
                                ),
                              ),
                              SizedBox(
                                width: chipWidth,
                                height: chipHeight,
                                child: _EditChip(
                                  icon: _CategoryChipIcon(
                                      category: _category),
                                  label:
                                      t.voice_review_category_placeholder,
                                  valueWidget: categoryValue,
                                  active: false,
                                  onTap: _editCategory,
                                ),
                              ),
                              SizedBox(
                                width: chipWidth,
                                height: chipHeight,
                                child: _EditChip(
                                  icon: Icon(
                                    Icons.event_rounded,
                                    size: 16,
                                    color: Colors.white
                                        .withValues(alpha: 0.75),
                                  ),
                                  label:
                                      t.voice_review_date_placeholder,
                                  valueWidget: dateValue,
                                  active: false,
                                  onTap: _editDate,
                                ),
                              ),
                              SizedBox(
                                width: chipWidth,
                                height: chipHeight,
                                child: _EditChip(
                                  icon: const Text('📝',
                                      style: TextStyle(fontSize: 16)),
                                  label:
                                      t.voice_review_description_placeholder,
                                  valueWidget: descriptionValue,
                                  active: false,
                                  onTap: _editDescription,
                                ),
                              ),
                            ];
                            return SizedBox(
                              height: chipHeight,
                              child: ShaderMask(
                                shaderCallback: (bounds) {
                                  return const LinearGradient(
                                    begin: Alignment.centerLeft,
                                    end: Alignment.centerRight,
                                    stops: [0.0, 0.88, 1.0],
                                    colors: [
                                      Colors.white,
                                      Colors.white,
                                      Colors.transparent,
                                    ],
                                  ).createShader(bounds);
                                },
                                blendMode: BlendMode.dstIn,
                                child: SingleChildScrollView(
                                  scrollDirection: Axis.horizontal,
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 20),
                                  physics:
                                      const BouncingScrollPhysics(),
                                  child: Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      for (var i = 0;
                                          i < chips.length;
                                          i++) ...[
                                        if (i > 0)
                                          const SizedBox(width: gap),
                                        chips[i],
                                      ],
                                    ],
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                      // Account row
                      Padding(
                        padding:
                            const EdgeInsets.fromLTRB(24, 10, 24, 0),
                        child: _AccountRow(
                          account: _account,
                          placeholder:
                              t.voice_review_account_placeholder,
                          onTap: _editAccount,
                        ),
                      ),
                      if (_proposalCurrency != null &&
                          _account != null &&
                          _proposalCurrency!.code.toUpperCase() !=
                              _account!.currency.code.toUpperCase())
                        Padding(
                          padding:
                              const EdgeInsets.fromLTRB(28, 8, 28, 0),
                          child: Row(
                            children: [
                              Icon(
                                Icons.swap_horiz_rounded,
                                size: 14,
                                color: Colors.white
                                    .withValues(alpha: 0.55),
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  'La cuenta es en ${_account!.currency.code}, '
                                  'el monto fue dicho en '
                                  '${_proposalCurrency!.code}. Se convertira '
                                  'al guardar.',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: Colors.white
                                        .withValues(alpha: 0.6),
                                    fontStyle: FontStyle.italic,
                                    letterSpacing: -0.1,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                  // Auto-save pill (top right)
                  if (showAuto)
                    Positioned(
                      top: 16,
                      right: 16,
                      child: _AutoSavePill(
                        secondsLeft: _autoSecondsLeft,
                        total: _autoConfirmDelay.inSeconds.toDouble(),
                        onCancel: _pauseAutoConfirm,
                      ),
                    ),
                  // Bottom actions — unified X + Enviar pair shared across
                  // every voice surface. "Editar más" stays as a secondary
                  // text affordance above the row so no existing action
                  // is lost (cancel ≡ close sheet, send ≡ save proposal).
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: SafeArea(
                      top: false,
                      minimum: const EdgeInsets.only(bottom: 14),
                      child: Padding(
                        padding:
                            const EdgeInsets.fromLTRB(20, 8, 20, 6),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Align(
                              alignment: Alignment.centerLeft,
                              child: TextButton(
                                onPressed:
                                    _isSaving ? null : _escalateToForm,
                                style: TextButton.styleFrom(
                                  foregroundColor: _kAccentOf(context),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 4,
                                  ),
                                  minimumSize: const Size(0, 32),
                                  tapTargetSize:
                                      MaterialTapTargetSize.shrinkWrap,
                                ),
                                child: Text(
                                  t.voice_review_edit_more,
                                  style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    letterSpacing: -0.1,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 6),
                            VoiceActionButtons(
                              onCancel: _isSaving
                                  ? () {}
                                  : () =>
                                      Navigator.of(context).maybePop(),
                              onSend:
                                  _isSaving ? null : () => _save(),
                              sendLabel: t.voice_review_save,
                              isSending: _isSaving,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────────────────
// EditChip — translucent glass card (168×110) with label + value
// ──────────────────────────────────────────────────────────────────────
class _EditChip extends StatelessWidget {
  const _EditChip({
    required this.icon,
    required this.label,
    required this.valueWidget,
    required this.active,
    required this.onTap,
  });

  final Widget icon;
  final String label;
  final Widget valueWidget;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final accent = _kAccentOf(context);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          height: 110,
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
          decoration: BoxDecoration(
            color: _kChipTint,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: active ? accent : _kChipBorderOf(context),
              width: 1,
            ),
            boxShadow: active
                ? [
                    BoxShadow(
                      color: accent.withValues(alpha: 0.13),
                      blurRadius: 0,
                      spreadRadius: 3,
                    ),
                  ]
                : null,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  SizedBox(
                    width: 18,
                    height: 18,
                    child: Center(child: icon),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.white.withValues(alpha: 0.55),
                      fontWeight: FontWeight.w500,
                      letterSpacing: 0.1,
                    ),
                  ),
                ],
              ),
              valueWidget,
            ],
          ),
        ),
      ),
    );
  }
}

class _AmountTypeBadge extends StatelessWidget {
  const _AmountTypeBadge({required this.type});
  final TransactionType type;

  @override
  Widget build(BuildContext context) {
    final isIncome = type == TransactionType.income;
    final color = isIncome ? _kIncomeGreen : _kExpenseRed;
    final glyph = isIncome ? '+' : '−';
    return Container(
      width: 18,
      height: 18,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color.withValues(alpha: 0.13),
      ),
      child: Center(
        child: Text(
          glyph,
          style: TextStyle(
            color: color,
            fontSize: 11,
            fontWeight: FontWeight.w700,
            height: 1,
          ),
        ),
      ),
    );
  }
}

class _CategoryChipIcon extends StatelessWidget {
  const _CategoryChipIcon({required this.category});
  final Category? category;

  @override
  Widget build(BuildContext context) {
    final c = category;
    if (c == null) {
      return Icon(
        Icons.category_outlined,
        size: 16,
        color: Colors.white.withValues(alpha: 0.7),
      );
    }
    return IconDisplayer(
      mainColor: ColorHex.get(c.color),
      supportedIcon: c.icon,
      size: 14,
      padding: 2,
      borderRadius: 99999,
    );
  }
}

// ──────────────────────────────────────────────────────────────────────
// Auto-save pill with circular progress ring
// ──────────────────────────────────────────────────────────────────────
class _AutoSavePill extends StatelessWidget {
  const _AutoSavePill({
    required this.secondsLeft,
    required this.total,
    required this.onCancel,
  });

  final double secondsLeft;
  final double total;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final pct = total <= 0 ? 0.0 : (secondsLeft / total).clamp(0.0, 1.0);
    final accent = _kAccentOf(context);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onCancel,
        borderRadius: BorderRadius.circular(9999),
        child: Container(
          padding:
              const EdgeInsets.fromLTRB(8, 6, 12, 6),
          decoration: BoxDecoration(
            color: accent.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(9999),
            border: Border.all(
              color: accent.withValues(alpha: 0.33),
              width: 0.5,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 22,
                height: 22,
                child: CustomPaint(
                  painter: _AutoRingPainter(progress: pct, accent: accent),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                Translations.of(context).wallex_ai.voice_review_auto_countdown(
                      seconds: secondsLeft.ceil(),
                    ),
                style: TextStyle(
                  color: accent,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.2,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AutoRingPainter extends CustomPainter {
  _AutoRingPainter({required this.progress, required this.accent});
  final double progress;
  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = 9.0;
    final track = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = accent.withValues(alpha: 0.25);
    canvas.drawCircle(center, radius, track);

    final fg = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round
      ..color = accent;
    final sweep = 6.28318 * progress;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -1.5708, // -90deg start
      sweep,
      false,
      fg,
    );
  }

  @override
  bool shouldRepaint(covariant _AutoRingPainter old) =>
      old.progress != progress || old.accent != accent;
}

// ──────────────────────────────────────────────────────────────────────
// Account row — icon chip + name + chevron
// ──────────────────────────────────────────────────────────────────────
class _AccountRow extends StatelessWidget {
  const _AccountRow({
    required this.account,
    required this.placeholder,
    required this.onTap,
  });

  final Account? account;
  final String placeholder;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = Translations.of(context).wallex_ai;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          decoration: BoxDecoration(
            color: _kRowTint,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.08),
              width: 0.5,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: account != null
                      ? Colors.white
                      : Colors.white.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  Icons.account_balance_rounded,
                  size: 20,
                  color: account != null
                      ? Theme.of(context).colorScheme.primary
                      : Colors.white.withValues(alpha: 0.6),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      t.voice_review_account_label.toUpperCase(),
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.white.withValues(alpha: 0.5),
                        letterSpacing: 0.3,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      account?.name ?? placeholder,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 15,
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                        letterSpacing: -0.2,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                color: Colors.white.withValues(alpha: 0.35),
                size: 20,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

