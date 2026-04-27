import 'package:flutter/material.dart';
import 'package:wallex/app/onboarding/theme/v3_tokens.dart';
import 'package:wallex/app/onboarding/widgets/v3_mini_phone_frame.dart';

/// Mini "Acceso a notificaciones" Android settings mockup, rendered inside a
/// [V3MiniPhoneFrame].
///
/// Shows Wallex pulsing at the top of the list (or a static green check when
/// the permission is already granted), and four faded peer apps (Google Pay,
/// Gmail, WhatsApp, Instagram) so the user's eye lands on the action they
/// need to take in the real Android settings screen.
///
/// Used by:
/// - `Slide08ActivateListener` (full onboarding flow).
/// - `ReturningUserFlow` step 2 (returning Google user).
class V3NotifAccessMockup extends StatelessWidget {
  const V3NotifAccessMockup({
    super.key,
    required this.granted,
    this.height = 300,
  });

  final bool granted;
  final double height;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final faint = isDark ? V3Tokens.faintDark : V3Tokens.faintLight;
    return V3MiniPhoneFrame(
      height: height,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Acceso a notificaciones',
            style: V3Tokens.uiStyle(
              size: 12,
              weight: FontWeight.w700,
              color: scheme.onSurface,
            ),
          ),
          const SizedBox(height: V3Tokens.spaceXs),
          _AppRow(
            name: 'Wallex',
            subtitle: 'Servicio de notificaciones',
            icon: Icons.account_balance_wallet,
            iconColor: V3Tokens.accent,
            on: true,
            highlighted: !granted,
            grantedCheck: granted,
          ),
          const SizedBox(height: V3Tokens.spaceXs),
          _AppRow(
            name: 'Google Pay',
            icon: Icons.payment,
            iconColor: const Color(0xFF5F6368),
            on: false,
            faintColor: faint,
          ),
          const SizedBox(height: V3Tokens.spaceXs),
          _AppRow(
            name: 'Gmail',
            icon: Icons.email,
            iconColor: const Color(0xFFD93025),
            on: false,
            faintColor: faint,
          ),
          const SizedBox(height: V3Tokens.spaceXs),
          _AppRow(
            name: 'WhatsApp',
            icon: Icons.chat,
            iconColor: const Color(0xFF25D366),
            on: false,
            faintColor: faint,
          ),
          const SizedBox(height: V3Tokens.spaceXs),
          _AppRow(
            name: 'Instagram',
            icon: Icons.camera_alt,
            iconColor: const Color(0xFFE1306C),
            on: false,
            faintColor: faint,
          ),
        ],
      ),
    );
  }
}

/// Single row inside [V3NotifAccessMockup]. When [highlighted] is true, the
/// row is wrapped in a pulsing accent border (alpha 0.15 → 0.4 → 0.15
/// over 2400ms). When [faintColor] is non-null the entire row renders at
/// reduced opacity to fade out the non-target apps.
class _AppRow extends StatefulWidget {
  const _AppRow({
    required this.name,
    required this.icon,
    required this.iconColor,
    required this.on,
    this.subtitle,
    this.highlighted = false,
    this.grantedCheck = false,
    this.faintColor,
  });

  final String name;
  final String? subtitle;
  final IconData icon;
  final Color iconColor;
  final bool on;
  final bool highlighted;
  final bool grantedCheck;
  final Color? faintColor;

  @override
  State<_AppRow> createState() => _AppRowState();
}

class _AppRowState extends State<_AppRow>
    with SingleTickerProviderStateMixin {
  AnimationController? _pulseCtrl;

  @override
  void initState() {
    super.initState();
    if (widget.highlighted) {
      _pulseCtrl = AnimationController(
        vsync: this,
        duration: V3Tokens.pulse,
      )..repeat();
    }
  }

  @override
  void didUpdateWidget(covariant _AppRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.highlighted && _pulseCtrl == null) {
      _pulseCtrl = AnimationController(
        vsync: this,
        duration: V3Tokens.pulse,
      )..repeat();
    } else if (!widget.highlighted && _pulseCtrl != null) {
      _pulseCtrl?.dispose();
      _pulseCtrl = null;
    }
  }

  @override
  void dispose() {
    _pulseCtrl?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final faded = widget.faintColor != null;
    final row = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: Row(
        children: [
          Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              color: widget.iconColor,
              borderRadius: BorderRadius.circular(6),
            ),
            alignment: Alignment.center,
            child: Icon(widget.icon, size: 14, color: Colors.white),
          ),
          const SizedBox(width: V3Tokens.spaceXs),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  widget.name,
                  style: V3Tokens.uiStyle(
                    size: 11,
                    weight: FontWeight.w600,
                    color: scheme.onSurface,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (widget.subtitle != null)
                  Text(
                    widget.subtitle!,
                    style: V3Tokens.uiStyle(
                      size: 9,
                      weight: FontWeight.w500,
                      color: scheme.onSurfaceVariant,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          ),
          if (widget.grantedCheck)
            const Icon(Icons.check_circle, color: Color(0xFF22C55E), size: 18)
          else
            _Toggle(on: widget.on),
        ],
      ),
    );

    Widget content = ClipRRect(
      borderRadius: BorderRadius.circular(V3Tokens.radiusSm),
      child: row,
    );

    if (widget.highlighted && _pulseCtrl != null) {
      content = AnimatedBuilder(
        animation: _pulseCtrl!,
        builder: (context, child) {
          // alpha 0.15 → 0.4 → 0.15 across the cycle.
          final t = _pulseCtrl!.value;
          final tri = t < 0.5 ? t * 2 : (1 - t) * 2;
          final alpha = 0.15 + (0.4 - 0.15) * tri;
          return DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(V3Tokens.radiusSm),
              border: Border.all(
                color: V3Tokens.accent.withValues(alpha: alpha),
                width: 1,
              ),
              boxShadow: [
                BoxShadow(
                  color: V3Tokens.accent.withValues(alpha: alpha * 0.6),
                  blurRadius: 8,
                  spreadRadius: 0,
                ),
              ],
            ),
            child: child,
          );
        },
        child: content,
      );
    }

    if (faded) {
      content = Opacity(opacity: 0.38, child: content);
    }

    return content;
  }
}

/// Static visual toggle (28x16 pill). Accent fill when [on], otherwise a
/// neutral track with the knob at the left edge.
class _Toggle extends StatelessWidget {
  const _Toggle({required this.on});

  final bool on;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final offTrack = isDark
        ? V3Tokens.borderStrongDark
        : V3Tokens.borderStrongLight;
    return Container(
      width: 28,
      height: 16,
      decoration: BoxDecoration(
        color: on ? V3Tokens.accent : offTrack,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Stack(
        children: [
          AnimatedAlign(
            duration: const Duration(milliseconds: 160),
            alignment: on ? Alignment.centerRight : Alignment.centerLeft,
            child: Container(
              width: 12,
              height: 12,
              margin: const EdgeInsets.symmetric(horizontal: 2),
              decoration: const BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
