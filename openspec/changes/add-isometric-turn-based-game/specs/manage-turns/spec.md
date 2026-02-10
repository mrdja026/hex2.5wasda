## ADDED Requirements
### Requirement: Round-Robin Turn Order
The system SHALL assign turns in a round-robin sequence across all active players.

#### Scenario: Turn advances after action
- **WHEN** the active player completes a valid action
- **THEN** the next player becomes active

### Requirement: Active-Player Action Gating
The system SHALL allow only the active player to issue actions during their turn.

#### Scenario: Inactive player blocked
- **WHEN** a non-active player attempts an action
- **THEN** the action is rejected and the active player remains unchanged

### Requirement: Single Action Per Turn
The system SHALL end the current turn after one valid action is executed.

#### Scenario: Action ends turn
- **WHEN** the active player executes an action
- **THEN** the turn ends and the next player becomes active
