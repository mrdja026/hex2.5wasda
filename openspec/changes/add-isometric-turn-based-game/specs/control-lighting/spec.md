## ADDED Requirements
### Requirement: Adjustable Lighting Sources
The system SHALL provide adjustable light sources that affect the scene.

#### Scenario: Lighting properties updated
- **WHEN** a light's position, intensity, or color is changed
- **THEN** the scene lighting updates accordingly

### Requirement: Sun Path Control
The system SHALL allow the user to drag the sun along an east-to-west path.

#### Scenario: Sun drag updates lighting
- **WHEN** the user drags the sun control
- **THEN** the directional light orientation updates
- **AND** the sun indicator reflects the new position
