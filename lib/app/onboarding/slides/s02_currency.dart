import 'package:flutter/material.dart';
import 'package:wallex/app/onboarding/theme/v3_tokens.dart';
import 'package:wallex/app/onboarding/widgets/v3_currency_tile.dart';
import 'package:wallex/app/onboarding/widgets/v3_slide_template.dart';

class Slide02Currency extends StatelessWidget {
  const Slide02Currency({
    super.key,
    required this.selected,
    required this.onSelect,
    required this.onNext,
    this.onSkip,
  });

  final String selected;
  final void Function(String code) onSelect;
  final VoidCallback onNext;
  final VoidCallback? onSkip;

  @override
  Widget build(BuildContext context) {
    return V3SlideTemplate(
      primaryLabel: 'Siguiente',
      onPrimary: onNext,
      onSecondary: onSkip,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '¿En qué moneda piensas?',
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
          ),
          const SizedBox(height: V3Tokens.spaceMd),
          Text(
            'Tu moneda preferida. La usamos para mostrar totales y presupuestos.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: V3Tokens.space24),
          V3CurrencyTile(
            code: 'USD',
            title: 'Dólar estadounidense',
            subtitle: 'Totales en USD. Ideal si ahorras en divisa.',
            selected: selected == 'USD',
            onTap: () => onSelect('USD'),
          ),
          const SizedBox(height: V3Tokens.spaceMd),
          V3CurrencyTile(
            code: 'VES',
            title: 'Bolívar',
            subtitle: 'Totales en Bs. Para gasto diario en Venezuela.',
            selected: selected == 'VES',
            onTap: () => onSelect('VES'),
          ),
          const SizedBox(height: V3Tokens.spaceMd),
          V3CurrencyTile(
            code: 'DUAL',
            title: 'Dual USD/VES',
            subtitle: 'Ambas monedas visibles a la vez.',
            selected: selected == 'DUAL',
            onTap: () => onSelect('DUAL'),
          ),
        ],
      ),
    );
  }
}
