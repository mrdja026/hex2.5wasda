# Change: Update movement and action logging specs

## Why

Movement validation and HUD logging behavior are now implemented and confirmed working, but the expected behavior is not fully captured in OpenSpec requirements.

## What Changes

- Add movement-budget requirements for turn flow (two moves per turn with explicit exhaustion behavior)
- Add player-movement validation requirements for blocked tiles and play-area bounds
- Add UI logging requirements for movement and system feedback, including bounded log history

## Impact

- Affected specs: manage-turns, manage-players, display-ui
- Affected code: `scripts/turn_manager.gd`, `scripts/game.gd`, `scripts/game_world.gd`, `scripts/game_ui.gd`
