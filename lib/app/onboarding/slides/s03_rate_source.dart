import 'package:flutter/material.dart';
import 'package:nitido/app/onboarding/theme/v3_tokens.dart';
import 'package:nitido/app/onboarding/widgets/v3_rate_tile.dart';
import 'package:nitido/app/onboarding/widgets/v3_slide_template.dart';

class Slide03RateSource extends StatelessWidget {
  const Slide03RateSource({
    super.key,
    required this.selected,
    required this.onSelect,
    required this.onNext,
    this.onSkip,
  });

  final String selected;
  final void Function(String source) onSelect;
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
            '¿Qué tasa de cambio usar?',
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
          ),
          const SizedBox(height: V3Tokens.spaceMd),
          Text(
            'Puedes cambiarla cuando quieras desde ajustes.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: V3Tokens.space24),
          V3RateTile(
            title: 'BCV',
            subtitle: 'Tasa oficial del Banco Central de Venezuela.',
            icon: Icons.account_balance,
            selected: selected == 'bcv',
            onTap: () => onSelect('bcv'),
          ),
          const SizedBox(height: V3Tokens.spaceMd),
          V3RateTile(
            title: 'Paralelo',
            subtitle: 'Tasa de mercado no oficial.',
            icon: Icons.trending_up,
            selected: selected == 'paralelo',
            onTap: () => onSelect('paralelo'),
          ),
        ],
      ),
    );
  }
}
