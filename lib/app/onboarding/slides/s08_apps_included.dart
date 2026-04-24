import 'package:flutter/material.dart';
import 'package:wallex/app/onboarding/bank_options.dart';
import 'package:wallex/app/onboarding/theme/v3_tokens.dart';
import 'package:wallex/app/onboarding/widgets/v3_bank_tile.dart';
import 'package:wallex/app/onboarding/widgets/v3_slide_template.dart';
import 'package:wallex/core/database/services/user-setting/user_setting_service.dart';
import 'package:wallex/core/services/bank_detection/bank_detection_service.dart';

class Slide08AppsIncluded extends StatefulWidget {
  const Slide08AppsIncluded({super.key, required this.onNext});

  final VoidCallback onNext;

  @override
  State<Slide08AppsIncluded> createState() => _Slide08AppsIncludedState();
}

class _Slide08AppsIncludedState extends State<Slide08AppsIncluded> {
  List<BankOption> _tiles = const [];
  final Map<String, bool> _toggleState = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadDetected();
  }

  Future<void> _loadDetected() async {
    final ids = await BankDetectionService().getInstalledBankIds();
    final tiles = <BankOption>[];
    if (ids.isEmpty) {
      // Fallback: show the full static list so the user can still configure
      // profiles even when detection returns nothing.
      tiles.addAll(kBanks.where((b) => b.profileId != null));
    } else {
      for (final profileId in ids) {
        final match = bankOptionByProfileId(profileId);
        if (match != null) tiles.add(match);
      }
    }
    final toggles = <String, bool>{
      for (final t in tiles)
        t.profileId!: UserSettingService.instance.isProfileEnabled(t.profileId!),
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
    if (key == null) return;
    await UserSettingService.instance.setItem(key, value ? '1' : '0');
    if (!mounted) return;
    setState(() => _toggleState[profileId] = value);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return V3SlideTemplate(
      primaryLabel: 'Siguiente',
      onPrimary: widget.onNext,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Apps detectadas',
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
          else if (_tiles.isEmpty)
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
                    onChanged: (v) => _onToggle(tile.profileId!, v),
                  ),
                  const SizedBox(height: V3Tokens.spaceSm),
                ],
              ],
            ),
        ],
      ),
    );
  }
}
