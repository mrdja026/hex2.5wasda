## ADDED Requirements
### Requirement: Menu Bar
The system SHALL display a menu bar with File and Debug menus.

#### Scenario: File exit
- **WHEN** the user selects File -> Exit
- **THEN** the application quits

#### Scenario: Debug stub
- **WHEN** the user selects Debug -> Debug
- **THEN** a debug stub action is recorded in the system panel

### Requirement: Corner Status Panels
The system SHALL display four corner panels for turn status, combat, movement, and system information.

#### Scenario: Panels visible on load
- **WHEN** the game scene is loaded
- **THEN** all four panels are visible with their respective headings

### Requirement: Parchment Styling
The system SHALL render HUD panels with parchment-style backgrounds and dark text.

#### Scenario: Parchment UI styling
- **WHEN** the HUD panels are displayed
- **THEN** the panels use parchment colors with readable dark text
