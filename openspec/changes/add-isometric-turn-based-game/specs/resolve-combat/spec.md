## ADDED Requirements
### Requirement: Adjacent Attack
The system SHALL allow a player to attack another player within adjacent hex distance 1.

#### Scenario: Adjacent attack succeeds
- **WHEN** the active player targets another player on an adjacent hex
- **THEN** damage is applied to the target

#### Scenario: Out-of-range attack blocked
- **WHEN** the active player targets another player beyond adjacent hex distance
- **THEN** the attack is rejected

### Requirement: Self Heal
The system SHALL allow a player to heal themselves during their turn.

#### Scenario: Heal restores health
- **WHEN** the active player uses the heal action
- **THEN** their health increases up to their maximum health
