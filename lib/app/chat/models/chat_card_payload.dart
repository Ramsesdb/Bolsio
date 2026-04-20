import 'package:flutter/material.dart';

sealed class ChatCardPayload {
  const ChatCardPayload();
}

class AccountPickPayload extends ChatCardPayload {
  final List<AccountPickItem> accounts;
  final String? prompt;

  const AccountPickPayload({required this.accounts, this.prompt});
}

class AccountPickItem {
  final String id;
  final String name;
  final String initial;
  final Color tileColor;
  final double balance;
  final String currencyCode;

  const AccountPickItem({
    required this.id,
    required this.name,
    required this.initial,
    required this.tileColor,
    required this.balance,
    required this.currencyCode,
  });
}

class ExpensePayload extends ChatCardPayload {
  final String kickerLabel;
  final double total;
  final String currencyCode;
  final double? deltaPct;
  final List<ExpenseCategoryRow> categories;

  const ExpensePayload({
    required this.kickerLabel,
    required this.total,
    required this.currencyCode,
    required this.categories,
    this.deltaPct,
  });
}

class ExpenseCategoryRow {
  final String label;
  final Color dotColor;
  final double amount;
  final double percent;

  const ExpenseCategoryRow({
    required this.label,
    required this.dotColor,
    required this.amount,
    required this.percent,
  });
}

class BalancePayload extends ChatCardPayload {
  final String kickerLabel;
  final double total;
  final String currencyCode;
  final List<BalanceBreakdownRow>? breakdown;

  const BalancePayload({
    required this.kickerLabel,
    required this.total,
    required this.currencyCode,
    this.breakdown,
  });
}

class BalanceBreakdownRow {
  final String currencyCode;
  final double amount;
  final double percent;

  const BalanceBreakdownRow({
    required this.currencyCode,
    required this.amount,
    required this.percent,
  });
}
