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
- **THEN** it receives a snapshot containing players, obstacles, map size, and active turn
- **AND** it renders the entities based on the snapshot data

### Requirement: Turn Command Submission

The client SHALL submit turn commands using the shared command grammar: move up, move down, move left, move right, attack, heal.

#### Scenario: Send move command

- **WHEN** the player chooses to move left
- **THEN** the client sends the move command to the backend
- **AND** the client awaits an acknowledgement or error response

#### Scenario: Force command when out of turn

- **WHEN** the player sends a move while it is not their turn
- **THEN** the client sends the command with force enabled
- **AND** it logs the action as a ghost turn

### Requirement: Apply State Updates

The client SHALL apply state updates from WebSocket broadcasts as defined by the shared contract.

#### Scenario: Apply update

- **WHEN** a state update is received
- **THEN** the client updates player positions, health, and obstacles

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
