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
@export var use_networked_game: bool = false
@export var tree_count: int = 10
@export var rock_count: int = 8
@export var buffer_tree_count: int = 18
@export var buffer_rock_count: int = 12

@onready var terrain: HexTerrain = $HexTerrain
@onready var turn_manager: TurnManager = $TurnManager
@onready var lighting_rig = $LightingRig
@onready var player_container: Node3D = $PlayerContainer
@onready var props_container: Node3D = $Props
@onready var turn_label: Label = $UI/TopLeftPanel/MarginContainer/TurnLabel
@onready var combat_label: Label = $UI/TopRightPanel/MarginContainer/CombatLabel
@onready var movement_label: Label = $UI/BottomLeftPanel/MarginContainer/MovementLabel
@onready var system_label: Label = $UI/BottomRightPanel/MarginContainer/SystemLabel
@onready var system_panel: PanelContainer = $UI/BottomRightPanel
@onready var file_menu: MenuButton = $UI/MenuBar/MarginContainer/HBoxContainer/FileMenu
@onready var debug_menu: MenuButton = $UI/MenuBar/MarginContainer/HBoxContainer/DebugMenu
@onready var camera: Camera3D = $Camera3D
@onready var join_panel: PanelContainer = $UI/JoinPanel
@onready var join_button: Button = $UI/JoinPanel/MarginContainer/VBoxContainer/JoinButton
@onready var join_status: Label = $UI/JoinPanel/MarginContainer/VBoxContainer/JoinStatus
@onready var network_console_panel: PanelContainer = $UI/NetworkConsolePanel
@onready var network_console_label: Label = $UI/NetworkConsolePanel/MarginContainer/ConsoleLabel

var _players: Array[PlayerUnit] = []
var _combat_log: Array[String] = []
var _movement_log: Array[String] = []
var _turn_log: Array[String] = []
var _system_log: Array[String] = []
var _network_log: Array[String] = []
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _is_panning: bool = false
var _blocked_axials: Dictionary = {}
var _prop_labels: Dictionary = {}
var _network: Node
var _network_players_by_id: Dictionary = {}
var _network_props: Dictionary = {}
var _network_initialized: bool = false
var _network_active_turn_id: int = 0
var _network_user_id: int = 0
var _network_channel_id: int = 0
var _network_player_names: Dictionary = {}
var _use_networked_game: bool = false
var _join_attempted: bool = false
var _debug_console_visible: bool = false
var _current_target: PlayerUnit = null
var _adjacent_targets: Array[PlayerUnit] = []
var _blood_decal_texture: Texture2D
var _hover_marker: MeshInstance3D
var _hover_axial: Vector2i = Vector2i.ZERO
var _hover_path: Array[Vector2i] = []
var _hover_time: float = 0.0
var _is_human_moving: bool = false
var _sun_dragging: bool = false
var _sun_azimuth: float = 45.0
var _sun_elevation: float = 45.0
var _sun_marker: MeshInstance3D
var _camera_forward: Vector3 = Vector3.ZERO
var _camera_focus_distance: float = 0.0
var _tree_trunk_material: StandardMaterial3D
var _tree_leaf_material: StandardMaterial3D
var _rock_primary_material: StandardMaterial3D
var _rock_secondary_material: StandardMaterial3D

const BUFFER_PROP_MAX: int = 30
var _light_palette_index: int = 0
var _light_presets: Array = [
	[Color(1.0, 0.98, 0.95), Color(0.9, 0.95, 1.0)],
	[Color(0.95, 0.85, 0.75), Color(1.0, 0.8, 0.6)],
	[Color(0.75, 0.85, 1.0), Color(0.7, 0.9, 1.0)],
	[Color(0.85, 0.95, 0.9), Color(0.6, 0.8, 0.75)]
]

const MAX_LOG_LINES: int = 6
const NETWORK_LOG_LINES: int = 12
const MOVE_DIRECTIONS: Array[Vector2i] = [
	Vector2i(0, -1),
	Vector2i(0, 1),
	Vector2i(-1, 0),
	Vector2i(1, 0)
]
const HEX_DIRECTIONS: Array[Vector2i] = [
	Vector2i(1, 0),
	Vector2i(1, -1),
	Vector2i(0, -1),
	Vector2i(-1, 0),
	Vector2i(-1, 1),
	Vector2i(0, 1)
]
const LIGHT_INTENSITY_STEP: float = 0.1
const LIGHT_INTENSITY_MIN: float = 0.2
const LIGHT_INTENSITY_MAX: float = 3.0
const LIGHT_HEIGHT_STEP: float = 0.5
const LIGHT_HEIGHT_MIN: float = 2.0
const LIGHT_HEIGHT_MAX: float = 10.0
const SUN_DRAG_SENSITIVITY: float = 0.2
const SUN_AZIMUTH_MIN: float = -120.0
const SUN_AZIMUTH_MAX: float = 120.0
const SUN_ELEVATION_MIN: float = 12.0
const SUN_ELEVATION_MAX: float = 65.0
const SUN_MARKER_RADIUS: float = 14.0
const SUN_MARKER_SIZE: float = 0.6
const MENU_FILE_EXIT: int = 1
const MENU_DEBUG_STUB: int = 1
const NETWORK_GRID_SIZE: int = 64
const NETWORK_GRID_CENTER: int = 32

func _ready() -> void:
	_rng.randomize()
	_ensure_input_map()
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	_cache_camera_offset()
	_create_sun_marker()
	_init_sun_from_lighting()
	_setup_menus()
	_setup_debug_console()
	_setup_join_ui()
	_register_buffer_tiles()
	_use_networked_game = use_networked_game and get_node_or_null("/root/GameNetwork") != null
	if _use_networked_game:
		_start_network_join()
	else:
		_spawn_players()
		_spawn_props()
	turn_manager.active_player_changed.connect(_on_active_player_changed)
	if not _use_networked_game:
		turn_manager.start_turns()
		_focus_camera_on_player(_get_player_by_id(1))
	_update_turn_panel()
	_update_combat_panel()
	_update_movement_panel()
	_update_system_panel()
	_create_hover_marker()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_zoom_camera(-camera_zoom_step)
			return
		if event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_zoom_camera(camera_zoom_step)
			return
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed and event.shift_pressed:
				_sun_dragging = true
				_set_sun_marker_visible(true)
				_clear_hover()
				return
			if not event.pressed and _sun_dragging:
				_sun_dragging = false
				_set_sun_marker_visible(false)
				_log_system("Sun drag: %0.1f/%0.1f" % [_sun_azimuth, _sun_elevation])
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
	if event is InputEventMouseMotion and _sun_dragging:
		_update_sun_drag(event.relative)
		return
	if event is InputEventMouseMotion:
		_update_hover_from_mouse(event.position)
		return
	if event.is_action_pressed("light_dir_down"):
		_adjust_directional_intensity(-LIGHT_INTENSITY_STEP)
		return
	if event.is_action_pressed("light_dir_up"):
		_adjust_directional_intensity(LIGHT_INTENSITY_STEP)
		return
	if event.is_action_pressed("light_point_down"):
		_adjust_point_intensity(-LIGHT_INTENSITY_STEP)
		return
	if event.is_action_pressed("light_point_up"):
		_adjust_point_intensity(LIGHT_INTENSITY_STEP)
		return
	if event.is_action_pressed("light_point_lower"):
		_adjust_point_height(-LIGHT_HEIGHT_STEP)
		return
	if event.is_action_pressed("light_point_raise"):
		_adjust_point_height(LIGHT_HEIGHT_STEP)
		return
	if event.is_action_pressed("light_color_cycle"):
		_cycle_light_colors()
		return
	if _use_networked_game:
		_handle_network_input(event)
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
		var height: float = terrain.get_tile_height(player.axial_position)
		player.position = terrain.axial_to_world(player.axial_position, height) + Vector3(0.0, 0.6, 0.0)
		if not turn_manager.register_player(player):
			player.queue_free()
			continue
		player_container.add_child(player)
		_players.append(player)
		_blocked_axials[player.axial_position] = true

func _spawn_props() -> void:
	if props_container == null:
		return
	var available: Array[Vector2i] = terrain.get_play_axials()
	var interior: Array[Vector2i] = []
	var interior_radius: int = max(terrain.play_radius - 1, 1)
	for axial in available:
		if terrain.axial_distance(Vector2i.ZERO, axial) <= interior_radius:
			interior.append(axial)
	interior.shuffle()
	var counts: Dictionary = {"trees": 0, "rocks": 0}
	var total_props: int = tree_count + rock_count
	var cluster_sizes: Array[int] = _build_cluster_sizes(total_props)
	for cluster_size in cluster_sizes:
		if interior.is_empty():
			break
		var center: Vector2i = interior.pop_back()
		_place_prop_cluster(center, cluster_size, interior_radius, counts)
	_spawn_buffer_props()

func _spawn_buffer_props() -> void:
	if props_container == null:
		return
	var buffer_axials: Array[Vector2i] = terrain.get_buffer_axials()
	buffer_axials.shuffle()
	var placed_trees: int = 0
	var placed_rocks: int = 0
	var total_allowed: int = min(buffer_tree_count + buffer_rock_count, BUFFER_PROP_MAX)
	for axial in buffer_axials:
		if _prop_labels.has(axial):
			continue
		if placed_trees + placed_rocks >= total_allowed:
			break
		if placed_trees < buffer_tree_count and placed_rocks < buffer_rock_count:
			if _rng.randi_range(0, 1) == 0:
				_place_buffer_prop(_create_tree(), axial, "Tree")
				placed_trees += 1
			else:
				_place_buffer_prop(_create_rock(), axial, "Rock")
				placed_rocks += 1
			continue
		if placed_trees < buffer_tree_count:
			_place_buffer_prop(_create_tree(), axial, "Tree")
			placed_trees += 1
			continue
		if placed_rocks < buffer_rock_count:
			_place_buffer_prop(_create_rock(), axial, "Rock")
			placed_rocks += 1
		continue
		break

func _build_cluster_sizes(total: int) -> Array[int]:
	var sizes: Array[int] = []
	var remaining: int = total
	while remaining > 0:
		var size: int = 3 + _rng.randi_range(0, 2)
		if remaining < 3:
			size = remaining
		if size > remaining:
			size = remaining
		sizes.append(size)
		remaining -= size
	return sizes

func _place_prop_cluster(center: Vector2i, size: int, interior_radius: int, counts: Dictionary) -> void:
	var candidates: Array[Vector2i] = _get_cluster_candidates(center)
	candidates.shuffle()
	var placed: int = 0
	for axial in candidates:
		if placed >= size:
			break
		if terrain.axial_distance(Vector2i.ZERO, axial) > interior_radius:
			continue
		if _is_blocked(axial, null):
			continue
		if counts["trees"] >= tree_count and counts["rocks"] >= rock_count:
			break
		var place_tree: bool = false
		if counts["trees"] < tree_count and counts["rocks"] < rock_count:
			place_tree = _rng.randi_range(0, 1) == 0
		elif counts["trees"] < tree_count:
			place_tree = true
		else:
			place_tree = false
		if place_tree:
			var tree: Node3D = _create_tree()
			_place_prop(tree, axial, true)
			_prop_labels[axial] = "Tree"
			counts["trees"] += 1
		else:
			var rock: Node3D = _create_rock()
			_place_prop(rock, axial, true)
			_prop_labels[axial] = "Rock"
			counts["rocks"] += 1
		_blocked_axials[axial] = true
		placed += 1

func _get_cluster_candidates(center: Vector2i) -> Array[Vector2i]:
	var candidates: Array[Vector2i] = [center]
	for direction in HEX_DIRECTIONS:
		candidates.append(center + direction)
	return candidates

func _place_buffer_prop(prop: Node3D, axial: Vector2i, label: String) -> void:
	if prop == null:
		return
	_place_prop(prop, axial, true)
	_prop_labels[axial] = label

func _register_buffer_tiles() -> void:
	_blocked_axials.clear()
	if terrain == null:
		return
	for axial in terrain.get_buffer_axials():
		_blocked_axials[axial] = true

func _cache_camera_offset() -> void:
	if camera == null:
		return
	_camera_forward = -camera.global_transform.basis.z
	if _camera_forward.length() > 0.0:
		_camera_forward = _camera_forward.normalized()
	_camera_focus_distance = (camera.global_position - _get_island_center()).dot(_camera_forward)

func _get_island_center() -> Vector3:
	if terrain == null:
		return Vector3.ZERO
	return terrain.axial_to_world(Vector2i.ZERO)

func _focus_camera_on_player(player: PlayerUnit) -> void:
	if camera == null:
		return
	var focus: Vector3 = _get_island_center()
	if player != null:
		focus = terrain.axial_to_world(player.axial_position)
	if _camera_forward == Vector3.ZERO:
		_cache_camera_offset()
	camera.global_position = focus + _camera_forward * _camera_focus_distance

func _get_player_by_id(player_id: int) -> PlayerUnit:
	for player in _players:
		if player.player_id == player_id:
			return player
	return null

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
	_update_turn_panel()
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
	if _player != null:
		_log_turn("Active -> P%s" % _player.player_id)
	else:
		_log_turn("Active -> -")
	if _player != null and not _is_human(_player):
		_run_ai_turn(_player)
	if _player != null and _is_human(_player):
		_auto_select_target(_player)
	if _player == null or not _is_human(_player):
		_clear_hover()

func _update_turn_panel() -> void:
	if turn_label == null:
		return
	if _use_networked_game:
		var lines: Array[String] = ["Turn Carousel"]
		var ids: Array = _network_players_by_id.keys()
		ids.sort()
		if ids.is_empty():
			lines.append("Previous: -")
			lines.append("Current: -")
			lines.append("Next: -")
		else:
			var current_id: int = _network_active_turn_id
			if current_id <= 0 or not ids.has(current_id):
				current_id = ids[0]
			var index: int = ids.find(current_id)
			var prev_id: int = ids[(index - 1 + ids.size()) % ids.size()]
			var next_id: int = ids[(index + 1) % ids.size()]
			lines.append("Previous: %s" % _network_player_label(prev_id))
			lines.append("Current: %s" % _network_player_label(current_id))
			lines.append("Next: %s" % _network_player_label(next_id))
		lines.append("Players: %s" % _network_players_by_id.size())
		turn_label.text = "\n".join(lines)
		return
	var active: PlayerUnit = turn_manager.get_active_player()
	var lines: Array[String] = ["Turn & Status"]
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
	lines.append("Players: %s" % turn_manager.player_count())
	lines.append("")
	lines.append("Turn Log:")
	if _turn_log.is_empty():
		lines.append("No recent turns")
	else:
		lines.append_array(_turn_log)
	turn_label.text = "\n".join(lines)

func _update_combat_panel() -> void:
	if combat_label == null:
		return
	var lines: Array[String] = ["Combat Log:"]
	if _combat_log.is_empty():
		lines.append("No combat yet")
	else:
		lines.append_array(_combat_log)
	combat_label.text = "\n".join(lines)

func _update_movement_panel() -> void:
	if movement_label == null:
		return
	var lines: Array[String] = ["Movement Log:"]
	if _movement_log.is_empty():
		lines.append("No movement yet")
	else:
		lines.append_array(_movement_log)
	movement_label.text = "\n".join(lines)

func _update_system_panel() -> void:
	if system_label == null:
		return
	var lines: Array[String] = ["System & Lighting"]
	if lighting_rig != null:
		lines.append("Dir Intensity: %0.2f" % lighting_rig.directional_intensity)
		lines.append("Dir Rot: %s" % _format_vector3(lighting_rig.directional_rotation_degrees))
		lines.append("Dir Color: %s" % _format_color(lighting_rig.directional_color))
		lines.append("Point Intensity: %0.2f" % lighting_rig.point_intensity)
		lines.append("Point Pos: %s" % _format_vector3(lighting_rig.point_position))
		lines.append("Point Color: %s" % _format_color(lighting_rig.point_color))
		lines.append("Sun Azimuth: %0.1f  Elevation: %0.1f" % [_sun_azimuth, _sun_elevation])
	else:
		lines.append("Lighting: -")
	lines.append("")
	lines.append("System Log:")
	if _system_log.is_empty():
		lines.append("No system events")
	else:
		lines.append_array(_system_log)
	lines.append("")
	lines.append("Controls:")
	lines.append("WASD: Move")
	lines.append("J: Attack  K: Heal")
	lines.append("Tab: Cycle Target")
	lines.append("Space: End Turn")
	lines.append("LMB: Move")
	lines.append("RMB Drag: Pan")
	lines.append("Wheel: Zoom")
	lines.append("Z/X: Dir Intensity")
	lines.append("C/V: Point Intensity")
	lines.append("B/N: Point Height")
	lines.append("M: Cycle Colors")
	lines.append("Shift + LMB: Drag Sun")
	system_label.text = "\n".join(lines)

func _setup_menus() -> void:
	if file_menu != null:
		var file_popup: PopupMenu = file_menu.get_popup()
		file_popup.clear()
		file_popup.add_item("Exit", MENU_FILE_EXIT)
		var file_handler: Callable = Callable(self, "_on_file_menu_id_pressed")
		if not file_popup.id_pressed.is_connected(file_handler):
			file_popup.id_pressed.connect(file_handler)
	if debug_menu != null:
		var debug_popup: PopupMenu = debug_menu.get_popup()
		debug_popup.clear()
		debug_popup.add_item("Debug", MENU_DEBUG_STUB)
		var debug_handler: Callable = Callable(self, "_on_debug_menu_id_pressed")
		if not debug_popup.id_pressed.is_connected(debug_handler):
			debug_popup.id_pressed.connect(debug_handler)

func _on_file_menu_id_pressed(id: int) -> void:
	if id == MENU_FILE_EXIT:
		get_tree().quit()

func _on_debug_menu_id_pressed(id: int) -> void:
	if id == MENU_DEBUG_STUB:
		_toggle_network_console()

func _ensure_input_map() -> void:
	_ensure_action("move_up", KEY_W)
	_ensure_action("move_down", KEY_S)
	_ensure_action("move_left", KEY_A)
	_ensure_action("move_right", KEY_D)
	_ensure_action("action_attack", KEY_J)
	_ensure_action("action_heal", KEY_K)
	_ensure_action("target_next", KEY_TAB)
	_ensure_action("action_end_turn", KEY_SPACE)
	_ensure_action("light_dir_down", KEY_Z)
	_ensure_action("light_dir_up", KEY_X)
	_ensure_action("light_point_down", KEY_C)
	_ensure_action("light_point_up", KEY_V)
	_ensure_action("light_point_lower", KEY_B)
	_ensure_action("light_point_raise", KEY_N)
	_ensure_action("light_color_cycle", KEY_M)

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

func _setup_debug_console() -> void:
	if system_panel != null:
		system_panel.visible = false
	if network_console_panel == null:
		return
	network_console_panel.visible = false
	_update_network_console()

func _toggle_network_console() -> void:
	if network_console_panel == null:
		return
	_debug_console_visible = not _debug_console_visible
	network_console_panel.visible = _debug_console_visible
	if _debug_console_visible:
		_update_network_console()

func _log_network(text: String) -> void:
	_append_console_log(_network_log, text, NETWORK_LOG_LINES)
	_update_network_console()

func _append_console_log(log: Array[String], text: String, max_lines: int) -> void:
	if text.is_empty():
		return
	log.append(text)
	while log.size() > max_lines:
		log.pop_front()

func _update_network_console() -> void:
	if network_console_label == null:
		return
	var lines: Array[String] = []
	lines.append("Network Console")
	lines.append("URL: %s" % _network_base_url())
	lines.append("User: %s | Channel: %s" % [_network_user_id, _channel_id_label()])
	lines.append("Active Turn: %s" % _network_active_turn_id)
	lines.append("--- Connectivity ---")
	if _network_log.is_empty():
		lines.append("(no events)")
	else:
		lines.append_array(_network_log)
	lines.append("--- Game Status ---")
	if _system_log.is_empty():
		lines.append("(no status)")
	else:
		lines.append_array(_system_log)
	network_console_label.text = "\n".join(lines)

func _network_base_url() -> String:
	if _network == null:
		return "-"
	return _network.base_url

func _channel_id_label() -> String:
	return "-" if _network_channel_id <= 0 else str(_network_channel_id)

func _network_player_label(user_id: int) -> String:
	return str(user_id)

func _update_turn_markers() -> void:
	for player in _players:
		if player == null:
			continue
		player.set_is_current_turn(player.player_id == _network_active_turn_id)

func _setup_join_ui() -> void:
	if join_panel == null:
		return
	join_panel.visible = not use_networked_game
	join_status.text = "Offline"
	if not join_button.pressed.is_connected(_on_join_pressed):
		join_button.pressed.connect(_on_join_pressed)

func _on_join_pressed() -> void:
	_start_network_join(true)

func _start_network_join(force: bool = false) -> void:
	if _join_attempted and not force:
		return
	if get_node_or_null("/root/GameNetwork") == null:
		_set_join_status("GameNetwork missing")
		_log_network("Network: GameNetwork missing")
		return
	_join_attempted = true
	_use_networked_game = true
	_clear_network_state()
	join_panel.visible = true
	join_button.disabled = true
	_set_join_status("Connecting...")
	_log_network("Network: join requested")
	_setup_network()

func _set_join_status(text: String) -> void:
	if join_status == null:
		return
	join_status.text = text

func _setup_network() -> void:
	_network = get_node("/root/GameNetwork")
	if _network == null:
		_use_networked_game = false
		join_button.disabled = false
		_set_join_status("GameNetwork missing")
		_log_network("Network: GameNetwork missing")
		return
	_network_user_id = _network.user_id
	if not _network.snapshot_received.is_connected(_on_network_snapshot_received):
		_network.snapshot_received.connect(_on_network_snapshot_received)
	if not _network.update_received.is_connected(_on_network_update_received):
		_network.update_received.connect(_on_network_update_received)
	if not _network.error_received.is_connected(_on_network_error_received):
		_network.error_received.connect(_on_network_error_received)
	if _network.has_signal("status_received"):
		if not _network.status_received.is_connected(_on_network_status_received):
			_network.status_received.connect(_on_network_status_received)
	_network.connect_to_game()
	_log_network("Network: connecting to %s" % _network.base_url)

func _handle_network_input(event: InputEvent) -> void:
	if event.is_action_pressed("move_up"):
		_send_network_command("move up")
		return
	if event.is_action_pressed("move_down"):
		_send_network_command("move down")
		return
	if event.is_action_pressed("move_left"):
		_send_network_command("move left")
		return
	if event.is_action_pressed("move_right"):
		_send_network_command("move right")
		return
	if event.is_action_pressed("action_attack"):
		_send_network_command("attack")
		return
	if event.is_action_pressed("action_heal"):
		_send_network_command("heal")
		return

func _send_network_command(command: String) -> void:
	if _network == null:
		return
	if not _is_network_turn():
		_log_system("Not your turn")
		_log_network("Blocked: not your turn")
		return
	_network.send_command(command)
	_log_system("Sent: %s" % command)
	_log_network("Sent: %s" % command)

func _is_network_turn() -> bool:
	if _network_active_turn_id <= 0:
		return true
	if _network_user_id <= 0:
		return true
	return _network_active_turn_id == _network_user_id

func _on_network_snapshot_received(snapshot: Dictionary) -> void:
	if _network != null:
		_network_user_id = _network.user_id
		_network_channel_id = _network.channel_id
	_apply_network_snapshot(snapshot)
	var players: Variant = snapshot.get("players", [])
	var obstacles: Variant = snapshot.get("obstacles", [])
	var player_count: int = players.size() if typeof(players) == TYPE_ARRAY else 0
	var obstacle_count: int = obstacles.size() if typeof(obstacles) == TYPE_ARRAY else 0
	_log_network("Snapshot: players=%s obstacles=%s turn=%s" % [player_count, obstacle_count, _network_active_turn_id])
	join_button.disabled = false
	_set_join_status("Connected")
	join_panel.visible = false

func _on_network_update_received(_update: Dictionary) -> void:
	_update_turn_panel()

func _on_network_error_received(message: String) -> void:
	_log_system("Network error: %s" % message)
	_log_network("Error: %s" % message)
	join_button.disabled = false
	_set_join_status(message)

func _on_network_status_received(message: String) -> void:
	_log_network(message)

func _apply_network_snapshot(snapshot: Dictionary) -> void:
	if not _network_initialized:
		_clear_network_state()
		_network_initialized = true
	_network_active_turn_id = int(snapshot.get("active_turn_user_id", 0))
	var players: Variant = snapshot.get("players", [])
	if typeof(players) == TYPE_ARRAY:
		_sync_network_players(players)
	var obstacles: Variant = snapshot.get("obstacles", [])
	if typeof(obstacles) == TYPE_ARRAY:
		_sync_network_obstacles(obstacles)
	_update_turn_markers()
	var local_player: PlayerUnit = _get_network_player(_network_user_id)
	if local_player != null:
		_focus_camera_on_player(local_player)
	_update_turn_panel()

func _clear_network_state() -> void:
	for player in _players:
		if is_instance_valid(player):
			player.queue_free()
	_players.clear()
	_network_players_by_id.clear()
	_network_player_names.clear()
	if props_container != null:
		for child in props_container.get_children():
			child.queue_free()
	_network_props.clear()
	_prop_labels.clear()
	_blocked_axials.clear()
	_register_buffer_tiles()

func _sync_network_players(players: Array) -> void:
	var seen: Dictionary = {}
	for entry in players:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var user_id: int = int(entry.get("user_id", 0))
		if user_id <= 0:
			continue
		seen[user_id] = true
		var player: PlayerUnit = _get_network_player(user_id)
		if player == null:
			player = _spawn_network_player(user_id)
		if player == null:
			continue
		_apply_network_player_state(player, entry)
		var display_name: String = str(entry.get("display_name", ""))
		var username: String = str(entry.get("username", ""))
		var label: String = display_name if not display_name.is_empty() else username
		_network_player_names[user_id] = label if not label.is_empty() else "P%s" % user_id
	var keys: Array = _network_players_by_id.keys()
	for key in keys:
		if not seen.has(key):
			_remove_network_player(_network_players_by_id[key])

func _spawn_network_player(user_id: int) -> PlayerUnit:
	if player_scene == null:
		return null
	var player: PlayerUnit = player_scene.instantiate() as PlayerUnit
	player.player_id = user_id
	player_container.add_child(player)
	_players.append(player)
	_network_players_by_id[user_id] = player
	return player

func _get_network_player(user_id: int) -> PlayerUnit:
	if _network_players_by_id.has(user_id):
		return _network_players_by_id[user_id]
	return null

func _remove_network_player(player: PlayerUnit) -> void:
	if player == null:
		return
	_players.erase(player)
	_network_players_by_id.erase(player.player_id)
	_network_player_names.erase(player.player_id)
	if is_instance_valid(player):
		player.queue_free()

func _apply_network_player_state(player: PlayerUnit, entry: Dictionary) -> void:
	var position_x: int = int(entry.get("position_x", 0))
	var position_y: int = int(entry.get("position_y", 0))
	var health: int = int(entry.get("health", player.health))
	var max_health: int = int(entry.get("max_health", player.max_health))
	var is_npc: bool = bool(entry.get("is_npc", false))
	var axial: Vector2i = _grid_to_axial(position_x, position_y)
	player.set_axial_position(axial)
	var height: float = terrain.get_tile_height(axial)
	player.position = terrain.axial_to_world(axial, height) + Vector3(0.0, 0.6, 0.0)
	player.set_health(health, max_health)
	player.set_is_npc(is_npc)

func _sync_network_obstacles(obstacles: Array) -> void:
	var seen: Dictionary = {}
	for entry in obstacles:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var position_x: int = int(entry.get("x", 0))
		var position_y: int = int(entry.get("y", 0))
		var kind: String = str(entry.get("type", "stone"))
		var axial: Vector2i = _grid_to_axial(position_x, position_y)
		seen[axial] = true
		if not _network_props.has(axial):
			var prop: Node3D = _create_tree() if kind == "tree" else _create_rock()
			if prop == null:
				continue
			_place_prop(prop, axial, false)
			_network_props[axial] = prop
		_prop_labels[axial] = "Tree" if kind == "tree" else "Stone"
	var keys: Array = _network_props.keys()
	for key in keys:
		if not seen.has(key):
			var prop_node: Node3D = _network_props[key]
			if is_instance_valid(prop_node):
				prop_node.queue_free()
			_network_props.erase(key)
			_prop_labels.erase(key)
	_blocked_axials.clear()
	_register_buffer_tiles()
	for key in seen.keys():
		_blocked_axials[key] = true

func _grid_to_axial(x: int, y: int) -> Vector2i:
	if terrain == null:
		return Vector2i.ZERO
	var radius: int = max(terrain.play_radius, 1)
	var scale: float = float(radius) / float(max(NETWORK_GRID_CENTER, 1))
	var q: int = int(round((x - NETWORK_GRID_CENTER) * scale))
	var r: int = int(round((y - NETWORK_GRID_CENTER) * scale))
	q = clamp(q, -radius, radius)
	r = clamp(r, -radius, radius)
	return Vector2i(q, r)

func _adjust_directional_intensity(delta: float) -> void:
	if lighting_rig == null:
		return
	lighting_rig.directional_intensity = clamp(lighting_rig.directional_intensity + delta, LIGHT_INTENSITY_MIN, LIGHT_INTENSITY_MAX)
	lighting_rig.apply_lighting()
	_log_system("Dir intensity: %0.2f" % lighting_rig.directional_intensity)

func _adjust_point_intensity(delta: float) -> void:
	if lighting_rig == null:
		return
	lighting_rig.point_intensity = clamp(lighting_rig.point_intensity + delta, LIGHT_INTENSITY_MIN, LIGHT_INTENSITY_MAX)
	lighting_rig.apply_lighting()
	_log_system("Point intensity: %0.2f" % lighting_rig.point_intensity)

func _adjust_point_height(delta: float) -> void:
	if lighting_rig == null:
		return
	var position: Vector3 = lighting_rig.point_position
	position.y = clamp(position.y + delta, LIGHT_HEIGHT_MIN, LIGHT_HEIGHT_MAX)
	lighting_rig.point_position = position
	lighting_rig.apply_lighting()
	_log_system("Point height: %0.1f" % lighting_rig.point_position.y)

func _cycle_light_colors() -> void:
	if lighting_rig == null:
		return
	if _light_presets.is_empty():
		return
	_light_palette_index = (_light_palette_index + 1) % _light_presets.size()
	var preset: Array = _light_presets[_light_palette_index]
	if preset.size() < 2:
		return
	lighting_rig.directional_color = preset[0]
	lighting_rig.point_color = preset[1]
	lighting_rig.apply_lighting()
	_log_system("Lighting palette: %s" % (_light_palette_index + 1))

func _init_sun_from_lighting() -> void:
	if lighting_rig == null:
		return
	_sun_azimuth = clamp(lighting_rig.directional_rotation_degrees.y, SUN_AZIMUTH_MIN, SUN_AZIMUTH_MAX)
	var t: float = (_sun_azimuth - SUN_AZIMUTH_MIN) / (SUN_AZIMUTH_MAX - SUN_AZIMUTH_MIN)
	var arc: float = sin(t * PI)
	_sun_elevation = lerp(SUN_ELEVATION_MIN, SUN_ELEVATION_MAX, arc)
	_apply_sun_rotation()

func _update_sun_drag(delta: Vector2) -> void:
	_sun_azimuth = clamp(_sun_azimuth + delta.x * SUN_DRAG_SENSITIVITY, SUN_AZIMUTH_MIN, SUN_AZIMUTH_MAX)
	var t: float = (_sun_azimuth - SUN_AZIMUTH_MIN) / (SUN_AZIMUTH_MAX - SUN_AZIMUTH_MIN)
	var arc: float = sin(t * PI)
	_sun_elevation = lerp(SUN_ELEVATION_MIN, SUN_ELEVATION_MAX, arc)
	_apply_sun_rotation()

func _apply_sun_rotation() -> void:
	if lighting_rig == null:
		return
	lighting_rig.directional_rotation_degrees = Vector3(-_sun_elevation, _sun_azimuth, 0.0)
	lighting_rig.apply_lighting()
	_update_sun_marker()
	_update_system_panel()

func _create_sun_marker() -> void:
	var mesh: SphereMesh = SphereMesh.new()
	mesh.radius = SUN_MARKER_SIZE * 0.5
	mesh.height = SUN_MARKER_SIZE
	_sun_marker = MeshInstance3D.new()
	_sun_marker.mesh = mesh
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = Color(1.0, 0.88, 0.5)
	material.emission_enabled = true
	material.emission = Color(1.0, 0.85, 0.4)
	material.emission_energy = 2.0
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_sun_marker.material_override = material
	_sun_marker.visible = false
	add_child(_sun_marker)

func _set_sun_marker_visible(visible: bool) -> void:
	if _sun_marker == null:
		return
	_sun_marker.visible = visible
	if visible:
		_update_sun_marker()

func _update_sun_marker() -> void:
	if _sun_marker == null:
		return
	var direction: Vector3 = _get_sun_direction()
	_sun_marker.position = -direction * SUN_MARKER_RADIUS

func _get_sun_direction() -> Vector3:
	var euler: Vector3 = Vector3(deg_to_rad(-_sun_elevation), deg_to_rad(_sun_azimuth), 0.0)
	var basis: Basis = Basis.from_euler(euler)
	return -basis.z

func _attempt_move(player: PlayerUnit, direction: Vector2i) -> bool:
	var from_world: Vector3 = player.global_position
	var target_axial: Vector2i = player.axial_position + direction
	if not terrain.is_within_play_area(target_axial):
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
	_log_movement("P%s moved %s -> %s. Near: [%s]" % [player.player_id, _format_world(from_world), _format_world(to_world), near_text])
	if _is_human(player):
		_auto_select_target(player)
	_update_turn_panel()
	return true

func _perform_attack(attacker: PlayerUnit, target: PlayerUnit) -> void:
	attacker.play_attack()
	target.apply_damage(attacker.attack_damage)
	_log_combat("P%s attacked P%s for %s. P%s HP: %s/%s" % [attacker.player_id, target.player_id, attacker.attack_damage, target.player_id, target.health, target.max_health])
	if not target.is_alive():
		_handle_death(target)
	turn_manager.end_turn()
	_update_turn_panel()

func _perform_heal(player: PlayerUnit) -> void:
	var before: int = player.health
	player.heal_self()
	var delta: int = player.health - before
	_log_combat("P%s healed %s. HP: %s/%s" % [player.player_id, delta, player.health, player.max_health])
	turn_manager.end_turn()
	_update_turn_panel()

func _append_log(log: Array[String], text: String) -> void:
	if text.is_empty():
		return
	log.append(text)
	while log.size() > MAX_LOG_LINES:
		log.pop_front()

func _log_combat(text: String) -> void:
	_append_log(_combat_log, text)
	_update_combat_panel()

func _log_movement(text: String) -> void:
	_append_log(_movement_log, text)
	_update_movement_panel()

func _log_turn(text: String) -> void:
	_append_log(_turn_log, text)
	_update_turn_panel()

func _log_system(text: String) -> void:
	_append_log(_system_log, text)
	_update_system_panel()
	_update_network_console()

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
	_update_turn_panel()

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

func _format_vector3(value: Vector3) -> String:
	return "(%.1f, %.1f, %.1f)" % [value.x, value.y, value.z]

func _format_color(color: Color) -> String:
	return "(%.2f, %.2f, %.2f)" % [color.r, color.g, color.b]

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
	var move: Vector3 = (right * delta.x + forward * delta.y) * camera_pan_speed
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
	if _use_networked_game:
		_clear_hover()
		return
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
	if not terrain.is_within_play_area(axial):
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
	if _use_networked_game:
		return
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
	_update_turn_panel()

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
	if not terrain.is_within_play_area(target_axial):
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
	_log_movement("P%s moved %s -> %s. Near: [%s]" % [player.player_id, _format_world(from_world), _format_world(target_world), near_text])
	if _is_human(player):
		_auto_select_target(player)
	_update_turn_panel()
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
		if not terrain.is_within_play_area(candidate):
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
	var trunk_material: StandardMaterial3D = _get_tree_trunk_material()
	var leaf_material: StandardMaterial3D = _get_tree_leaf_material()
	var trunk_mesh: CylinderMesh = CylinderMesh.new()
	trunk_mesh.top_radius = 0.12
	trunk_mesh.bottom_radius = 0.18
	trunk_mesh.height = 1.0
	trunk_mesh.radial_segments = 6
	var trunk: MeshInstance3D = MeshInstance3D.new()
	trunk.mesh = trunk_mesh
	trunk.material_override = trunk_material
	trunk.position = Vector3(0, 0.5, 0)
	tree.add_child(trunk)
	var tier_count: int = 4 + _rng.randi_range(0, 3)
	for i in range(tier_count):
		var tier_mesh: CylinderMesh = CylinderMesh.new()
		var tier_height: float = 0.18 + float(i) * 0.02
		var tier_radius: float = 0.55 - float(i) * 0.07
		tier_mesh.height = tier_height
		tier_mesh.top_radius = tier_radius * 0.18
		tier_mesh.bottom_radius = tier_radius
		tier_mesh.radial_segments = 6
		var tier: MeshInstance3D = MeshInstance3D.new()
		tier.mesh = tier_mesh
		tier.material_override = leaf_material
		tier.position = Vector3(0.0, 0.9 + float(i) * 0.18, 0.0)
		tier.rotation.y = deg_to_rad(_rng.randi_range(0, 359))
		tree.add_child(tier)
	for i in range(2):
		var knot_mesh: CylinderMesh = CylinderMesh.new()
		knot_mesh.top_radius = 0.04
		knot_mesh.bottom_radius = 0.06
		knot_mesh.height = 0.12
		knot_mesh.radial_segments = 6
		var knot: MeshInstance3D = MeshInstance3D.new()
		knot.mesh = knot_mesh
		knot.material_override = trunk_material
		var angle: float = deg_to_rad(_rng.randi_range(0, 359))
		var radius: float = 0.16
		knot.position = Vector3(cos(angle) * radius, 0.4 + 0.2 * float(i), sin(angle) * radius)
		tree.add_child(knot)
	return tree

func _create_rock() -> Node3D:
	var rock: Node3D = Node3D.new()
	var primary: StandardMaterial3D = _get_rock_primary_material()
	var secondary: StandardMaterial3D = _get_rock_secondary_material()
	var shard_count: int = 2 + _rng.randi_range(0, 4)
	for i in range(shard_count):
		var shard_mesh: CylinderMesh = CylinderMesh.new()
		var height: float = 0.45 + _rng.randf_range(0.0, 0.45)
		var radius: float = 0.18 + _rng.randf_range(0.0, 0.12)
		shard_mesh.top_radius = radius * 0.1
		shard_mesh.bottom_radius = radius
		shard_mesh.height = height
		shard_mesh.radial_segments = 6
		var shard: MeshInstance3D = MeshInstance3D.new()
		shard.mesh = shard_mesh
		shard.material_override = secondary if _rng.randi_range(0, 4) == 0 else primary
		shard.position = Vector3(
			_rng.randf_range(-0.25, 0.25),
			height * 0.5,
			_rng.randf_range(-0.25, 0.25)
		)
		shard.rotation_degrees = Vector3(
			_rng.randf_range(-12.0, 12.0),
			_rng.randf_range(0.0, 360.0),
			_rng.randf_range(-12.0, 12.0)
		)
		rock.add_child(shard)
	return rock

func _get_tree_trunk_material() -> StandardMaterial3D:
	if _tree_trunk_material == null:
		_tree_trunk_material = StandardMaterial3D.new()
		_tree_trunk_material.albedo_color = Color(0.35, 0.22, 0.12)
	return _tree_trunk_material

func _get_tree_leaf_material() -> StandardMaterial3D:
	if _tree_leaf_material == null:
		_tree_leaf_material = StandardMaterial3D.new()
		_tree_leaf_material.albedo_color = Color(0.14, 0.36, 0.2)
	return _tree_leaf_material

func _get_rock_primary_material() -> StandardMaterial3D:
	if _rock_primary_material == null:
		_rock_primary_material = StandardMaterial3D.new()
		_rock_primary_material.albedo_color = Color(0.36, 0.33, 0.3)
		_rock_primary_material.roughness = 0.95
	return _rock_primary_material

func _get_rock_secondary_material() -> StandardMaterial3D:
	if _rock_secondary_material == null:
		_rock_secondary_material = StandardMaterial3D.new()
		_rock_secondary_material.albedo_color = Color(0.28, 0.25, 0.22)
		_rock_secondary_material.roughness = 0.98
	return _rock_secondary_material

func _place_prop(prop: Node3D, axial: Vector2i, randomize: bool) -> void:
	if prop == null:
		return
	props_container.add_child(prop)
	var height: float = terrain.get_tile_height(axial)
	prop.position = terrain.axial_to_world(axial, height)
	if randomize:
		prop.rotation.y = deg_to_rad(_rng.randi_range(0, 359))
		var scale: float = _rng.randf_range(0.85, 1.15)
		prop.scale = Vector3.ONE * scale
	else:
		prop.rotation = Vector3.ZERO
		prop.scale = Vector3.ONE

func _handle_death(player: PlayerUnit) -> void:
	if player == null:
		return
	_log_combat("P%s was defeated" % player.player_id)
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
