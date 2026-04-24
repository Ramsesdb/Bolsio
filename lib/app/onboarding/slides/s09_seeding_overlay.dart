import 'package:flutter/material.dart';
import 'package:wallex/app/onboarding/widgets/v3_seeding_overlay.dart';
import 'package:wallex/core/database/utils/personal_ve_seeders.dart';

/// Theatrical seeding slide. Calls `PersonalVESeeder.seedAll` and waits for
/// both the seeding future and a 500 ms minimum visual delay before advancing.
/// The seeder is idempotent (guarded by `existingAccounts.isNotEmpty` in
/// `personal_ve_seeders.dart:28`), so re-entry is safe.
class Slide09SeedingOverlay extends StatefulWidget {
  const Slide09SeedingOverlay({
    super.key,
    required this.selectedBankIds,
    required this.onDone,
  });

  final Set<String> selectedBankIds;
  final VoidCallback onDone;

  @override
  State<Slide09SeedingOverlay> createState() => _Slide09SeedingOverlayState();
}

class _Slide09SeedingOverlayState extends State<Slide09SeedingOverlay> {
  @override
  void initState() {
    super.initState();
    _runSeeding();
  }

  Future<void> _runSeeding() async {
    await Future.wait<void>([
      PersonalVESeeder.seedAll(
        selectedBankIds: widget.selectedBankIds.toList(),
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
