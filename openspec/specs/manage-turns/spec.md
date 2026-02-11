# manage-turns Specification

## Purpose
TBD - created by archiving change update-movement-and-action-logs. Update Purpose after archive.
## Requirements
### Requirement: Per-Turn Movement Budget
The system SHALL allow the active player to perform up to two valid movement actions before movement is exhausted for that turn.

#### Scenario: Valid movement consumes budget
- **WHEN** the active player performs a valid move
- **THEN** the remaining move budget is reduced by one

#### Scenario: Movement budget exhausted
- **WHEN** the active player has already used two valid moves this turn
- **THEN** additional move attempts are rejected until the turn changes

