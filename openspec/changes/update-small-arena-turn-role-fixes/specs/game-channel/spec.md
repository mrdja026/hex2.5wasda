## ADDED Requirements

### Requirement: Human-Playable Slot Guarantee
For active small-arena channels, the system MUST maintain at least one non-NPC participant slot that can be controlled from the Godot client.

#### Scenario: NPC-seeded channel receives first real player
- **WHEN** a channel already contains seeded NPC participants and no active human participant
- **AND** a real user successfully completes `game_join`
- **THEN** that user is assigned the human-playable slot (`is_npc=false`)
- **AND** the user is eligible to receive normal turn ownership

#### Scenario: Human slot recovery after leave
- **WHEN** the current human participant leaves the channel
- **THEN** the next successful real-user `game_join` is assigned the human-playable slot

### Requirement: Strict Turn Fairness Without Username Privileges
Small-arena turn progression MUST NOT grant identity-based extra actions or indefinite loops.

#### Scenario: Legacy privileged username cannot act indefinitely
- **WHEN** a user with username `admina` performs a successful action
- **THEN** turn ownership follows normal authoritative rotation rules
- **AND** a second immediate action from the same user is rejected unless that user is active again

### Requirement: Authoritative Per-Turn Budget
Small-arena MUST enforce a strict per-turn budget for each actor: at most two valid movement steps and one action.

#### Scenario: Playable character exceeds movement budget
- **WHEN** a playable character submits a third valid movement command in the same turn window
- **THEN** backend rejects the command as budget exceeded
- **AND** authoritative position and turn ownership remain unchanged until a valid next step

#### Scenario: Playable character exceeds action budget
- **WHEN** a playable character submits a second action command in the same turn window
- **THEN** backend rejects the command as budget exceeded
- **AND** client receives explicit rejection feedback

### Requirement: Backend NPC Turn Program
For each NPC-controlled turn, the backend MUST execute a bounded autonomous program: up to two random movement attempts followed by one action resolution step.

#### Scenario: NPC executes movement phase then action phase
- **WHEN** an NPC becomes active turn owner
- **THEN** the backend evaluates up to two random movement attempts using play-zone and blocked-cell validation
- **AND** the backend then resolves one action step (`attack` when valid target exists, otherwise heal/no-op branch)

#### Scenario: NPC heal decision gate
- **WHEN** an NPC has no valid attack target and is below max health
- **THEN** backend applies a 50/50 random heal decision
- **AND** the turn loop progresses regardless of heal/no-heal outcome

### Requirement: Non-Blocking NPC Failure Handling
NPC movement/action failures MUST NOT stall authoritative turn progression.

#### Scenario: NPC attempts invalid move outside play zone
- **WHEN** an NPC movement attempt is rejected (for example, outside battle zone)
- **THEN** backend continues NPC loop processing and/or advances turn
- **AND** the active turn can return to a human participant without manual recovery

### Requirement: Godot Turn/Role Diagnostics
The Godot client MUST expose authoritative role and turn diagnostics so stuck-loop regressions are immediately visible.

#### Scenario: Debug UI shows role and turn source
- **WHEN** snapshot/update/action_result events are applied
- **THEN** the join/debug UI shows current local role (`is_npc`), `active_turn_user_id`, and latest backend status/error entry

### Requirement: Immediate State Refresh After Successful UI Actions
For UI-driven `#game` actions, successful action handling MUST push updated authoritative state immediately.

#### Scenario: admina action triggers immediate refresh
- **WHEN** `admina` performs a successful action via the UI `#game` channel flow
- **THEN** backend emits `action_result` and the corresponding refreshed `game_state_update` without delayed/manual recovery
- **AND** Godot and UI clients apply the new active turn/state in the same action cycle
