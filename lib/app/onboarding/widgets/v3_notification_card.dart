import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:wallex/app/onboarding/theme/v3_tokens.dart';

/// Animated notification card used in slide 5 (auto-import sell).
/// Entrance animation: `v3-notif-in` — fade + slide from top-right over
/// [V3Tokens.notifInStagger], with a per-card [delay] for staggering.
class V3NotificationCard extends StatelessWidget {
  const V3NotificationCard({
    super.key,
    required this.appName,
    required this.title,
    required this.body,
    required this.amount,
    required this.brandColor,
    required this.icon,
    this.delay = Duration.zero,
  });

  final String appName;
  final String title;
  final String body;
  final String amount;
  final Color brandColor;
  final IconData icon;
  final Duration delay;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(V3Tokens.spaceMd),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(V3Tokens.radiusMd),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: brandColor,
              borderRadius: BorderRadius.circular(V3Tokens.radiusSm),
            ),
            alignment: Alignment.center,
            child: Icon(icon, color: Colors.white, size: 18),
          ),
          const SizedBox(width: V3Tokens.spaceMd),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        appName,
                        style: Theme.of(context).textTheme.labelMedium?.copyWith(
                              color: scheme.onSurfaceVariant,
                              fontWeight: FontWeight.w500,
                            ),
                      ),
                    ),
                    Text(
                      amount,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: V3Tokens.accent,
                          ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  title,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                ),
                Text(
                  body,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    )
        .animate(delay: delay)
        .fadeIn(duration: V3Tokens.notifInStagger, curve: Curves.easeOut)
        .slideX(
          begin: 0.25,
          end: 0,
          duration: V3Tokens.notifInStagger,
          curve: Curves.easeOutCubic,
        );
  }
}
