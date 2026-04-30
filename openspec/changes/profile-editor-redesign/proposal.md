# Proposal: profile-editor-redesign

## Intent

The current `Editar perfil` bottom sheet reads as a stack of mismatched controls: a full-width "Subir foto" button outshouts the avatar hero, a `Wrap` orphans the last preset row (4+4+2), the footer pairs a circular X with a pill Save (two design systems on one row), and selection state can lie — `selectedAvatar` and `_hasCustomAvatar` are independent, so a preset tile can show the teal ring while the rendered avatar is the uploaded photo. Users can't tell what's selected, and the visual language doesn't match the post-redesign AI chat module. This change rewrites the sheet against the approved mockup at [editar-perfil.html](c:/Users/ramse/OneDrive/Documents/vacas/wallex/mockups/editar-perfil.html), using the same token surface and selection grammar as the chat module.

## Scope

### In Scope
- Full visual rewrite of [edit_profile_modal.dart](c:/Users/ramse/OneDrive/Documents/vacas/wallex/lib/app/settings/widgets/edit_profile_modal.dart) `build()` — hero block (140 px halo avatar + inline name field + counter row), unified avatar grid, custom sticky footer (`Cancelar` text + `Guardar` pill).
- Extend [BolsioAiTokens](c:/Users/ramse/OneDrive/Documents/vacas/wallex/lib/app/chat/theme/bolsio_ai_tokens.dart) with `tileSurface`, `selectedTileShadow`, `heroHaloShadow` (and any other mockup-derived getters); update doc-comment to reframe scope as "Wallex sheet surfaces" not chat-only.
- Collapse `selectedAvatar` + `_hasCustomAvatar` into one sealed `_selectedAvatarSource` (`uploadedPhoto | predeterminado(name)`); relax the Save guard at [edit_profile_modal.dart:226](c:/Users/ramse/OneDrive/Documents/vacas/wallex/lib/app/settings/widgets/edit_profile_modal.dart:226).
- Adaptive grid: 11 tiles in 4-4-3 layout when no upload exists, 12 tiles in 4-4-4 when an upload exists.
- Six new i18n keys in [en.json](c:/Users/ramse/OneDrive/Documents/vacas/wallex/lib/i18n/json/en.json) + [es.json](c:/Users/ramse/OneDrive/Documents/vacas/wallex/lib/i18n/json/es.json) ONLY (slang fallback covers the 8 secondary locales).
- Update [dashboard_nav_test.dart:28](c:/Users/ramse/OneDrive/Documents/vacas/wallex/integration_test/tests/navigation/dashboard_nav_test.dart:28) to a stable finder (Cancelar key/text) for the X-icon removal.
- `GoogleFonts.nunito()` for hero name + section title (already in `pubspec.yaml`).

### Out of Scope
- New avatar SVG asset set (mockup illustrates richer assets — defer to `profile-avatar-asset-refresh`).
- Light theme (dark only, matching chat v2 precedent).
- Firebase sync changes — `_avatarOwnerId='current'`, `_avatarRole='avatar'` contract preserved.
- Project-wide `bolsio → wallex` rename — own change.
- Drift / DB migration — `SettingKey.avatar` stays a string id.
- Adding `ThemeExtension` machinery to `BolsioAiTokens`.
- The `BottomSheetFooter` widget itself (kept for other modals; this sheet uses an inline footer).

## Decisions

The orchestrator locked these — no alternatives, no debate.

### Decision 1 — Tokens: extend `BolsioAiTokens`, don't fork
Add new getters (`tileSurface`, `selectedTileShadow`, `heroHaloShadow`, plus any others derived from the mockup) to [bolsio_ai_tokens.dart](c:/Users/ramse/OneDrive/Documents/vacas/wallex/lib/app/chat/theme/bolsio_ai_tokens.dart). Update the class doc-comment at [bolsio_ai_tokens.dart:13](c:/Users/ramse/OneDrive/Documents/vacas/wallex/lib/app/chat/theme/bolsio_ai_tokens.dart:13) to describe it as the shared design-token source for **Wallex sheet surfaces** (chat + profile + future). Class name and file path stay `BolsioAiTokens` — a project-wide rebrand is its own change.

### Decision 2 — "Tu foto" tile uses an in-memory sentinel; no DB write for uploads
Collapse the dual flags into a single sealed `_selectedAvatarSource` enum: `uploadedPhoto` (sentinel) | `predeterminado(name)`. The two persistence paths stay mutually exclusive:
- Selecting `uploadedPhoto` → Save uses the existing custom-avatar path (`AttachmentsService` row); does NOT write to `SettingKey.avatar`.
- Selecting a `predeterminado(name)` → Save writes the preset id via `SettingKey.avatar` AND clears the custom photo (existing `_usePresetAvatar` flow).

Save guard at [edit_profile_modal.dart:226](c:/Users/ramse/OneDrive/Documents/vacas/wallex/lib/app/settings/widgets/edit_profile_modal.dart:226) is relaxed to allow save when `_selectedAvatarSource == uploadedPhoto`, not only when a preset is set. No model migration. No new sentinel in `SettingKey.avatar`. The DB stays clean.

### Decision 3 — Grid is adaptive (11 or 12 tiles), with conditional tile #1
- **Upload exists:** 12 tiles in 4-4-4. Tile #1 = uploaded photo with "Tu foto" badge. Tiles #2–11 = the 10 predeterminados. Tile #12 = dashed "Reemplazar foto".
- **No upload:** 11 tiles in 4-4-3. Tile #1 = dashed "Subir foto" action. Tiles #2–11 = the 10 predeterminados. No phantom empty cells.
- Tapping the dashed tile invokes the existing `image_picker` → `AttachmentsService` upload flow. Post-upload the grid re-renders to the 12-tile state, the new photo becomes tile #1, and selection auto-moves to it.

## Affected Areas

| Area | Impact | Description |
|------|--------|-------------|
| [lib/app/settings/widgets/edit_profile_modal.dart](c:/Users/ramse/OneDrive/Documents/vacas/wallex/lib/app/settings/widgets/edit_profile_modal.dart) | Modified | Full `build()` rewrite + `_selectedAvatarSource` state collapse + relaxed save guard at line 226 |
| [lib/app/chat/theme/bolsio_ai_tokens.dart](c:/Users/ramse/OneDrive/Documents/vacas/wallex/lib/app/chat/theme/bolsio_ai_tokens.dart) | Modified | New getters + doc-comment scope update |
| [lib/i18n/json/en.json](c:/Users/ramse/OneDrive/Documents/vacas/wallex/lib/i18n/json/en.json), [lib/i18n/json/es.json](c:/Users/ramse/OneDrive/Documents/vacas/wallex/lib/i18n/json/es.json) | Modified | 6 new keys (hero hint, grid heading, count aside, "Tu foto" badge, upload tile, Cancelar). Audit `profile.use-preset-avatar` for retirement |
| [lib/i18n/generated/translations.g.dart](c:/Users/ramse/OneDrive/Documents/vacas/wallex/lib/i18n/generated/translations.g.dart) | Regenerated | `dart run slang` after JSON edits |
| [integration_test/tests/navigation/dashboard_nav_test.dart](c:/Users/ramse/OneDrive/Documents/vacas/wallex/integration_test/tests/navigation/dashboard_nav_test.dart) | Modified | Line 28 finder swap (X → Cancelar) |
| [profile_hero_card.dart](c:/Users/ramse/OneDrive/Documents/vacas/wallex/lib/app/settings/widgets/profile_hero_card.dart), [dashboard.page.dart](c:/Users/ramse/OneDrive/Documents/vacas/wallex/lib/app/home/dashboard.page.dart) | Untouched | Callers still launch via `showModalBottomSheet` |
| [attachments_service.dart](c:/Users/ramse/OneDrive/Documents/vacas/wallex/lib/core/services/attachments/attachments_service.dart), [firebase_sync_service.dart](c:/Users/ramse/OneDrive/Documents/vacas/wallex/lib/core/services/firebase_sync_service.dart) | Untouched | Avatar upload + sync contracts preserved |

## Acceptance Criteria

- [ ] One bottom sheet, one footer row (`Cancelar` text + `Guardar` pill, 48 px). Zero circular icon buttons.
- [ ] Hero avatar always reflects `_selectedAvatarSource` — selection state cannot lie.
- [ ] Hero block uses `BolsioAiTokens.heroHaloShadow` (no thick teal border).
- [ ] Counter is inline under the name underline, paired with muted hint label "Tu nombre visible" / "Your display name".
- [ ] Grid renders 11 tiles (4-4-3) when no upload exists; 12 tiles (4-4-4) when one does. No phantom empty cells.
- [ ] When upload exists, tile #1 shows the photo with a "Tu foto" badge; tile #12 is the dashed replace action.
- [ ] When no upload, tile #1 is the dashed upload action; tile #12 is absent.
- [ ] Selection cue is exactly one ring + checkmark; no double rings, no orphan teal borders.
- [ ] Save is enabled when `_selectedAvatarSource == uploadedPhoto` even without a preset chosen — guard at line 226 relaxed.
- [ ] All colors via `BolsioAiTokens.of(context)`; zero hardcoded hex in the rewritten file.
- [ ] Hero name + section title use `GoogleFonts.nunito()`.
- [ ] 6 new i18n keys present in `en.json` + `es.json` only; secondary locales fall back via slang.
- [ ] `dashboard_nav_test.dart:28` compiles against the new sheet (no `Icons.close`).
- [ ] `flutter analyze` clean. No `pubspec.yaml` change. No Drift migration. No Firebase sync change.

## Risks

| Risk | Likelihood | Mitigation |
|------|------------|------------|
| `dashboard_nav_test.dart` finder breaks on X removal | High | Update selector to text/Key in the same change (in scope above) |
| Selection state regression — two-way binding bug returns | Medium | Single sealed `_selectedAvatarSource`; both `_usePresetAvatar` and `_uploadCustomAvatar` mutate ONLY through the source setter |
| Save guard at line 226 still blocks uploaded-only selection | Medium | Spec scenario covers it; relaxed guard is in acceptance criteria |
| `BolsioAiTokens` doc-comment lies about "chat-only" scope | Low | Update doc-comment in same edit (Decision 1) |
| Hero halo + 11–12 tile shadows + `AnimatedSwitcher` raise paint count | Low | `RepaintBoundary` around the hero; verify on POCO rodin before declaring done |
| `Icons.close` still referenced elsewhere on the sheet | Low | Grep for `Icons.close` in `edit_profile_modal.dart` during apply |
| Orphan translations of deprecated `profile.use-preset-avatar` in secondary locales | Low | Acceptable; flag for cleanup in a future i18n hygiene pass |
| Keyboard collision with sticky footer on small phones | Low | `ModalContainer.responseToKeyboard: true` already adds `viewInsets.bottom`; validate with rename + soft keyboard |

## Rollback Plan

Single-file rollback: revert [edit_profile_modal.dart](c:/Users/ramse/OneDrive/Documents/vacas/wallex/lib/app/settings/widgets/edit_profile_modal.dart), [bolsio_ai_tokens.dart](c:/Users/ramse/OneDrive/Documents/vacas/wallex/lib/app/chat/theme/bolsio_ai_tokens.dart), the two i18n JSONs, regenerate slang, and revert the test selector. No DB state, no Firebase docs, no `pubspec.yaml`, no asset additions — nothing persistent to unwind.

## Dependencies

None new. `google_fonts ^6.2.1`, `image_picker`, `AttachmentsService`, `BolsioAiTokens`, `ModalContainer`, `UserAvatarDisplay`, `Tappable` are all already in the codebase.

## Implementation breakdown hint (validates scope; full breakdown is sdd-tasks's job)

- **Tanda 1** — Token extension + doc-comment refresh on `BolsioAiTokens`. Smallest, lowest-risk landing. Unblocks all UI work.
- **Tanda 2** — `_selectedAvatarSource` state collapse + Save-guard relax. Pure logic refactor; no visual change yet. Verifiable by manual interaction (selection no longer lies).
- **Tanda 3** — Hero block + name field + counter row rewrite. Visual surface lands.
- **Tanda 4** — Adaptive grid (11/12 tiles) + sticky footer + dashed-tile painter. Largest visual change.
- **Tanda 5** — i18n keys (en + es), slang regen, integration test finder swap. Wraps up.

Five tandas, each landable independently, each visually verifiable on POCO rodin.
