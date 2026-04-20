# settings Specification (delta)

## Purpose

Adds the `aiVoiceEnabled` sub-toggle under the AI settings group, gated by the master `nexusAiEnabled` flag.

## ADDED Requirements

### Requirement: aiVoiceEnabled Setting Key

The system MUST add `SettingKey.aiVoiceEnabled` to the user-settings enum with default value `'1'` when `nexusAiEnabled == '1'`. This SHALL be a trailing enum addition requiring NO Drift migration.

#### Scenario: Default value on fresh install with AI enabled

- GIVEN a fresh install where `nexusAiEnabled` is `'1'`
- WHEN settings are read for the first time
- THEN `aiVoiceEnabled` resolves to `'1'`

#### Scenario: Respects master toggle off

- GIVEN `nexusAiEnabled = '0'`
- WHEN any UI queries whether voice is usable
- THEN the combined check returns false regardless of `aiVoiceEnabled` value

### Requirement: AI Settings Page Toggle

The `AiSettingsPage` MUST render a `SwitchListTile` bound to `aiVoiceEnabled`, disabled (greyed) when `nexusAiEnabled = '0'`. Label SHALL use `t.settings.ai.voice_input.title` / `.subtitle`.

#### Scenario: Toggle disables both surfaces

- GIVEN `aiVoiceEnabled = '1'` and both UI mic affordances are visible
- WHEN the user toggles it to `'0'`
- THEN the chat mic button and the FAB 4th action both disappear on next rebuild
- AND existing transactions and chat history remain unaffected

#### Scenario: Greyed when master is off

- GIVEN `nexusAiEnabled = '0'`
- WHEN `AiSettingsPage` renders
- THEN the voice toggle is disabled and shows the master-toggle tooltip
