## Main game controller coordinating world, UI, camera, and network systems.
# class_name Game
extends Node3D

# --- Constants ---
const HEX_DIRECTIONS: Array[Vector2i] = [
	Vector2i(1, 0), Vector2i(1, -1), Vector2i(0, -1),
	Vector2i(-1, 0), Vector2i(-1, 1), Vector2i(0, 1)
]
const MOVE_DIRECTIONS: Array[Vector2i] = [
	Vector2i(0, -1), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(1, 0)
]
const FILE_MENU_RECONNECT: int = 1
const FILE_MENU_SHOW_JOIN: int = 2
const FILE_MENU_QUIT: int = 3
const DEBUG_MENU_TOGGLE_CONSOLE: int = 101
const BACKEND_GRID_MAX_INDEX: float = 63.0

# --- Exports ---
@export var player_scene: PackedScene = preload("res://scenes/PlayerUnit.tscn")
@export var spawn_positions: Array[Vector2i] = [
	Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)
]
@export var ai_action_delay: float = 0.5
@export var use_networked_game: bool = false
@export var tree_count: int = 10
@export var rock_count: int = 8

# --- Onready Nodes (Generic types to avoid parser issues) ---
@onready var terrain: Node3D = $HexTerrain
@onready var turn_manager: Node = $TurnManager
@onready var lighting_rig: Node3D = $LightingRig
@onready var player_container: Node3D = $PlayerContainer
@onready var props_container: Node3D = $Props
@onready var camera_node: Camera3D = $Camera3D

@onready var world: Node3D = $GameWorld
@onready var ui: Node = $GameUI
@onready var camera_mgr: Node = $GameCamera

# UI References
@onready var turn_label: Label = $UI/TopLeftPanel/MarginContainer/TurnLabel as Label
@onready var combat_label: Label = $UI/TopRightPanel/MarginContainer/CombatLabel as Label
@onready var movement_label: Label = $UI/BottomLeftPanel/MarginContainer/MovementLabel as Label
@onready var system_label: Label = $UI/BottomRightPanel/MarginContainer/SystemLabel as Label
@onready var join_panel: PanelContainer = $UI/JoinPanel as PanelContainer
@onready var join_status: Label = $UI/JoinPanel/MarginContainer/VBoxContainer/JoinStatus as Label
@onready var join_button: Button = $UI/JoinPanel/MarginContainer/VBoxContainer/JoinButton as Button
@onready var network_console_label: Label = $UI/NetworkConsolePanel/MarginContainer/ConsoleLabel as Label
@onready var network_console_panel: PanelContainer = $UI/NetworkConsolePanel as PanelContainer
@onready var file_menu: MenuButton = $UI/MenuBar/MarginContainer/HBoxContainer/FileMenu as MenuButton
@onready var debug_menu: MenuButton = $UI/MenuBar/MarginContainer/HBoxContainer/DebugMenu as MenuButton

# --- Private Variables ---
var _players: Array[Node3D] = []
var _current_target: Node3D = null
var _network: Node = null
var _network_active_turn_id: int = 0
var _network_players_by_id: Dictionary = {}
var _is_ws_connected: bool = false
var _online_human_count: int = 0
var _heartbeat_ok: bool = true
var _heartbeat_latency_ms: int = -1
var _heartbeat_missed_count: int = 0
var _join_status_message: String = "Offline"
var _is_panning: bool = false
var _is_human_moving: bool = false
var _use_networked_game: bool = false
var _hover_marker: MeshInstance3D
var _hover_axial: Vector2i = Vector2i.ZERO
var _hover_path: Array[Vector2i] = []
var _hover_time: float = 0.0

# --- Built-in Overrides ---

func _ready() -> void:
	_ensure_input_map()
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	_setup_components()
	_setup_network_state()
	
	if turn_manager and turn_manager.has_signal("active_player_changed"):
		turn_manager.connect("active_player_changed", _on_active_player_changed)
	
	if not _use_networked_game:
		_spawn_initial_players()
		if world:
			world.call("spawn_initial_props", tree_count, rock_count)
			world.call("spawn_buffer_props", 18, 12, 30)
		if turn_manager:
			turn_manager.call("start_turns")
		_focus_camera_on_player(_get_player_by_id(1))
	
	_create_hover_marker()
	_update_all_ui()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		_handle_mouse_button(event as InputEventMouseButton)
	elif event is InputEventMouseMotion:
		_handle_mouse_motion(event as InputEventMouseMotion)
	else:
		_handle_keyboard_input(event)

func _process(delta: float) -> void:
	if _hover_marker and _hover_marker.visible:
		_hover_time += delta
		var pulse: float = sin(_hover_time * 8.0) * 0.12
		var base: Vector3 = terrain.call("axial_to_world", _hover_axial)
		# Higher float (0.3) and stronger pulse
		_hover_marker.position = base + Vector3(0.0, 0.3 + pulse, 0.0)

# --- Private Methods ---

func _ensure_input_map() -> void:
	_ensure_action("move_up", KEY_W)
	_ensure_action("move_down", KEY_S)
	_ensure_action("move_left", KEY_A)
	_ensure_action("move_right", KEY_D)
	_ensure_action("action_attack", KEY_J)
	_ensure_action("action_heal", KEY_K)
	_ensure_action("target_next", KEY_TAB)
	_ensure_action("action_end_turn", KEY_SPACE)

func _ensure_action(action_name: String, keycode: int) -> void:
	if not InputMap.has_action(action_name):
		InputMap.add_action(action_name)
	var events := InputMap.action_get_events(action_name)
	var found := false
	for event: InputEvent in events:
		if event is InputEventKey and event.keycode == keycode:
			found = true
			break
	if not found:
		var key_event := InputEventKey.new()
		key_event.keycode = keycode
		InputMap.action_add_event(action_name, key_event)

func _setup_components() -> void:
	if world:
		world.call("setup", terrain, props_container)
	if camera_mgr:
		camera_mgr.call("setup", camera_node, terrain.call("axial_to_world", Vector2i.ZERO))
	
	# Assign UI references
	if ui:
		ui.set("turn_label", turn_label)
		ui.set("combat_label", combat_label)
		ui.set("movement_label", movement_label)
		ui.set("system_label", system_label)
		ui.set("join_status", join_status)
		ui.set("network_console_label", network_console_label)
	
	if join_button and not join_button.pressed.is_connected(_on_join_pressed):
		join_button.pressed.connect(_on_join_pressed)
	_setup_menu_buttons()

func _setup_menu_buttons() -> void:
	if file_menu:
		var file_popup: PopupMenu = file_menu.get_popup()
		file_popup.clear()
		file_popup.add_item("Reconnect", FILE_MENU_RECONNECT)
		file_popup.add_item("Show Join Panel", FILE_MENU_SHOW_JOIN)
		file_popup.add_separator()
		file_popup.add_item("Quit", FILE_MENU_QUIT)
		if not file_popup.id_pressed.is_connected(_on_file_menu_id_pressed):
			file_popup.id_pressed.connect(_on_file_menu_id_pressed)
	if debug_menu:
		var debug_popup: PopupMenu = debug_menu.get_popup()
		debug_popup.clear()
		debug_popup.add_item("Toggle Network Console", DEBUG_MENU_TOGGLE_CONSOLE)
		if not debug_popup.id_pressed.is_connected(_on_debug_menu_id_pressed):
			debug_popup.id_pressed.connect(_on_debug_menu_id_pressed)

func _setup_network_state() -> void:
	_use_networked_game = use_networked_game and get_node_or_null("/root/GameNetwork") != null
	if _use_networked_game:
		_network = get_node("/root/GameNetwork")
		_connect_network_signals()
		_attempt_network_connect()
		join_panel.visible = true
		network_console_panel.visible = true
		if _network.has_method("set_debug_heartbeat_enabled"):
			_network.call("set_debug_heartbeat_enabled", network_console_panel.visible)
		_update_presence_badge()
		if ui:
			ui.call("log_network", "Network mode enabled")
			var logger_node: Node = get_node_or_null("/root/GameLogger")
			if logger_node and logger_node.has_method("get_log_path"):
				ui.call("log_network", "Log file: %s" % logger_node.call("get_log_path"))
			ui.call("log_network", "Connecting to %s..." % _network.get("base_url"))
	elif ui:
		ui.call("log_network", "Network mode disabled")

func _connect_network_signals() -> void:
	if _network:
		_network.connect("snapshot_received", _on_network_snapshot_received)
		_network.connect("update_received", _on_network_update_received)
		_network.connect("error_received", _on_network_error_received)
		_network.connect("status_received", _on_network_status_received)
		if _network.has_signal("connection_state_changed"):
			_network.connect("connection_state_changed", _on_network_connection_state_changed)
		if _network.has_signal("heartbeat_status_changed"):
			_network.connect("heartbeat_status_changed", _on_heartbeat_status_changed)

func _spawn_initial_players() -> void:
	for i: int in range(spawn_positions.size()):
		var player: Node3D = player_scene.instantiate() as Node3D
		player.set("player_id", i + 1)
		player.call("set_axial_position", spawn_positions[i])
		var height: float = terrain.call("get_tile_height", spawn_positions[i])
		player.position = terrain.call("axial_to_world", spawn_positions[i], height) + Vector3(0.0, 0.6, 0.0)
		if turn_manager and turn_manager.call("register_player", player):
			player_container.add_child(player)
			_players.append(player)
			world.call("set_blocked", spawn_positions[i], true)
		else:
			player.queue_free()

func _handle_mouse_button(event: InputEventMouseButton) -> void:
	match event.button_index:
		MOUSE_BUTTON_WHEEL_UP:
			if camera_mgr: camera_mgr.call("zoom", -1.0)
		MOUSE_BUTTON_WHEEL_DOWN:
			if camera_mgr: camera_mgr.call("zoom", 1.0)
		MOUSE_BUTTON_RIGHT:
			_is_panning = event.pressed
		MOUSE_BUTTON_LEFT:
			if event.pressed:
				_try_mouse_move()

func _handle_mouse_motion(event: InputEventMouseMotion) -> void:
	if _is_panning:
		if camera_mgr: camera_mgr.call("pan", event.relative)
	else:
		_update_hover_from_mouse(event.position)

func _handle_keyboard_input(event: InputEvent) -> void:
	if _use_networked_game:
		_handle_network_input(event)
		return
		
	if not _is_human_turn() or _is_human_moving:
		return
		
	if event.is_action_pressed("move_up"): _try_move(Vector2i(0, -1))
	elif event.is_action_pressed("move_down"): _try_move(Vector2i(0, 1))
	elif event.is_action_pressed("move_left"): _try_move(Vector2i(-1, 0))
	elif event.is_action_pressed("move_right"): _try_move(Vector2i(1, 0))
	elif event.is_action_pressed("action_attack"): _try_attack()
	elif event.is_action_pressed("action_heal"): _try_heal()
	elif event.is_action_pressed("action_end_turn"): _end_human_turn()
	elif event.is_action_pressed("target_next"): _cycle_target()

func _try_move(direction: Vector2i) -> void:
	var player: Node3D = turn_manager.call("get_active_player") if turn_manager else null
	if player and turn_manager.call("can_move", player):
		_attempt_move(player, direction)
		_clear_hover()

func _attempt_move(player: Node3D, direction: Vector2i) -> bool:
	var axial_raw = player.get("axial_position")
	if typeof(axial_raw) != TYPE_VECTOR2I:
		_log_system("Move failed: P%s axial unset (%s)" % [player.get("player_id"), axial_raw])
		return false
	var axial_pos: Vector2i = axial_raw
	var target_axial: Vector2i = axial_pos + direction
	
	var in_play: bool = terrain.call("is_within_play_area", target_axial)
	var blocked: bool = world.call("is_blocked", target_axial, axial_pos)
	if not in_play or blocked:
		_log_system("Move blocked: target %s in_play=%s blocked=%s" % [target_axial, in_play, blocked])
		return false
	
	if not turn_manager.call("consume_move"):
		_log_system("Move failed: no moves left for P%s" % player.get("player_id"))
		return false
		
	world.call("set_blocked", axial_pos, false)
	player.call("set_axial_position", target_axial)
	player.position = terrain.call("axial_to_world", target_axial) + Vector3(0.0, 0.6, 0.0)
	world.call("set_blocked", target_axial, true)
	player.call("play_run")
	
	var near: Array = world.call("get_adjacent_entity_names", target_axial, _players, player)
	if ui:
		ui.call("log_movement", "P%d moved to %s. Near: %s" % [player.get("player_id"), target_axial, near])
		var moves_left: int = turn_manager.call("moves_left") if turn_manager else -1
		_log_system("Move ok: P%s -> %s (moves_left=%s)" % [player.get("player_id"), target_axial, moves_left])
	
	if _is_human(player):
		_auto_select_target(player)
	_update_all_ui()
	return true

func _try_attack() -> void:
	var attacker: Node3D = turn_manager.call("get_active_player") if turn_manager else null
	if not attacker or not turn_manager.call("can_use_action", attacker): return
	
	var target: Node3D = _current_target
	var attacker_axial: Vector2i = attacker.get("axial_position")
	if not target or (terrain.call("axial_distance", attacker_axial, target.get("axial_position")) as int) > 1:
		var targets: Array = _get_adjacent_targets(attacker)
		if targets.is_empty(): return
		target = targets[0] as Node3D
		_set_target(target)
		
	_perform_attack(attacker, target)

func _perform_attack(attacker: Node3D, target: Node3D) -> void:
	attacker.call("play_attack")
	target.call("apply_damage", attacker.get("attack_damage"))
	if ui: ui.call("log_combat", "P%d hit P%d for %d. HP: %d/%d" % [attacker.get("player_id"), target.get("player_id"), attacker.get("attack_damage"), target.get("health"), target.get("max_health")])
	
	if not target.call("is_alive"):
		_handle_death(target)
		
	if turn_manager: turn_manager.call("end_turn")
	_update_all_ui()

func _try_heal() -> void:
	var player: Node3D = turn_manager.call("get_active_player") if turn_manager else null
	if player and turn_manager.call("can_use_action", player):
		var before: int = player.get("health")
		player.call("heal_self")
		if ui: ui.call("log_combat", "P%d healed for %d. HP: %d/%d" % [player.get("player_id"), (player.get("health") as int) - before, player.get("health"), player.get("max_health")])
		if turn_manager: turn_manager.call("end_turn")
		_update_all_ui()

func _handle_death(player: Node3D) -> void:
	if ui: ui.call("log_combat", "P%d was defeated!" % player.get("player_id"))
	world.call("spawn_death_effect", player.global_position)
	if turn_manager: turn_manager.call("remove_player", player)
	world.call("set_blocked", player.get("axial_position"), false)
	if _current_target == player: _set_target(null)
	_players.erase(player)
	player.queue_free()

func _on_active_player_changed(player: Node3D) -> void:
	if player:
		if ui: ui.call("log_turn", "Active -> P%d" % player.get("player_id"))
		if not _is_human(player):
			_run_ai_turn(player)
		else:
			_auto_select_target(player)
	_clear_hover()
	_update_all_ui()

func _run_ai_turn(player: Node3D) -> void:
	await get_tree().create_timer(ai_action_delay).timeout
	if not turn_manager or turn_manager.call("get_active_player") != player: return
	
	var moves: int = 0
	while moves < 2 and turn_manager.call("can_move", player):
		var directions: Array[Vector2i] = MOVE_DIRECTIONS.duplicate()
		directions.shuffle()
		var moved: bool = false
		for d: Vector2i in directions:
			if _attempt_move(player, d):
				moved = true
				break
		if not moved: break
		moves += 1
		await get_tree().create_timer(ai_action_delay).timeout
		
	if turn_manager and turn_manager.call("get_active_player") == player and turn_manager.call("can_use_action", player):
		var target: Node3D = _find_adjacent_target(player)
		if target: _perform_attack(player, target)
		else: _try_heal()

# --- Network Handlers ---

func _on_join_pressed() -> void:
	_attempt_network_connect()

func _attempt_network_connect() -> void:
	if not _network:
		var network_singleton: Node = get_node_or_null("/root/GameNetwork")
		if network_singleton:
			_network = network_singleton
			_connect_network_signals()
			_use_networked_game = true
		else:
			if network_console_panel:
				network_console_panel.visible = true
			_set_join_status("GameNetwork autoload is missing")
			if ui:
				ui.call("log_network", "GameNetwork autoload is missing")
			return
	if join_button:
		join_button.disabled = true
	_set_join_status("Checking backend...")
	if network_console_panel:
		network_console_panel.visible = true
		if _network.has_method("set_debug_heartbeat_enabled"):
			_network.call("set_debug_heartbeat_enabled", true)
	if ui:
		ui.call("log_network", "Join requested")
	_network.call("connect_to_game")

func _on_file_menu_id_pressed(id: int) -> void:
	match id:
		FILE_MENU_RECONNECT:
			_attempt_network_connect()
		FILE_MENU_SHOW_JOIN:
			if join_panel:
				join_panel.visible = true
			if join_button:
				join_button.disabled = false
		FILE_MENU_QUIT:
			get_tree().quit()

func _on_debug_menu_id_pressed(id: int) -> void:
	if id == DEBUG_MENU_TOGGLE_CONSOLE and network_console_panel:
		network_console_panel.visible = not network_console_panel.visible
		if _network and _network.has_method("set_debug_heartbeat_enabled"):
			_network.call("set_debug_heartbeat_enabled", network_console_panel.visible)
		_update_all_ui()

func _handle_network_input(event: InputEvent) -> void:
	if not _is_network_turn() or not _network: return
	if event.is_action_pressed("move_up"): _network.call("send_command", "move up")
	elif event.is_action_pressed("move_down"): _network.call("send_command", "move down")
	elif event.is_action_pressed("move_left"): _network.call("send_command", "move left")
	elif event.is_action_pressed("move_right"): _network.call("send_command", "move right")
	elif event.is_action_pressed("action_attack"): _network.call("send_command", "attack")
	elif event.is_action_pressed("action_heal"): _network.call("send_command", "heal")

func _on_network_snapshot_received(snapshot: Dictionary) -> void:
	_network_active_turn_id = int(snapshot.get("active_turn_user_id", 0))
	_online_human_count = _count_human_players(snapshot.get("players", []) as Array)
	var battlefield_payload: Dictionary = {}
	var raw_battlefield: Variant = snapshot.get("battlefield", {})
	if typeof(raw_battlefield) == TYPE_DICTIONARY:
		battlefield_payload = raw_battlefield as Dictionary
	if ui:
		ui.call(
			"log_network",
			"Snapshot players=%s obstacles=%s props=%s active=%s" % [
				(snapshot.get("players", []) as Array).size(),
				(snapshot.get("obstacles", []) as Array).size(),
				(battlefield_payload.get("props", []) as Array).size(),
				_network_active_turn_id,
			],
		)
	if world:
		world.call("clear_state")
	if battlefield_payload.is_empty():
		_sync_network_obstacles(snapshot.get("obstacles", []) as Array)
	else:
		_sync_network_battlefield(battlefield_payload)
	_sync_network_players(snapshot.get("players", []) as Array, true)
	if join_panel: join_panel.visible = false
	if join_button: join_button.disabled = false
	_set_join_status("Joined #game")
	_update_presence_badge()
	_update_all_ui()


func _on_network_update_received(update: Dictionary) -> void:
	if update.has("active_turn_user_id"):
		_network_active_turn_id = int(update.get("active_turn_user_id", 0))
	_online_human_count = _count_human_players(update.get("players", []) as Array)
	if ui:
		ui.call(
			"log_network",
			"Update players=%s active=%s" % [
				(update.get("players", []) as Array).size(),
				_network_active_turn_id,
			],
		)
	_sync_network_players(update.get("players", []) as Array, false)
	_update_presence_badge()
	_update_all_ui()

func _on_network_connection_state_changed(is_connected: bool) -> void:
	_is_ws_connected = is_connected
	if not is_connected:
		_online_human_count = 0
		_heartbeat_ok = false
		_heartbeat_latency_ms = -1
		_heartbeat_missed_count = 0
	_update_presence_badge()
	_update_all_ui()

func _on_heartbeat_status_changed(ok: bool, latency_ms: int, missed_count: int) -> void:
	_heartbeat_ok = ok
	_heartbeat_latency_ms = latency_ms
	_heartbeat_missed_count = missed_count
	_update_all_ui()

func _on_network_error_received(msg: String) -> void:
	if ui: ui.call("log_network", "Error: %s" % msg)
	if join_button: join_button.disabled = false
	_set_join_status(msg)
	_update_all_ui()

func _on_network_status_received(msg: String) -> void:
	if ui: ui.call("log_network", msg)
	if join_panel and join_panel.visible:
		_set_join_status(msg)
	_update_all_ui()

func _count_human_players(players_data: Array) -> int:
	var count: int = 0
	for item: Variant in players_data:
		if typeof(item) != TYPE_DICTIONARY:
			continue
		var entry: Dictionary = item as Dictionary
		if bool(entry.get("is_npc", false)):
			continue
		count += 1
	return count

func _is_online_presence() -> bool:
	return _is_ws_connected and _online_human_count > 0

func _update_presence_badge() -> void:
	if debug_menu:
		debug_menu.text = "Debug [%s]" % ("ONLINE" if _is_online_presence() else "OFFLINE")
	_render_join_status()

func _set_join_status(message: String) -> void:
	_join_status_message = message
	_render_join_status()

func _render_join_status() -> void:
	if not join_status:
		return
	var heartbeat_text: String = "OK"
	if not _heartbeat_ok:
		heartbeat_text = "STALE (%s missed)" % _heartbeat_missed_count
	elif _heartbeat_latency_ms >= 0:
		heartbeat_text = "OK (%sms)" % _heartbeat_latency_ms
	join_status.text = "%s\nPresence: %s\nHeartbeat: %s" % [
		_join_status_message,
		"ONLINE" if _is_online_presence() else "OFFLINE",
		heartbeat_text,
	]

# --- Helper Methods ---

func _get_player_by_id(id: int) -> Node3D:
	for p: Node3D in _players:
		if (p.get("player_id") as int) == id: return p
	return null

func _is_human(player: Node3D) -> bool:
	return player != null and (player.get("player_id") as int) == 1

func _is_human_turn() -> bool:
	return _is_human(turn_manager.call("get_active_player") if turn_manager else null)

func _is_network_turn() -> bool:
	return _network != null and (_network_active_turn_id == 0 or _network_active_turn_id == (_network.get("user_id") as int))

func _get_adjacent_targets(player: Node3D) -> Array:
	var targets: Array = []
	var player_axial: Vector2i = player.get("axial_position")
	for p: Node3D in _players:
		if p != player and p.call("is_alive"):
			if (terrain.call("axial_distance", player_axial, p.get("axial_position")) as int) == 1:
				targets.append(p)
	targets.sort_custom(func(a: Node, b: Node) -> bool: return (a.get("health") as int) < (b.get("health") as int))
	return targets

func _find_adjacent_target(player: Node3D) -> Node3D:
	var targets: Array = _get_adjacent_targets(player)
	return targets[0] as Node3D if not targets.is_empty() else null

func _auto_select_target(player: Node3D) -> void:
	var targets: Array = _get_adjacent_targets(player)
	_set_target(targets[0] as Node3D if not targets.is_empty() else null)

func _set_target(target: Node3D) -> void:
	if _current_target: _current_target.call("set_targeted", false)
	_current_target = target
	if _current_target: _current_target.call("set_targeted", true)

func _cycle_target() -> void:
	var active: Node3D = turn_manager.call("get_active_player") if turn_manager else null
	if not _is_human(active): return
	var targets: Array = _get_adjacent_targets(active)
	if targets.is_empty():
		_set_target(null)
		return
	var idx: int = targets.find(_current_target)
	_set_target(targets[(idx + 1) % targets.size()] as Node3D)

func _end_human_turn() -> void:
	if turn_manager: turn_manager.call("end_turn")
	_update_all_ui()

func _update_all_ui() -> void:
	if _use_networked_game and _network:
		var ids: Array = _players.map(func(p: Node3D) -> int: return p.get("player_id") as int)
		ids.sort()
		if ui:
			ui.call("update_turn_panel_online", ids, _network_active_turn_id, _players.size())
			ui.call(
				"update_network_console",
				_network.get("base_url"),
				_network.get("user_id"),
				str(_network.get("channel_id")),
				_network_active_turn_id,
				_is_online_presence(),
				_online_human_count,
				_heartbeat_ok,
				_heartbeat_latency_ms,
				_heartbeat_missed_count
			)
	else:
		var active: Node3D = turn_manager.call("get_active_player") if turn_manager else null
		if ui: ui.call("update_turn_panel_offline", active, _current_target, _players.size())
	
	if ui: ui.call("update_system_panel", lighting_rig)
	
	var active_id: int = -1
	if _use_networked_game:
		active_id = _network_active_turn_id
	elif turn_manager:
		var active_player: Node3D = turn_manager.call("get_active_player")
		if active_player:
			active_id = active_player.get("player_id")
		
	for p: Node3D in _players:
		p.call("set_is_current_turn", (p.get("player_id") as int) == active_id)

func _log_system(text: String) -> void:
	if ui and not text.is_empty():
		ui.call("log_system", text)

# --- Hover & Mouse Move ---

func _create_hover_marker() -> void:
	var mesh: CylinderMesh = CylinderMesh.new()
	var t_size: float = terrain.get("tile_size") if terrain else 1.2
	mesh.top_radius = t_size * 0.95
	mesh.bottom_radius = t_size * 0.95
	mesh.height = 0.06
	mesh.radial_segments = 6
	_hover_marker = MeshInstance3D.new()
	_hover_marker.mesh = mesh
	_hover_marker.visible = false
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.albedo_color = Color(0.95, 0.8, 0.2, 0.35)
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_hover_marker.material_override = mat
	add_child(_hover_marker)

func _update_hover_from_mouse(screen_pos: Vector2) -> void:
	if _use_networked_game or not _is_human_turn() or _is_human_moving:
		_clear_hover()
		return
	if not camera_node:
		_clear_hover()
		return
	var origin: Vector3 = camera_node.project_ray_origin(screen_pos)
	var dir: Vector3 = camera_node.project_ray_normal(screen_pos)
	if abs(dir.y) < 0.0001: return
	var t: float = -origin.y / dir.y
	if t < 0: return
	var world_pos: Vector3 = origin + dir * t
	var axial: Vector2i = terrain.call("world_to_axial", world_pos)
	if not terrain.call("is_within_play_area", axial) or world.call("is_blocked", axial):
		_clear_hover()
		return
	_hover_axial = axial
	# Floating higher (0.3)
	_hover_marker.position = terrain.call("axial_to_world", axial) + Vector3(0, 0.3, 0)
	_hover_marker.visible = true

func _clear_hover() -> void:
	if _hover_marker: _hover_marker.visible = false

func _try_mouse_move() -> void:
	if _hover_marker and _hover_marker.visible:
		var player: Node3D = turn_manager.call("get_active_player") if turn_manager else null
		if not player: return
		var axial_pos: Vector2i = player.get("axial_position")
		var dist: int = terrain.call("axial_distance", axial_pos, _hover_axial)
		if dist == 1:
			_attempt_move(player, _hover_axial - axial_pos)

# --- Simplified Network Sync ---

func _sync_network_battlefield(battlefield: Dictionary) -> void:
	if world == null:
		return
	var rendered_props: int = 0
	var rendered_buffer: int = 0
	var seen_axials: Dictionary = {}

	var props_data: Array = battlefield.get("props", []) as Array
	for item: Variant in props_data:
		if typeof(item) != TYPE_DICTIONARY:
			continue
		var entry: Dictionary = item as Dictionary
		var backend_pos: Vector2i = Vector2i.ZERO
		if entry.has("position") and typeof(entry.get("position")) == TYPE_DICTIONARY:
			var position: Dictionary = entry.get("position") as Dictionary
			backend_pos = Vector2i(int(position.get("x", 0)), int(position.get("y", 0)))
		var axial: Vector2i = _map_backend_position_to_world_axial(backend_pos)
		if seen_axials.has(axial):
			continue
		seen_axials[axial] = true
		var prop_type: String = str(entry.get("type", "rock")).to_lower()
		if prop_type != "tree":
			prop_type = "rock"
		var is_blocking: bool = bool(entry.get("is_blocking", true))
		world.call("spawn_network_prop", prop_type, axial, is_blocking)
		rendered_props += 1

	var buffer_data: Dictionary = battlefield.get("buffer", {}) as Dictionary
	var buffer_tiles: Array = buffer_data.get("tiles", []) as Array
	for item: Variant in buffer_tiles:
		if typeof(item) != TYPE_DICTIONARY:
			continue
		var entry: Dictionary = item as Dictionary
		var backend_pos := Vector2i(int(entry.get("x", 0)), int(entry.get("y", 0)))
		var axial: Vector2i = _map_backend_position_to_world_axial(backend_pos)
		if seen_axials.has(axial):
			continue
		world.call("set_blocked", axial, true)
		seen_axials[axial] = true
		rendered_buffer += 1

	if ui:
		ui.call(
			"log_network",
			"Battlefield rendered props=%s buffer=%s" % [rendered_props, rendered_buffer],
		)

func _sync_network_players(data: Array, is_full_sync: bool) -> void:
	var seen_ids: Dictionary = {}
	for item: Variant in data:
		if typeof(item) != TYPE_DICTIONARY:
			continue
		var entry: Dictionary = item as Dictionary
		var user_id: int = int(entry.get("user_id", 0))
		if user_id <= 0:
			continue
		seen_ids[user_id] = true

		var player: Node3D = _network_players_by_id.get(user_id)
		var is_new_player: bool = false
		if player == null or not is_instance_valid(player):
			player = player_scene.instantiate() as Node3D
			player.set("player_id", user_id)
			player_container.add_child(player)
			_network_players_by_id[user_id] = player
			is_new_player = true

		var next_axial: Vector2i = _extract_axial_from_payload(entry)
		var previous_axial: Vector2i = player.get("axial_position") as Vector2i
		if world and not is_new_player and previous_axial != next_axial:
			world.call("set_blocked", previous_axial, false)

		player.call("set_axial_position", next_axial)
		player.position = terrain.call("axial_to_world", next_axial) + Vector3(0, 0.6, 0)
		player.call("set_health", int(entry.get("health", 10)), int(entry.get("max_health", 10)))
		if entry.has("is_npc"):
			player.call("set_is_npc", bool(entry.get("is_npc", false)))

		if world:
			world.call("set_blocked", next_axial, true)

	if is_full_sync:
		for key: Variant in _network_players_by_id.keys():
			var tracked_id: int = int(key)
			if seen_ids.has(tracked_id):
				continue
			var stale_player: Node3D = _network_players_by_id.get(tracked_id)
			if stale_player != null and is_instance_valid(stale_player):
				var stale_axial: Vector2i = stale_player.get("axial_position") as Vector2i
				if world:
					world.call("set_blocked", stale_axial, false)
				stale_player.queue_free()
			_network_players_by_id.erase(tracked_id)

	_players.clear()
	for value: Variant in _network_players_by_id.values():
		var current_player: Node3D = value as Node3D
		if current_player != null and is_instance_valid(current_player):
			_players.append(current_player)


func _extract_axial_from_payload(entry: Dictionary) -> Vector2i:
	var backend_position: Vector2i = Vector2i.ZERO
	var has_position_dict: bool = false
	if entry.has("position"):
		var raw_position: Variant = entry.get("position")
		if typeof(raw_position) == TYPE_DICTIONARY:
			var position: Dictionary = raw_position as Dictionary
			backend_position = Vector2i(int(position.get("x", 0)), int(position.get("y", 0)))
			has_position_dict = true
	if not has_position_dict:
		backend_position = Vector2i(int(entry.get("position_x", 0)), int(entry.get("position_y", 0)))
	return _map_backend_position_to_world_axial(backend_position)

func _map_backend_position_to_world_axial(backend_position: Vector2i) -> Vector2i:
	if terrain == null:
		return backend_position
	var radius: int = int(terrain.get("play_radius")) + int(terrain.get("buffer_thickness"))
	if radius <= 0:
		return Vector2i.ZERO
	var normalized_x: float = clampf(float(backend_position.x) / BACKEND_GRID_MAX_INDEX, 0.0, 1.0)
	var normalized_y: float = clampf(float(backend_position.y) / BACKEND_GRID_MAX_INDEX, 0.0, 1.0)
	var mapped: Vector2i = Vector2i(
		int(round(lerp(-float(radius), float(radius), normalized_x))),
		int(round(lerp(-float(radius), float(radius), normalized_y))),
	)
	if bool(terrain.call("is_within_bounds", mapped)):
		return mapped
	return _nearest_world_axial(mapped)

func _nearest_world_axial(axial: Vector2i) -> Vector2i:
	if terrain == null:
		return axial
	var world_axials: Array = terrain.call("get_all_axials")
	if world_axials.is_empty():
		return Vector2i.ZERO
	var best: Vector2i = world_axials[0] as Vector2i
	var best_distance: int = int(terrain.call("axial_distance", axial, best))
	for item: Variant in world_axials:
		if typeof(item) != TYPE_VECTOR2I:
			continue
		var candidate: Vector2i = item as Vector2i
		var distance: int = int(terrain.call("axial_distance", axial, candidate))
		if distance < best_distance:
			best = candidate
			best_distance = distance
	return best

func _sync_network_obstacles(data: Array) -> void:
	for item: Variant in data:
		if typeof(item) != TYPE_DICTIONARY:
			continue
		var entry: Dictionary = item as Dictionary
		var backend_position: Vector2i = Vector2i.ZERO
		if entry.has("position") and typeof(entry.get("position")) == TYPE_DICTIONARY:
			var position: Dictionary = entry.get("position") as Dictionary
			backend_position = Vector2i(int(position.get("x", 0)), int(position.get("y", 0)))
		else:
			backend_position = Vector2i(int(entry.get("x", 0)), int(entry.get("y", 0)))
		var axial: Vector2i = _map_backend_position_to_world_axial(backend_position)
		if world:
			world.call("set_blocked", axial, true)

func _focus_camera_on_player(p: Node3D) -> void:
	if p and camera_mgr: camera_mgr.call("focus_on_position", p.global_position)
