import 'package:flutter/material.dart';
import 'package:wallex/app/onboarding/bank_options.dart';
import 'package:wallex/app/onboarding/theme/v3_tokens.dart';
import 'package:wallex/app/onboarding/widgets/v3_bank_tile.dart';
import 'package:wallex/app/onboarding/widgets/v3_slide_template.dart';
import 'package:wallex/core/database/services/user-setting/user_setting_service.dart';
import 'package:wallex/core/services/auto_import/supported_banks.dart';
import 'package:wallex/core/services/bank_detection/bank_detection_service.dart';

final RegExp _kPlayStoreUrl = RegExp(
  r'^https://play\.google\.com/store/apps/details\?id=([\w\.]+)',
);

class Slide09AppsIncluded extends StatefulWidget {
  const Slide09AppsIncluded({
    super.key,
    required this.onNext,
    this.onSkip,
  });

  final VoidCallback onNext;
  final VoidCallback? onSkip;

  @override
  State<Slide09AppsIncluded> createState() => _Slide09AppsIncludedState();
}

class _Slide09AppsIncludedState extends State<Slide09AppsIncluded> {
  List<BankOption> _tiles = const [];
  final Map<String, bool> _toggleState = {};
  bool _loading = true;

  final TextEditingController _urlController = TextEditingController();
  bool _urlValid = false;

  @override
  void initState() {
    super.initState();
    _loadDetected();
    _urlController.addListener(_onUrlChanged);
  }

  @override
  void dispose() {
    _urlController.removeListener(_onUrlChanged);
    _urlController.dispose();
    super.dispose();
  }

  void _onUrlChanged() {
    final text = _urlController.text.trim();
    final valid = _kPlayStoreUrl.hasMatch(text);
    if (valid != _urlValid) {
      setState(() => _urlValid = valid);
    }
  }

  Future<void> _loadDetected() async {
    final ids = await BankDetectionService().getInstalledBankIds();
    final tiles = <BankOption>[];
    if (ids.isEmpty) {
      // Fallback: show only banks with a working parser so the user can
      // still configure auto-import even when detection returns nothing.
      // Banks without a parser ("Próximamente") only appear when actually
      // detected on-device — no point showing a disabled tile otherwise.
      tiles.addAll(
        kBanks.where(
          (b) => b.profileId != null && b.autoImportSupported,
        ),
      );
    } else {
      // Dedupe profileIds (BDV/Zinli have legacy package aliases).
      final seen = <String>{};
      for (final profileId in ids) {
        if (!seen.add(profileId)) continue;
        final match = bankOptionByProfileId(profileId);
        if (match != null) tiles.add(match);
      }
    }
    final toggles = <String, bool>{
      for (final t in tiles)
        t.profileId!:
            UserSettingService.instance.isProfileEnabled(t.profileId!),
    };
    if (!mounted) return;
    setState(() {
      _tiles = tiles;
      _toggleState
        ..clear()
        ..addAll(toggles);
      _loading = false;
    });
  }

  SettingKey? _settingKeyFor(String profileId) {
    switch (profileId) {
      case 'bdv_sms':
        return SettingKey.bdvSmsProfileEnabled;
      case 'bdv_notif':
        return SettingKey.bdvNotifProfileEnabled;
      case 'binance_api':
        return SettingKey.binanceApiProfileEnabled;
      case 'zinli_notif':
        return SettingKey.zinliNotifProfileEnabled;
    }
    return null;
  }

  Future<void> _onToggle(String profileId, bool value) async {
    final key = _settingKeyFor(profileId);
    // No SettingKey means this profile has no real parser yet ("Próximamente"
    // tiles). We still update the in-memory toggle state for visual
    // consistency, but skip persistence — there's nothing to enable.
    if (key != null) {
      await UserSettingService.instance.setItem(key, value ? '1' : '0');
    }
    if (!mounted) return;
    setState(() => _toggleState[profileId] = value);
  }

  /// Visual-only "remove" affordance: drops the tile from the visible list.
  /// For tiles with a real parser, also turns the persisted toggle OFF so
  /// the user's intent is reflected in settings.
  Future<void> _onRemove(String profileId) async {
    final key = _settingKeyFor(profileId);
    if (key != null) {
      await UserSettingService.instance.setItem(key, '0');
    }
    if (!mounted) return;
    setState(() {
      _tiles = _tiles.where((t) => t.profileId != profileId).toList();
      _toggleState.remove(profileId);
    });
  }

  Future<void> _onAddManual() async {
    final text = _urlController.text.trim();
    final match = _kPlayStoreUrl.firstMatch(text);
    if (match == null) return;
    final pkg = match.group(1);
    final messenger = ScaffoldMessenger.of(context);
    if (pkg == null) {
      messenger.showSnackBar(
        const SnackBar(content: Text('URL no válida')),
      );
      return;
    }
    final profileId = kAnyPackageToProfileId[pkg];
    if (profileId == null) {
      messenger.showSnackBar(
        const SnackBar(content: Text('App no soportada todavía')),
      );
      return;
    }
    final option = bankOptionByProfileId(profileId);
    if (option == null) {
      messenger.showSnackBar(
        const SnackBar(content: Text('App no soportada todavía')),
      );
      return;
    }
    // Already in list? Just enable its toggle.
    final already = _tiles.any((t) => t.profileId == profileId);
    if (!already) {
      setState(() => _tiles = [..._tiles, option]);
    }
    await _onToggle(profileId, true);
    _urlController.clear();
    if (!mounted) return;
    messenger.showSnackBar(
      SnackBar(content: Text('${option.name} añadida')),
    );
  }

  bool get _hasGPay =>
      _tiles.any((t) => t.profileId == 'gpay_notif');

  Future<void> _onAddGPay() async {
    if (_hasGPay) return;
    final option = bankOptionByProfileId('gpay_notif');
    if (option == null) return;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _tiles = [..._tiles, option]);
    // Mark the toggle ON visually. Google Pay has no parser yet so this
    // does not persist a SettingKey — it just keeps the tile consistent
    // with the rest of the list.
    await _onToggle('gpay_notif', true);
    if (!mounted) return;
    messenger.showSnackBar(
      const SnackBar(content: Text('Google Pay añadido')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final mutedLabel = isDark ? V3Tokens.mutedDark : V3Tokens.mutedLight;
    final detectedCount = _tiles.length;

    return V3SlideTemplate(
      primaryLabel: 'Siguiente',
      onPrimary: widget.onNext,
      onSecondary: widget.onSkip,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Aplicaciones incluidas',
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
          ),
          const SizedBox(height: V3Tokens.spaceMd),
          Text(
            'Elige de qué apps queremos leer notificaciones. Puedes cambiarlo luego en Ajustes.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: V3Tokens.space24),
          if (_loading)
            const Padding(
              padding: EdgeInsets.all(V3Tokens.space24),
              child: Center(child: CircularProgressIndicator()),
            )
          else ...[
            _SectionLabel(
              text: 'DETECTADAS · $detectedCount',
              color: mutedLabel,
            ),
            const SizedBox(height: V3Tokens.spaceMd),
            if (_tiles.isEmpty)
              Container(
                padding: const EdgeInsets.all(V3Tokens.space16),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(V3Tokens.radiusMd),
                ),
                child: const Text(
                  'No detectamos apps compatibles instaladas. Podrás activarlas más tarde en Ajustes → Auto-import.',
                ),
              )
            else
              Column(
                children: [
                  for (final tile in _tiles) ...[
                    V3BankTile(
                      name: tile.name,
                      brandColor: tile.color,
                      icon: tile.icon,
                      selected: _toggleState[tile.profileId] ?? true,
                      onTap: null,
                      // Disable the switch for tiles without a parser yet:
                      // pass null so V3Switch renders at 0.4 opacity and
                      // ignores taps. The "Próximamente" badge makes the
                      // reason visible to the user.
                      onChanged: tile.autoImportSupported
                          ? (v) => _onToggle(tile.profileId!, v)
                          : null,
                      onRemove: () => _onRemove(tile.profileId!),
                      badgeLabel:
                          tile.autoImportSupported ? null : 'Próximamente',
                    ),
                    const SizedBox(height: V3Tokens.spaceSm),
                  ],
                ],
              ),
            const SizedBox(height: V3Tokens.space24),
            _SectionLabel(
              text: 'AGREGAR MANUALMENTE',
              color: mutedLabel,
            ),
            const SizedBox(height: V3Tokens.spaceMd),
            _ManualInstructions(color: mutedLabel),
            const SizedBox(height: V3Tokens.spaceMd),
            _AddManualField(
              controller: _urlController,
              enabled: _urlValid,
              onSubmit: _onAddManual,
              isDark: isDark,
            ),
            const SizedBox(height: V3Tokens.spaceMd),
            _AddGPayChip(
              isDark: isDark,
              alreadyAdded: _hasGPay,
              onTap: _hasGPay ? null : _onAddGPay,
            ),
          ],
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.text, required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: V3Tokens.uiStyle(
        size: 11,
        weight: FontWeight.w600,
        letterSpacing: 0.8,
        color: color,
      ),
    );
  }
}

/// Helper text shown above the manual-add TextField. Explains how to grab
/// the Play Store URL from the long-press app menu on the home screen.
class _ManualInstructions extends StatelessWidget {
  const _ManualInstructions({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    final base = V3Tokens.uiStyle(
      size: 12.5,
      weight: FontWeight.w400,
      color: color,
      height: 1.5,
    );
    final bold = base.copyWith(fontWeight: FontWeight.w600);
    return Text.rich(
      TextSpan(
        style: base,
        children: [
          const TextSpan(
            text:
                'Mantén presionada la app bancaria en tu pantalla de inicio → toca ',
          ),
          TextSpan(text: 'Información de la app', style: bold),
          const TextSpan(
            text:
                ' → busca la opción para abrirla en Play Store y copia el enlace.',
          ),
        ],
      ),
    );
  }
}

class _AddManualField extends StatelessWidget {
  const _AddManualField({
    required this.controller,
    required this.enabled,
    required this.onSubmit,
    required this.isDark,
  });

  final TextEditingController controller;
  final bool enabled;
  final VoidCallback onSubmit;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final mutedColor = isDark ? V3Tokens.mutedDark : V3Tokens.mutedLight;
    final borderColor = isDark
        ? const Color(0x24FFFFFF) // ~0.14 alpha white
        : const Color(0x24000000); // ~0.14 alpha black

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(V3Tokens.radiusMd),
        border: Border.all(color: borderColor, width: 1),
      ),
      child: Row(
        children: [
          Icon(Icons.link, size: 18, color: mutedColor),
          const SizedBox(width: V3Tokens.spaceMd),
          Expanded(
            child: TextField(
              controller: controller,
              keyboardType: TextInputType.url,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) {
                if (enabled) onSubmit();
              },
              style: V3Tokens.uiStyle(
                size: 14,
                weight: FontWeight.w500,
                color: scheme.onSurface,
              ),
              decoration: InputDecoration(
                isDense: true,
                contentPadding: EdgeInsets.zero,
                border: InputBorder.none,
                hintText: 'Pega la URL de Play Store',
                hintStyle: V3Tokens.uiStyle(
                  size: 14,
                  weight: FontWeight.w500,
                  color: mutedColor,
                ),
              ),
            ),
          ),
          const SizedBox(width: V3Tokens.spaceXs),
          SizedBox(
            width: 32,
            height: 32,
            child: Material(
              color: enabled
                  ? V3Tokens.accent
                  : V3Tokens.accent.withValues(alpha: 0.25),
              borderRadius: BorderRadius.circular(8),
              child: InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: enabled ? onSubmit : null,
                child: const Icon(
                  Icons.check_rounded,
                  size: 18,
                  color: Color(0xFF0A0A0A),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Pill-shaped shortcut to add Google Pay manually without needing to paste
/// a Play Store URL. Renders as a 999-radius chip with an "+ Añadir G Pay"
/// label. When [onTap] is null the chip renders disabled (lower opacity)
/// — used when Google Pay is already in the list.
class _AddGPayChip extends StatelessWidget {
  const _AddGPayChip({
    required this.isDark,
    required this.alreadyAdded,
    required this.onTap,
  });

  final bool isDark;
  final bool alreadyAdded;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final mutedColor = isDark ? V3Tokens.mutedDark : V3Tokens.mutedLight;
    final pillBg = isDark ? V3Tokens.pillBgDark : V3Tokens.pillBgLight;
    final borderColor = isDark
        ? const Color(0x1FFFFFFF) // ~0.12 alpha white
        : const Color(0x1F000000); // ~0.12 alpha black
    final disabled = onTap == null;
    final label = alreadyAdded ? 'Ya añadido' : 'Añadir G Pay';
    return Opacity(
      opacity: disabled ? 0.55 : 1.0,
      child: Material(
        color: pillBg,
        borderRadius: BorderRadius.circular(V3Tokens.radiusPill),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(V3Tokens.radiusPill),
          child: Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(V3Tokens.radiusPill),
              border: Border.all(color: borderColor, width: 1),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  alreadyAdded ? Icons.check_rounded : Icons.add,
                  size: 16,
                  color: mutedColor,
                ),
                const SizedBox(width: V3Tokens.spaceXs),
                Text(
                  label,
                  style: V3Tokens.uiStyle(
                    size: 13,
                    weight: FontWeight.w600,
                    color: scheme.onSurface,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
