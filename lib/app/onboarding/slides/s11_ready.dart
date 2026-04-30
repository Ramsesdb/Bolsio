import 'package:flutter/material.dart';
import 'package:kilatex/app/onboarding/theme/v3_tokens.dart';
import 'package:kilatex/app/onboarding/widgets/v3_slide_template.dart';

class Slide11Ready extends StatelessWidget {
  const Slide11Ready({
    super.key,
    required this.onFinish,
    required this.isFinishing,
  });

  final VoidCallback onFinish;
  final bool isFinishing;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    // Clamp hero size for narrow phones. Default target = 80 from spec.
    final double width = MediaQuery.of(context).size.width;
    final double computed = width * 0.18;
    final double heroSize = computed.clamp(56.0, 80.0).toDouble();

    return V3SlideTemplate(
      primaryLabel: isFinishing ? 'Un momento…' : 'Empezar',
      onPrimary: onFinish,
      primaryEnabled: !isFinishing,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: V3Tokens.space16),
          Text(
            'Todo\nlisto',
            style: V3Tokens.displayStyle(
              size: heroSize,
              letterSpacing: -3.5,
              height: 0.95,
              color: scheme.onSurface,
            ),
          ),
          const SizedBox(height: V3Tokens.space16),
          Container(
            width: 64,
            height: 3,
            decoration: BoxDecoration(
              color: V3Tokens.accent,
              borderRadius: BorderRadius.circular(999),
            ),
          ),
          const SizedBox(height: V3Tokens.space24),
          Text(
            'Wallex ya está configurado a tu medida. Empieza a controlar tus finanzas.',
            style: V3Tokens.uiStyle(
              size: 14,
              weight: FontWeight.w500,
              color: scheme.onSurfaceVariant,
            ),
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
