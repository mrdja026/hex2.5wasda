# display-ui Specification

## Purpose
TBD - created by archiving change update-movement-and-action-logs. Update Purpose after archive.
## Requirements
### Requirement: Movement and System Feedback Logs
The system SHALL append movement and system feedback entries to the HUD so players can understand successful actions and rejected movement attempts.

#### Scenario: Successful move is logged
- **WHEN** a player completes a valid movement action
- **THEN** the movement panel shows an entry with the player and destination
- **AND** the system panel shows the resulting movement state

#### Scenario: Rejected move is logged
- **WHEN** a movement attempt is rejected due to bounds, blocking, or move exhaustion
- **THEN** the system panel shows a reasoned rejection entry

### Requirement: Bounded HUD Log History
The system SHALL keep bounded log history per HUD panel so recent events remain visible without unbounded growth.

#### Scenario: Log history trims oldest entries
- **WHEN** the number of entries exceeds the configured limit for a panel
- **THEN** the oldest entries are removed and the newest entries remain visible

