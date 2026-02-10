# Isometric Hex Turn-Based Prototype

Small Godot 4 prototype for a 2.5D isometric, hex-based, turn-driven combat loop.

## Features
- Hex terrain with shader and borders
- Turn order with 2 moves + 1 action per turn
- Attack and self-heal actions
- P1 manual controls, NPCs take turns automatically
- Targeting, outline highlight, and combat log
- Props (trees/rocks), lighting, and death effects

## Requirements
- Godot 4.6 (tested with 4.6-stable)

## Start
Option 1: Use the helper script
```
./run_godot.bat
```

Option 2: Open manually
1. Launch Godot 4.6
2. Open this folder
3. Press Play

## Controls (P1 only)
- WASD: move
- Left click: move to hovered hex (max 2 steps)
- J: attack adjacent target
- K: heal
- Tab: cycle adjacent targets
- Space: end turn
- Right click drag: pan camera
- Mouse wheel: zoom
- Z/X: directional light intensity
- C/V: point light intensity
- B/N: point light height
- M: cycle light color presets
- Shift + left click drag: move sun east to west

## Playtest Checklist
- Terrain renders in an isometric view on scene load
- Players spawn with health bars and are capped at 10
- Turn order advances after a valid action
- Adjacent attacks apply damage; out-of-range attacks are blocked
- Heal action restores health without exceeding max
- Lighting controls update scene intensity, height, and colors

## Notes
- Combat log appears bottom-right; controls legend bottom-left.
- NPCs act with a short delay between moves/actions.
