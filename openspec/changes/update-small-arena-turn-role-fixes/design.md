## Context
Small-arena networking is backend-authoritative, but role assignment and turn automation currently allow edge cases that make gameplay feel broken: no controllable human slot, legacy privileged turns, stalled NPC loops after invalid moves, per-turn budget violations, and delayed/missing state refresh after certain UI-triggered actions (notably `admina` actions in `#game`).

## Goals / Non-Goals
- Goals:
  - Guarantee at least one human-playable participant for active Godot network sessions.
  - Enforce strict turn fairness with no privileged indefinite action loops.
  - Enforce a strict per-turn budget of max two movement steps plus one action for each actor.
  - Define deterministic NPC autonomous loop behavior that never stalls turn progression.
  - Ensure successful actions always push an immediate authoritative refresh to clients.
  - Keep backend as source of truth while preserving Godot parity and diagnostics.
- Non-Goals:
  - Redesign combat system, damage values, or map generation algorithm.
  - Introduce client-side simulation authority.
  - Add new transport message types beyond current snapshot/update/action_result contract.

## Decisions
- Decision: Human slot is a channel-level invariant.
  - Rule: if no active human is assigned, the next successful real-user `game_join` claims human role.
  - Rule: NPC seeding must not permanently consume the human slot.
- Decision: Legacy privileged-turn behavior is disabled for small-arena.
  - Rule: each successful actor action advances turn exactly once in turn order.
  - Rule: no username-based turn multipliers (including `admina`).
- Decision: Per-turn budget is authoritative and uniform.
  - Rule: each actor may perform at most two valid movement steps and one action during its turn window.
  - Rule: additional move/action attempts in the same turn are rejected with explicit backend feedback.
- Decision: NPC autonomous behavior is bounded and non-blocking.
  - Rule: each NPC turn evaluates up to two random valid movement attempts.
  - Rule: after movement phase, NPC attempts an action (attack when valid target exists, otherwise heal with 50/50 policy when damaged, else no-op).
  - Rule: invalid NPC moves/actions must still advance the loop to prevent deadlock.
- Decision: Action success always emits immediate refresh.
  - Rule: after each successful action_result (human or NPC, including `admina`), backend emits updated authoritative turn/player state without delay.

## Risks / Trade-offs
- Risk: Tighter role constraints may change existing seeded-channel behavior.
  - Mitigation: add regression tests for first join, rejoin after human leave, and NPC-seeded channels.
- Risk: More NPC activity could increase event volume.
  - Mitigation: keep update payload lightweight and preserve per-action broadcasting contract.
- Risk: Strict per-turn budget may expose existing client assumptions.
  - Mitigation: keep rejection reasons explicit and visible in Godot diagnostics/UI logs.

## Migration Plan
1. Add backend tests first for role assignment, turn fairness, and NPC loop progression.
2. Update backend turn/role logic to satisfy the new invariants.
3. Update Godot diagnostics/turn indicators to clearly expose human-role ownership and active-turn source.
4. Run contract + integration smoke flow: join -> snapshot -> human turn -> npc loop -> next human turn.

## Open Questions
- Should NPC "move x2" mean two mandatory successful moves, or up to two attempts within bounds/blocked constraints? (Default in this change: up to two attempts, non-blocking.)
