import 'package:flutter/material.dart';
import 'package:wallex/app/onboarding/theme/v3_tokens.dart';

/// Full-screen overlay shown during slide 9 while `PersonalVESeeder.seedAll`
/// runs. Guaranteed to be visible at least 500 ms (enforced by caller via
/// `Future.wait([seedFuture, Future.delayed(500ms)])`).
class V3SeedingOverlay extends StatelessWidget {
  const V3SeedingOverlay({
    super.key,
    required this.title,
    required this.subtitle,
  });

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.all(V3Tokens.space24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 96,
            height: 96,
            decoration: BoxDecoration(
              color: V3Tokens.accent.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: const SizedBox(
              width: 44,
              height: 44,
              child: CircularProgressIndicator(
                strokeWidth: 3.5,
                color: V3Tokens.accent,
              ),
            ),
          ),
          const SizedBox(height: V3Tokens.space24),
          Text(
            title,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: V3Tokens.spaceMd),
          Text(
            subtitle,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
