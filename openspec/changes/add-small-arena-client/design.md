## Context
The client currently constructs terrain in `_ready()` and applies network snapshots afterward. For `small-arena`, initialization must be backend-authoritative and handshake-gated.

## Goals / Non-Goals
- Goals:
  - Ensure no client-created network arena before backend readiness.
  - Render a backend-authored 10x10 staggered hex board.
  - Support six-direction movement command tokens.
  - Keep turn UI/state aligned after each backend update.
- Non-Goals:
  - Reworking offline/local game mode.
  - Changing combat formulas.

## Decisions
- Decision: Gate network world bootstrap behind `game_join_ack` success and first `game_snapshot`.
  - Rationale: Enforces backend source-of-truth and removes pre-handshake divergence.
- Decision: Client uses backend map/props/players as immutable initialization input in network mode.
  - Rationale: Prevents local generation mismatch and spawn drift.
- Decision: Client sends six directional command tokens exactly as schema-defined.
  - Rationale: Keeps transport parity across Godot/backend/web.

## Risks / Trade-offs
- Risk: Existing scene startup dependencies assume terrain exists at `_ready()`.
  - Mitigation: Introduce a deferred network arena build path after handshake.
- Risk: Input mapping/UI may still expose legacy 4-direction controls.
  - Mitigation: Keep all command mapping centralized and schema-driven.

## Migration Plan
1. Add handshake-ready gating flag.
2. Move network terrain/entity creation to post-snapshot path.
3. Update movement token mapping to six directions.
4. Verify turn UI refreshes on each backend action/update.

## Open Questions
- None for proposal stage.
