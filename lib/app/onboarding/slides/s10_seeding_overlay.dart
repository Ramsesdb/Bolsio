import 'package:flutter/material.dart';
import 'package:wallex/app/onboarding/widgets/v3_seeding_overlay.dart';
import 'package:wallex/core/database/utils/personal_ve_seeders.dart';

/// Theatrical seeding slide. Calls `PersonalVESeeder.seedAll` and waits for
/// both the seeding future and a 500 ms minimum visual delay before advancing.
/// The seeder is idempotent (guarded by `existingAccounts.isNotEmpty` in
/// `personal_ve_seeders.dart:28`), so re-entry is safe.
class Slide10SeedingOverlay extends StatefulWidget {
  const Slide10SeedingOverlay({
    super.key,
    required this.selectedBankIds,
    required this.onDone,
    this.alsoUsdForBank = const <String, bool>{},
    this.currencyMode = 'USD',
  });

  final Set<String> selectedBankIds;

  /// Per-bank "also USD" flags (key = bank id). Only populated when the
  /// user picked DUAL in s02 and toggled the sub-row on a bank with
  /// `supportsBoth = true`. Forwarded to the seeder so it creates a
  /// second USD account in addition to the native VES one.
  final Map<String, bool> alsoUsdForBank;

  /// Currency selection from s02 — `'USD'`, `'VES'` or `'DUAL'`. Forwarded
  /// to the seeder so it can auto-create both VES+USD accounts for
  /// Venezuelan banks when the user picked USD.
  final String currencyMode;

  final VoidCallback onDone;

  @override
  State<Slide10SeedingOverlay> createState() => _Slide10SeedingOverlayState();
}

class _Slide10SeedingOverlayState extends State<Slide10SeedingOverlay> {
  @override
  void initState() {
    super.initState();
    _runSeeding();
  }

  Future<void> _runSeeding() async {
    await Future.wait<void>([
      PersonalVESeeder.seedAll(
        selectedBankIds: widget.selectedBankIds.toList(),
        alsoUsdForBank: widget.alsoUsdForBank,
        currencyMode: widget.currencyMode,
      ),
      Future<void>.delayed(const Duration(milliseconds: 500)),
    ]);
    if (!mounted) return;
    widget.onDone();
  }

  @override
  Widget build(BuildContext context) {
    return const V3SeedingOverlay(
      title: 'Preparando tu Wallex…',
      subtitle: 'Creamos tus cuentas y categorías iniciales. Tomará un momento.',
    );
  }
}
