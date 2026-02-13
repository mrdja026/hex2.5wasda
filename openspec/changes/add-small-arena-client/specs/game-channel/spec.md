## ADDED Requirements

### Requirement: Handshake-Gated Network Arena Bootstrap
The Godot client MUST NOT construct the network arena world before backend handshake success (`game_join_ack` with success) and first authoritative snapshot application.

#### Scenario: Startup before handshake success
- **WHEN** the client enters network mode and has not yet received successful `game_join_ack` and first `game_snapshot`
- **THEN** it does not create the network arena board, participants, or props
- **AND** it waits for backend readiness events

#### Scenario: Handshake success initializes world
- **WHEN** the client receives successful `game_join_ack` and applies the first `game_snapshot`
- **THEN** it initializes the network arena from that payload

### Requirement: Backend-Authoritative Small Arena Rendering
The client MUST render the network arena as a 10x10 staggered hex board using backend snapshot payload data and MUST NOT synthesize local terrain/props/participants for network sessions.

#### Scenario: Snapshot contains 10x10 arena payload
- **WHEN** the client applies a `game_snapshot`
- **THEN** it renders a 10x10 staggered hex board
- **AND** it renders trees, rocks, and participants from backend payload data only

### Requirement: Six-Direction Command Compliance
The client MUST use six directional movement command tokens for small-arena movement submissions.

#### Scenario: Player movement intent in network mode
- **WHEN** the player attempts movement in one of the six hex directions
- **THEN** the client sends one of: `move_n`, `move_ne`, `move_se`, `move_s`, `move_sw`, `move_nw`

### Requirement: Authoritative Turn-State Application
The client MUST apply `active_turn_user_id` and participant state from backend events after every action/update and reflect that state in turn UI.

#### Scenario: Backend emits action and state updates
- **WHEN** the client receives `action_result` and `game_state_update`
- **THEN** it updates current turn and participant state from backend payloads
- **AND** it does not advance turns locally without backend confirmation
