import 'package:flutter/material.dart';
import 'package:wallex/app/onboarding/theme/v3_tokens.dart';
import 'package:wallex/app/onboarding/widgets/v3_mini_phone_frame.dart';
import 'package:wallex/app/onboarding/widgets/v3_notification_card.dart';
import 'package:wallex/app/onboarding/widgets/v3_slide_template.dart';

class Slide05AutoImportSell extends StatelessWidget {
  const Slide05AutoImportSell({
    super.key,
    required this.onNext,
    this.onSkip,
  });

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
            'Registra tus gastos solo.',
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
          ),
          const SizedBox(height: V3Tokens.spaceMd),
          Text(
            'Wallex lee tus notificaciones de banco y agrega transacciones automáticamente.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: V3Tokens.space24),
          // V3MiniPhone (300x280) centered, framing two stacked notifs:
          //   1. Banesco Móvil (source bank) — delay 200ms, no highlight
          //   2. Wallex (auto-categorised) — delay 1000ms, highlighted
          // The v3 spec stacks them with a 8px vertical gap inside the
          // AMOLED interior. The frame itself "floats" centered against
          // the slide background.
          Align(
            alignment: Alignment.topCenter,
            child: const V3MiniPhoneFrame(
              height: 280,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  V3NotificationCard(
                    appName: 'Banesco Móvil',
                    title: 'Compra exitosa',
                    body:
                        'Compra por \$12,50 en Farmatodo procesada exitosamente',
                    amount: '09:41',
                    // Verde Banesco oficial (logo móvil).
                    brandColor: Color(0xFF00B04F),
                    icon: Icons.account_balance,
                    delay: Duration(milliseconds: 200),
                  ),
                  SizedBox(height: V3Tokens.spaceXs),
                  V3NotificationCard(
                    appName: 'Wallex',
                    title: '−\$12,50 · Farmatodo',
                    body: 'Categoría: Salud · Banesco',
                    amount: '09:41',
                    brandColor: V3Tokens.accent,
                    icon: Icons.account_balance_wallet,
                    delay: Duration(milliseconds: 1000),
                    highlighted: true,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
