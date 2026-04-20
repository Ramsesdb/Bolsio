import 'package:drift/drift.dart' as drift;
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:intl/intl.dart';
import 'package:wallex/app/accounts/account_type_selector.dart';
import 'package:wallex/app/accounts/widgets/retroactive_dialogs.dart';
import 'package:wallex/app/categories/form/icon_and_color_selector.dart';
import 'package:wallex/app/layout/page_framework.dart';
import 'package:wallex/core/database/app_db.dart';
import 'package:wallex/core/database/services/account/account_service.dart';
import 'package:wallex/core/database/services/currency/currency_service.dart';
import 'package:wallex/core/database/services/exchange-rate/exchange_rate_service.dart';
import 'package:wallex/core/database/services/transaction/transaction_service.dart';
import 'package:wallex/core/extensions/color.extensions.dart';
import 'package:wallex/core/extensions/lists.extensions.dart';
import 'package:wallex/core/models/account/account.dart';
import 'package:wallex/core/models/currency/currency.dart';
import 'package:wallex/core/models/supported-icon/icon_displayer.dart';
import 'package:wallex/core/models/supported-icon/supported_icon.dart';
import 'package:wallex/core/presentation/helpers/snackbar.dart';
import 'package:wallex/core/presentation/theme.dart';
import 'package:wallex/core/presentation/widgets/color_picker/color_picker.dart';
import 'package:wallex/core/presentation/widgets/currency_selector_modal.dart';
import 'package:wallex/core/presentation/widgets/form_fields/date_form_field.dart';
import 'package:wallex/core/presentation/widgets/form_fields/read_only_form_field.dart';
import 'package:wallex/core/presentation/widgets/icon_selector_modal.dart';
import 'package:wallex/core/presentation/widgets/inline_info_card.dart';
import 'package:wallex/core/presentation/widgets/persistent_footer_button.dart';
import 'package:wallex/core/presentation/widgets/show_more_content_button.dart';
import 'package:wallex/core/presentation/widgets/transaction_filter/transaction_filter_set.dart';
import 'package:wallex/core/routes/route_utils.dart';
import 'package:wallex/core/services/supported_icon/supported_icon_service.dart';
import 'package:wallex/core/utils/text_field_utils.dart';
import 'package:wallex/core/utils/uuid.dart';
import 'package:wallex/i18n/generated/translations.g.dart';

import '../../core/models/transaction/transaction_type.enum.dart';

/// Relative diff threshold that triggers the strong-confirmation flow when
/// editing `trackedSince` on an existing account. If the absolute delta
/// between the current and simulated balance exceeds this fraction of the
/// current balance (and the current balance is non-zero), we require the
/// user to type CONFIRM/CONFIRMAR.
const double _kRetroactiveDiffThreshold = 0.5;

class AccountFormPage extends StatefulWidget {
  const AccountFormPage({super.key, this.account});

  /// Account UUID to edit (if any)
  final Account? account;

  @override
  State<AccountFormPage> createState() => _AccountFormPageState();
}

class _AccountFormPageState extends State<AccountFormPage> {
  final _formKey = GlobalKey<FormState>();

  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _ibanController = TextEditingController();
  final TextEditingController _swiftController = TextEditingController();
  final TextEditingController _textController = TextEditingController();
  final TextEditingController _balanceController = TextEditingController();

  AccountType _type = AccountType.normal;
  SupportedIcon _icon = SupportedIconService.instance.defaultSupportedIcon;
  Color _color = ColorHex.get(defaultColorPickerOptions.randomItem());
  Currency? _currency;
  Currency? _userPrCurrency;

  late final Account? _accountToEdit;

  DateTime _openingDate = DateTime.now();
  DateTime? _closeDate;
  DateTime? _trackedSinceDate;

  Future<void> submitForm() async {
    final accountService = AccountService.instance;

    double newBalance = double.parse(_balanceController.text);

    // Validation: trackedSince cannot be after the closing date.
    if (_trackedSinceDate != null &&
        _closeDate != null &&
        _trackedSinceDate!.isAfter(_closeDate!)) {
      WallexSnackbar.warning(
        SnackbarParams(t.account.form.tracked_since_validation_after_closing),
      );
      return;
    }

    if (_accountToEdit != null) {
      // Check if there are transactions before the opening date of the account:
      if ((await TransactionService.instance
              .getTransactions(
                filters: TransactionFilterSet(
                  accountsIDs: [_accountToEdit.id],
                  maxDate: _openingDate,
                ),
                limit: 2,
              )
              .first)
          .isNotEmpty) {
        WallexSnackbar.warning(
          SnackbarParams(t.account.form.tr_before_opening_date),
        );

        return;
      }

      newBalance =
          _accountToEdit.iniValue +
          newBalance -
          await accountService.getAccountMoney(account: _accountToEdit).first;
    }

    // Retroactive balance preview: only when editing an existing account and
    // trackedSince actually changed. If the balance impact is non-negligible
    // we ask for user confirmation (simple or strong) before persisting.
    final isEditing = _accountToEdit != null;
    final trackedSinceChanged =
        isEditing && _trackedSinceDate != _accountToEdit.trackedSince;

    bool needsRetroactiveConfirmation = false;
    double currentBalance = 0;
    double simulatedBalance = 0;

    if (isEditing && trackedSinceChanged) {
      currentBalance = await accountService
          .getAccountsMoney(accountIds: [_accountToEdit.id])
          .first;
      simulatedBalance = await accountService
          .getAccountsMoneyPreview(
            accountId: _accountToEdit.id,
            simulatedTrackedSince: _trackedSinceDate,
          )
          .first;

      if ((currentBalance - simulatedBalance).abs() > 0.005) {
        needsRetroactiveConfirmation = true;
      }
    }

    if (needsRetroactiveConfirmation) {
      final diff = (currentBalance - simulatedBalance).abs();
      final bool isStrong =
          simulatedBalance < 0 ||
          (currentBalance.abs() > 0 &&
              diff / currentBalance.abs() > _kRetroactiveDiffThreshold) ||
          (currentBalance.abs() == 0 && simulatedBalance < 0);

      if (!mounted) return;
      final editingCurrency = _accountToEdit!.currency;
      final confirmed = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (_) => isStrong
            ? RetroactiveStrongConfirmDialog(
                currentBalance: currentBalance,
                simulatedBalance: simulatedBalance,
                currency: editingCurrency,
              )
            : RetroactivePreviewDialog(
                currentBalance: currentBalance,
                simulatedBalance: simulatedBalance,
                currency: editingCurrency,
              ),
      );

      if (confirmed != true) {
        if (!mounted) return;
        if (isStrong) {
          WallexSnackbar.warning(
            SnackbarParams(t.account.retroactive.strong_confirm_mismatch),
          );
        }
        return;
      }
    }

    Account accountToSubmit = Account(
      id: _accountToEdit?.id ?? generateUUID(),
      name: _nameController.text,
      displayOrder: _accountToEdit?.displayOrder ?? 10,
      iniValue: newBalance,
      date: _openingDate,
      closingDate: _closeDate,
      trackedSince: _trackedSinceDate,
      type: _type,
      iconId: _icon.id,
      color: _color.toHex(),
      currency: _currency!,
      iban: _ibanController.text.isEmpty ? null : _ibanController.text,
      description: _textController.text.isEmpty ? null : _textController.text,
      swift: _swiftController.text.isEmpty ? null : _swiftController.text,
    );

    // Check for accounts with same names before continue:
    if (_accountToEdit == null || _accountToEdit.name != accountToSubmit.name) {
      final db = AppDB.instance;
      final query = db.select(db.accounts)
        ..addColumns([db.accounts.id.count()])
        ..where((tbl) => tbl.name.isValue(_nameController.text));

      if (await query.watchSingleOrNull().first != null) {
        WallexSnackbar.error(
          SnackbarParams.fromError(
            t.account.form.already_exists,
            duration: const Duration(seconds: 6),
          ),
        );

        return;
      }
    }

    if (_accountToEdit != null) {
      await accountService
          .updateAccount(accountToSubmit)
          .then((value) => {RouteUtils.popRoute()});
    } else {
      await accountService
          .insertAccount(accountToSubmit)
          .then((value) => {RouteUtils.popRoute()});
    }
  }

  @override
  void initState() {
    super.initState();

    _accountToEdit = widget.account;

    if (_accountToEdit != null) {
      _fillForm();
    }

    CurrencyService.instance.ensureAndGetPreferredCurrency().first.then((
      value,
    ) {
      setState(() {
        if (widget.account == null) {
          _currency = value;
        }
        _userPrCurrency = value;
      });
    });
  }

  void _fillForm() {
    if (_accountToEdit == null) return;

    final accountService = AccountService.instance;

    _nameController.text = _accountToEdit.name;
    _ibanController.text = _accountToEdit.iban ?? '';
    _swiftController.text = _accountToEdit.swift ?? '';
    _textController.text = _accountToEdit.description ?? '';

    _openingDate = _accountToEdit.date;
    _closeDate = _accountToEdit.closingDate;
    _trackedSinceDate = _accountToEdit.trackedSince;

    _type = _accountToEdit.type;

    accountService.getAccountMoney(account: _accountToEdit).first.then((value) {
      if (!mounted) return;
      _balanceController.text = value.toString();

      _color = _accountToEdit.getComputedColor(context);
    });

    _icon = _accountToEdit.icon;

    CurrencyService.instance
        .getCurrencyByCode(_accountToEdit.currency.code)
        .first
        .then((value) {
          setState(() {
            _currency = value;
          });
        });

    setState(() {});
  }

  @override
  void dispose() {
    _nameController.dispose();
    _balanceController.dispose();
    _textController.dispose();
    _ibanController.dispose();
    _swiftController.dispose();

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = Translations.of(context);
    final pageTitle = widget.account != null
        ? t.account.form.edit
        : t.account.form.create;
    final footerButtons = [
      PersistentFooterButton(
        child: FilledButton.icon(
          onPressed: () {
            if (_formKey.currentState!.validate()) {
              submitForm();
            }
          },
          icon: const Icon(Icons.save),
          label: Text(pageTitle),
        ),
      ),
    ];

    return PageFramework(
      title: pageTitle,
      persistentFooterButtons: footerButtons,
      body: Builder(
        builder: (context) {
          if (widget.account != null && _accountToEdit == null) {
            return const LinearProgressIndicator();
          }

          final isDark = isAppInDarkBrightness(context);

          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  IconAndColorSelector(
                    iconSelectorModalSubtitle:
                        t.icon_selector.select_account_icon,
                    iconDisplayer: IconDisplayer(
                      supportedIcon: _icon,
                      size: 36,
                      isOutline: true,
                      outlineWidth: 1.5,
                      onTap: () {
                        showIconSelectorModal(
                          context,
                          IconSelectorModal(
                            preselectedIconID: _icon.id,
                            subtitle: t.icon_selector.select_account_icon,
                            onIconSelected: (selectedIcon) {
                              setState(() {
                                _icon = selectedIcon;
                              });
                            },
                          ),
                        );
                      },
                      mainColor: _color.lighten(
                        isDark ? IconDisplayer.darkLightenFactor : 0,
                      ),
                      secondaryColor: _color.lighten(
                        isDark ? 0 : IconDisplayer.darkLightenFactor,
                      ),
                      displayMode: IconDisplayMode.polygon,
                    ),
                    onDataChange: ((data) {
                      setState(() {
                        _icon = data.icon;
                        _color = data.color;
                      });
                    }),
                    data: (color: _color, icon: _icon),
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _nameController,
                    decoration: InputDecoration(
                      labelText: '${t.account.form.name} *',
                      hintText: 'Ex.: My account',
                    ),
                    validator: (value) =>
                        fieldValidator(value, isRequired: true),
                    autovalidateMode: AutovalidateMode.onUserInteraction,
                    textInputAction: TextInputAction.next,
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _balanceController,
                    decoration: InputDecoration(
                      labelText: widget.account != null
                          ? '${t.account.form.current_balance} *'
                          : '${t.account.form.initial_balance} *',
                      hintText: 'Ex.: 200',
                      suffixText: _currency?.symbol,
                    ),
                    keyboardType: TextInputType.number,
                    enabled:
                        !(widget.account != null && widget.account!.isClosed),
                    inputFormatters: twoDecimalDigitFormatter,
                    validator: (value) => fieldValidator(
                      value,
                      validator: ValidatorType.double,
                      isRequired: true,
                    ),
                    autovalidateMode: AutovalidateMode.onUserInteraction,
                    textInputAction: TextInputAction.next,
                  ),
                  const SizedBox(height: 16),
                  ReadOnlyTextFormField(
                    displayValue: _currency != null
                        ? _currency!.name
                        : t.general.unspecified,
                    onTap: () {
                      if (_currency == null) return;

                      showCurrencySelectorModal(
                        context,
                        CurrencySelectorModal(
                          preselectedCurrency: _currency!,
                          onCurrencySelected: (newCurrency) {
                            setState(() {
                              _currency = newCurrency;
                            });
                          },
                        ),
                      );
                    },
                    decoration: InputDecoration(
                      labelText: t.currencies.currency,
                      suffixIcon: const Icon(Icons.arrow_drop_down),
                      prefixIcon: _currency != null
                          ? Container(
                              margin: const EdgeInsets.all(10),
                              clipBehavior: Clip.hardEdge,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(100),
                              ),
                              child: SvgPicture.asset(
                                _currency!.currencyIconPath,
                                height: 25,
                                width: 25,
                              ),
                            )
                          : null,
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (_currency != null)
                    StreamBuilder(
                      stream: ExchangeRateService.instance
                          .getLastExchangeRateOf(currencyCode: _currency!.code),
                      builder: (context, snapshot) {
                        if (snapshot.hasData ||
                            _currency?.code == _userPrCurrency?.code) {
                          return Container();
                        } else {
                          return InlineInfoCard(
                            text: t.account.form.currency_not_found_warn,
                            mode: InlineInfoCardMode.warn,
                          );
                        }
                      },
                    ),
                  StreamBuilder(
                    stream: _accountToEdit == null
                        ? Stream.value(true)
                        : TransactionService.instance
                              .countTransactions(
                                filters: TransactionFilterSet(
                                  transactionTypes: [
                                    TransactionType.expense,
                                    TransactionType.income,
                                  ],
                                  accountsIDs: [_accountToEdit.id],
                                ),
                              )
                              .map((count) => count == 0),
                    builder: (context, snapshot) {
                      if (!snapshot.hasData || snapshot.data! == false) {
                        return Container();
                      }

                      return Column(
                        children: [
                          const SizedBox(height: 12),
                          AccountTypeSelector(
                            selectedType: _type,
                            onSelected: (newType) {
                              setState(() {
                                _type = newType;
                              });
                            },
                          ),
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: 16),
                  ShowMoreContentButton(
                    child: Column(
                      children: [
                        const SizedBox(height: 12),
                        DateTimeFormField(
                          decoration: InputDecoration(
                            suffixIcon: const Icon(Icons.event),
                            labelText: '${t.account.date} *',
                          ),
                          initialDate: _openingDate,
                          dateFormat: DateFormat.yMMMd().add_jm(),
                          lastDate: _closeDate ?? DateTime.now(),
                          validator: (e) =>
                              e == null ? t.general.validations.required : null,
                          onDateSelected: (DateTime value) {
                            setState(() {
                              _openingDate = value;
                            });
                          },
                        ),
                        const SizedBox(height: 22),
                        if (_accountToEdit != null &&
                            _accountToEdit.isClosed) ...[
                          DateTimeFormField(
                            decoration: InputDecoration(
                              suffixIcon: const Icon(Icons.event),
                              labelText: t.account.close_date,
                            ),
                            initialDate: _closeDate,
                            firstDate: _openingDate,
                            lastDate: DateTime.now(),
                            dateFormat: DateFormat.yMMMd().add_jm(),
                            onDateSelected: (DateTime value) {
                              setState(() {
                                _closeDate = value;
                              });
                            },
                          ),
                          const SizedBox(height: 22),
                        ],
                        DateTimeFormField(
                          key: ValueKey(
                            'tracked-since-${_trackedSinceDate?.toIso8601String() ?? "null"}',
                          ),
                          decoration: InputDecoration(
                            suffixIcon: _trackedSinceDate != null
                                ? IconButton(
                                    icon: const Icon(Icons.clear),
                                    tooltip: t.account.retroactive.cancel,
                                    onPressed: () {
                                      setState(() {
                                        _trackedSinceDate = null;
                                      });
                                    },
                                  )
                                : const Icon(Icons.event),
                            labelText: t.account.form.tracked_since,
                            hintText: t.account.form.tracked_since_hint,
                            helperText: t.account.form.tracked_since_hint,
                          ),
                          initialDate: _trackedSinceDate,
                          firstDate: _openingDate,
                          lastDate: DateTime.now(),
                          dateFormat: DateFormat.yMMMd().add_jm(),
                          onDateSelected: (DateTime value) {
                            setState(() {
                              _trackedSinceDate = value;
                            });
                          },
                        ),
                        const SizedBox(height: 8),
                        InlineInfoCard(
                          text: t.account.form.tracked_since_info,
                          mode: InlineInfoCardMode.info,
                        ),
                        const SizedBox(height: 22),
                        TextFormField(
                          controller: _ibanController,
                          decoration: InputDecoration(
                            labelText: t.account.form.iban,
                          ),
                          textInputAction: TextInputAction.next,
                        ),
                        const SizedBox(height: 22),
                        TextFormField(
                          controller: _swiftController,
                          decoration: InputDecoration(
                            labelText: t.account.form.swift,
                          ),
                          textInputAction: TextInputAction.next,
                        ),
                        const SizedBox(height: 22),
                        TextFormField(
                          minLines: 2,
                          maxLines: 10,
                          controller: _textController,
                          decoration: InputDecoration(
                            labelText: t.account.form.notes,
                            hintText: t.account.form.notes_placeholder,
                            alignLabelWithHint: true,
                          ),
                          textInputAction: TextInputAction.next,
                        ),
                        const SizedBox(height: 22),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
