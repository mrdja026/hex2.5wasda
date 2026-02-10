extends Node3D

@export var player_scene: PackedScene = preload("res://scenes/PlayerUnit.tscn")
@export var spawn_positions: Array[Vector2i] = [
	Vector2i(0, 0),
	Vector2i(1, 0),
	Vector2i(0, 1),
	Vector2i(-1, 0)
]
@export var ai_action_delay: float = 0.5
@export var camera_pan_speed: float = 0.03
@export var camera_zoom_step: float = 1.0
@export var camera_zoom_min: float = 8.0
@export var camera_zoom_max: float = 40.0
@export var tree_count: int = 10
@export var rock_count: int = 8

@onready var terrain: HexTerrain = $HexTerrain
@onready var turn_manager: TurnManager = $TurnManager
@onready var player_container: Node3D = $PlayerContainer
@onready var props_container: Node3D = $Props
@onready var debug_label: Label = $UI/DebugLabel
@onready var log_label: Label = $UI/CombatLog
@onready var controls_label: Label = $UI/ControlsLabel
@onready var camera: Camera3D = $Camera3D

var _players: Array[PlayerUnit] = []
var _combat_log: Array[String] = []
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _is_panning: bool = false
var _blocked_axials: Dictionary = {}
var _prop_labels: Dictionary = {}
var _current_target: PlayerUnit = null
var _adjacent_targets: Array[PlayerUnit] = []
var _blood_decal_texture: Texture2D
var _hover_marker: MeshInstance3D
var _hover_axial: Vector2i = Vector2i.ZERO
var _hover_path: Array[Vector2i] = []
var _hover_time: float = 0.0
var _is_human_moving: bool = false

const MAX_LOG_LINES: int = 6
const MOVE_DIRECTIONS: Array[Vector2i] = [
	Vector2i(0, -1),
	Vector2i(0, 1),
	Vector2i(-1, 0),
	Vector2i(1, 0)
]

func _ready() -> void:
	_rng.randomize()
	_ensure_input_map()
	_spawn_players()
	_spawn_props()
	turn_manager.active_player_changed.connect(_on_active_player_changed)
	turn_manager.start_turns()
	_update_debug_label()
	_update_combat_log()
	_update_controls_label()
	_create_hover_marker()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_zoom_camera(-camera_zoom_step)
			return
		if event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_zoom_camera(camera_zoom_step)
			return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT:
		_is_panning = event.pressed
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		_try_mouse_move()
		return
	if event is InputEventMouseMotion and _is_panning:
		_pan_camera(event.relative)
		return
	if event is InputEventMouseMotion:
		_update_hover_from_mouse(event.position)
		return
	if not _is_human_turn():
		return
	if _is_human_moving:
		return
	if event.is_action_pressed("target_next"):
		_cycle_target()
		return
	if event.is_action_pressed("action_end_turn"):
		_end_human_turn()
		return
	if event.is_action_pressed("move_up"):
		_try_move(Vector2i(0, -1))
		return
	if event.is_action_pressed("move_down"):
		_try_move(Vector2i(0, 1))
		return
	if event.is_action_pressed("move_left"):
		_try_move(Vector2i(-1, 0))
		return
	if event.is_action_pressed("move_right"):
		_try_move(Vector2i(1, 0))
		return
	if event.is_action_pressed("action_attack"):
		_try_attack()
		return
	if event.is_action_pressed("action_heal"):
		_try_heal()
		return

func _spawn_players() -> void:
	for i in range(spawn_positions.size()):
		if player_scene == null:
			return
		var player: PlayerUnit = player_scene.instantiate() as PlayerUnit
		player.player_id = i + 1
		player.set_axial_position(spawn_positions[i])
		player.position = terrain.axial_to_world(player.axial_position) + Vector3(0.0, 0.6, 0.0)
		if not turn_manager.register_player(player):
			player.queue_free()
			continue
		player_container.add_child(player)
		_players.append(player)
		_blocked_axials[player.axial_position] = true

func _spawn_props() -> void:
	if props_container == null:
		return
	var available: Array[Vector2i] = terrain.get_all_axials()
	available.shuffle()
	var placed: int = 0
	for axial in available:
		if _is_blocked(axial, null):
			continue
		if placed < tree_count:
			var tree: Node3D = _create_tree()
			_place_prop(tree, axial)
			_blocked_axials[axial] = true
			_prop_labels[axial] = "Tree"
			placed += 1
			continue
		if placed < tree_count + rock_count:
			var rock: Node3D = _create_rock()
			_place_prop(rock, axial)
			_blocked_axials[axial] = true
			_prop_labels[axial] = "Rock"
			placed += 1
			continue
		break

func _try_attack() -> void:
	var attacker: PlayerUnit = turn_manager.get_active_player()
	if attacker == null:
		return
	if not turn_manager.can_use_action(attacker):
		return
	var target: PlayerUnit = _current_target
	if target == null or not _is_adjacent(attacker, target):
		var targets: Array[PlayerUnit] = _get_adjacent_targets(attacker)
		if targets.is_empty():
			return
		target = targets[0]
		_set_target(target)
	_perform_attack(attacker, target)

func _try_move(direction: Vector2i) -> void:
	var player: PlayerUnit = turn_manager.get_active_player()
	if player == null:
		return
	if not turn_manager.can_move(player):
		return
	_attempt_move(player, direction)
	_clear_hover()

func _try_heal() -> void:
	var player: PlayerUnit = turn_manager.get_active_player()
	if player == null:
		return
	if not turn_manager.can_use_action(player):
		return
	_perform_heal(player)

func _end_human_turn() -> void:
	turn_manager.end_turn()
	_update_debug_label()
	_clear_hover()

func _find_adjacent_target(attacker: PlayerUnit) -> PlayerUnit:
	for player in _players:
		if player == attacker:
			continue
		if not player.is_alive():
			continue
		if terrain.axial_distance(attacker.axial_position, player.axial_position) == 1:
			return player
	return null

func _is_occupied(axial: Vector2i, exclude: PlayerUnit) -> bool:
	for player in _players:
		if player == exclude:
			continue
		if not player.is_alive():
			continue
		if player.axial_position == axial:
			return true
	return false

func _is_blocked(axial: Vector2i, exclude: PlayerUnit) -> bool:
	if _blocked_axials.has(axial):
		if exclude != null and exclude.axial_position == axial:
			return false
		return true
	return _is_occupied(axial, exclude)

func _on_active_player_changed(_player: PlayerUnit) -> void:
	_update_debug_label()
	if _player != null and not _is_human(_player):
		_run_ai_turn(_player)
	if _player != null and _is_human(_player):
		_auto_select_target(_player)
	if _player == null or not _is_human(_player):
		_clear_hover()

func _update_debug_label() -> void:
	if debug_label == null:
		return
	var active: PlayerUnit = turn_manager.get_active_player()
	var lines: Array[String] = []
	if active:
		lines.append("Active Player: P%s" % active.player_id)
		lines.append("Health: %s/%s" % [active.health, active.max_health])
		var action_text: String = "Ready" if turn_manager.action_available() else "Used"
		lines.append("Moves Left: %s | Action: %s" % [turn_manager.moves_left(), action_text])
		if _current_target != null:
			lines.append("Target: P%s (%s/%s)" % [_current_target.player_id, _current_target.health, _current_target.max_health])
		else:
			lines.append("Target: -")
	else:
		lines.append("Active Player: -")
	lines.append("Move: WASD | Actions: [J] Attack  [K] Heal")
	lines.append("Players: %s" % turn_manager.player_count())
	debug_label.text = "\n".join(lines)

func _update_combat_log() -> void:
	if log_label == null:
		return
	var lines: Array[String] = ["Combat Log:"]
	lines.append_array(_combat_log)
	log_label.text = "\n".join(lines)

func _update_controls_label() -> void:
	if controls_label == null:
		return
	var lines: Array[String] = []
	lines.append("Controls:")
	lines.append("WASD: Move")
	lines.append("J: Attack  K: Heal")
	lines.append("Tab: Cycle Target")
	lines.append("Space: End Turn")
	lines.append("LMB: Move")
	lines.append("RMB Drag: Pan")
	lines.append("Wheel: Zoom")
	controls_label.text = "\n".join(lines)

func _ensure_input_map() -> void:
	_ensure_action("move_up", KEY_W)
	_ensure_action("move_down", KEY_S)
	_ensure_action("move_left", KEY_A)
	_ensure_action("move_right", KEY_D)
	_ensure_action("action_attack", KEY_J)
	_ensure_action("action_heal", KEY_K)
	_ensure_action("target_next", KEY_TAB)
	_ensure_action("action_end_turn", KEY_SPACE)

func _ensure_action(action_name: String, keycode: Key) -> void:
	if not InputMap.has_action(action_name):
		InputMap.add_action(action_name)
	var events: Array[InputEvent] = InputMap.action_get_events(action_name)
	for event in events:
		if event is InputEventKey and event.keycode == keycode:
			return
	var key_event: InputEventKey = InputEventKey.new()
	key_event.keycode = keycode
	InputMap.action_add_event(action_name, key_event)

func _attempt_move(player: PlayerUnit, direction: Vector2i) -> bool:
	var from_world: Vector3 = player.global_position
	var target_axial: Vector2i = player.axial_position + direction
	if not terrain.is_within_bounds(target_axial):
		return false
	if _is_blocked(target_axial, player):
		return false
	if not turn_manager.consume_move():
		return false
	_blocked_axials.erase(player.axial_position)
	player.set_axial_position(target_axial)
	player.position = terrain.axial_to_world(target_axial) + Vector3(0.0, 0.6, 0.0)
	_blocked_axials[player.axial_position] = true
	player.play_run()
	var to_world: Vector3 = player.global_position
	var near_list: Array[String] = _get_adjacent_entity_names(player.axial_position, player)
	var near_text: String = "None" if near_list.is_empty() else ", ".join(near_list)
	_log_event("P%s moved %s -> %s. Near: [%s]" % [player.player_id, _format_world(from_world), _format_world(to_world), near_text])
	if _is_human(player):
		_auto_select_target(player)
	_update_debug_label()
	return true

func _perform_attack(attacker: PlayerUnit, target: PlayerUnit) -> void:
	attacker.play_attack()
	target.apply_damage(attacker.attack_damage)
	_log_event("P%s attacked P%s for %s. P%s HP: %s/%s" % [attacker.player_id, target.player_id, attacker.attack_damage, target.player_id, target.health, target.max_health])
	if not target.is_alive():
		_handle_death(target)
	turn_manager.end_turn()
	_update_debug_label()

func _perform_heal(player: PlayerUnit) -> void:
	var before: int = player.health
	player.heal_self()
	var delta: int = player.health - before
	_log_event("P%s healed %s. HP: %s/%s" % [player.player_id, delta, player.health, player.max_health])
	turn_manager.end_turn()
	_update_debug_label()

func _log_event(text: String) -> void:
	if text.is_empty():
		return
	_combat_log.append(text)
	while _combat_log.size() > MAX_LOG_LINES:
		_combat_log.pop_front()
	_update_combat_log()

func _is_human(player: PlayerUnit) -> bool:
	return player != null and player.player_id == 1

func _is_human_turn() -> bool:
	return _is_human(turn_manager.get_active_player())

func _is_adjacent(a: PlayerUnit, b: PlayerUnit) -> bool:
	if a == null or b == null:
		return false
	return terrain.axial_distance(a.axial_position, b.axial_position) == 1

func _get_adjacent_targets(player: PlayerUnit) -> Array[PlayerUnit]:
	var targets: Array[PlayerUnit] = []
	if player == null:
		return targets
	for other in _players:
		if other == player:
			continue
		if not other.is_alive():
			continue
		if terrain.axial_distance(player.axial_position, other.axial_position) == 1:
			targets.append(other)
	var sorter: Callable = Callable(self, "_sort_targets")
	targets.sort_custom(sorter)
	return targets

func _sort_targets(a: PlayerUnit, b: PlayerUnit) -> bool:
	if a.health == b.health:
		return a.player_id < b.player_id
	return a.health < b.health

func _auto_select_target(player: PlayerUnit) -> void:
	_adjacent_targets = _get_adjacent_targets(player)
	if _adjacent_targets.is_empty():
		_set_target(null)
		return
	_set_target(_adjacent_targets[0])

func _cycle_target() -> void:
	var active: PlayerUnit = turn_manager.get_active_player()
	if not _is_human(active):
		return
	_adjacent_targets = _get_adjacent_targets(active)
	if _adjacent_targets.is_empty():
		_set_target(null)
		return
	var index: int = _adjacent_targets.find(_current_target)
	if index == -1:
		_set_target(_adjacent_targets[0])
		return
	index = (index + 1) % _adjacent_targets.size()
	_set_target(_adjacent_targets[index])

func _set_target(target: PlayerUnit) -> void:
	if _current_target == target:
		return
	if _current_target != null:
		_current_target.set_targeted(false)
	_current_target = target
	if _current_target != null:
		_current_target.set_targeted(true)
	_update_debug_label()

func _get_adjacent_entity_names(origin: Vector2i, exclude: PlayerUnit) -> Array[String]:
	var names: Array[String] = []
	for other in _players:
		if other == exclude:
			continue
		if not other.is_alive():
			continue
		if terrain.axial_distance(origin, other.axial_position) == 1:
			names.append("P%s" % other.player_id)
	var keys: Array = _prop_labels.keys()
	for key in keys:
		var axial: Vector2i = key
		if terrain.axial_distance(origin, axial) == 1:
			var label: String = _prop_labels[axial]
			names.append(label)
	names.sort()
	return names

func _format_world(position: Vector3) -> String:
	return "(%.1f, %.1f, %.1f)" % [position.x, position.y, position.z]

func _run_ai_turn(player: PlayerUnit) -> void:
	await get_tree().create_timer(ai_action_delay).timeout
	if player != turn_manager.get_active_player():
		return
	if not player.is_alive():
		turn_manager.end_turn()
		return
	var moves_done: int = 0
	while moves_done < 2 and turn_manager.can_move(player):
		var moved: bool = _ai_try_move(player)
		if not moved:
			break
		moves_done += 1
		await get_tree().create_timer(ai_action_delay).timeout
		if player != turn_manager.get_active_player():
			return
	if player != turn_manager.get_active_player():
		return
	if turn_manager.can_use_action(player):
		await get_tree().create_timer(ai_action_delay).timeout
		if player != turn_manager.get_active_player():
			return
		_ai_take_action(player)

func _ai_try_move(player: PlayerUnit) -> bool:
	var directions: Array[Vector2i] = MOVE_DIRECTIONS.duplicate()
	directions.shuffle()
	for direction in directions:
		if _attempt_move(player, direction):
			return true
	return false

func _ai_take_action(player: PlayerUnit) -> void:
	var prefer_attack: bool = _rng.randi_range(0, 1) == 0
	var target: PlayerUnit = _find_adjacent_target(player)
	if prefer_attack and target != null:
		_perform_attack(player, target)
		return
	_perform_heal(player)

func _pan_camera(delta: Vector2) -> void:
	if camera == null:
		return
	var right: Vector3 = camera.global_transform.basis.x
	var forward: Vector3 = -camera.global_transform.basis.z
	right.y = 0.0
	forward.y = 0.0
	if right.length() > 0.0:
		right = right.normalized()
	if forward.length() > 0.0:
		forward = forward.normalized()
	var move: Vector3 = (right * -delta.x + forward * -delta.y) * camera_pan_speed
	camera.global_position += move

func _zoom_camera(delta: float) -> void:
	if camera == null:
		return
	var size: float = clamp(camera.size + delta, camera_zoom_min, camera_zoom_max)
	camera.size = size

func _create_hover_marker() -> void:
	var mesh: CylinderMesh = CylinderMesh.new()
	mesh.top_radius = terrain.tile_size * 0.95
	mesh.bottom_radius = terrain.tile_size * 0.95
	mesh.height = 0.06
	mesh.radial_segments = 6
	mesh.rings = 1
	_hover_marker = MeshInstance3D.new()
	_hover_marker.mesh = mesh
	_hover_marker.visible = false
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = Color(0.95, 0.8, 0.2, 0.35)
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_hover_marker.material_override = material
	add_child(_hover_marker)

func _update_hover_from_mouse(screen_pos: Vector2) -> void:
	if not _is_human_turn() or _is_human_moving:
		_clear_hover()
		return
	if camera == null:
		_clear_hover()
		return
	var player: PlayerUnit = turn_manager.get_active_player()
	if player == null:
		_clear_hover()
		return
	var origin: Vector3 = camera.project_ray_origin(screen_pos)
	var direction: Vector3 = camera.project_ray_normal(screen_pos)
	if abs(direction.y) < 0.0001:
		_clear_hover()
		return
	var t: float = -origin.y / direction.y
	if t < 0.0:
		_clear_hover()
		return
	var world: Vector3 = origin + direction * t
	var axial: Vector2i = terrain.world_to_axial(world)
	if not terrain.is_within_bounds(axial):
		_clear_hover()
		return
	var path: Array[Vector2i] = _compute_path(player, axial)
	if path.is_empty():
		_clear_hover()
		return
	_hover_axial = axial
	_hover_path = path
	_show_hover(axial)

func _show_hover(axial: Vector2i) -> void:
	if _hover_marker == null:
		return
	var base_position: Vector3 = terrain.axial_to_world(axial)
	_hover_marker.position = base_position + Vector3(0.0, 0.05, 0.0)
	_hover_marker.visible = true
	_hover_time = 0.0

func _clear_hover() -> void:
	_hover_path.clear()
	if _hover_marker != null:
		_hover_marker.visible = false

func _try_mouse_move() -> void:
	if not _is_human_turn() or _is_human_moving:
		return
	if _hover_path.is_empty():
		return
	var player: PlayerUnit = turn_manager.get_active_player()
	if player == null:
		return
	var path: Array[Vector2i] = _hover_path.duplicate()
	_clear_hover()
	_execute_mouse_path(player, path)

func _execute_mouse_path(player: PlayerUnit, path: Array[Vector2i]) -> void:
	_is_human_moving = true
	await _move_path_steps(player, path)
	_is_human_moving = false
	_update_debug_label()

func _move_path_steps(player: PlayerUnit, path: Array[Vector2i]) -> void:
	for step in path:
		if player != turn_manager.get_active_player():
			break
		if not turn_manager.can_move(player):
			break
		var moved: bool = await _move_step_animated(player, step)
		if not moved:
			break

func _move_step_animated(player: PlayerUnit, target_axial: Vector2i) -> bool:
	if not terrain.is_within_bounds(target_axial):
		return false
	if _is_blocked(target_axial, player):
		return false
	if not turn_manager.consume_move():
		return false
	var from_world: Vector3 = player.global_position
	_blocked_axials.erase(player.axial_position)
	player.set_axial_position(target_axial)
	_blocked_axials[player.axial_position] = true
	var target_world: Vector3 = terrain.axial_to_world(target_axial) + Vector3(0.0, 0.6, 0.0)
	player.play_run()
	var tween: Tween = create_tween()
	tween.tween_property(player, "position", target_world, 0.25).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	await tween.finished
	var near_list: Array[String] = _get_adjacent_entity_names(player.axial_position, player)
	var near_text: String = "None" if near_list.is_empty() else ", ".join(near_list)
	_log_event("P%s moved %s -> %s. Near: [%s]" % [player.player_id, _format_world(from_world), _format_world(target_world), near_text])
	if _is_human(player):
		_auto_select_target(player)
	_update_debug_label()
	return true

func _compute_path(player: PlayerUnit, target_axial: Vector2i) -> Array[Vector2i]:
	var path: Array[Vector2i] = []
	if player == null:
		return path
	if target_axial == player.axial_position:
		return path
	var moves_available: int = turn_manager.moves_left()
	if moves_available <= 0:
		return path
	var distance: int = terrain.axial_distance(player.axial_position, target_axial)
	if distance > 2 or distance > moves_available:
		return path
	if _is_blocked(target_axial, player):
		return path
	if distance == 1:
		path.append(target_axial)
		return path
	if moves_available < 2:
		return path
	var step: Vector2i = _choose_step_towards(player.axial_position, target_axial, player)
	if step == Vector2i.ZERO:
		return path
	path.append(step)
	path.append(target_axial)
	return path

func _choose_step_towards(start_axial: Vector2i, target_axial: Vector2i, player: PlayerUnit) -> Vector2i:
	var best_step: Vector2i = Vector2i.ZERO
	var best_score: float = -9999.0
	var start_world: Vector3 = terrain.axial_to_world(start_axial)
	var target_world: Vector3 = terrain.axial_to_world(target_axial)
	var target_dir: Vector3 = (target_world - start_world).normalized()
	for direction in [Vector2i(1, 0), Vector2i(1, -1), Vector2i(0, -1), Vector2i(-1, 0), Vector2i(-1, 1), Vector2i(0, 1)]:
		var candidate: Vector2i = start_axial + direction
		if not terrain.is_within_bounds(candidate):
			continue
		if _is_blocked(candidate, player):
			continue
		if terrain.axial_distance(candidate, target_axial) != 1:
			continue
		var candidate_world: Vector3 = terrain.axial_to_world(candidate)
		var candidate_dir: Vector3 = (candidate_world - start_world).normalized()
		var score: float = target_dir.dot(candidate_dir)
		if score > best_score:
			best_score = score
			best_step = candidate
	return best_step

func _process(delta: float) -> void:
	if _hover_marker != null and _hover_marker.visible:
		_hover_time += delta
		var pulse: float = sin(_hover_time * 6.0) * 0.05
		var base: Vector3 = terrain.axial_to_world(_hover_axial)
		_hover_marker.position = base + Vector3(0.0, 0.05 + pulse, 0.0)

func _create_tree() -> Node3D:
	var tree: Node3D = Node3D.new()
	var trunk_mesh: CylinderMesh = CylinderMesh.new()
	trunk_mesh.top_radius = 0.15
	trunk_mesh.bottom_radius = 0.2
	trunk_mesh.height = 1.0
	var trunk: MeshInstance3D = MeshInstance3D.new()
	trunk.mesh = trunk_mesh
	var trunk_material: StandardMaterial3D = StandardMaterial3D.new()
	trunk_material.albedo_color = Color(0.35, 0.22, 0.12)
	trunk.material_override = trunk_material
	trunk.position = Vector3(0, 0.5, 0)
	var trunk_top: MeshInstance3D = MeshInstance3D.new()
	var trunk_top_mesh: CylinderMesh = CylinderMesh.new()
	trunk_top_mesh.top_radius = 0.08
	trunk_top_mesh.bottom_radius = 0.15
	trunk_top_mesh.height = 0.5
	trunk_top.mesh = trunk_top_mesh
	trunk_top.material_override = trunk_material
	trunk_top.position = Vector3(0, 1.1, 0)
	var canopy_mesh: SphereMesh = SphereMesh.new()
	canopy_mesh.radius = 0.55
	var canopy: MeshInstance3D = MeshInstance3D.new()
	canopy.mesh = canopy_mesh
	var canopy_material: StandardMaterial3D = StandardMaterial3D.new()
	canopy_material.albedo_color = Color(0.15, 0.4, 0.2)
	canopy.material_override = canopy_material
	canopy.position = Vector3(0, 1.2, 0)
	var canopy_mid: MeshInstance3D = MeshInstance3D.new()
	var canopy_mid_mesh: SphereMesh = SphereMesh.new()
	canopy_mid_mesh.radius = 0.4
	canopy_mid.mesh = canopy_mid_mesh
	canopy_mid.material_override = canopy_material
	canopy_mid.position = Vector3(0.3, 1.1, 0.2)
	var branch_mesh: CapsuleMesh = CapsuleMesh.new()
	branch_mesh.radius = 0.05
	branch_mesh.height = 0.5
	var branch_l: MeshInstance3D = MeshInstance3D.new()
	branch_l.mesh = branch_mesh
	branch_l.material_override = trunk_material
	branch_l.position = Vector3(-0.35, 0.9, 0)
	branch_l.rotation_degrees = Vector3(0, 0, 45)
	var branch_r: MeshInstance3D = MeshInstance3D.new()
	branch_r.mesh = branch_mesh
	branch_r.material_override = trunk_material
	branch_r.position = Vector3(0.35, 0.95, 0.1)
	branch_r.rotation_degrees = Vector3(0, 0, -45)
	tree.add_child(trunk)
	tree.add_child(trunk_top)
	tree.add_child(branch_l)
	tree.add_child(branch_r)
	tree.add_child(canopy)
	tree.add_child(canopy_mid)
	return tree

func _create_rock() -> Node3D:
	var rock: Node3D = Node3D.new()
	var mesh: SphereMesh = SphereMesh.new()
	mesh.radius = 0.45
	var instance: MeshInstance3D = MeshInstance3D.new()
	instance.mesh = mesh
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = Color(0.35, 0.35, 0.38)
	instance.material_override = material
	instance.scale = Vector3(1.2, 0.8, 1.0)
	instance.position = Vector3(0, 0.2, 0)
	var shard_mesh: SphereMesh = SphereMesh.new()
	shard_mesh.radius = 0.25
	var shard_a: MeshInstance3D = MeshInstance3D.new()
	shard_a.mesh = shard_mesh
	shard_a.material_override = material
	shard_a.position = Vector3(0.35, 0.25, -0.1)
	var shard_b: MeshInstance3D = MeshInstance3D.new()
	shard_b.mesh = shard_mesh
	shard_b.material_override = material
	shard_b.position = Vector3(-0.25, 0.18, 0.25)
	shard_b.scale = Vector3(0.8, 0.6, 0.7)
	var flat_mesh: BoxMesh = BoxMesh.new()
	flat_mesh.size = Vector3(0.5, 0.2, 0.4)
	var flat: MeshInstance3D = MeshInstance3D.new()
	flat.mesh = flat_mesh
	flat.material_override = material
	flat.position = Vector3(0.0, 0.1, -0.35)
	flat.rotation_degrees = Vector3(10.0, 20.0, 0.0)
	rock.add_child(instance)
	rock.add_child(shard_a)
	rock.add_child(shard_b)
	rock.add_child(flat)
	return rock

func _place_prop(prop: Node3D, axial: Vector2i) -> void:
	if prop == null:
		return
	props_container.add_child(prop)
	prop.position = terrain.axial_to_world(axial)
	prop.rotation.y = deg_to_rad(_rng.randi_range(0, 359))
	var scale: float = _rng.randf_range(0.85, 1.15)
	prop.scale = Vector3.ONE * scale

func _handle_death(player: PlayerUnit) -> void:
	if player == null:
		return
	_log_event("P%s was defeated" % player.player_id)
	_spawn_death_effect(player.global_position)
	turn_manager.remove_player(player)
	_blocked_axials.erase(player.axial_position)
	if _current_target == player:
		_set_target(null)
	_players.erase(player)
	player.queue_free()

func _spawn_death_effect(position: Vector3) -> void:
	var particles: GPUParticles3D = GPUParticles3D.new()
	particles.one_shot = true
	particles.amount = 24
	particles.lifetime = 0.6
	particles.explosiveness = 0.9
	var process: ParticleProcessMaterial = ParticleProcessMaterial.new()
	process.gravity = Vector3(0.0, -6.0, 0.0)
	process.initial_velocity_min = 2.0
	process.initial_velocity_max = 5.0
	process.direction = Vector3(0.0, 1.0, 0.0)
	process.spread = 45.0
	process.color = Color(0.7, 0.0, 0.0, 1.0)
	particles.process_material = process
	particles.position = position + Vector3(0.0, 0.5, 0.0)
	add_child(particles)
	particles.emitting = true
	var decal: Decal = Decal.new()
	decal.extents = Vector3(0.6, 0.2, 0.6)
	decal.set_texture(Decal.TEXTURE_ALBEDO, _get_blood_decal_texture())
	decal.position = Vector3(position.x, 0.05, position.z)
	add_child(decal)
	var timer: SceneTreeTimer = get_tree().create_timer(1.0)
	timer.timeout.connect(_on_death_effect_timeout.bind(particles))

func _on_death_effect_timeout(particles: GPUParticles3D) -> void:
	if is_instance_valid(particles):
		particles.queue_free()

func _get_blood_decal_texture() -> Texture2D:
	if _blood_decal_texture != null:
		return _blood_decal_texture
	var size: int = 64
	var image: Image = Image.create(size, size, false, Image.FORMAT_RGBA8)
	image.fill(Color(0.0, 0.0, 0.0, 0.0))
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.randomize()
	var center: Vector2 = Vector2(size * 0.5, size * 0.5)
	var base_radius: float = size * 0.35
	for y in range(size):
		for x in range(size):
			var dx: float = float(x) - center.x
			var dy: float = float(y) - center.y
			var dist: float = sqrt(dx * dx + dy * dy)
			var jitter: float = rng.randf_range(-3.0, 3.0)
			var radius: float = base_radius + jitter
			if dist <= radius:
				var alpha: float = clamp(1.0 - dist / radius, 0.0, 1.0)
				alpha *= rng.randf_range(0.6, 1.0)
				image.set_pixel(x, y, Color(0.5, 0.0, 0.0, alpha))
	var texture: ImageTexture = ImageTexture.create_from_image(image)
	_blood_decal_texture = texture
	return _blood_decal_texture
