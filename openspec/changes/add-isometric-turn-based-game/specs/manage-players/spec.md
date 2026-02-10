## ADDED Requirements
### Requirement: Session Player Limit
The system SHALL support up to 10 active players in a session.

#### Scenario: Player cap enforced
- **WHEN** an 11th player is added
- **THEN** the system rejects the addition and reports the cap

### Requirement: Player State
The system SHALL track each player's position on the hex grid and health values.

#### Scenario: Player state initialized
- **WHEN** a player is spawned
- **THEN** their position and health are initialized to valid values
