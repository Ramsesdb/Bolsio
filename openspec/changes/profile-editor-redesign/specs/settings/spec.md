# Delta: Profile Editor Redesign

Operationalizes the visual + interaction rewrite of `EditProfileModal` against
[mockups/editar-perfil.html](c:/Users/ramse/OneDrive/Documents/vacas/wallex/mockups/editar-perfil.html).
Decisions are locked in [proposal.md](c:/Users/ramse/OneDrive/Documents/vacas/wallex/openspec/changes/profile-editor-redesign/proposal.md);
this delta describes observable behavior only.

---

## ADDED Requirements

### Requirement: Single source of truth for active avatar selection

The system MUST hold avatar selection in exactly one state value with two
mutually exclusive variants: `uploadedPhoto` (sentinel) or `predeterminado(name)`.
The hero avatar above the grid MUST always render the same source as the tile
that displays the selection ring + checkmark. At any moment, AT MOST ONE tile
MUST show the selected cue.

#### Scenario: Hero mirrors selected predeterminado tile

- GIVEN the sheet is open and no upload exists
- WHEN the user taps the `man_with_goatee` tile
- THEN tile `man_with_goatee` MUST be the only tile showing the accent ring + checkmark
- AND the hero avatar MUST render the `man_with_goatee` SVG

#### Scenario: Hero mirrors uploaded photo tile

- GIVEN the user has an uploaded photo and tile #1 is selected
- WHEN the sheet is rendered
- THEN tile #1 MUST be the only tile with the accent ring + checkmark
- AND the hero MUST render the uploaded photo
- AND no preset tile MUST show a residual selection ring

#### Scenario: Switching from uploaded to predeterminado

- GIVEN tile #1 (uploaded photo) is selected
- WHEN the user taps a predeterminado tile
- THEN the predeterminado tile MUST become the only selected tile
- AND tile #1 MUST lose its selection cue
- AND the hero MUST swap to the predeterminado SVG

---

### Requirement: Save guard relaxed to accept uploaded-photo selection

The Guardar button MUST be enabled when the in-memory selection is either a
`predeterminado` OR `uploadedPhoto`. Guardar MUST be disabled ONLY when the
name field fails its validator. The pre-redesign guard at
[edit_profile_modal.dart:226](c:/Users/ramse/OneDrive/Documents/vacas/wallex/lib/app/settings/widgets/edit_profile_modal.dart:226)
that disabled Save when `selectedAvatar == null` MUST be removed.

#### Scenario: Save enabled when only uploaded photo is the selection

- GIVEN a valid name in the field
- AND the user has an uploaded photo and tile #1 (uploadedPhoto) is selected
- AND no predeterminado is selected
- WHEN the user looks at the footer
- THEN the Guardar button MUST be enabled

#### Scenario: Save disabled when name is invalid

- GIVEN tile #1 (uploadedPhoto) is selected
- WHEN the user clears the name field
- THEN the form validator MUST fail
- AND the Guardar button MUST be disabled

#### Scenario: Save enabled with predeterminado selection

- GIVEN a valid name and a predeterminado tile is selected
- WHEN the user looks at the footer
- THEN the Guardar button MUST be enabled

---

### Requirement: Adaptive grid renders 11 or 12 tiles

The avatar grid MUST render exactly 11 tiles in a 4-4-3 layout when no uploaded
photo exists, OR exactly 12 tiles in a 4-4-4 layout when an uploaded photo
exists. NO phantom or empty cells MUST appear in either state.

- When no upload exists: tile #1 MUST be the dashed "Subir foto" upload-action;
  tiles #2..#11 MUST be the 10 predeterminados.
- When an upload exists: tile #1 MUST be the uploaded photo with a "Tu foto"
  badge; tiles #2..#11 MUST be the 10 predeterminados; tile #12 MUST be the
  dashed "Reemplazar foto" upload-action.

#### Scenario: 11-tile state on first open without upload

- GIVEN the user has never uploaded a photo
- WHEN the sheet opens
- THEN the grid MUST render 11 tiles in a 4-4-3 arrangement
- AND tile #1 MUST be the dashed upload-action labeled "Subir foto"
- AND tile #12 MUST NOT exist

#### Scenario: 12-tile state with existing upload

- GIVEN the user has a previously uploaded photo
- WHEN the sheet opens
- THEN the grid MUST render 12 tiles in a 4-4-4 arrangement
- AND tile #1 MUST display the uploaded photo with a "Tu foto" badge
- AND tile #12 MUST be the dashed upload-action labeled "Reemplazar foto"

---

### Requirement: Upload-from-grid flow

Tapping the dashed upload tile (#1 in the 11-tile state, #12 in the 12-tile
state) MUST open the system image picker. On a successful pick the photo MUST
be uploaded via `AttachmentsService` (`ownerType=userProfile`, `ownerId='current'`,
`role='avatar'`). On upload success the grid MUST re-render to the 12-tile state
and the active selection MUST move to tile #1.

#### Scenario: First upload from 11-tile state

- GIVEN the grid is in the 11-tile state
- WHEN the user taps tile #1 (dashed "Subir foto")
- AND picks an image successfully
- THEN `AttachmentsService` MUST receive a new avatar attachment for the current user
- AND the grid MUST re-render with 12 tiles
- AND tile #1 MUST be the freshly-uploaded photo
- AND the in-memory selection MUST be `uploadedPhoto`
- AND the hero MUST render the uploaded photo

#### Scenario: Replace existing photo from 12-tile state

- GIVEN the grid is in the 12-tile state
- WHEN the user taps tile #12 (dashed "Reemplazar foto")
- AND picks a new image successfully
- THEN the existing avatar attachment MUST be replaced
- AND the grid MUST stay in 12-tile state
- AND tile #1 MUST display the new photo
- AND the selection MUST be `uploadedPhoto`

#### Scenario: User cancels image picker

- GIVEN the grid is in either state
- WHEN the user taps the upload tile
- AND dismisses the picker without selecting an image
- THEN no upload MUST happen
- AND the prior selection MUST be preserved
- AND the grid MUST NOT change shape

---

### Requirement: Mutual exclusion of avatar persistence paths

The `uploadedPhoto` and `predeterminado(name)` selections MUST be mutually
exclusive in memory. On Guardar, EXACTLY ONE persistence path MUST run:

- If selection is `predeterminado(name)`: write the preset id to
  `SettingKey.avatar` AND clear any existing custom avatar attachment via the
  existing `_usePresetAvatar` flow.
- If selection is `uploadedPhoto`: leave the `AttachmentsService` row in place
  AND MUST NOT write a sentinel to `SettingKey.avatar`.

#### Scenario: Selecting predeterminado clears in-memory custom photo selection

- GIVEN tile #1 (uploadedPhoto) is selected
- WHEN the user taps a predeterminado tile
- THEN the in-memory selection MUST be `predeterminado(name)`
- AND `uploadedPhoto` MUST NO LONGER be the selection state
- AND no write to disk MUST occur until Guardar is pressed

#### Scenario: Selecting uploadedPhoto clears in-memory predeterminado selection

- GIVEN a predeterminado tile is selected
- WHEN the user taps tile #1 (which holds the uploaded photo)
- THEN the in-memory selection MUST be `uploadedPhoto`
- AND no predeterminado MUST remain selected

#### Scenario: Save with predeterminado runs only the preset path

- GIVEN selection is `predeterminado('woman')`
- WHEN the user taps Guardar
- THEN `SettingKey.avatar` MUST receive `'woman'`
- AND the existing custom avatar attachment (if any) MUST be deleted
- AND `AttachmentsService` MUST NOT receive a new upload during Save

#### Scenario: Save with uploadedPhoto runs only the attachment path

- GIVEN selection is `uploadedPhoto` and an attachment row exists
- WHEN the user taps Guardar
- THEN `SettingKey.avatar` MUST NOT receive a sentinel write
- AND `AttachmentsService` MUST NOT delete or replace the attachment

---

### Requirement: Cancelar discards in-memory changes

The Cancelar control MUST dismiss the sheet without writing to
`SettingKey.avatar`, `SettingKey.userName`, or `AttachmentsService`. The control
MUST be a text button (NOT a circular icon button).

#### Scenario: Cancelar after changing selection

- GIVEN the prior persisted selection was `predeterminado('man')`
- WHEN the user taps `predeterminado('woman')` and then taps Cancelar
- THEN the sheet MUST dismiss
- AND `SettingKey.avatar` MUST still equal `'man'` on disk

#### Scenario: Cancelar after typing a new name

- GIVEN the persisted name is "Ramses"
- WHEN the user types "Ramses Briceño" and taps Cancelar
- THEN the sheet MUST dismiss
- AND `SettingKey.userName` MUST still equal "Ramses" on disk

#### Scenario: Cancelar after picking and uploading a photo

- GIVEN the user just uploaded a new photo via the dashed tile
- WHEN the user taps Cancelar
- THEN the sheet MUST dismiss
- AND the freshly-uploaded attachment MUST remain on disk (Cancelar does NOT
  roll back upload side effects from the picker flow; only the in-memory
  selection is discarded)

> Note: the upload itself happens at picker-success time, not at Save time.
> Cancelar only abandons the in-memory selection; it does not rewind a successful
> upload. This matches existing behavior and is acceptable per
> [proposal.md](c:/Users/ramse/OneDrive/Documents/vacas/wallex/openspec/changes/profile-editor-redesign/proposal.md)
> rollback plan.

---

### Requirement: Visual outcomes match mockup

The rewritten sheet MUST render with the following observable visual properties,
sourced exclusively from `BolsioAiTokens.of(context)` (zero hardcoded hex in
[edit_profile_modal.dart](c:/Users/ramse/OneDrive/Documents/vacas/wallex/lib/app/settings/widgets/edit_profile_modal.dart)):

- Hero avatar diameter SHALL be ~140 logical pixels.
- Hero avatar MUST use a soft halo (token: `heroHaloShadow`) and MUST NOT have
  a thick teal border.
- Footer MUST contain exactly two controls: a `TextButton` labeled "Cancelar"
  on the left and a pill `FilledButton` labeled "Guardar" on the right.
- Footer MUST NOT contain a circular icon button (no `Icons.close`).
- A tile in the selected state MUST show: a 2px accent ring, an outer
  low-alpha accent glow, AND a circular checkmark badge at the bottom-right.
- A tile in the unselected state MUST show none of the above three cues.
- Hero name and grid section title MUST use `GoogleFonts.nunito()`.

#### Scenario: Footer composition

- GIVEN the sheet is open
- WHEN inspecting the sticky footer row
- THEN the footer MUST contain a Cancelar text button and a Guardar pill button
- AND no circular `Icons.close` button MUST be present anywhere in the sheet

#### Scenario: Selection cue uniqueness

- GIVEN any selection state
- WHEN counting tiles with the (ring + checkmark) cue
- THEN the count MUST equal exactly 1

#### Scenario: No hardcoded colors

- GIVEN the rewritten `edit_profile_modal.dart`
- WHEN scanning the file for `Color(0x` or `0xFF` literals
- THEN zero hardcoded hex color literals MUST appear

---

### Requirement: Internationalization with slang base-locale fallback

New i18n keys (hero hint, grid heading, count aside, "Tu foto" badge, upload
tile label, Cancelar) MUST exist in
[en.json](c:/Users/ramse/OneDrive/Documents/vacas/wallex/lib/i18n/json/en.json)
AND [es.json](c:/Users/ramse/OneDrive/Documents/vacas/wallex/lib/i18n/json/es.json).
The 8 secondary locales (de, fr, hu, it, tr, uk, zh-CN, zh-TW) MUST NOT receive
new keys; slang's `base_locale=en` fallback covers them.

#### Scenario: Spanish locale renders new strings

- GIVEN the device locale is `es`
- WHEN the sheet renders
- THEN the section title, hint, badge, upload label, and Cancelar MUST render
  in Spanish

#### Scenario: Secondary locale falls back to English

- GIVEN the device locale is `de`
- AND no German translations were added for the new keys
- WHEN the sheet renders
- THEN the new strings MUST render in English (slang fallback)
- AND no missing-key error MUST surface to the user

#### Scenario: Integration test selector still resolves

- GIVEN the integration test
  [dashboard_nav_test.dart](c:/Users/ramse/OneDrive/Documents/vacas/wallex/integration_test/tests/navigation/dashboard_nav_test.dart)
- WHEN the test attempts to dismiss the sheet
- THEN it MUST find the Cancelar control by text or key (NOT by `Icons.close`)
