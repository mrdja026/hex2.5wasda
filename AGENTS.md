<!-- OPENSPEC:START -->
# OpenSpec Instructions

These instructions are for AI assistants working in this project.

Always open `@/openspec/AGENTS.md` when the request:
- Mentions planning or proposals (words like proposal, spec, change, plan)
- Introduces new capabilities, breaking changes, architecture shifts, or big performance/security work
- Sounds ambiguous and you need the authoritative spec before coding

Use `@/openspec/AGENTS.md` to learn:
- How to create and apply change proposals
- Spec format and conventions
- Project structure and guidelines

Keep this managed block so 'openspec update' can refresh the instructions.

Use read tool before writing to get the newest version.In code mode

This guide outlines the best practices and coding standards for Godot 4.x development, formatted as a system prompt (or `Agents.md` equivalent) to guide an AI assistant or development team.

---
# Aditional repos
There is an aditional repo that is in the root of this repo and /some-kind-of-irc which is the backend as a source of truth for the godot game that is client.
# Godot 4.x Development Standards (Agents.md)

## 1. Core Philosophy
*   **Scene Independence:** Every scene should be able to run and be tested in isolation.
*   **Encapsulation:** "Signal Up, Call Down." Use signals for child-to-parent communication and method calls for parent-to-child interactions.
*   **Composition over Inheritance:** Prefer small, modular nodes (Components) over deep inheritance hierarchies.
*   **Data-Driven Design:** Use `Resource` files for configuration, stats, and item definitions to keep logic separate from data.

## 2. Naming Conventions
*   **Files & Folders:** `snake_case.gd`, `player_controller.tscn`. (Crucial for cross-platform case-sensitivity).
*   **Classes & Nodes:** `PascalCase`. (Matches built-in engine nodes).
*   **Functions & Variables:** `snake_case`.
*   **Constants & Enums:** `CONSTANT_CASE`.
*   **Private Members:** Prepend with an underscore (e.g., `_private_variable`, `func _private_method()`).
*   **Signals:** Past tense (e.g., `health_changed`, `door_opened`).

## 3. GDScript Style Guide (Order of Operations)
Follow this exact order in every script:
1.  **Annotations:** `@tool`, `@icon`
2.  **Class Definition:** `class_name ClassName`
3.  **Inheritance:** `extends Node`
4.  **Signals:** `signal name(args)`
5.  **Enums & Constants:** `enum Name { ... }`, `const NAME = ...`
6.  **Exported Variables:** `@export var variable_name: Type`
7.  **Public Variables:** `var variable_name: Type`
8.  **Onready Variables:** `@onready var node_name = $NodeName`
9.  **Private Variables:** `var _variable_name: Type`
10. **Built-in Overrides:** `_init()`, `_ready()`, `_process(delta)`, `_physics_process(delta)`, `_input(event)`
11. **Public Methods:** `func do_something() -> void:`
12. **Private Methods:** `func _do_internal() -> void:`

## 4. Coding Standards
*   **Static Typing:** Always use type hints (`var x: int = 5`, `func f() -> void`). It improves IDE autocompletion and runtime performance.
*   **Infer Types:** Use `:=` when the type is obvious (e.g., `@onready var sprite := $Sprite2D`).
*   **Documentation:** Use `##` (double hash) for class-level and member documentation comments. These appear in the Godot inspector.
*   **Avoid String Hardcoding:** Use `NodePath`, `StringName`, or `Group` constants.
*   **Node Access:** Use `@onready` and the `$` shorthand for children. Never use `find_node()` or `get_child(0)`.

## 5. Architectural Patterns
*   **The Signal Bus:** For global events (e.g., `game_started`, `player_died`), use an Autoload singleton named `GameEvents.gd` or `Signals.gd`.
*   **Component Pattern:**
    *   Create a `Hitbox` (Area2D/3D) and `Hurtbox` (Area2D/3D).
    *   Use a `HealthComponent` (Node) to manage HP logic.
    *   Add these as children to any entity that needs that behavior.
*   **State Machines:** For complex actors, use a Node-based Finite State Machine (FSM) where each state is its own script/node.
*   **Resource Management:** Create custom resources for any repetitive data (e.g., `EnemyData.gd` extending `Resource`).

## 6. Project Organization
Use the **"Entity-First"** approach for scalability:
```text
res://
├── assets/             # Global assets (fonts, shaders, themes)
├── common/             # Shared scripts, components, and singletons
├── core/               # Global systems (level loader, save system)
├── entities/           # Folder per entity
│   └── player/
│       ├── player.tscn
│       ├── player.gd
│       ├── player_sprite.png
│       └── components/  # Local components
└── scenes/             # Levels and UI screens
    ├── main_menu/
    └── level_1/
```

## 7. Performance & Optimization
*   **Physics:** Use `_physics_process` only for physics-related code.
*   **Object Pooling:** For frequently spawned objects like bullets, use an Object Pool to avoid `instantiate()` and `queue_free()` overhead.
*   **Signals over Polling:** Don't check variables in `_process` every frame. Emit a signal when the variable changes.
*   **Collision Layers:** Carefully define Collision Layers (what I am) and Masks (what I hit) in the Project Settings to avoid unnecessary physics calculations.

## 8. Version Control
*   **Ignore Files:** Ensure `.godot/`, `*.tmp`, and local `export_presets.cfg` are in `.gitignore`.
*   **Text-Based**: Keep scenes and resources in .tscn and .tres format (text-based) to allow for Git diffs.
<!-- OPENSPEC:END -->

## Learned Lessons (Networked Game)

- CRITICAL: Frontend game rendering and state must remain in parity with Godot behavior and backend snapshot contracts; do not introduce changes that break cross-client sync.
- CRITICAL: `some-kind-of-irc/backend/tests/test_command_schema_contract.py` must always pass because it is the backend-to-Godot command contract for transport tokens.
- CRITICAL: Both repos (Godot client and backend) must implement and emit the same transport tokens from this contract even when runtime schema validation is not yet enforced.
- In network mode, render battlefield props/buffer from backend snapshot payload; do not locally randomize battlefield state.
- Keep WebSocket state and heartbeat visible in join/debug UI to avoid silent join failures.
- Write network diagnostics to project `logs/` so sync issues can be verified post-run.
- Map backend 64x64 coordinates deterministically to local hex world bounds for consistent rendering.

## Technical Debt

- Add lightweight runtime payload shape checks in Godot for `game_snapshot`/`game_state_update`.
- Reduce script size in `scripts/Game.gd` by extracting network battlefield sync helpers into a dedicated script.
- Add integration smoke tests for “join -> snapshot -> render players/props/buffer -> move” flow.
