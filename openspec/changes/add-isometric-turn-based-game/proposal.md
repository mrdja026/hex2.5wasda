# Change: Add 2.5D isometric turn-based gameplay

## Why
Provide a clear plan to build a 2.5D isometric, hex-based, turn-driven combat loop with core actions, visuals, and lighting.

## What Changes
- Add 2.5D isometric hex terrain rendering with shader-driven materials
- Add a mountainous buffer ring around the battle zone to block movement
- Add a turn manager with action gating and round-robin sequencing
- Add combat actions (attack and self-heal) with adjacency rules
- Add player session limits (max 10 players) and player state tracking
- Add attack animation triggers for player actions
- Add adjustable scene lighting sources
- Add a parchment-styled HUD with four corner panels and a menu bar

## Impact
- Affected specs: render-hex-terrain, manage-turns, resolve-combat, manage-players, animate-characters, control-lighting, display-ui
- Affected code: new Godot scenes and scripts for terrain, units, turn manager, combat, animation, lighting, and UI
