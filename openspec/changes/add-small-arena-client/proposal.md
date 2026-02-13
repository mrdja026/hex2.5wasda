# Change: Add small-arena client contract

## Why
The networked game flow still allows client-side world construction before backend readiness, and current rendering/movement assumptions do not match the desired small 10x10 hex arena mode.

## What Changes
- Define a strict backend-first bootstrap for Godot network sessions: no arena/world creation before successful handshake and first snapshot.
- Add client requirements for rendering a 10x10 staggered hex arena from backend payload only.
- Add client command requirements for six-direction hex movement tokens.
- Add client requirements for authoritative participant and turn rendering from backend state updates.

## Impact
- Affected specs: `game-channel` (new capability for this repository).
- Affected code (planned): `scripts/Game.gd`, `scripts/hex_terrain.gd`, `scripts/network_sync.gd`, `scripts/game_network.gd`, UI/turn indicators.
