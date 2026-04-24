import 'package:flutter/material.dart';
import 'package:wallex/app/onboarding/bank_options.dart';
import 'package:wallex/app/onboarding/theme/v3_tokens.dart';
import 'package:wallex/app/onboarding/widgets/v3_bank_tile.dart';
import 'package:wallex/app/onboarding/widgets/v3_slide_template.dart';

class Slide04InitialAccounts extends StatelessWidget {
  const Slide04InitialAccounts({
    super.key,
    required this.selectedBankIds,
    required this.onToggleBank,
    required this.onNext,
  });

  final Set<String> selectedBankIds;
  final void Function(String id) onToggleBank;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    return V3SlideTemplate(
      primaryLabel: 'Siguiente',
      onPrimary: onNext,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Tus cuentas',
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
          ),
          const SizedBox(height: V3Tokens.spaceMd),
          Text(
            'Selecciona los bancos y billeteras que usas. Creamos las cuentas por ti.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: V3Tokens.space24),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              mainAxisSpacing: V3Tokens.spaceMd,
              crossAxisSpacing: V3Tokens.spaceMd,
              childAspectRatio: 3.2,
            ),
            itemCount: kBanks.length,
            itemBuilder: (_, i) {
              final bank = kBanks[i];
              return V3BankTile(
                name: bank.name,
                brandColor: bank.color,
                icon: bank.icon,
                selected: selectedBankIds.contains(bank.id),
                onTap: () => onToggleBank(bank.id),
              );
            },
          ),
        ],
      ),
    );
  }
}
