import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:wallex/app/accounts/account_form.dart';
import 'package:wallex/app/transactions/form/transaction_form.page.dart';
import 'package:wallex/app/transactions/receipt_import/receipt_import_flow.dart';
import 'package:wallex/app/transactions/voice_input/voice_capture_flow.dart';
import 'package:wallex/core/database/services/transaction/transaction_service.dart';
import 'package:wallex/core/database/services/user-setting/user_setting_service.dart';
import 'package:wallex/core/presentation/widgets/confirm_dialog.dart';
import 'package:wallex/core/routes/route_utils.dart';
import 'package:wallex/i18n/generated/translations.g.dart';

void _showShouldCreateAccountWarn(BuildContext context) {
  final t = Translations.of(context);

  if (!context.mounted) return;

  confirmDialog(
    context,
    dialogTitle: t.home.should_create_account_header,
    contentParagraphs: [Text(t.home.should_create_account_message)],
    confirmationText: t.ui_actions.continue_text,
  ).then((value) {
    if (value != true || !context.mounted) return;

    RouteUtils.pushRoute(const AccountFormPage());
  });
}

void onNewTransactionButtonPressed(BuildContext context) {
  TransactionService.instance.checkIfCreateTransactionIsPossible().first.then((
    value,
  ) {
    if (!context.mounted) return;

    if (!value) {
      _showShouldCreateAccountWarn(context);
    } else {
      RouteUtils.pushRoute(const TransactionFormPage());
    }
  });
}

Future<bool> _canCreateTransaction(BuildContext context) async {
  final allowed = await TransactionService.instance
      .checkIfCreateTransactionIsPossible()
      .first;

  if (!context.mounted) return false;
  if (!allowed) {
    _showShouldCreateAccountWarn(context);
    return false;
  }

  return true;
}

Future<void> _showCameraPermissionDialog(BuildContext context) async {
  final t = Translations.of(context);

  await confirmDialog(
    context,
    dialogTitle: t.transaction.receipt_import.error.image_corrupt,
    contentParagraphs: [
      const Text(
        'Camera permission is required to take receipt photos. You can enable it in app settings.',
      ),
    ],
    confirmationText: t.ui_actions.continue_text,
  ).then((confirmed) async {
    if (confirmed == true) {
      await openAppSettings();
    }
  });
}

/// Internal descriptor for a child fan-out FAB action.
class _FanAction {
  const _FanAction({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;
}

class NewTransactionButton extends StatefulWidget {
  const NewTransactionButton({
    super.key,
    this.isExtended = true,
    this.scrollController,
  });

  final bool isExtended;
  final ScrollController? scrollController;

  @override
  State<NewTransactionButton> createState() => _NewTransactionButtonState();
}

class _NewTransactionButtonState extends State<NewTransactionButton>
    with SingleTickerProviderStateMixin {
  static const _fanDuration = Duration(milliseconds: 250);
  static const double _childSize = 48;
  static const double _gap = 10;
  static const double _mainFabSize = 56;

  late final AnimationController _ctrl;
  final GlobalKey _fabKey = GlobalKey();
  OverlayEntry? _overlayEntry;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: _fanDuration);
    _ctrl.addStatusListener(_onAnimStatus);
  }

  @override
  void dispose() {
    _ctrl.removeStatusListener(_onAnimStatus);
    _removeOverlay();
    _ctrl.dispose();
    super.dispose();
  }

  void _onAnimStatus(AnimationStatus status) {
    if (status == AnimationStatus.dismissed) {
      _removeOverlay();
    }
  }

  void _removeOverlay() {
    _overlayEntry?.remove();
    _overlayEntry = null;
  }

  bool get _isOpen => _ctrl.status == AnimationStatus.forward ||
      _ctrl.status == AnimationStatus.completed;

  Future<void> _startReceiptImport(ImageSource source) async {
    final canCreate = await _canCreateTransaction(context);
    if (!canCreate || !mounted) return;

    if (source == ImageSource.camera) {
      var status = await Permission.camera.status;
      if (!status.isGranted) {
        status = await Permission.camera.request();
      }

      if (!status.isGranted) {
        if (!mounted) return;
        await _showCameraPermissionDialog(context);
        return;
      }
    }

    if (!mounted) return;
    await ReceiptImportFlow.start(context, source);
  }

  Future<void> _startVoiceCapture() async {
    final canCreate = await _canCreateTransaction(context);
    if (!canCreate || !mounted) return;
    await VoiceCaptureFlow.start(context);
  }

  void _toggle() {
    if (_isOpen) {
      _close();
    } else {
      _open();
    }
  }

  void _open() {
    if (_overlayEntry != null) return;

    final renderBox =
        _fabKey.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox == null) return;

    final fabTopLeft = renderBox.localToGlobal(Offset.zero);
    final fabSize = renderBox.size;
    final screenSize = MediaQuery.of(context).size;

    // Right edge of FAB in screen coords; children are centered on the FAB's
    // horizontal center.
    final fabCenterX = fabTopLeft.dx + fabSize.width / 2;
    final fabTopY = fabTopLeft.dy;

    final t = Translations.of(context);

    final aiEnabled = appStateSettings[SettingKey.nexusAiEnabled] == '1';
    // aiVoiceEnabled defaults to '1' when null (no seed row means "enabled").
    final aiVoiceEnabled =
        appStateSettings[SettingKey.aiVoiceEnabled] != '0';
    final voiceAffordance = aiEnabled && aiVoiceEnabled;

    final actions = <_FanAction>[
      // Top (index 0, farthest from + FAB)
      _FanAction(
        icon: Icons.edit_note_rounded,
        tooltip: t.transaction.create,
        onPressed: () => onNewTransactionButtonPressed(context),
      ),
      // Voice (shown only when AI + voice sub-toggle are both enabled)
      if (voiceAffordance)
        _FanAction(
          icon: Icons.mic_rounded,
          tooltip: t.wallex_ai.voice_fab_tooltip,
          onPressed: _startVoiceCapture,
        ),
      // Middle
      _FanAction(
        icon: Icons.photo_library_outlined,
        tooltip: t.transaction.receipt_import.entry_gallery,
        onPressed: () => _startReceiptImport(ImageSource.gallery),
      ),
      // Bottom (index 2, closest to + FAB)
      _FanAction(
        icon: Icons.photo_camera_outlined,
        tooltip: t.transaction.receipt_import.entry_camera,
        onPressed: () => _startReceiptImport(ImageSource.camera),
      ),
    ];

    _overlayEntry = OverlayEntry(
      builder: (overlayContext) {
        return _FanOverlay(
          animation: _ctrl,
          fabCenterX: fabCenterX,
          fabTopY: fabTopY,
          fabSize: fabSize,
          screenSize: screenSize,
          childSize: _childSize,
          gap: _gap,
          actions: actions,
          onDismiss: _close,
        );
      },
    );

    Overlay.of(context, rootOverlay: true).insert(_overlayEntry!);
    _ctrl.forward();
  }

  void _close() {
    if (_overlayEntry == null) return;
    _ctrl.reverse();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SizedBox(
      key: _fabKey,
      width: _mainFabSize,
      height: _mainFabSize,
      child: AnimatedBuilder(
        animation: _ctrl,
        builder: (context, _) {
          return FloatingActionButton(
            heroTag: null,
            shape: const CircleBorder(),
            backgroundColor: cs.primaryContainer.withValues(alpha: 0.85),
            foregroundColor: cs.onPrimaryContainer,
            onPressed: _toggle,
            child: Transform.rotate(
              angle: _ctrl.value * 0.785398, // ~45deg at full open
              child: const Icon(Icons.add_rounded),
            ),
          );
        },
      ),
    );
  }
}

/// Overlay body: tap-out barrier + 3 staggered fanned FAB children, positioned
/// above the main FAB in global coords.
class _FanOverlay extends StatelessWidget {
  const _FanOverlay({
    required this.animation,
    required this.fabCenterX,
    required this.fabTopY,
    required this.fabSize,
    required this.screenSize,
    required this.childSize,
    required this.gap,
    required this.actions,
    required this.onDismiss,
  });

  final Animation<double> animation;
  final double fabCenterX;
  final double fabTopY;
  final Size fabSize;
  final Size screenSize;
  final double childSize;
  final double gap;
  final List<_FanAction> actions;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    // "bottom" coordinate (distance from screen bottom) of the main FAB's top.
    final fabBottomFromScreenBottom = screenSize.height - fabTopY;

    return Stack(
      children: [
        // Transparent tap-out barrier.
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onDismiss,
            child: const SizedBox.expand(),
          ),
        ),
        // Fanned children. index 0 -> top (farthest); index 2 -> just above +.
        for (int i = 0; i < actions.length; i++)
          _FanChild(
            animation: animation,
            index: i,
            totalCount: actions.length,
            bottom: fabBottomFromScreenBottom +
                8 +
                (actions.length - 1 - i) * (childSize + gap),
            centerX: fabCenterX,
            childSize: childSize,
            icon: actions[i].icon,
            tooltip: actions[i].tooltip,
            backgroundColor: cs.primaryContainer.withValues(alpha: 0.85),
            foregroundColor: cs.onPrimaryContainer,
            onPressed: () {
              onDismiss();
              actions[i].onPressed();
            },
          ),
      ],
    );
  }
}

class _FanChild extends StatelessWidget {
  const _FanChild({
    required this.animation,
    required this.index,
    required this.totalCount,
    required this.bottom,
    required this.centerX,
    required this.childSize,
    required this.icon,
    required this.tooltip,
    required this.backgroundColor,
    required this.foregroundColor,
    required this.onPressed,
  });

  final Animation<double> animation;
  final int index;
  final int totalCount;
  final double bottom;
  final double centerX;
  final double childSize;
  final IconData icon;
  final String tooltip;
  final Color backgroundColor;
  final Color foregroundColor;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    // Stagger: each child starts ~50ms after the previous. With 250ms total
    // duration, that's 0.2 units per stagger step. We stagger in reverse so
    // the child closest to the + FAB (largest index, i.e. bottom) animates
    // first.
    final staggerStart = (totalCount - 1 - index) * 0.2;
    final staggerEnd = (staggerStart + 0.8).clamp(0.0, 1.0);
    final curved = CurvedAnimation(
      parent: animation,
      curve: Interval(
        staggerStart.clamp(0.0, 1.0),
        staggerEnd,
        curve: Curves.easeOut,
      ),
      reverseCurve: Interval(
        staggerStart.clamp(0.0, 1.0),
        staggerEnd,
        curve: Curves.easeIn,
      ),
    );

    return AnimatedBuilder(
      animation: curved,
      builder: (context, _) {
        final v = curved.value;
        // Slide up from the + FAB toward final position.
        final slideOffset = (1 - v) * 20.0;
        return Positioned(
          left: centerX - childSize / 2,
          bottom: bottom - slideOffset,
          width: childSize,
          height: childSize,
          child: IgnorePointer(
            ignoring: v < 0.05,
            child: Opacity(
              opacity: v.clamp(0.0, 1.0),
              child: Transform.scale(
                scale: 0.6 + 0.4 * v,
                child: FloatingActionButton.small(
                  heroTag: null,
                  tooltip: tooltip,
                  shape: const CircleBorder(),
                  elevation: 2,
                  backgroundColor: backgroundColor,
                  foregroundColor: foregroundColor,
                  onPressed: onPressed,
                  child: Icon(icon),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
