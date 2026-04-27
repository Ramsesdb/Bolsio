import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:wallex/app/onboarding/theme/v3_tokens.dart';
import 'package:wallex/app/onboarding/widgets/v3_slide_template.dart';
import 'package:wallex/core/services/auto_import/capture/permission_coordinator.dart';

class Slide07PostNotifications extends StatefulWidget {
  const Slide07PostNotifications({
    super.key,
    required this.onNext,
  });

  final VoidCallback onNext;

  @override
  State<Slide07PostNotifications> createState() =>
      _Slide07PostNotificationsState();
}

class _Slide07PostNotificationsState extends State<Slide07PostNotifications>
    with WidgetsBindingObserver {
  bool _granted = false;
  bool _deniedPermanently = false;
  bool _awaitingResumeAfterRequest = false;
  bool _checked = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _bootstrap();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _awaitingResumeAfterRequest) {
      _refreshAndMaybeAdvance();
    }
  }

  Future<void> _bootstrap() async {
    final result = await PermissionCoordinator.instance.check();
    if (!mounted) return;
    if (result.postNotifications) {
      widget.onNext();
      return;
    }
    final status = await Permission.notification.status;
    if (!mounted) return;
    setState(() {
      _granted = false;
      _deniedPermanently = status.isPermanentlyDenied;
      _checked = true;
    });
  }

  Future<void> _refreshAndMaybeAdvance() async {
    final result = await PermissionCoordinator.instance.check();
    if (!mounted) return;
    final granted = result.postNotifications;
    final status = await Permission.notification.status;
    if (!mounted) return;
    setState(() {
      _granted = granted;
      _deniedPermanently = status.isPermanentlyDenied;
    });
    if (granted) {
      _awaitingResumeAfterRequest = false;
      widget.onNext();
    }
  }

  Future<void> _request() async {
    if (_deniedPermanently) {
      _awaitingResumeAfterRequest = true;
      await openAppSettings();
      return;
    }
    _awaitingResumeAfterRequest = true;
    await PermissionCoordinator.instance.requestPostNotifications();
    final result = await PermissionCoordinator.instance.check();
    if (!mounted) return;
    if (result.postNotifications) {
      _awaitingResumeAfterRequest = false;
      widget.onNext();
      return;
    }
    final status = await Permission.notification.status;
    if (!mounted) return;
    setState(() {
      _granted = false;
      _deniedPermanently = status.isPermanentlyDenied;
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (!_checked) {
      return const Center(child: CircularProgressIndicator());
    }
    return V3SlideTemplate(
      primaryLabel: _deniedPermanently ? 'Abrir ajustes' : 'Permitir notificaciones',
      onPrimary: _request,
      secondaryLabel: 'Omitir',
      onSecondary: widget.onNext,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Permite que Wallex te avise',
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
          ),
          const SizedBox(height: V3Tokens.spaceMd),
          Text(
            'Te notificaremos cuando capturemos una transacción nueva o si necesitamos tu atención. Puedes desactivarlo después en Ajustes.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: V3Tokens.space24),
          _NotifPreview(granted: _granted),
          if (_deniedPermanently) ...[
            const SizedBox(height: V3Tokens.space16),
            Container(
              padding: const EdgeInsets.all(V3Tokens.space16),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(V3Tokens.radiusMd),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.info_outline, size: 18),
                  const SizedBox(width: V3Tokens.spaceXs),
                  Expanded(
                    child: Text(
                      'El permiso fue denegado permanentemente. Ábrelo en Ajustes → Notificaciones para activarlo.',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _NotifPreview extends StatelessWidget {
  const _NotifPreview({required this.granted});

  final bool granted;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(V3Tokens.spaceMd),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(V3Tokens.radiusMd),
        border: Border.all(color: V3Tokens.accent, width: 1),
        boxShadow: [
          BoxShadow(
            color: V3Tokens.accent.withValues(alpha: 0.10),
            blurRadius: 0,
            spreadRadius: 3,
          ),
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
              color: V3Tokens.accent,
              borderRadius: BorderRadius.circular(V3Tokens.radiusSm),
            ),
            alignment: Alignment.center,
            child: Icon(
              granted ? Icons.notifications_active : Icons.notifications,
              color: Colors.white,
              size: 18,
            ),
          ),
          const SizedBox(width: V3Tokens.spaceMd),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Wallex',
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                        fontWeight: FontWeight.w500,
                      ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Nueva transacción registrada',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                ),
                Text(
                  'Capturamos un pago de Bs. 250,00 desde tu BDV.',
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
    );
  }
}
