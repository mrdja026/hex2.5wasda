## 1. Handshake-Gated Arena Lifecycle
- [x] 1.1 Block client arena/world construction until `game_join_ack` is successful and first `game_snapshot` is applied.
- [x] 1.2 Ensure network mode does not trigger offline/local terrain or participant generation paths.

## 2. Small Arena Rendering Contract
- [x] 2.1 Render 10x10 staggered hex board using backend snapshot map metadata.
- [x] 2.2 Render trees/rocks/players only from backend payload; do not synthesize client entities in network mode.

## 3. Movement + Turn Sync
- [x] 3.1 Support six-direction command tokens (`move_n`, `move_ne`, `move_se`, `move_s`, `move_sw`, `move_nw`).
- [x] 3.2 Apply active turn updates after every backend state update/action result and keep turn UI in sync.

## 4. Validation
- [ ] 4.1 Manual verify: no world appears before handshake success.
- [ ] 4.2 Manual verify: first snapshot shows 10x10 arena with authoritative props/participants.
- [ ] 4.3 Manual verify: six-direction movement and turn progression follow backend updates.
