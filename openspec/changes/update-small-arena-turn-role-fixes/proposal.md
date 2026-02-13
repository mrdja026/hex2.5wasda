# Change: Update small-arena turn and role authority fixes

## Why
Current small-arena behavior regressed in multiple ways: channels can end up with no human-playable Godot participant, `admina` can act repeatedly without fair turn rotation, NPC autonomous turns do not follow the intended loop behavior, and manual verification shows state refresh timing issues in the UI channel flow. In addition, some playable characters can exceed the expected per-turn budget (`max 2 hex moves + 1 action`). These regressions break expected multiplayer flow and make sessions appear stuck or desynced.

## What Changes
- Add explicit game-channel requirements to guarantee one human-playable participant slot for active Godot sessions.
- Add explicit fairness requirements that remove/disable privileged indefinite turn behavior (including legacy `admina` bias).
- Add explicit backend NPC loop requirements: random movement sequence, conditional action resolution, and non-blocking turn progression.
- Add explicit authoritative turn-budget requirements for all playable participants (`max 2 hex moves + 1 action` per turn).
- Add explicit real-time state-push requirements so successful actions (including `admina`) immediately trigger refreshed authoritative state for the UI channel.
- Add verification requirements for Godot client observability so users can confirm human role ownership and authoritative turn progress.

## Impact
- Affected specs: `game-channel`
- Affected code (planned):
  - Godot repo: `scripts/Game.gd`, `scripts/network_sync.gd`, `scripts/game_network.gd`, join/turn diagnostics UI
  - Backend source-of-truth (nested repo): `some-kind-of-irc/backend/src/services/game_service.py`, `some-kind-of-irc/backend/src/main.py`, `some-kind-of-irc/backend/tests/*`
