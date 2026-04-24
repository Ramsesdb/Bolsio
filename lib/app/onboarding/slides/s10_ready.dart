import 'package:flutter/material.dart';
import 'package:wallex/app/onboarding/theme/v3_tokens.dart';
import 'package:wallex/app/onboarding/widgets/v3_slide_template.dart';

class Slide10Ready extends StatelessWidget {
  const Slide10Ready({
    super.key,
    required this.onFinish,
    required this.isFinishing,
  });

  final VoidCallback onFinish;
  final bool isFinishing;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return V3SlideTemplate(
      primaryLabel: isFinishing ? 'Un momento…' : 'Empezar',
      onPrimary: onFinish,
      primaryEnabled: !isFinishing,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 88,
              height: 88,
              decoration: BoxDecoration(
                color: V3Tokens.accent.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: const Icon(
                Icons.check_rounded,
                color: V3Tokens.accent,
                size: 48,
              ),
            ),
          ),
          const SizedBox(height: V3Tokens.space24),
          Text(
            '¡Todo listo!',
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: V3Tokens.spaceMd),
          Text(
            'Wallex ya está configurado a tu medida. Empieza a controlar tus finanzas.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: V3Tokens.space24),
          const _Feature(
            icon: Icons.auto_awesome,
            text: 'Registro automático de transacciones',
          ),
          const SizedBox(height: V3Tokens.spaceMd),
          const _Feature(
            icon: Icons.pie_chart_outline,
            text: 'Dashboards y presupuestos multi-moneda',
          ),
          const SizedBox(height: V3Tokens.spaceMd),
          const _Feature(
            icon: Icons.shield_outlined,
            text: 'Tus datos en tu dispositivo',
          ),
        ],
      ),
    );
  }
}

class _Feature extends StatelessWidget {
  const _Feature({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: V3Tokens.accent, size: 22),
        const SizedBox(width: V3Tokens.spaceMd),
        Expanded(child: Text(text)),
      ],
    );
  }
}
