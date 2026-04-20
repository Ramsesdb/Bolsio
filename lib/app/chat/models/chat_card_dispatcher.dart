import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:wallex/app/chat/models/chat_card_payload.dart';
import 'package:wallex/app/chat/theme/wallex_ai_tokens.dart';
import 'package:wallex/core/database/services/account/account_service.dart';
import 'package:wallex/core/database/services/category/category_service.dart';
import 'package:wallex/core/extensions/color.extensions.dart';

// Maps read-only data-tool results to inline ChatCardPayloads.
// Only read-only tools become cards; mutating tools (create_transaction,
// create_transfer) keep going through showToolApprovalSheet. Unknown tools
// or malformed payloads fall back to the plain text bubble.
class ChatCardDispatcher {
  const ChatCardDispatcher();

  Future<ChatCardPayload?> fromToolResult({
    required String toolName,
    required Map<String, dynamic> args,
    required String rawJson,
  }) async {
    try {
      final decoded = jsonDecode(rawJson);
      if (decoded is! Map<String, dynamic>) return null;
      if (decoded['status'] != 'ok') return null;
      final data = decoded['data'];
      if (data is! Map<String, dynamic>) return null;

      switch (toolName) {
        case 'get_balance':
          return _balanceFromData(data);
        case 'get_stats_by_category':
          return _expenseFromData(data);
        default:
          return null;
      }
    } catch (e, st) {
      debugPrint('ChatCardDispatcher error for $toolName: $e\n$st');
      return null;
    }
  }

  Future<BalancePayload?> _balanceFromData(Map<String, dynamic> data) async {
    final total = _asDouble(data['total']);
    if (total == null) return null;

    final accountsRaw = data['accounts'];
    if (accountsRaw is! List) {
      final currency = (data['currency'] as String?) ?? 'USD';
      return BalancePayload(
        kickerLabel: 'Saldo total',
        total: total,
        currencyCode: currency,
      );
    }

    final byCurrency = <String, double>{};
    for (final entry in accountsRaw) {
      if (entry is! Map) continue;
      final code = (entry['currency'] as String?) ?? 'USD';
      final bal = _asDouble(entry['balance']) ?? 0.0;
      byCurrency[code] = (byCurrency[code] ?? 0.0) + bal;
    }

    final rows = <BalanceBreakdownRow>[];
    if (byCurrency.isNotEmpty && total != 0) {
      final sortedEntries = byCurrency.entries.toList()
        ..sort((a, b) => b.value.abs().compareTo(a.value.abs()));
      for (final e in sortedEntries) {
        rows.add(BalanceBreakdownRow(
          currencyCode: e.key,
          amount: e.value,
          percent: total == 0 ? 0.0 : e.value.abs() / total.abs(),
        ));
      }
    }

    final preferred = byCurrency.isNotEmpty
        ? (byCurrency.entries.toList()
              ..sort((a, b) => b.value.abs().compareTo(a.value.abs())))
            .first
            .key
        : 'USD';

    return BalancePayload(
      kickerLabel: 'Saldo total',
      total: total,
      currencyCode: preferred,
      breakdown: rows.length > 1 ? rows : null,
    );
  }

  Future<ExpensePayload?> _expenseFromData(Map<String, dynamic> data) async {
    final total = _asDouble(data['total']);
    if (total == null || total == 0) return null;

    final catsRaw = data['categories'];
    if (catsRaw is! List || catsRaw.isEmpty) return null;

    final rows = <ExpenseCategoryRow>[];
    for (final entry in catsRaw) {
      if (entry is! Map) continue;
      final id = entry['categoryId']?.toString();
      final name = (entry['categoryName'] as String?) ?? '—';
      final amount = _asDouble(entry['amount']) ?? 0.0;
      Color dotColor = WallexAiTokens.hexBank;
      if (id != null) {
        try {
          final cat = await CategoryService.instance.getCategoryById(id).first;
          if (cat != null) {
            dotColor = ColorHex.get(cat.color);
          }
        } catch (_) {
          // Category lookup is best-effort; fallback color is acceptable.
        }
      }
      rows.add(ExpenseCategoryRow(
        label: name,
        dotColor: dotColor,
        amount: amount,
        percent: total == 0 ? 0.0 : amount / total,
      ));
    }

    if (rows.isEmpty) return null;

    final type = (data['type'] as String?) ?? 'expense';
    final kicker = type == 'income' ? 'Ingresos' : 'Gastos';

    return ExpensePayload(
      kickerLabel: kicker,
      total: total,
      currencyCode: 'USD',
      categories: rows,
    );
  }

  static double? _asDouble(Object? raw) {
    if (raw is num) return raw.toDouble();
    if (raw is String) return double.tryParse(raw);
    return null;
  }

  // Not wired to a current tool — the agent lacks a dedicated
  // "pick_account" tool, so AccountPickCard is surfaced only via a
  // future dedicated tool. Kept as a helper so later tandas can use it
  // by reading the user's existing accounts directly from AccountService.
  Future<AccountPickPayload> accountPickFromService({String? prompt}) async {
    final accounts = await AccountService.instance.getAccounts().first;
    final items = <AccountPickItem>[];
    for (final a in accounts) {
      final bal = await AccountService.instance
          .getAccountMoney(account: a, convertToPreferredCurrency: false)
          .first;
      final initial = a.name.isEmpty ? '?' : a.name.characters.first.toUpperCase();
      final color = a.color != null
          ? ColorHex.get(a.color!)
          : WallexAiTokens.hexBank;
      items.add(AccountPickItem(
        id: a.id,
        name: a.name,
        initial: initial,
        tileColor: color,
        balance: bal,
        currencyCode: a.currency.code,
      ));
    }
    return AccountPickPayload(accounts: items, prompt: prompt);
  }
}
