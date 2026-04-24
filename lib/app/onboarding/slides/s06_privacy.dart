import 'package:flutter/material.dart';
import 'package:wallex/app/onboarding/theme/v3_tokens.dart';
import 'package:wallex/app/onboarding/widgets/v3_slide_template.dart';

class Slide06Privacy extends StatelessWidget {
  const Slide06Privacy({super.key, required this.onNext});

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
            'Tu privacidad es prioridad',
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
          ),
          const SizedBox(height: V3Tokens.spaceMd),
          Text(
            'Cómo manejamos tus datos.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: V3Tokens.space24),
          const _PrivacyBullet(
            icon: Icons.phone_android,
            title: 'Procesamiento en tu dispositivo',
            body: 'Las notificaciones se leen y parsean localmente. No salen de tu teléfono.',
          ),
          const SizedBox(height: V3Tokens.space16),
          const _PrivacyBullet(
            icon: Icons.lock_outline,
            title: 'Sin envío a terceros',
            body: 'No compartimos tu información con anunciantes ni agregadores.',
          ),
          const SizedBox(height: V3Tokens.space16),
          const _PrivacyBullet(
            icon: Icons.filter_alt_outlined,
            title: 'Solo tus bancos',
            body: 'Solo leemos notificaciones que coinciden con patrones conocidos (BDV, Zinli, Binance, etc.).',
          ),
        ],
      ),
    );
  }
}

class _PrivacyBullet extends StatelessWidget {
  const _PrivacyBullet({
    required this.icon,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: V3Tokens.accent.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(V3Tokens.radiusMd),
          ),
          alignment: Alignment.center,
          child: Icon(icon, color: V3Tokens.accent, size: 20),
        ),
        const SizedBox(width: V3Tokens.space16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
              ),
              const SizedBox(height: 2),
              Text(
                body,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
