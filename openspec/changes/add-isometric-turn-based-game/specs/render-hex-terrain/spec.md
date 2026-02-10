## ADDED Requirements
### Requirement: Isometric Hex Terrain
The system SHALL render a 2.5D isometric terrain composed of hexagonal tiles.

#### Scenario: Terrain visible on load
- **WHEN** the game scene is loaded
- **THEN** a hexagonal tile terrain is visible in an isometric view

### Requirement: Terrain Shader Materials
The system SHALL apply shader-driven materials to terrain tiles.

#### Scenario: Shader parameters adjustable
- **WHEN** terrain shader parameters are modified
- **THEN** the terrain visual appearance updates at runtime

### Requirement: Mountain Buffer Ring
The system SHALL render a mountainous buffer ring around the battle zone and keep it impassable.

#### Scenario: Buffer ring blocks movement
- **WHEN** the game scene is loaded
- **THEN** a raised mountain ring surrounds the battle tiles
- **AND** movement targets outside the battle zone are rejected
