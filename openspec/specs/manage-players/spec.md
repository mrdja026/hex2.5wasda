# manage-players Specification

## Purpose
TBD - created by archiving change update-movement-and-action-logs. Update Purpose after archive.
## Requirements
### Requirement: Validated Hex Movement
The system SHALL move a player only when the destination hex is within the play area and not blocked by terrain, props, or another player.

#### Scenario: Successful move updates occupancy
- **WHEN** the active player moves to a valid adjacent hex
- **THEN** the player's axial position and world position are updated
- **AND** the previous hex is unblocked
- **AND** the destination hex is marked blocked

#### Scenario: Invalid move is rejected
- **WHEN** the active player attempts to move outside the play area or into a blocked hex
- **THEN** the move is rejected
- **AND** the player's position remains unchanged

