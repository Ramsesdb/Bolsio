# Design: profile-editor-redesign

## Technical Approach

Single-file rewrite of [edit_profile_modal.dart](c:/Users/ramse/OneDrive/Documents/vacas/wallex/lib/app/settings/widgets/edit_profile_modal.dart) plus additive getters on [bolsio_ai_tokens.dart](c:/Users/ramse/OneDrive/Documents/vacas/wallex/lib/app/chat/theme/bolsio_ai_tokens.dart). State for the avatar selection collapses into a sealed class held by the existing `_EditProfileModalState`. No new providers, no theme extension, no Drift change. The mockup at [editar-perfil.html](c:/Users/ramse/OneDrive/Documents/vacas/wallex/mockups/editar-perfil.html) is the visual contract.

## 1. State machine — `_selectedAvatarSource`

**Shape**: `sealed class _AvatarSource` with two subclasses. Picked sealed class over `enum`-with-data because Dart 3 sealed types give exhaustive `switch` with payload, which is what the grid renderer and Save guard both need.

```dart
sealed class _AvatarSource { const _AvatarSource(); }
class _UploadedPhoto extends _AvatarSource { const _UploadedPhoto(); }
class _Predeterminado extends _AvatarSource {
  final String name;          // e.g. 'man', 'executive_woman'
  const _Predeterminado(this.name);
}
```

No `None` state. `initState` resolves to `_UploadedPhoto()` if `_loadCustomAvatarState` finds an attachment, else `_Predeterminado(appStateSettings[SettingKey.avatar] ?? 'man')`. The Save button is therefore always enabled once the form validates — the line-226 guard collapses to `_formKey.currentState?.validate() ?? false`.

**Transitions** (single setter `_setAvatarSource(_AvatarSource s)` wraps `setState` and bumps `_avatarVersion`):

| User action | Old state | New state | Side effects |
|---|---|---|---|
| Tap preset tile | any | `_Predeterminado(name)` | `HapticFeedback.lightImpact()` |
| Tap dashed upload tile | any | (unchanged until upload finishes) | `_uploadCustomAvatar()` runs |
| Upload success | any | `_UploadedPhoto()` | `AttachmentsService.attach`, `_avatarVersion++` |
| Upload cancelled (no file) | any | (unchanged) | none |
| Tap "Tu foto" tile (12-tile mode) | `_Predeterminado` | `_UploadedPhoto()` | none (attachment already exists) |

State lives in `State<EditProfileModal>`. Modal is short-lived; promoting to a Bloc/Provider would just add ceremony.

## 2. Widget tree

```
ModalContainer (title: t.settings.edit_profile, showTitleDivider: true)
├── body: SingleChildScrollView
│   └── Column (cross: stretch, gap: 28)
│       ├── _HeroBlock                         ← RepaintBoundary
│       │   ├── Container (140x140, heroHalo shadows)
│       │   │   └── UserAvatarDisplay(key: ValueKey('hero-$_avatarVersion'))
│       │   └── _NameField
│       │       ├── TextFormField (underline, GoogleFonts.nunito 23px)
│       │       └── Row [hint left | counter right]
│       └── _PickerSection
│           ├── Row [heading "Tu avatar" | aside "11/12 opciones"]
│           └── GridView.count(crossAxisCount: 4, shrinkWrap: true)
│               └── List<_AvatarTile>           ← each RepaintBoundary
└── footer: _ProfileFooter (Container, top divider, safe-area)
    ├── TextButton(key: ValueKey('edit-profile-cancel'), 'Cancelar')
    └── FilledButton.icon(key: ValueKey('edit-profile-save'), 'Guardar')
```

Stable keys: `edit-profile-cancel` (test handle), `edit-profile-save`, per-tile `ValueKey('avatar-tile-$id')`. `RepaintBoundary` wraps the hero (layered shadows) and each tile (selection shadow animation).

## 3. `BolsioAiTokens` extension

Add to [bolsio_ai_tokens.dart](c:/Users/ramse/OneDrive/Documents/vacas/wallex/lib/app/chat/theme/bolsio_ai_tokens.dart):

| Getter | Returns | Resolves to |
|---|---|---|
| `tileSurface` | `Color` | `_cs.surfaceContainer` — tile resting bg (replaces `primaryContainer` misuse) |
| `tileSurfaceHover` | `Color` | `_cs.surfaceContainerHigh` — hover/press state |
| `tileSurfaceSelected` | `Color` | `_cs.surfaceContainerHigh` — same as hover (selection cued by ring + check, not bg) |
| `selectedTileShadow` | `List<BoxShadow>` | 2-px accent ring + 6-px low-alpha accent halo |
| `heroHaloShadow` | `List<BoxShadow>` | 1-px white outline + 8-px white wash + 18px black drop |
| `dashedBorderColor` | `Color` | `_cs.onSurface.withValues(alpha: 0.18)` — fed to a `CustomPainter` |
| `accentSoft` | `Color` | `_cs.primary.withValues(alpha: 0.16)` — pin-pill background |
| `accentFaint` | `Color` | `_cs.primary.withValues(alpha: 0.10)` — dashed-tile hover bg |
| `accentOn` | `Color` | `_cs.onPrimary` — checkmark icon color |

Doc-comment edit at [bolsio_ai_tokens.dart:13](c:/Users/ramse/OneDrive/Documents/vacas/wallex/lib/app/chat/theme/bolsio_ai_tokens.dart:13): replace "scoped to the chat feature" with "shared design-token source for Wallex sheet surfaces (chat, profile, future modals)".

## 4. Adaptive grid algorithm

```
hasUpload = _selectedAvatarSource is _UploadedPhoto
            || _hasCustomAvatar  // attachment exists even if preset selected
tiles = []
if hasUpload:
  tiles.add(UploadedTile(selected: source is _UploadedPhoto, pin: 'Tu foto'))
for name in allAvatars:                        # 10 presets
  tiles.add(PresetTile(name, selected: source is _Predeterminado && source.name == name))
tiles.add(DashedUploadTile(label: hasUpload ? 'Reemplazar' : 'Subir foto'))
# Result: 12 tiles (4-4-4) when hasUpload, 11 tiles (4-4-3) otherwise
```

Post-upload: the algorithm reruns; selection auto-moves to `_UploadedPhoto()`, tile #1 appears with the photo, count switches 11→12.

## 5. Upload flow

1. User taps `DashedUploadTile`. `Tappable.onTap` → `_uploadCustomAvatar()`.
2. `_askImageSource()` shows gallery/camera bottom sheet.
3. User picks → `ReceiptImageService().pickAndCompress()` returns a `File?`.
4. If null, return — no state change.
5. `setState(() => _uploading = true)`; old attachment deleted; new one written via `AttachmentsService.attach`.
6. `_setAvatarSource(_UploadedPhoto())` + `_hasCustomAvatar = true` + `_avatarVersion++`.
7. Grid re-renders to 12-tile mode; hero re-fetches via the new ValueKey.

## 6. Persistence on Save

```
switch (_selectedAvatarSource) {
  case _UploadedPhoto():
    // Attachment already written by _uploadCustomAvatar.
    // Clear SettingKey.avatar so next session resolves via attachment, not stale preset.
    await userSettingsService.setItem(SettingKey.avatar, '', updateGlobalState: true);
  case _Predeterminado(:final name):
    await userSettingsService.setItem(SettingKey.avatar, name, updateGlobalState: true);
    // Delete attachment if present (existing _usePresetAvatar path).
    if (_hasCustomAvatar) await AttachmentsService.instance.deleteByOwner(...);
}
await userSettingsService.setItem(SettingKey.userName, _nameController.text);
RouteUtils.popRoute();
```

The empty-string clear is safe: `UserAvatarDisplay` already short-circuits to attachment when present, and `UserAvatar` falls back to `'man'` when name is empty (verified in [user_avatar.dart:45](c:/Users/ramse/OneDrive/Documents/vacas/wallex/lib/core/presentation/widgets/user_avatar.dart:45)). No new helper needed.

## 7. Typography integration

`google_fonts: ^6.2.1` already in [pubspec.yaml:98](c:/Users/ramse/OneDrive/Documents/vacas/wallex/pubspec.yaml:98). No version bump. Wire locally inside `EditProfileModal`:

```dart
final heroNameStyle = GoogleFonts.nunito(
  fontSize: 23, fontWeight: FontWeight.w600, letterSpacing: -0.23,
  color: tokens.text,
);
final sectionHeadingStyle = GoogleFonts.nunito(
  fontSize: 11.5, fontWeight: FontWeight.w600, letterSpacing: 1.4,
  color: tokens.muted,
);
```

No theme extension hook — Nunito is local to this surface only (the chat uses system stack).

## 8. Test strategy

| Layer | Coverage |
|---|---|
| Widget | Table-driven `_AvatarSource` transitions: preset tap, upload-tile tap (mock picker), uploaded-tile tap. Save guard: validates name, dispatches correct `setItem` calls per branch. |
| Golden | **No.** Tokens are theme-driven (varies per accent); golden churn would exceed value. Manual visual QA on POCO rodin per memory `project_wallex_build_optimal`. |
| Integration | Update [dashboard_nav_test.dart:28](c:/Users/ramse/OneDrive/Documents/vacas/wallex/integration_test/tests/navigation/dashboard_nav_test.dart:28): replace `find.byIcon(Icons.close)` with `find.byKey(const ValueKey('edit-profile-cancel'))`. |

Per memory `feedback_flutter_tests_slow.md`: only `flutter analyze` runs inside tandas; tests defer.

## 9. Open design questions

1. **Should "Tu foto" pin-pill be a `Stack` overlay or a `Tooltip`?** Recommend `Stack` overlay — matches mockup pixel-for-pixel and avoids long-press requirement.
2. **`SingleChildScrollView` vs `CustomScrollView` for the body?** Recommend `SingleChildScrollView` — body is short, sticky footer lives in `ModalContainer.footer` slot, no slivers needed.
3. **Should the dashed border use `CustomPainter` or `dotted_border` package?** Recommend `CustomPainter` — 12 lines, no dep added (per explore.md Q9).
