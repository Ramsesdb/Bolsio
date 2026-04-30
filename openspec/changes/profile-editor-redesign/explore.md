# Exploration: profile-editor-redesign

> Phase: explore. No code changes. Visual + interaction redesign of the `Editar perfil` bottom sheet, anchored on the approved HTML mockup at [mockups/editar-perfil.html](c:/Users/ramse/OneDrive/Documents/vacas/wallex/mockups/editar-perfil.html). The mockup is the visual source of truth; this document maps it to the existing Wallex (codename `bolsio`) Flutter codebase.

---

## Problem statement

The current `EditProfileModal` reads as a stack of mismatched controls. Diagnosed problems (verified against the file referenced below):

1. **Inverted hierarchy.** The full-width `FilledButton.icon` "Subir foto personalizada" at [edit_profile_modal.dart:198-204](c:/Users/ramse/OneDrive/Documents/vacas/wallex/lib/app/settings/widgets/edit_profile_modal.dart:198) screams louder than the avatar preview and the Save action.
2. **Broken grid.** The avatar list is a `Wrap` (not a real grid) at [edit_profile_modal.dart:215-222](c:/Users/ramse/OneDrive/Documents/vacas/wallex/lib/app/settings/widgets/edit_profile_modal.dart:215) over `allAvatars` (10 entries at [edit_profile_modal.dart:36-47](c:/Users/ramse/OneDrive/Documents/vacas/wallex/lib/app/settings/widgets/edit_profile_modal.dart:36)). The wrap renders 4+4+2 with the last row centered — orphan layout.
3. **Inconsistent footer.** [`BottomSheetFooter`](c:/Users/ramse/OneDrive/Documents/vacas/wallex/lib/core/presentation/widgets/bottom_sheet_footer.dart:6) pairs a circular outlined `IconButton` with `Icons.close` ([bottom_sheet_footer.dart:79-86](c:/Users/ramse/OneDrive/Documents/vacas/wallex/lib/core/presentation/widgets/bottom_sheet_footer.dart:79)) against a pill `FilledButton.icon` Save. Two design systems on the same row.
4. **Ambiguous selection state.** When `_hasCustomAvatar` is true, `selectedAvatar` (the preset id) is still set, so a preset tile in the grid still draws the teal selection ring at [edit_profile_modal.dart:318-320](c:/Users/ramse/OneDrive/Documents/vacas/wallex/lib/app/settings/widgets/edit_profile_modal.dart:318) even though the actual rendered avatar is the uploaded photo. Two competing "selected" surfaces — the hero preview and one preset tile.
5. **Counter floats orphaned.** `TextFormField` with `maxLength: 20` ([edit_profile_modal.dart:189](c:/Users/ramse/OneDrive/Documents/vacas/wallex/lib/app/settings/widgets/edit_profile_modal.dart:189)) shows the default Material counter to the right of the field — disconnected from the field's underline.
6. **Tile background clashes.** `Tappable` uses `Theme.of(context).colorScheme.primaryContainer` as `bgColor` ([edit_profile_modal.dart:307](c:/Users/ramse/OneDrive/Documents/vacas/wallex/lib/app/settings/widgets/edit_profile_modal.dart:307)) which under the user's selected accent (teal/mint) lands on a saturated dark green that fights the page background.

The mockup resolves all six in one redesign (single 4×3 grid, sticky pill footer, halo hero, counter inline under the field, neutral surface tiles).

## User stories

1. **One-tap selection.** As a user opening the sheet, I want to see my current avatar (uploaded photo OR preset) immediately as the hero, with the matching tile in the grid showing a checkmark — never two competing "selected" cues.
2. **Predictable upload.** As a user wanting to change my photo, I want a single dashed "Subir foto" tile at the end of the grid (#12) that opens the gallery/camera chooser; the result instantly takes over tile #1 ("Tu foto") and the hero, without modal dismissal.
3. **Quick name edit.** As a user, I want to rename inline under the avatar with a visible character counter and clear save/cancel affordances anchored to the bottom of the sheet, never scrolling away.
4. **Consistent visual language with the chat module.** Same accent moment (single mint), same hairline borders, same surface palette as the post-redesign AI chat, so the app feels cohesive.

## Affected systems / files (verified)

### Touched (existing — visual rewrite)
- [lib/app/settings/widgets/edit_profile_modal.dart](c:/Users/ramse/OneDrive/Documents/vacas/wallex/lib/app/settings/widgets/edit_profile_modal.dart) — full rewrite of the `build()` body. State (`selectedAvatar`, `_hasCustomAvatar`, `_uploading`, `_avatarVersion`, `_nameController`) and side effects (`_uploadCustomAvatar`, `_usePresetAvatar`, `_loadCustomAvatarState`) stay; only layout changes. The `_formKey` + `Form` validator still wraps the inline name field. Save callback at [edit_profile_modal.dart:226-250](c:/Users/ramse/OneDrive/Documents/vacas/wallex/lib/app/settings/widgets/edit_profile_modal.dart:226) is preserved as-is.
- [lib/app/settings/widgets/profile_hero_card.dart](c:/Users/ramse/OneDrive/Documents/vacas/wallex/lib/app/settings/widgets/profile_hero_card.dart) — caller; **no change expected** (it still launches the modal via `showModalBottomSheet`).
- [lib/app/home/dashboard.page.dart:697-708](c:/Users/ramse/OneDrive/Documents/vacas/wallex/lib/app/home/dashboard.page.dart:697) — second caller from the dashboard avatar tap; **no change expected**.

### Touched (i18n — en + es ONLY, per memory `feedback_wallex_i18n_fallback.md`)
- [lib/i18n/json/en.json](c:/Users/ramse/OneDrive/Documents/vacas/wallex/lib/i18n/json/en.json) and [lib/i18n/json/es.json](c:/Users/ramse/OneDrive/Documents/vacas/wallex/lib/i18n/json/es.json) — add new keys for: hero hint label ("Tu nombre visible"), grid heading label ("Tu avatar"), grid count aside ("12 opciones"), tile pin label ("Tu foto"), upload tile label ("Subir foto"), cancel button ("Cancelar"). The existing `profile.upload-custom-avatar` and `profile.use-preset-avatar` keys ([en.json:1131-1134](c:/Users/ramse/OneDrive/Documents/vacas/wallex/lib/i18n/json/en.json:1131)) survive — propose to deprecate `use-preset-avatar` (no longer needed: the dashed upload tile + tile-#1 selection model replaces the "Use preset avatar" toggle). DO NOT touch the 8 secondary locales (de, fr, hu, it, tr, uk, zh-CN, zh-TW) — slang falls back to en.
- [lib/i18n/generated/translations.g.dart](c:/Users/ramse/OneDrive/Documents/vacas/wallex/lib/i18n/generated/translations.g.dart) and siblings — regenerated by `dart run slang`, not hand-edited.

### Touched (test — required, will break otherwise)
- [integration_test/tests/navigation/dashboard_nav_test.dart:28](c:/Users/ramse/OneDrive/Documents/vacas/wallex/integration_test/tests/navigation/dashboard_nav_test.dart:28) — currently dismisses the sheet with `find.byIcon(Icons.close)`. The redesign kills the circular X. The test must switch to `find.text(t.ui_actions.cancel)` (or whatever new key we land on).

### Reused (no changes expected)
- [lib/app/chat/theme/bolsio_ai_tokens.dart](c:/Users/ramse/OneDrive/Documents/vacas/wallex/lib/app/chat/theme/bolsio_ai_tokens.dart) — the chat tokens module. **Confirmed real**, file exists, class name is `BolsioAiTokens` (NOT `WallexAiTokens` as the brief assumed — the codename is still `bolsio` in the codebase per `pubspec.yaml` and `openspec/config.yaml`). API: `BolsioAiTokens.of(context)`. It is a context-bound accessor (NOT a `ThemeExtension`), exposing `accent`, `surface`, `bubbleAi`, `surfaceAlt`, `text`, `muted`, `fainter`, `border`, `divider`, plus typography recipes and static radii. **Pattern is reusable verbatim.** See "Risks & decisions" Q1 for whether to extend it or fork.
- [lib/core/presentation/widgets/modal_container.dart](c:/Users/ramse/OneDrive/Documents/vacas/wallex/lib/core/presentation/widgets/modal_container.dart) — the bottom-sheet shell. Already used by `EditProfileModal` ([edit_profile_modal.dart:176](c:/Users/ramse/OneDrive/Documents/vacas/wallex/lib/app/settings/widgets/edit_profile_modal.dart:176)). Header + divider + bodyPadding + footer slot already match the mockup's structure. Reuse as-is.
- [lib/app/common/widgets/user_avatar_display.dart](c:/Users/ramse/OneDrive/Documents/vacas/wallex/lib/app/common/widgets/user_avatar_display.dart) — resolves "current uploaded avatar OR fall back to preset SVG" via the attachments service. Hero block uses this.
- [lib/core/presentation/widgets/user_avatar.dart](c:/Users/ramse/OneDrive/Documents/vacas/wallex/lib/core/presentation/widgets/user_avatar.dart) — renders preset SVGs from `assets/icons/avatars/{name}.svg`. Available preset names (verified on disk in `assets/icons/avatars/`): `man`, `woman`, `executive_man`, `executive_woman`, `blonde_man`, `blonde_woman`, `black_man`, `black_woman`, `woman_with_bangs`, `man_with_goatee` — exactly **10 SVGs**, matching `allAvatars`.
- [lib/core/services/attachments/attachments_service.dart](c:/Users/ramse/OneDrive/Documents/vacas/wallex/lib/core/services/attachments/attachments_service.dart) — uploaded avatar pipeline (`AttachmentOwnerType.userProfile`, `ownerId: 'current'`, `role: 'avatar'`). The redesign reuses this 1:1.
- [lib/core/services/firebase_sync_service.dart:425-460](c:/Users/ramse/OneDrive/Documents/vacas/wallex/lib/core/services/firebase_sync_service.dart:425) — Firebase sync of avatar to Firestore (NOT Storage — base64 inside the doc, capped at 400 KB / 512 px). The redesign does not touch this; the contract (`_avatarOwnerId = 'current'`, `_avatarRole = 'avatar'`) is preserved.
- [lib/core/database/services/user-setting/user_setting_service.dart:6-9](c:/Users/ramse/OneDrive/Documents/vacas/wallex/lib/core/database/services/user-setting/user_setting_service.dart:6) — `SettingKey.userName` and `SettingKey.avatar` (string keys). The redesign keeps writing to the same keys; no migration.
- `google_fonts ^6.2.1` ([pubspec.yaml:98](c:/Users/ramse/OneDrive/Documents/vacas/wallex/pubspec.yaml:98)) — already a dependency. `GoogleFonts.nunito()` is available without adding anything new.
- `image_picker` — already used by `_uploadCustomAvatar` ([edit_profile_modal.dart:3](c:/Users/ramse/OneDrive/Documents/vacas/wallex/lib/app/settings/widgets/edit_profile_modal.dart:3)). No change.
- [lib/core/presentation/widgets/tappable.dart](c:/Users/ramse/OneDrive/Documents/vacas/wallex/lib/core/presentation/widgets/tappable.dart) — used for tile interaction. Reusable.

### Not affected (explicit out-of-scope)
- Drift schema. No new columns, no migration. `SettingKey.avatar` stays a string id pointing to the chosen preset (or empty/legacy when a custom photo is in use).
- Firebase sync of avatar (already handled, see above).
- The 10 preset SVGs themselves. The mockup illustrates richer avatars (cat, mountain, plant, fox, etc.) but adopting that asset set is a separate change — see "Recommended scope (v1)" below.
- Light theme. The mockup is dark-only; light theme of this sheet is not in scope (the rest of the app's light variants of dark-tuned mockups have been deferred consistently per the AI chat v2 precedent).
- The `BottomSheetFooter` widget itself. The redesign replaces `footer:` with a custom bar inline (mockup's "Cancelar" + "Guardar" pair). `BottomSheetFooter` continues to live for other modals.
- `BolsioAiTokens` rename to `WallexAiTokens`. The class name is intentionally left at `BolsioAiTokens` (the package name `bolsio` is still in `pubspec.yaml`); a project-wide rebrand is a separate, large change.

---

## Recommended scope (v1)

### IN
- Visual rewrite of `EditProfileModal.build()`:
  - **Hero block.** 140-px circular `UserAvatarDisplay` with a soft halo (1-px subtle outer ring + 8-px low-alpha glow + drop shadow), no thick teal border. Inline below it: an underline-style `TextField` (centered text, accent caret, accent underline on focus, hairline underline at rest), with a leading-trailing pencil glyph on the right of the row. Below the underline: a two-column meta row — left: hint label ("Tu nombre visible"); right: tabular-num counter `N / 20`.
  - **Single 4×3 picker.** A real `GridView.count(crossAxisCount: 4)` (or `Wrap` with computed tile width) over a list of 12 entries:
    - Tile #1 = "Tu foto" — the uploaded photo when present (with a tiny "Tu foto" pill on top), OR an empty-state placeholder tile when the user has not uploaded yet (in which case it acts as a shortcut to upload — same target as #12).
    - Tiles #2–#11 = the 10 existing preset SVGs.
    - Tile #12 = dashed-border "Subir foto" action, accent on hover/press.
  - **Selection state.** Single source of truth: 2-px accent ring + 6-px low-alpha accent glow + 22-px circular checkmark badge bottom-right. Driven by a single value (`'__upload__' | preset-name`). The hero mirrors whatever tile is selected.
  - **Sticky footer.** Custom row with `TextButton("Cancelar")` left and `FilledButton.icon(Icons.check, "Guardar")` right (pill, 48 px tall). No circular X, no `BottomSheetFooter`.
- New design tokens accessor for profile surfaces — see Q1 below for whether this is a new `BolsioProfileTokens` or shared additions to `BolsioAiTokens`.
- Six new i18n keys in en.json + es.json. No changes to other locales.
- Update the integration test selector to dismiss via Cancel text (not `Icons.close`).
- Save / Cancel logic unchanged — the redesign is visual-only at the data-flow level. `selectedAvatar` semantics shift slightly (now also tracks "uploaded" as a synthetic value); the `UserSettingService.setItem(SettingKey.avatar, ...)` write at [edit_profile_modal.dart:240-244](c:/Users/ramse/OneDrive/Documents/vacas/wallex/lib/app/settings/widgets/edit_profile_modal.dart:240) keeps writing the preset id when a preset is chosen, and is skipped (or writes empty string) when a custom photo is the selection — see Q3.

### OUT (deferred, named explicitly so sdd-propose can confirm)
- Replacing the 10 preset SVGs with a richer asset set (cat, mountain, plant, fox, moon, etc., as illustrated in the mockup). Use existing 10 in v1; commission/import new assets in a follow-up `profile-avatar-asset-refresh` change.
- Light theme. Dark-only.
- Firebase sync changes.
- Drift / database model changes. The `SettingKey.avatar` column stays a string.
- A standalone `WallexProfileTokens` rebrand-named class. Naming follows existing `BolsioAiTokens` precedent.
- Renaming or migrating `BolsioAiTokens` → `WallexAiTokens`. Package codename remains `bolsio`.
- The "Use preset avatar" toggle button at [edit_profile_modal.dart:205-213](c:/Users/ramse/OneDrive/Documents/vacas/wallex/lib/app/settings/widgets/edit_profile_modal.dart:205) is removed by the redesign (its function is folded into the unified grid: tapping any preset tile when a custom photo is active deletes the attachment via the existing `_usePresetAvatar` path). The deprecated string `profile.use-preset-avatar` can stay in en.json for one release as a graveyard entry, then be removed.
- Avatar tile entry-/exit-animations beyond the existing `AnimatedSwitcher` ([edit_profile_modal.dart:264](c:/Users/ramse/OneDrive/Documents/vacas/wallex/lib/app/settings/widgets/edit_profile_modal.dart:264)) on the hero. Static crossfades only.

---

## Open questions, answered

### Q1 — `BolsioAiTokens` vs new `BolsioProfileTokens` vs shared base?
**Recommendation: extend `BolsioAiTokens` with a small set of "profile" getters. Do NOT fork.**
- The mockup's tokens (`--bg-sheet`, `--surface-container`, `--accent-primary`, `--text-primary`, etc.) are 1:1 already represented in `BolsioAiTokens` (`surface`, `surfaceAlt`, `accent`, `text`, `muted`, `border`, `divider`). The only profile-specific additions are: `tileTint` (a `surfaceContainer`-equivalent for the avatar tiles), `selectedRingShadow` recipe, and `heroHaloShadow` recipe.
- A separate `BolsioProfileTokens` would duplicate ~80% of `BolsioAiTokens` for one screen — overkill, exactly the kind of premature abstraction the chat tokens file's own doc-comment warns against.
- If, later, a third surface (e.g. settings) wants its own scoped tokens, that's the moment to extract a shared base. For now, "chat tokens are the design tokens" is the simpler narrative.
- Concrete plan: add three getters to `BolsioAiTokens` (`tileSurface`, `selectedTileShadow` returning a `List<BoxShadow>`, `heroHaloShadow` returning a `List<BoxShadow>`). The class name stays `BolsioAiTokens` and we accept the slight misnomer for one release; if a true rebrand happens we rename `BolsioAi` → `Wallex` everywhere in one shot.
- **If the user pushes back** on extending the chat tokens class for a non-chat surface, fall back to creating `lib/app/settings/theme/profile_tokens.dart` with the same API shape. Decision point for `sdd-propose`.

### Q2 — Where does the "Tu foto" tile come from when the user has NOT uploaded yet?
**Recommendation: tile #1 collapses into a shortcut to upload (visually identical to tile #12).**
- The mockup shows tile #1 as the uploaded photo. When `_hasCustomAvatar == false`, the cleanest UX is to render tile #1 also as a dashed "Subir foto" tile, OR hide tile #1 entirely and shift the grid to 4×3 of preset+upload (10 presets + 1 upload = 11 tiles, with one trailing empty cell).
- Simpler and visually consistent: **always render 12 tiles. When no uploaded photo exists, tile #1 mirrors tile #12** (dashed, "+" icon, "Subir foto" label) — both invoke `_uploadCustomAvatar`. This keeps the grid count stable, never has orphan rows, and gives the user two equally-valid entry points to upload.
- Alternative (deferred): use a "ghost" preview generated from the user's initials (mockup's `av-rb` example with "RB"). Pretty, but introduces font/asset/color logic. Defer.

### Q3 — Storage model: how do we represent "uploaded photo is selected" in `SettingKey.avatar`?
**Recommendation: leave `SettingKey.avatar` untouched and add a synthetic in-memory marker.**
- Today, `SettingKey.avatar` stores a preset id (e.g. `'man'`). When `_hasCustomAvatar == true` the actual rendered photo comes from the attachments table — `SettingKey.avatar` is *ignored* but still written.
- The redesign needs a single `selectedAvatar` UI state that covers "uploaded" + 10 presets. Options:
  - **(A) Use a sentinel string** (`'__uploaded__'`) and write it to `SettingKey.avatar`. Risk: any reader that does `assets/icons/avatars/$avatar.svg` ([user_avatar.dart:45](c:/Users/ramse/OneDrive/Documents/vacas/wallex/lib/core/presentation/widgets/user_avatar.dart:45)) crashes on missing asset. Would require touching every consumer (8+ call sites identified by `SettingKey.avatar` grep).
  - **(B) Keep current behavior**: when the user picks "uploaded" in the new grid, write `''` (or the previous preset id) to `SettingKey.avatar` and rely on the attachments table being the source of truth. `UserAvatarDisplay` already short-circuits to the attachment when present. This is invisible to existing readers.
- **Pick B.** No model migration, no risk of crashing the SVG asset loader, no Firebase sync schema impact. The `selectedAvatar` UI variable becomes a nullable enum-equivalent local to the modal: `'__upload__' | <preset-name>`; only the preset case writes to `SettingKey.avatar`. The "uploaded" choice persists implicitly through the existence of the attachment row.

### Q4 — Counter UX: standard `decoration.counterText` or custom?
**Recommendation: custom row below the underline.**
- The mockup pairs the counter with a hint ("Tu nombre visible") on the same row, both in the muted text token. `InputDecoration.counterText` puts the counter right-aligned but cannot host the hint label.
- Build a 2-column `Row` below the `TextField`: `Text(hint)` left, `Text('${name.length} / 20', style: tabularNum)` right. `TextField` itself uses `decoration: InputDecoration(counterText: '')` to suppress the default. Identical pattern to what the mockup HTML shows.

### Q5 — Drag handle: keep `showDragHandle: true` on `showModalBottomSheet`?
**Recommendation: yes, keep it.** The mockup's HTML draws its own handle (`.sheet__handle`), but Flutter's built-in handle (driven by `showDragHandle: true` at [profile_hero_card.dart:30](c:/Users/ramse/OneDrive/Documents/vacas/wallex/lib/app/settings/widgets/profile_hero_card.dart:30) and [dashboard.page.dart:703](c:/Users/ramse/OneDrive/Documents/vacas/wallex/lib/app/home/dashboard.page.dart:703)) is identical visually and free. No need to draw our own.

### Q6 — Sheet height / scrolling
**Recommendation: existing `isScrollControlled: true` + `ModalContainer` body scroll.** The mockup's body scrolls (the picker can grow); `ModalContainer` already wraps the body in a `Padding` inside a `Column`. We need to wrap the body in a `SingleChildScrollView` to ensure the hero + grid scroll while the footer stays sticky. Confirm: the current `EditProfileModal` does NOT wrap in a scroll view ([edit_profile_modal.dart:181-223](c:/Users/ramse/OneDrive/Documents/vacas/wallex/lib/app/settings/widgets/edit_profile_modal.dart:181)) — keyboards on small phones probably push it. Add the scroll view as part of the redesign.

### Q7 — Typography
**Recommendation: `GoogleFonts.nunito()` for the title and the hero name, system stack for body.** `google_fonts: ^6.2.1` is already in `pubspec.yaml`; no new dep. The mockup CSS asks for `ui-rounded` / "SF Pro Rounded" — Nunito is the closest free Google-fonted match and is consistent with the rounded-geometric brief.

---

## Risks & unknowns

1. **Integration test breakage.** [dashboard_nav_test.dart:28](c:/Users/ramse/OneDrive/Documents/vacas/wallex/integration_test/tests/navigation/dashboard_nav_test.dart:28) dismisses via `find.byIcon(Icons.close)`. The redesign removes the icon. Update the selector in the same change. Per memory `feedback_flutter_tests_slow.md`, do NOT block tandas on `flutter test` — but DO update the test source file so it reflects the new UI. Validation can run later.
2. **Selection-state two-way binding.** Today `selectedAvatar` and `_hasCustomAvatar` are independent — bug #4. The redesign collapses them into a single `selectedAvatar` variable that takes a sentinel for "uploaded". The existing `_usePresetAvatar` callback (deletes the attachment) and `_uploadCustomAvatar` (replaces it) both still mutate `_hasCustomAvatar` directly. Re-order so the single `selectedAvatar` setter is the place where both states converge. If we get this wrong, the grid will lie about the selection again.
3. **`selectedAvatar == null` Save guard** ([edit_profile_modal.dart:226-227](c:/Users/ramse/OneDrive/Documents/vacas/wallex/lib/app/settings/widgets/edit_profile_modal.dart:226)) currently disables Save when no preset is picked. Under the new model, "uploaded" is a valid selection — make sure the guard treats `selectedAvatar = '__uploaded__'` (or whatever sentinel) as enabled. Otherwise users with a custom photo who never tapped a preset can't save name changes.
4. **`SettingKey.avatar` write semantics.** Per Q3, picking "uploaded" should NOT write a sentinel to `SettingKey.avatar`. Make sure the Save flow only writes the preset id when a preset is chosen, and writes the existing value (no-op) or empty string when "uploaded" is chosen. Audit consumers — 8+ call sites (`appStateSettings[SettingKey.avatar]`) all already tolerate empty strings (they pass through to `UserAvatarDisplay` which short-circuits to attachment first).
5. **`BolsioAiTokens` extension spreads chat-feature scope.** Adding `tileSurface`, `selectedTileShadow`, `heroHaloShadow` to a class explicitly doc-commented as "scoped to the chat feature" ([bolsio_ai_tokens.dart:13-15](c:/Users/ramse/OneDrive/Documents/vacas/wallex/lib/app/chat/theme/bolsio_ai_tokens.dart:13)) is a small-but-real concern. Either accept it (and update the doc comment) or fork (per Q1). Lean toward accept + update doc.
6. **i18n drift on secondary locales.** Per memory `feedback_wallex_i18n_fallback.md`, slang falls back to en.json when a key is missing. We add 6 keys to en + es; the 8 secondary locales (de, fr, hu, it, tr, uk, zh-CN, zh-TW) inherit en automatically. But: the existing `profile.upload-custom-avatar` key IS translated in some secondary locales (verify in sdd-spec). If we deprecate it, those translations become orphaned — fine, but flag in proposal.
7. **`isScrollControlled: true` + sticky footer = manual `Padding` for keyboard.** When the keyboard opens (rename), the body must scroll under the footer, not push the footer off-screen. `ModalContainer` already has `responseToKeyboard: true` ([modal_container.dart:55-59](c:/Users/ramse/OneDrive/Documents/vacas/wallex/lib/core/presentation/widgets/modal_container.dart:55)) which adds `viewInsets.bottom` padding. This is wrong when we have a sticky footer (it'll move the footer up by the keyboard height — actually fine, that's what we want). Validate on a real device.
8. **Hero halo drop shadow performance.** Layered `BoxShadow`s on a 140 px circle inside a list-rebuilding modal is cheap, but combined with `AnimatedSwitcher` + 11 grid tiles each with their own selection shadow, the per-frame paint count climbs. POCO rodin handles it; verify on a low-end device before declaring done. Mitigation: pre-render the halo as a `RepaintBoundary` so only the inner `UserAvatarDisplay` repaints when `_avatarVersion` changes.
9. **`Icons.upload_file_outlined` vs custom dashed circle.** The mockup's tile #12 is a custom-painted circle (1.5-px dashed border). Flutter has no built-in dashed-border. Options: (a) use a `dotted_border` package (new dep — avoid), (b) use `CustomPainter` with `drawCircle` + dash math (10 lines of paint), (c) draw an SVG. Pick (b). Kept inline in the modal file; no new dep.
10. **Avatar SVG palette mismatch.** The 10 existing SVGs use a fixed palette baked into the assets. The mockup tiles use a single muted accent tint — the existing SVGs may clash visually. Out of scope (per "OUT" list above) — call it out so the user knows the v1 ship will look "close to mockup" but not "exact mockup" until the asset refresh follow-up.

---

## Success criteria

- One bottom sheet, one footer row (Cancelar + Guardar), zero circular icon buttons.
- Hero avatar reflects the active selection at all times — never disagrees with the grid.
- Tile #1 always shows the uploaded photo when present, or a dashed "Subir foto" tile when not.
- Selection state uses exactly one cue (accent ring + checkmark) — no double rings, no orphan teal borders on inactive tiles.
- Counter is visually attached to the name field, paired with the muted hint label.
- All colors come from `BolsioAiTokens.of(context)` (or its profile extension) — no hardcoded hex anywhere in `edit_profile_modal.dart`.
- `flutter analyze` clean.
- New strings added only to `en.json` and `es.json`; secondary locales inherit via fallback.
- `dashboard_nav_test.dart` selector updated and the test compiles (run is optional per the `feedback_flutter_tests_slow.md` policy).
- No Drift schema change. No Firebase sync change. No `pubspec.yaml` change.
- Save / Cancel data flow unchanged from a domain perspective (still writes `userName`, still writes `avatar` preset id when a preset is chosen, still updates `appStateSettings[SettingKey.avatar]`).

---

## Ready for proposal

**Yes.** Recommendations are concrete and reuse `BolsioAiTokens`, `ModalContainer`, `UserAvatarDisplay`, `AttachmentsService`, `image_picker`, and `google_fonts` — all already in the codebase. No schema migration, no new dependency, no sync change. Three decisions for `sdd-propose` to lock:
- Extend `BolsioAiTokens` vs fork into `BolsioProfileTokens` (recommendation: extend).
- Sentinel string vs implicit empty for "uploaded" in `SettingKey.avatar` (recommendation: implicit empty / no-write).
- Tile #1 behavior when no upload exists (recommendation: dashed shortcut, twin of tile #12).
