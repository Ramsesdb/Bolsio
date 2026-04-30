import 'package:flutter/material.dart';
import 'package:kilatex/app/settings/pages/ai/ai_settings.page.dart';
import 'package:kilatex/core/database/services/user-setting/user_setting_service.dart';
import 'package:kilatex/core/presentation/app_colors.dart';
import 'package:kilatex/core/presentation/widgets/tappable.dart';
import 'package:kilatex/core/routes/route_utils.dart';

class WallexAiHeroCard extends StatefulWidget {
  const WallexAiHeroCard({super.key});

  @override
  State<WallexAiHeroCard> createState() => _WallexAiHeroCardState();
}

class _WallexAiHeroCardState extends State<WallexAiHeroCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _glowAnim;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat(reverse: true);
    _glowAnim = Tween<double>(begin: 0.18, end: 0.42).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  String _providerLabel(String? providerId) {
    switch (providerId) {
      case 'nexus':
        return 'Nexus';
      case 'openai':
        return 'OpenAI';
      case 'anthropic':
        return 'Anthropic';
      case 'gemini':
        return 'Gemini';
      default:
        return providerId ?? 'Nexus';
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final theme = Theme.of(context);
    final appColors = AppColors.of(context);

    final aiEnabled = appStateSettings[SettingKey.nexusAiEnabled] == '1';
    final provider = _providerLabel(appStateSettings[SettingKey.activeAiProvider]);

    return AnimatedBuilder(
      animation: _glowAnim,
      builder: (ctx, child) {
        final isDark = Theme.of(ctx).brightness == Brightness.dark;
        final glowAlpha = isDark ? _glowAnim.value : _glowAnim.value * 0.35;
        return DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                cs.primary.withValues(alpha: 0.08),
                Colors.transparent,
              ],
            ),
            boxShadow: [
              BoxShadow(
                color: cs.primary.withValues(alpha: glowAlpha),
                blurRadius: 18,
                spreadRadius: 1,
              ),
            ],
          ),
          child: child!,
        );
      },
      child: Tappable(
        borderRadius: BorderRadius.circular(16),
        onTap: () => RouteUtils.pushRoute(const AiSettingsPage()),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            spacing: 12,
            children: [
              Icon(Icons.auto_awesome, size: 28, color: cs.primary),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  spacing: 2,
                  children: [
                    Text(
                      'Wallex AI',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      aiEnabled
                          ? 'Activado · $provider'
                          : 'Configura tu asistente financiero',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: appColors.textHint,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.arrow_forward_ios, size: 14, color: appColors.textHint),
            ],
          ),
        ),
      ),
    );
  }
}
