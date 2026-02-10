## Context
Build a small 2.5D isometric, hex-grid, turn-based combat prototype in Godot. The request includes shader-based terrain, turn sequencing, attack/heal actions, attack animations, and adjustable lighting.

## Goals / Non-Goals
- Goals: deliver a playable hex combat loop with turns, attack/heal actions, and readable visuals
- Goals: keep player count capped at 10 and ensure action gating by active turn
- Non-Goals: networking, AI opponents, inventory/equipment systems, progression, or UI polish

## Decisions
- Decision: Use axial hex coordinates (q, r) with distance = max(|dq|, |dr|, |dq+dr|)
- Decision: Render in 3D with an orthographic isometric camera to achieve 2.5D look
- Decision: Use a single action per turn (attack, heal, or end turn) for the core loop
- Decision: Define "near" as adjacent hex distance 1 for attack range
- Decision: Use ShaderMaterial parameters for terrain appearance (color, texture blend, height)
- Decision: Use AnimationPlayer/AnimationTree to trigger attack animations on action resolve
- Decision: Provide adjustable light nodes (directional + point) with runtime-tunable parameters

## Risks / Trade-offs
- Hex-to-world mapping errors can cause misaligned tiles; validate with debug overlays
- Shader complexity can impact performance; start with simple parameters and extend later
- One-action turns are simple but may feel limiting; revisit after playtesting

## Migration Plan
Not applicable; this is a new capability set.

## Open Questions
- Should movement be included as a turn action in the initial prototype?
- Should attacks have ranged options or remain strictly adjacent only?
- Is healing limited by cooldowns or action points beyond the one-action model?
- Are the 10 players all local human-controlled, or should AI fill empty slots?
