import 'dart:math';

import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:wallex/app/layout/page_framework.dart';
import 'package:wallex/app/transactions/label_value_info_table.dart';
import 'package:wallex/app/transactions/utils/transaction_details.utils.dart';
import 'package:wallex/app/transactions/widgets/translucent_transaction_status_card.dart';
import 'package:wallex/core/database/services/currency/currency_service.dart';
import 'package:wallex/core/database/services/exchange-rate/exchange_rate_service.dart';
import 'package:wallex/core/database/services/transaction/transaction_service.dart';
import 'package:wallex/core/extensions/color.extensions.dart';
import 'package:wallex/core/extensions/padding.extension.dart';
import 'package:wallex/core/extensions/string.extension.dart';
import 'package:wallex/core/models/supported-icon/supported_icon.dart';
import 'package:wallex/core/models/tags/tag.dart';
import 'package:wallex/core/models/transaction/transaction.dart';
import 'package:wallex/core/models/transaction/transaction_status.enum.dart';
import 'package:wallex/core/presentation/helpers/snackbar.dart';
import 'package:wallex/core/presentation/theme.dart';
import 'package:wallex/core/presentation/widgets/card_with_header.dart';
import 'package:wallex/core/presentation/widgets/confirm_dialog.dart';
import 'package:wallex/core/presentation/widgets/wallex_quick_actions_buttons.dart';
import 'package:wallex/core/presentation/widgets/number_ui_formatters/currency_displayer.dart';
import 'package:wallex/core/database/services/debts/debt_service.dart';
import 'package:wallex/core/models/debt/debt.dart';
import 'package:wallex/core/routes/route_utils.dart';
import 'package:wallex/core/services/view-actions/transaction_view_actions_service.dart';
import 'package:wallex/core/utils/constants.dart';
import 'package:wallex/i18n/generated/translations.g.dart';

import '../../core/models/transaction/transaction_type.enum.dart';
import '../../core/presentation/app_colors.dart';

class TransactionDetailAction {
  final String label;
  final IconData icon;

  final void Function() onClick;

  TransactionDetailAction({
    required this.label,
    required this.icon,
    required this.onClick,
  });
}

class TransactionDetailsPage extends StatefulWidget {
  const TransactionDetailsPage({
    super.key,
    required this.transaction,
    required this.heroTag,
  });

  final MoneyTransaction transaction;

  final Object? heroTag;

  @override
  State<TransactionDetailsPage> createState() => _TransactionDetailsPageState();
}

class _TransactionDetailsPageState extends State<TransactionDetailsPage> {
  /// Maps exchange rate source codes to user-facing labels.
  String _exchangeRateSourceLabel(String? source) {
    switch (source) {
      case 'bcv':
        return 'BCV';
      case 'paralelo':
        return 'Paralelo';
      case 'manual':
        return 'Manual';
      case 'auto':
        return 'Automatica'; // TODO: i18n
      default:
        return source ?? 'Desconocida'; // TODO: i18n
    }
  }

  void showSkipTransactionModal(
    BuildContext context,
    MoneyTransaction transaction,
  ) {
    final nextPaymentDate = transaction.followingDateToNext;

    confirmDialog(
      context,
      dialogTitle: t.transaction.next_payments.skip_dialog_title,
      confirmationText: t.ui_actions.confirm,
      contentParagraphs: [
        Text(
          nextPaymentDate != null
              ? t.transaction.next_payments.skip_dialog_msg(
                  date: DateFormat.yMMMd().format(nextPaymentDate),
                )
              : t.recurrent_transactions.details.last_payment_info,
        ),
      ],
    ).then((isConfirmed) {
      if (isConfirmed != true) return;

      if (nextPaymentDate == null) {
        TransactionService.instance.deleteTransaction(transaction.id).then((
          value,
        ) {
          WallexSnackbar.success(
            SnackbarParams(
              '${t.transaction.next_payments.skip_success}. ${t.transaction.next_payments.recurrent_rule_finished}',
            ),
          );

          RouteUtils.popRoute();
        });

        return;
      }

      // Change the next payment date and the remaining iterations (if required)
      TransactionService.instance.setTransactionNextPayment(transaction).then((
        inserted,
      ) {
        if (inserted == 0) return;

        WallexSnackbar.success(
          SnackbarParams(t.transaction.next_payments.skip_success),
        );
      });
    });
  }

  Widget _cardPay({
    required MoneyTransaction transaction,
    required DateTime date,
    bool isNext = false,
  }) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 2, horizontal: 8),
      child: ListTile(
        enabled: isNext,
        contentPadding: const EdgeInsets.only(left: 16, right: 6),
        tileColor: transaction.nextPayStatus!.color(context).withOpacity(0.1),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
        leading: Icon(
          isNext ? transaction.nextPayStatus!.icon : Icons.access_time,
          color: transaction.nextPayStatus!.color(context),
        ),
        title: Text(DateFormat.yMMMd().format(date)),
        subtitle: !isNext
            ? null
            : Text(
                transaction.nextPayStatus!.displayDaysToPay(
                  context,
                  transaction.daysToPay(),
                ),
              ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          spacing: 4,
          children: [
            IconButton(
              color: AppColors.of(context).danger,
              disabledColor: AppColors.of(context).danger.withOpacity(0.7),
              icon: const Icon(Icons.cancel_rounded),
              tooltip: t.transaction.next_payments.skip,
              onPressed: !isNext
                  ? null
                  : () => showSkipTransactionModal(context, transaction),
            ),
            IconButton(
              onPressed: !isNext
                  ? null
                  : () => showPayModal(context, transaction),
              color: AppColors.of(context).success,
              tooltip: !isNext ? null : t.transaction.next_payments.accept,
              disabledColor: AppColors.of(context).success.withOpacity(0.7),
              icon: const Icon(Icons.price_check_rounded),
            ),
          ],
        ),
      ),
    );
  }

  void showPayModal(BuildContext context, MoneyTransaction transaction) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        return Padding(
          padding: const EdgeInsets.only(top: 8.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ...(getPayActions(context, transaction).map(
                (e) => ListTile(
                  leading: Icon(e.icon),
                  title: Text(e.label),
                  enabled: e.onClick != null,
                  onTap: e.onClick == null
                      ? null
                      : () {
                          RouteUtils.popRoute();
                          e.onClick!();
                        },
                ),
              )),
              if (transaction.recurrentInfo.isRecurrent &&
                  transaction.isOnLastPayment)
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.info_outline_rounded,
                        size: 14,
                        weight: 200,
                      ),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          t.recurrent_transactions.details.last_payment_info,
                          style: Theme.of(context).textTheme.labelSmall!
                              .copyWith(fontWeight: FontWeight.w300),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget statusDisplayer(MoneyTransaction transaction) {
    if (transaction.status == null && transaction.recurrentInfo.isNoRecurrent) {
      throw Exception('Error');
    }

    if (transaction.recurrentInfo.isRecurrent) {
      return _recurrencyStatusCard(transaction);
    }

    return _transactionStatusCard(transaction);
  }

  Widget _recurrencyStatusCard(MoneyTransaction transaction) {
    final bool isDarkTheme = Theme.of(context).brightness == Brightness.dark;
    final color = isDarkTheme
        ? Theme.of(context).colorScheme.primary
        : Theme.of(context).colorScheme.primary.lighten(0.2);

    return TranslucentTransactionStatusCard(
      color: color,
      initiallyExpanded: true,
      icon: Icons.repeat_rounded,
      title: t.recurrent_transactions.details.title,
      body: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: 8,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Text(t.recurrent_transactions.details.descr),
            ),
            Column(
              children: [
                ...transaction
                    .getNextDatesOfRecurrency(limit: 3)
                    .mapIndexed(
                      (index, e) => _cardPay(
                        date: e,
                        transaction: transaction,
                        isNext: index == 0,
                      ),
                    ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _transactionStatusCard(MoneyTransaction transaction) {
    final color = transaction.status!.color;

    return TranslucentTransactionStatusCard(
      color: color,
      initiallyExpanded: transaction.status == TransactionStatus.pending,
      icon: transaction.status?.icon,
      title: t.transaction.status
          .tr_status(status: transaction.status!.displayName(context))
          .capitalize(),
      body: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: 12,
          children: [
            Text(transaction.status!.description(context)),
            if (transaction.status == TransactionStatus.pending)
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: color.darken(0.2),
                    foregroundColor: Colors.white,
                  ),
                  onPressed: () => showPayModal(context, transaction),
                  child: Text(t.transaction.next_payments.accept_dialog_title),
                ),
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = Translations.of(context);

    return StreamBuilder(
      stream: TransactionService.instance.getTransactionById(
        widget.transaction.id,
      ),
      initialData: widget.transaction,
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const LinearProgressIndicator();
        }

        final transaction = snapshot.data!;

        final transactionDetailsActions = TransactionViewActionService()
            .transactionDetailsActions(
              context,
              transaction: transaction,
              navigateBackOnDelete: true,
            );

        return PageFramework(
          title: t.transaction.details,
          body: CustomScrollView(
            slivers: [
              SliverPersistentHeader(
                pinned: true,
                delegate: _TransactionDetailHeader(
                  heroTag: widget.heroTag,
                  transaction: transaction,
                ),
              ),
              SliverToBoxAdapter(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(
                        16,
                        16,
                        16,
                        24,
                      ).withSafeBottom(context),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (transaction.status != null ||
                              transaction.recurrentInfo.isRecurrent)
                            statusDisplayer(transaction),
                          if (transaction.isReversed)
                            TranslucentTransactionStatusCard(
                              color: AppColors.of(context).brand,
                              body: Padding(
                                padding: const EdgeInsets.all(12),
                                child: Text(
                                  transaction.type == TransactionType.expense
                                      ? t
                                            .transaction
                                            .reversed
                                            .description_for_expenses
                                      : t
                                            .transaction
                                            .reversed
                                            .description_for_incomes,
                                ),
                              ),
                              icon: MoneyTransaction.reversedIcon,
                              title: t.transaction.reversed.title,
                            ),
                          CardWithHeader(
                            title: 'Info',
                            body: LabelValueInfoTable(
                              items: [
                                LabelValueInfoItem(
                                  value: buildInfoTileWithIconAndColor(
                                    icon: transaction.account.icon,
                                    color: transaction.account
                                        .getComputedColor(context)
                                        .lighten(
                                          isAppInDarkBrightness(context)
                                              ? 0.5
                                              : 0,
                                        ),
                                    data: transaction.account.name,
                                  ),
                                  label: transaction.isTransfer
                                      ? t.transfer.form.from
                                      : t.general.account,
                                ),
                                if (transaction.isIncomeOrExpense)
                                  LabelValueInfoItem(
                                    value: buildInfoTileWithIconAndColor(
                                      icon: transaction.category!.icon,
                                      color:
                                          ColorHex.get(
                                            transaction.category!.color,
                                          ).lighten(
                                            isAppInDarkBrightness(context)
                                                ? 0.5
                                                : 0,
                                          ),
                                      data: transaction.category!.name,
                                    ),
                                    label: t.general.category,
                                  ),
                                if (transaction.isTransfer)
                                  LabelValueInfoItem(
                                    value: buildInfoTileWithIconAndColor(
                                      icon: transaction.receivingAccount!.icon,
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.primary,
                                      data: transaction.receivingAccount!.name,
                                    ),
                                    label: t.transfer.form.to,
                                  ),
                                // --- Received amount in destination currency ---
                                if (transaction.isTransfer &&
                                    transaction.valueInDestiny != null &&
                                    transaction.receivingAccount != null &&
                                    transaction.receivingAccount!.currency.code !=
                                        transaction.account.currency.code)
                                  LabelValueInfoItem(
                                    value: CurrencyDisplayer(
                                      amountToConvert: transaction.valueInDestiny!,
                                      currency: transaction.receivingAccount!.currency,
                                      integerStyle: const TextStyle(
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    label: 'Recibido', // TODO: i18n
                                  ),
                                LabelValueInfoItem(
                                  value: Text(
                                    DateFormat.yMMMMd().format(
                                      transaction.date,
                                    ),
                                    softWrap: false,
                                    overflow: TextOverflow.fade,
                                  ),
                                  label: t.general.time.date,
                                ),
                                LabelValueInfoItem(
                                  value: Text(
                                    DateFormat.Hm().format(transaction.date),
                                    softWrap: false,
                                    overflow: TextOverflow.fade,
                                  ),
                                  label: t.general.time.time,
                                ),
                                // --- Applied exchange rate row ---
                                if (transaction.exchangeRateApplied != null)
                                  LabelValueInfoItem(
                                    value: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        const Icon(
                                          Icons.currency_exchange_rounded,
                                          size: 14,
                                        ),
                                        const SizedBox(width: 4),
                                        Flexible(
                                          child: Text(
                                            '${transaction.exchangeRateApplied!.toStringAsFixed(2)} Bs/USD (${_exchangeRateSourceLabel(transaction.exchangeRateSource)})', // TODO: i18n
                                            softWrap: false,
                                            overflow: TextOverflow.fade,
                                          ),
                                        ),
                                      ],
                                    ),
                                    label: 'Tasa aplicada', // TODO: i18n
                                  )
                                else if (transaction.account.currencyId !=
                                    (transaction.receivingAccount?.currencyId ??
                                        transaction.account.currencyId))
                                  LabelValueInfoItem(
                                    value: Tooltip(
                                      message:
                                          'Esta transaccion es anterior a la version que registra tasas. '
                                          'Edita la transaccion para asignar una tasa retroactiva.', // TODO: i18n
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(
                                            Icons.info_outline,
                                            size: 14,
                                            color: Theme.of(context)
                                                .colorScheme
                                                .error,
                                          ),
                                          const SizedBox(width: 4),
                                          const Text(
                                            'no registrada', // TODO: i18n
                                            style: TextStyle(
                                              fontStyle: FontStyle.italic,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    label: 'Tasa aplicada', // TODO: i18n
                                  ),
                              ],
                            ),
                          ),
                          if (transaction.tags.isNotEmpty) ...[
                            const SizedBox(height: 16),
                            CardWithHeader(
                              title: t.tags.display(n: 2),
                              bodyPadding: const EdgeInsets.all(12),
                              body: Wrap(
                                spacing: 6,
                                runSpacing: 0,
                                children: List.generate(
                                  transaction.tags.length,
                                  (index) {
                                    final tag = transaction.tags[index];

                                    return TransactionTagChip(tag: tag);
                                  },
                                ),
                              ),
                            ),
                          ],
                          if (transaction.debtId != null)
                            _LinkedDebtCard(
                              debtId: transaction.debtId!,
                              transactionId: transaction.id,
                            ),
                          if (transaction.notes != null) ...[
                            const SizedBox(height: 16),
                            CardWithHeader(
                              title: t.transaction.form.description,
                              bodyPadding: const EdgeInsets.all(16),
                              body: Text(transaction.notes!),
                            ),
                          ],
                          StreamBuilder(
                            stream: CurrencyService.instance
                                .ensureAndGetPreferredCurrency(),
                            builder: (context, snapshot) {
                              if (!snapshot.hasData ||
                                  snapshot.data!.code ==
                                      transaction.account.currencyId) {
                                return Container();
                              }

                              final userCurrency = snapshot.data!;

                              return Container(
                                margin: const EdgeInsets.only(top: 16),
                                child: CardWithHeader(
                                  title: t.transaction.form
                                      .exchange_to_preferred_title(
                                        currency: userCurrency.code,
                                      ),
                                  body: Column(
                                    children: [
                                      StreamBuilder<double?>(
                                        stream: ExchangeRateService.instance
                                            .getLastExchangeRateOf(
                                              currencyCode: transaction
                                                  .account
                                                  .currency
                                                  .code,
                                              date: DateTime.now(),
                                            )
                                            .map(
                                              (event) =>
                                                  event?.exchangeRate,
                                            ),
                                        builder: (context, snapshot) {
                                          final rate = snapshot.data;

                                          if (rate == null) {
                                            return buildInfoListTile(
                                              title: t.general.today,
                                              subtitle: Row(
                                                children: [
                                                  const Icon(
                                                    Icons
                                                        .currency_exchange_rounded,
                                                    size: 12,
                                                  ),
                                                  const SizedBox(width: 4),
                                                  const Text(
                                                    'Tasa no disponible', // TODO: i18n
                                                  ),
                                                ],
                                              ),
                                              trailing: const Text('--'),
                                            );
                                          }

                                          return buildInfoListTile(
                                            title: t.general.today,
                                            subtitle: Row(
                                              children: [
                                                const Icon(
                                                  Icons
                                                      .currency_exchange_rounded,
                                                  size: 12,
                                                ),
                                                const SizedBox(width: 4),
                                                Text(
                                                  '1 ${transaction.account.currency.code} = ${rate.toStringAsFixed(2)} ${userCurrency.code}',
                                                ),
                                              ],
                                            ),
                                            trailing: CurrencyDisplayer(
                                              currency: userCurrency,
                                              integerStyle: const TextStyle(
                                                fontWeight: FontWeight.bold,
                                              ),
                                              amountToConvert:
                                                  rate *
                                                  transaction.value,
                                            ),
                                          );
                                        },
                                      ),
                                      StreamBuilder<double?>(
                                        stream: ExchangeRateService.instance
                                            .getLastExchangeRateOf(
                                              currencyCode: transaction
                                                  .account
                                                  .currency
                                                  .code,
                                              date: transaction.date,
                                            )
                                            .map(
                                              (event) {
                                                // Prefer the stored transaction rate over the DB lookup
                                                if (transaction.exchangeRateApplied != null) {
                                                  return transaction.exchangeRateApplied;
                                                }
                                                return event?.exchangeRate;
                                              },
                                            ),
                                        builder: (context, snapshot) {
                                          final rate = snapshot.data;

                                          if (rate == null) {
                                            return buildInfoListTile(
                                              title: t
                                                  .transaction
                                                  .form
                                                  .exchange_to_preferred_in_date,
                                              subtitle: Row(
                                                children: [
                                                  const Icon(
                                                    Icons
                                                        .currency_exchange_rounded,
                                                    size: 12,
                                                  ),
                                                  const SizedBox(width: 4),
                                                  const Text(
                                                    'Tasa no disponible', // TODO: i18n
                                                  ),
                                                ],
                                              ),
                                              trailing: const Text('--'),
                                            );
                                          }

                                          return buildInfoListTile(
                                            title: t
                                                .transaction
                                                .form
                                                .exchange_to_preferred_in_date,
                                            subtitle: Row(
                                              children: [
                                                const Icon(
                                                  Icons
                                                      .currency_exchange_rounded,
                                                  size: 12,
                                                ),
                                                const SizedBox(width: 4),
                                                Text(
                                                  '1 ${transaction.account.currency.code} = ${rate.toStringAsFixed(2)} ${userCurrency.code}',
                                                ),
                                              ],
                                            ),
                                            trailing: CurrencyDisplayer(
                                              currency: userCurrency,
                                              integerStyle: const TextStyle(
                                                fontWeight: FontWeight.bold,
                                              ),
                                              amountToConvert:
                                                  rate *
                                                  transaction.value,
                                            ),
                                          );
                                        },
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                          const SizedBox(height: 16),
                          CardWithHeader(
                            title: t.general.quick_actions,
                            body: WallexQuickActionsButton(
                              actions: transactionDetailsActions,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  ListTile buildInfoListTile({
    required String title,
    required Widget trailing,
    Widget? subtitle,
  }) {
    return ListTile(
      minVerticalPadding: 4,
      dense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 0),
      trailing: trailing,
      subtitle: subtitle,
      title: Text(
        title,
        style: TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w500,
          color: Theme.of(context).colorScheme.onSurface.withOpacity(0.85),
        ),
      ),
    );
  }

  Row buildInfoTileWithIconAndColor({
    required SupportedIcon icon,
    required String data,
    required Color color,
  }) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        icon.display(color: color),
        const SizedBox(width: 8),
        Text(data, style: TextStyle(color: color)),
      ],
    );
  }
}

class TransactionTagChip extends StatelessWidget {
  const TransactionTagChip({
    super.key,
    required this.tag,
    this.visualDensity = VisualDensity.standard,
  });

  final Tag tag;
  final VisualDensity visualDensity;

  @override
  Widget build(BuildContext context) {
    if (visualDensity == VisualDensity.compact) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: tag.colorData.lighten(0.8),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Row(
          spacing: 2,
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Tag.icon, color: tag.colorData, size: 14),
            Text(
              tag.name,
              style: Theme.of(
                context,
              ).textTheme.labelMedium!.copyWith(color: tag.colorData),
            ),
          ],
        ),
      );
    }

    return Chip(
      backgroundColor: tag.colorData.lighten(0.8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(6),
        side: const BorderSide(
          width: 0,
          color: Colors.transparent,
          style: BorderStyle.none,
        ),
      ),
      elevation: 0,
      label: Text(
        tag.name,
        style: Theme.of(
          context,
        ).textTheme.labelMedium!.copyWith(color: tag.colorData),
      ),
      visualDensity: visualDensity,
      avatar: Icon(Tag.icon, color: tag.colorData),
    );
  }
}

class _TransactionDetailHeader extends SliverPersistentHeaderDelegate {
  const _TransactionDetailHeader({
    required this.transaction,
    required this.heroTag,
  });

  final MoneyTransaction transaction;
  final Object? heroTag;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlap) {
    final shrinkPercent = shrinkOffset / maxExtent;

    return Container(
      color: Theme.of(context).colorScheme.surface,
      padding: const EdgeInsets.only(left: 24, right: 24, top: 16, bottom: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                AnimatedDefaultTextStyle(
                  duration: const Duration(milliseconds: 100),
                  style: Theme.of(context).textTheme.headlineMedium!.copyWith(
                    fontSize: 34 - (1 - pow(1 - shrinkPercent, 4)) * 16,
                    fontWeight: FontWeight.bold,
                    color: transaction.status == TransactionStatus.voided
                        ? Colors.grey.shade400
                        : transaction.type == TransactionType.transfer
                        ? null
                        : transaction.type.color(context),
                    decoration: transaction.status == TransactionStatus.voided
                        ? TextDecoration.lineThrough
                        : null,
                  ),
                  child: CurrencyDisplayer(
                    amountToConvert: transaction.value,
                    currency: transaction.account.currency,
                  ),
                ),
                Text(
                  transaction.displayName(context),
                  softWrap: true,
                  overflow: TextOverflow.fade,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                if (transaction.recurrentInfo.isNoRecurrent)
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 200),
                    transitionBuilder:
                        (Widget child, Animation<double> animation) {
                          return SizeTransition(
                            sizeFactor: animation,
                            child: ScaleTransition(
                              scale: animation,
                              alignment: Alignment.centerLeft,
                              child: child,
                            ),
                          );
                        },
                    child: shrinkPercent > 0.3
                        ? const SizedBox.shrink()
                        : Text(
                            transaction.date.year == currentYear
                                ? DateFormat.MMMMEEEEd().format(
                                    transaction.date,
                                  )
                                : DateFormat.yMMMEd().format(transaction.date),
                          ),
                  )
                else
                  Row(
                    children: [
                      Icon(
                        Icons.repeat_rounded,
                        size: 14,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        transaction.recurrentInfo.formText(context),
                        style: TextStyle(
                          fontWeight: FontWeight.w300,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ),
          const SizedBox(width: 24),
          Hero(
            tag: heroTag ?? UniqueKey(),
            child: transaction.getDisplayIcon(
              context,
              size: 42 - (1 - pow(1 - shrinkPercent, 4)) * 16,
            ),
          ),
        ],
      ),
    );
  }

  @override
  double get maxExtent => 120;

  @override
  double get minExtent => 80;

  @override
  bool shouldRebuild(covariant _TransactionDetailHeader oldDelegate) =>
      oldDelegate.transaction != transaction || oldDelegate.heroTag != heroTag;
}

class _LinkedDebtCard extends StatelessWidget {
  const _LinkedDebtCard({
    required this.debtId,
    required this.transactionId,
  });

  final String debtId;
  final String transactionId;

  @override
  Widget build(BuildContext context) {
    final t = Translations.of(context);

    return StreamBuilder<Debt?>(
      stream: DebtService.instance.getDebtById(debtId),
      builder: (context, snapshot) {
        if (!snapshot.hasData || snapshot.data == null) {
          return const SizedBox.shrink();
        }

        final debt = snapshot.data!;
        final color = debt.type.color(context);

        return Padding(
          padding: const EdgeInsets.only(top: 16),
          child: CardWithHeader(
            title: t.debts.display(n: 1),
            body: ListTile(
              leading: Icon(Debt.icon, color: color),
              title: Text(debt.name),
              trailing: IconButton(
                icon: const Icon(Icons.link_off_rounded),
                tooltip: t.debts.actions.unlink_transaction.title,
                onPressed: () {
                  TransactionViewActionService()
                      .unlinkTransactionFromDebtWithAlertAndSnackbar(
                        context,
                        transactionId: transactionId,
                      );
                },
              ),
            ),
          ),
        );
      },
    );
  }
}
