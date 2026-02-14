## ADDED Requirements

### Requirement: Backend Endpoint Configuration

The client SHALL default the backend base URL to http://localhost:8002 and allow overriding when needed.

#### Scenario: Local backend configuration

- **WHEN** the base URL is set to a local server address or uses the default
- **THEN** the client uses that address for REST and WebSocket connections

### Requirement: Auth Game Session

The client SHALL call auth_game to obtain a guest session, channel id, and snapshot.

#### Scenario: Auth game on startup

- **WHEN** the client starts a networked session
- **THEN** it calls auth_game and stores the access token and user id
- **AND** it uses the returned snapshot to initialize the game state

### Requirement: Join #game and Load Snapshot

The client SHALL join #game and load the current game snapshot as defined by the shared contract.

#### Scenario: Successful join

- **WHEN** the client joins the #game channel
- **THEN** it receives a snapshot containing players, obstacles, battlefield payload, map size, and active turn
- **AND** it renders the entities based on the snapshot data

### Requirement: Turn Command Submission

The client SHALL submit turn commands using the shared command grammar: move up, move down, move left, move right, attack, heal.

#### Scenario: Send move command

- **WHEN** the player chooses to move left
- **THEN** the client sends the move command to the backend
- **AND** the client awaits an acknowledgement or error response

#### Scenario: Out-of-turn command

- **WHEN** the player sends a move while it is not their turn
- **THEN** the client still sends the command via WebSocket
- **AND** it displays the backend rejection/error without applying local state changes

### Requirement: Apply State Updates

The client SHALL apply state updates from WebSocket broadcasts as defined by the shared contract.

#### Scenario: Apply update

- **WHEN** a state update is received
- **THEN** the client updates player positions, health, and obstacles

### Requirement: Backend-Authoritative Battlefield Rendering

The client SHALL treat snapshot battlefield payload as authoritative for network-mode world rendering.

#### Scenario: Snapshot contains battlefield props and buffer

- **WHEN** a snapshot includes battlefield props and buffer tiles
- **THEN** the client renders trees/rocks and buffer blocking from payload data
- **AND** it does not run local random battlefield generation for network sync

### Requirement: Network Diagnostics

The client SHALL expose connection diagnostics for easier join/debug troubleshooting.

#### Scenario: Join and runtime diagnostics

- **WHEN** the client enters network mode and joins #game
- **THEN** it shows status transitions, heartbeat health, and connection state in UI
- **AND** it writes network logs to a file in the project `logs/` directory

### Requirement: NPC Visual Differentiation

The client SHALL render NPC players in blue and non-NPC players in red.

#### Scenario: Snapshot includes NPCs

- **WHEN** the client receives a snapshot with is_npc flags
- **THEN** it renders NPCs in blue and non-NPC players in red

### Requirement: Turn Carousel Display

The client SHALL show previous, current, and next player in a turn carousel.

#### Scenario: Carousel updates on snapshot

- **WHEN** a snapshot is applied
- **THEN** the client updates the turn carousel with previous, current, and next players
