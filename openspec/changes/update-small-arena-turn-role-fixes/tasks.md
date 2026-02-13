## 1. Human-Playable Role Invariant
- [ ] 1.1 Ensure successful real-user `game_join` claims/retains the single human slot when vacant.
- [ ] 1.2 Ensure NPC seeding does not permanently consume the human slot before first playable join.
- [ ] 1.3 Add regression tests for: first join, human leave + rejoin, and NPC-seeded channel recovery.

## 2. Turn Fairness (No Privileged Infinite Actions)
- [ ] 2.1 Remove/disable username-based privileged turn logic for small-arena (including `admina`).
- [ ] 2.2 Ensure each successful action advances exactly one actor step in authoritative order.
- [ ] 2.3 Add regression test proving `admina` cannot act indefinitely without normal turn rotation.

## 3. Authoritative Turn Budget
- [ ] 3.1 Enforce per-turn budget for all actors: maximum 2 valid hex moves and 1 action.
- [ ] 3.2 Reject budget-overrun attempts with explicit backend error messages.
- [ ] 3.3 Add regression test where a playable character attempts to exceed `2 moves + 1 action`.

## 4. NPC Autonomous Turn Loop
- [ ] 4.1 Implement backend NPC loop as up to two random movement attempts followed by action resolution.
- [ ] 4.2 Apply 50/50 heal policy when no valid attack target is available and NPC is damaged.
- [ ] 4.3 Ensure failed NPC movement/action attempts cannot stall turn progression.
- [ ] 4.4 Broadcast action_result + state updates so Godot turn UI remains authoritative.

## 5. State Refresh Reliability
- [ ] 5.1 Ensure successful `admina` actions in UI `#game` flow always push immediate authoritative `game_state_update`.
- [ ] 5.2 Add regression test for action_result + update broadcast ordering and timing after `admina` action.

## 6. Godot Verification
- [ ] 6.1 Surface current player role (`is_npc`) and active turn in join/debug UI for quick diagnosis.
- [ ] 6.2 Manual verify at least one controllable non-NPC participant exists in active channel.
- [ ] 6.3 Manual verify loop: human action -> NPC loop -> next human action.
- [ ] 6.4 Manual verify budget enforcement (`2 moves + 1 action`) from Godot client input path.

## 7. Contract Validation
- [ ] 7.1 Ensure backend command schema contract test remains green (`some-kind-of-irc/backend/tests/test_command_schema_contract.py`).
- [ ] 7.2 Add/update backend tests for role assignment, fairness, budget limits, refresh timing, and NPC loop behavior.
