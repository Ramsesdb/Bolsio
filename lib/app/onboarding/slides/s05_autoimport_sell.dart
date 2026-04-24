import 'package:flutter/material.dart';
import 'package:wallex/app/onboarding/theme/v3_tokens.dart';
import 'package:wallex/app/onboarding/widgets/v3_notification_card.dart';
import 'package:wallex/app/onboarding/widgets/v3_slide_template.dart';

class Slide05AutoImportSell extends StatelessWidget {
  const Slide05AutoImportSell({super.key, required this.onNext});

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
          const V3NotificationCard(
            appName: 'Banco de Venezuela',
            title: 'Pago recibido',
            body: 'Transferencia de Juan Pérez',
            amount: '+50 Bs',
            brandColor: Color(0xFF1A237E),
            icon: Icons.account_balance,
          ),
          const SizedBox(height: V3Tokens.spaceMd),
          const V3NotificationCard(
            appName: 'Zinli',
            title: 'Compra aprobada',
            body: 'Supermercado La Candelaria',
            amount: '-\$12.40',
            brandColor: Color(0xFF6A1B9A),
            icon: Icons.wallet,
            delay: Duration(milliseconds: 200),
          ),
          const SizedBox(height: V3Tokens.spaceMd),
          const V3NotificationCard(
            appName: 'Binance',
            title: 'Depósito confirmado',
            body: 'USDT recibido en cuenta',
            amount: '+\$100.00',
            brandColor: Color(0xFFF3BA2F),
            icon: Icons.currency_bitcoin,
            delay: Duration(milliseconds: 400),
          ),
        ],
      ),
    );
  }
}
