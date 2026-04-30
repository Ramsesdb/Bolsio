# Tasks: profile-editor-redesign

Five tandas, each independently mergeable. Per memory `feedback_flutter_tests_slow.md`, **only `flutter analyze` runs inside tandas — no `flutter test`**. Per memory `feedback_wallex_i18n_fallback.md`, **only `en.json` + `es.json` get new keys** in tanda 5.

Sequencing matches design.md §1-§7 (validated): tokens → state collapse → hero → grid+footer+test → i18n+cleanup. Footer ships with the grid in tanda 4 (not earlier) because the `dashboard_nav_test.dart:28` finder swap is gated on the `Icons.close` removal; splitting would break the integration test between merges.

---

## Tanda 1 — Token extension (foundation, additive)

**Goal**: Extend `BolsioAiTokens` with 9 new getters and refresh the doc-comment scope. Pure addition, no caller change.

**Touched files**:
- [bolsio_ai_tokens.dart](c:/Users/ramse/OneDrive/Documents/vacas/wallex/lib/app/chat/theme/bolsio_ai_tokens.dart)

**Sub-tasks**:
- [ ] 1.1 Update class doc-comment at [bolsio_ai_tokens.dart:13](c:/Users/ramse/OneDrive/Documents/vacas/wallex/lib/app/chat/theme/bolsio_ai_tokens.dart:13): replace "scoped to the chat feature" with "shared design-token source for Wallex sheet surfaces (chat, profile, future modals)".
- [ ] 1.2 Add `Color get tileSurface` → `_cs.surfaceContainer`.
- [ ] 1.3 Add `Color get tileSurfaceHover` → `_cs.surfaceContainerHigh` and `Color get tileSurfaceSelected` → `_cs.surfaceContainerHigh`.
- [ ] 1.4 Add `List<BoxShadow> get selectedTileShadow` (2-px accent ring + 6-px low-alpha accent halo, per design.md §3).
- [ ] 1.5 Add `List<BoxShadow> get heroHaloShadow` (1-px white outline + 8-px white wash + 18-px black drop).
- [ ] 1.6 Add `Color get dashedBorderColor` → `_cs.onSurface.withValues(alpha: 0.18)`.
- [ ] 1.7 Add `Color get accentSoft` (alpha 0.16), `Color get accentFaint` (alpha 0.10), `Color get accentOn` → `_cs.onPrimary`.

**Done-when**:
- `flutter analyze` clean (no `flutter test`).
- App still builds; `BolsioAiTokens.of(context)` callers in chat module unaffected (no breaking signature change).
- Manual smoke: open AI chat, confirm visuals unchanged.

---

## Tanda 2 — State machine collapse + Save guard relax

**Goal**: Replace `selectedAvatar` + `_hasCustomAvatar` two-flag bug with a sealed `_AvatarSource`. Relax Save guard. **No visual change yet** — current layout stays.

**Touched files**:
- [edit_profile_modal.dart](c:/Users/ramse/OneDrive/Documents/vacas/wallex/lib/app/settings/widgets/edit_profile_modal.dart)

**Sub-tasks**:
- [ ] 2.1 Define `sealed class _AvatarSource` with subclasses `_UploadedPhoto` and `_Predeterminado(String name)` (per design.md §1) at top of the file (private to library).
- [ ] 2.2 Replace `String? selectedAvatar` and `bool _hasCustomAvatar` with a single `_AvatarSource _selectedAvatarSource` field. Keep `_hasCustomAvatar` only as a derived computed getter pointing at the attachment row (needed for grid algorithm in tanda 4).
- [ ] 2.3 In `initState`, resolve initial source: if `_loadCustomAvatarState` finds an attachment use `_UploadedPhoto()`, else `_Predeterminado(appStateSettings[SettingKey.avatar] ?? 'man')`.
- [ ] 2.4 Add private setter `_setAvatarSource(_AvatarSource s)` that wraps `setState` and bumps `_avatarVersion` — every existing mutation site (`_usePresetAvatar`, post-upload callback) MUST route through it.
- [ ] 2.5 Relax Save guard at [edit_profile_modal.dart:226](c:/Users/ramse/OneDrive/Documents/vacas/wallex/lib/app/settings/widgets/edit_profile_modal.dart:226) to `_formKey.currentState?.validate() ?? false` only. Remove the `selectedAvatar == null` check.
- [ ] 2.6 Refactor `_save()` body to a `switch (_selectedAvatarSource)` with two arms (per design.md §6): `_UploadedPhoto` clears `SettingKey.avatar` to empty string and skips attachment ops; `_Predeterminado(:final name)` writes name and deletes attachment if `_hasCustomAvatar`.
- [ ] 2.7 Manually verify (no test run): open sheet, switch between an uploaded photo and a preset, observe that exactly one selection cue is shown at any time AND that Save stays enabled.

**Open Q from design (carry forward)**: none affect this tanda.

**Done-when**:
- `flutter analyze` clean. No `flutter test`.
- Spec scenarios "Save enabled when only uploaded photo is the selection" and "Save disabled when name is invalid" hold via manual interaction.
- No reference to `selectedAvatar` or `_hasCustomAvatar` as a stored field remains in the file (`_hasCustomAvatar` may persist only as a getter).

---

## Tanda 3 — Hero block rewrite

**Goal**: Replace the top section with the mockup hero (140-px halo avatar + inline name field + counter row + "Tu nombre visible" hint). Grid+footer untouched in this tanda.

**Touched files**:
- [edit_profile_modal.dart](c:/Users/ramse/OneDrive/Documents/vacas/wallex/lib/app/settings/widgets/edit_profile_modal.dart)

**Sub-tasks**:
- [ ] 3.1 Extract a private `_HeroBlock` widget wrapping `RepaintBoundary` per design.md §2.
- [ ] 3.2 Inside `_HeroBlock`, render a 140×140 `Container` with `BoxDecoration(boxShadow: tokens.heroHaloShadow)`, child `UserAvatarDisplay(key: ValueKey('hero-$_avatarVersion'))`. Drop the prior thick teal border.
- [ ] 3.3 Replace the existing "Subir foto" full-width button + name field stack with a `Column`: avatar on top, name `TextFormField` below using `GoogleFonts.nunito(fontSize: 23, weight: w600, letterSpacing: -0.23)`, single-line underline input (per mockup [editar-perfil.html](c:/Users/ramse/OneDrive/Documents/vacas/wallex/mockups/editar-perfil.html)).
- [ ] 3.4 Add the inline counter row directly under the underline: `Row` with muted hint label on the left (i18n placeholder key `profile.name-helper`, will land in tanda 5; for now use a TODO string `'Tu nombre visible'`) and `'${chars}/30'` on the right.
- [ ] 3.5 Wire counter to `_nameController` length via `addListener` in `initState` (or `ValueListenableBuilder` on the controller). Update only the counter widget — do not rebuild the whole sheet.
- [ ] 3.6 Confirm zero hardcoded hex remains in the `_HeroBlock` subtree — every color via `BolsioAiTokens.of(context)`.

**Open Q from design (carry forward)**: design.md §9 Q2 "SingleChildScrollView vs CustomScrollView". **Default: `SingleChildScrollView`**. Resolve in apply only if scrolling glitches show.

**Done-when**:
- `flutter analyze` clean. No `flutter test`.
- Sheet still opens (existing grid + footer below remain functional, just visually mismatched until tanda 4).
- Spec scenarios "Hero mirrors selected predeterminado tile" and "Hero mirrors uploaded photo tile" pass via manual interaction.

---

## Tanda 4 — Adaptive grid + sticky footer + integration test finder swap

**Goal**: Replace `Wrap` with the 11/12-tile adaptive grid, replace the footer (kill circular X), wire dashed-tile upload, AND swap the `dashboard_nav_test.dart:28` finder in the SAME tanda (gated on X removal — must not split).

**Touched files**:
- [edit_profile_modal.dart](c:/Users/ramse/OneDrive/Documents/vacas/wallex/lib/app/settings/widgets/edit_profile_modal.dart)
- [dashboard_nav_test.dart](c:/Users/ramse/OneDrive/Documents/vacas/wallex/integration_test/tests/navigation/dashboard_nav_test.dart)

**Sub-tasks**:
- [ ] 4.1 Implement `_PickerSection` with header row (heading "Tu avatar" placeholder + aside "11/12 opciones" placeholder — i18n in tanda 5) and `GridView.count(crossAxisCount: 4, shrinkWrap: true, physics: NeverScrollableScrollPhysics())`.
- [ ] 4.2 Implement `_buildTiles()` per design.md §4 algorithm: if `hasUpload` → prepend `UploadedTile` (with "Tu foto" badge), append 10 preset tiles, append `DashedUploadTile('Reemplazar')`. Else → 10 preset tiles + `DashedUploadTile('Subir foto')` only (11 total, no phantom cells).
- [ ] 4.3 Implement `_AvatarTile` widget with `RepaintBoundary`, key `ValueKey('avatar-tile-$id')`, selection cue = `tokens.selectedTileShadow` ring + glow + checkmark badge (token: `accentOn` icon on `accentSoft` circle). Unselected tiles render none of those three cues.
- [ ] 4.4 Implement `_DashedUploadTile` with a `CustomPainter`-based dashed border (design.md §9 Q3 default — no new package). On tap → call existing `_uploadCustomAvatar()` flow (design.md §5). Post-upload, `_setAvatarSource(_UploadedPhoto())`.
- [ ] 4.5 Replace the current `BottomSheetFooter` usage with an inline `_ProfileFooter`: `TextButton(key: ValueKey('edit-profile-cancel'), child: Text('Cancelar'))` + `FilledButton(key: ValueKey('edit-profile-save'), child: Text('Guardar'))`. **Remove every `Icons.close` reference in this file.** Footer container has top divider + safe-area padding.
- [ ] 4.6 Grep `edit_profile_modal.dart` for `Icons.close` and `Color(0x` / `0xFF` literals — both must return zero matches.
- [ ] 4.7 Update [dashboard_nav_test.dart:28](c:/Users/ramse/OneDrive/Documents/vacas/wallex/integration_test/tests/navigation/dashboard_nav_test.dart:28): replace `find.byIcon(Icons.close)` with `find.byKey(const ValueKey('edit-profile-cancel'))`. **MUST land in this tanda — splitting would break the integration test between merges.**

**Open Q from design (carry forward)**:
- design.md §9 Q1 "Tu foto" pin = Stack overlay (default). Resolve in apply only if Stack causes layout overflow.
- design.md §9 Q3 dashed border = `CustomPainter` (default, no new dep).

**Done-when**:
- `flutter analyze` clean. No `flutter test`.
- Manual: 11/12-tile state transitions correctly when the user picks a photo via the dashed tile.
- Spec scenarios "11-tile state on first open without upload", "12-tile state with existing upload", "Footer composition", "Selection cue uniqueness", "No hardcoded colors" all pass via manual inspection.
- `dashboard_nav_test.dart` compiles (verify with `flutter analyze` — full integration run deferred per memory).

---

## Tanda 5 — i18n keys + cleanup

**Goal**: Land 6 new i18n keys in `en.json` + `es.json` ONLY, regen slang, retire deprecated keys, final hex sweep.

**Touched files**:
- [en.json](c:/Users/ramse/OneDrive/Documents/vacas/wallex/lib/i18n/json/en.json)
- [es.json](c:/Users/ramse/OneDrive/Documents/vacas/wallex/lib/i18n/json/es.json)
- [translations.g.dart](c:/Users/ramse/OneDrive/Documents/vacas/wallex/lib/i18n/generated/translations.g.dart) (regenerated, not hand-edited)
- [edit_profile_modal.dart](c:/Users/ramse/OneDrive/Documents/vacas/wallex/lib/app/settings/widgets/edit_profile_modal.dart) (swap placeholder strings → i18n calls)

**Sub-tasks**:
- [ ] 5.1 **DO NOT touch the 9 secondary locales** (de, fr, hu, it, tr, uk, zh-CN, zh-TW, plus any other non-en/es). Slang `base_locale=en` covers them via fallback per memory `feedback_wallex_i18n_fallback.md`.
- [ ] 5.2 Add 6 keys to `en.json` and `es.json` under `profile.*`: `name-helper` ("Your display name" / "Tu nombre visible"), `avatar-section-title` ("Your avatar" / "Tu avatar"), `avatar-options-count` ("{count} options" / "{count} opciones"), `your-photo-badge` ("Your photo" / "Tu foto"), `upload-photo` ("Upload photo" / "Subir foto") + `replace-photo` ("Replace photo" / "Reemplazar foto"), `cancel-button` ("Cancel" / "Cancelar").
- [ ] 5.3 Audit and retire `profile.use-preset-avatar` if no longer referenced (was tied to the removed full-width button). Remove from `en.json` + `es.json` only.
- [ ] 5.4 Run `dart run slang` to regenerate `translations.g.dart`. Commit the generated file.
- [ ] 5.5 In `edit_profile_modal.dart`, swap the placeholder strings from tandas 3-4 (`'Tu nombre visible'`, `'Tu avatar'`, `'11 opciones'` etc., `'Subir foto'`, `'Reemplazar'`, `'Tu foto'`, `'Cancelar'`, `'Guardar'`) to `t.profile.<key>` calls. Pluralize/interpolate count via slang's `${count}` placeholder.
- [ ] 5.6 Final pass: grep `edit_profile_modal.dart` for any remaining `Color(0x` / `0xFF` / hardcoded copy strings. All must be zero.

**Done-when**:
- `flutter analyze` clean. No `flutter test`.
- Spec scenarios "Spanish locale renders new strings" and "Secondary locale falls back to English" pass via manual locale switch.
- `dart run slang` exits clean; generated file is committed.
- Acceptance criteria checklist in [proposal.md](c:/Users/ramse/OneDrive/Documents/vacas/wallex/openspec/changes/profile-editor-redesign/proposal.md) all satisfied.
