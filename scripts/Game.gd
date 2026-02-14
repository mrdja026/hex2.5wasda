## Main game controller coordinating world, UI, camera, and network systems.
class_name Game
extends Node3D

const HexTerrain = preload("res://scripts/hex_terrain.gd")
const TurnManager = preload("res://scripts/turn_manager.gd")
const LightingRig = preload("res://scripts/lighting_rig.gd")
const GameWorld = preload("res://scripts/game_world.gd")
const GameUI = preload("res://scripts/game_ui.gd")
const GameCamera = preload("res://scripts/game_camera.gd")
const PlayerUnit = preload("res://scripts/player_unit.gd")
const NetworkSync = preload("res://scripts/network_sync.gd")
const GameNetworkClient = preload("res://scripts/game_network.gd")
const NetworkProtocol = preload("res://scripts/network_protocol.gd")
const NetworkGameState = preload("res://scripts/network_game_state.gd")
const NetworkStateManager = preload("res://scripts/network_state_manager.gd")
const TargetManager = preload("res://scripts/target_manager.gd")

# --- Constants ---
const MOVE_DIRECTIONS: Array[Vector2i] = [
	Vector2i(0, -1), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(1, 0)
]
const FILE_MENU_RECONNECT: int = 1
const FILE_MENU_SHOW_JOIN: int = 2
const FILE_MENU_QUIT: int = 3
const DEBUG_MENU_TOGGLE_CONSOLE: int = 101
const ACTION_MOVE_UP: StringName = &"move_up"
const ACTION_MOVE_DOWN: StringName = &"move_down"
const ACTION_MOVE_LEFT: StringName = &"move_left"
const ACTION_MOVE_RIGHT: StringName = &"move_right"
const ACTION_MOVE_NW: StringName = &"move_nw"
const ACTION_MOVE_NE: StringName = &"move_ne"
const ACTION_MOVE_SW: StringName = &"move_sw"
const ACTION_MOVE_SE: StringName = &"move_se"
const ACTION_ATTACK: StringName = &"action_attack"
const ACTION_HEAL: StringName = &"action_heal"
const ACTION_END_TURN: StringName = &"action_end_turn"
const ACTION_TARGET_NEXT: StringName = &"target_next"

# --- Exports ---
@export var player_scene: PackedScene = preload("res://scenes/PlayerUnit.tscn")
@export var spawn_positions: Array[Vector2i] = [
	Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)
]
@export var ai_action_delay: float = 0.5
@export var use_networked_game: bool = false
@export var tree_count: int = 10
@export var rock_count: int = 8

# --- Onready Nodes ---
@onready var terrain: HexTerrain = $HexTerrain as HexTerrain
@onready var turn_manager: TurnManager = $TurnManager as TurnManager
@onready var lighting_rig: LightingRig = $LightingRig as LightingRig
@onready var player_container: Node3D = $PlayerContainer
@onready var props_container: Node3D = $Props
@onready var camera_node: Camera3D = $Camera3D
@onready var world: GameWorld = $GameWorld as GameWorld
@onready var ui: GameUI = $GameUI as GameUI
@onready var camera_mgr: GameCamera = $GameCamera as GameCamera

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
var _players: Array[PlayerUnit] = []
var _network: GameNetworkClient = null
var _network_sync: NetworkSync = null
var _network_state: NetworkGameState = NetworkGameState.new()
var _network_state_manager: NetworkStateManager = NetworkStateManager.new()
var _target_manager: TargetManager = TargetManager.new()
var _is_panning: bool = false
var _is_human_moving: bool = false
var _use_networked_game: bool = false
var _hover_marker: MeshInstance3D
var _hover_axial: Vector2i = Vector2i.ZERO
var _hover_time: float = 0.0

# --- Built-in Overrides ---

func _ready() -> void:
	_ensure_input_map()
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	_setup_components()
	_setup_network_state()
	
	if turn_manager and not turn_manager.active_player_changed.is_connected(_on_active_player_changed):
		turn_manager.active_player_changed.connect(_on_active_player_changed)
	
	if not _use_networked_game:
		if terrain:
			terrain.build()
		_spawn_initial_players()
		if world:
			world.spawn_initial_props(tree_count, rock_count)
		if turn_manager:
			turn_manager.start_turns()
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
		var base: Vector3 = terrain.axial_to_world(_hover_axial)
		_hover_marker.position = base + Vector3(0.0, 0.3 + pulse, 0.0)

# --- Setup ---

func _ensure_input_map() -> void:
	_ensure_action(String(ACTION_MOVE_UP), KEY_W)
	_ensure_action(String(ACTION_MOVE_DOWN), KEY_S)
	_ensure_action(String(ACTION_MOVE_LEFT), KEY_A)
	_ensure_action(String(ACTION_MOVE_RIGHT), KEY_D)
	_ensure_action(String(ACTION_MOVE_NW), KEY_Q)
	_ensure_action(String(ACTION_MOVE_NE), KEY_E)
	_ensure_action(String(ACTION_MOVE_SW), KEY_Z)
	_ensure_action(String(ACTION_MOVE_SE), KEY_C)
	_ensure_action(String(ACTION_ATTACK), KEY_J)
	_ensure_action(String(ACTION_HEAL), KEY_K)
	_ensure_action(String(ACTION_TARGET_NEXT), KEY_TAB)
	_ensure_action(String(ACTION_END_TURN), KEY_SPACE)

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
		world.setup(terrain, props_container)
	if camera_mgr:
		camera_mgr.setup(camera_node, terrain.axial_to_world(Vector2i.ZERO))
	if ui:
		ui.turn_label = turn_label
		ui.combat_label = combat_label
		ui.movement_label = movement_label
		ui.system_label = system_label
		ui.join_status = join_status
		ui.network_console_label = network_console_label
	_setup_network_sync()
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

func _setup_network_sync() -> void:
	_network_sync = get_node_or_null("NetworkSync") as NetworkSync
	if _network_sync == null:
		_network_sync = NetworkSync.new()
		_network_sync.name = "NetworkSync"
		add_child(_network_sync)
	_network_sync.setup(terrain, world, player_container, player_scene, ui)
	if not _network_sync.snapshot_applied.is_connected(_on_network_snapshot_applied):
		_network_sync.snapshot_applied.connect(_on_network_snapshot_applied)
	if not _network_sync.update_applied.is_connected(_on_network_update_applied):
		_network_sync.update_applied.connect(_on_network_update_applied)
	if not _network_sync.players_changed.is_connected(_on_network_players_changed):
		_network_sync.players_changed.connect(_on_network_players_changed)
	if not _network_sync.validation_error.is_connected(_on_network_sync_validation_error):
		_network_sync.validation_error.connect(_on_network_sync_validation_error)

func _setup_network_state() -> void:
	_use_networked_game = use_networked_game and (get_node_or_null("/root/GameNetwork") as GameNetworkClient) != null
	if _use_networked_game:
		_network = get_node_or_null("/root/GameNetwork") as GameNetworkClient
		_connect_network_signals()
		_attempt_network_connect()
		join_panel.visible = true
		network_console_panel.visible = true
		if _network:
			_network.set_debug_heartbeat_enabled(network_console_panel.visible)
		_update_presence_badge()
		if ui:
			ui.log_network("Network mode enabled")
			var logger_node: Node = get_node_or_null("/root/GameLogger")
			if logger_node and logger_node.has_method("get_log_path"):
				ui.log_network("Log file: %s" % logger_node.call("get_log_path"))
			if _network:
				ui.log_network("Connecting to %s..." % _network.base_url)
	elif ui:
		ui.log_network("Network mode disabled")

func _connect_network_signals() -> void:
	if _network == null:
		return
	if not _network.snapshot_received.is_connected(_on_network_snapshot_received):
		_network.snapshot_received.connect(_on_network_snapshot_received)
	if not _network.update_received.is_connected(_on_network_update_received):
		_network.update_received.connect(_on_network_update_received)
	if not _network.error_received.is_connected(_on_network_error_received):
		_network.error_received.connect(_on_network_error_received)
	if not _network.status_received.is_connected(_on_network_status_received):
		_network.status_received.connect(_on_network_status_received)
	if not _network.action_result_received.is_connected(_on_network_action_result_received):
		_network.action_result_received.connect(_on_network_action_result_received)
	if not _network.connection_state_changed.is_connected(_on_network_connection_state_changed):
		_network.connection_state_changed.connect(_on_network_connection_state_changed)
	if not _network.heartbeat_status_changed.is_connected(_on_heartbeat_status_changed):
		_network.heartbeat_status_changed.connect(_on_heartbeat_status_changed)

# --- Offline gameplay ---

func _spawn_initial_players() -> void:
	for i: int in range(spawn_positions.size()):
		var player: PlayerUnit = player_scene.instantiate() as PlayerUnit
		if player == null:
			continue
		player.player_id = i + 1
		player.set_axial_position(spawn_positions[i])
		var height: float = terrain.get_tile_height(spawn_positions[i])
		player.position = terrain.axial_to_world(spawn_positions[i], height) + Vector3(0.0, 0.6, 0.0)
		if turn_manager and turn_manager.register_player(player):
			player_container.add_child(player)
			_players.append(player)
			world.set_blocked(spawn_positions[i], true)
		else:
			player.queue_free()

func _handle_mouse_button(event: InputEventMouseButton) -> void:
	match event.button_index:
		MOUSE_BUTTON_WHEEL_UP:
			if camera_mgr: camera_mgr.zoom(-1.0)
		MOUSE_BUTTON_WHEEL_DOWN:
			if camera_mgr: camera_mgr.zoom(1.0)
		MOUSE_BUTTON_RIGHT:
			_is_panning = event.pressed
		MOUSE_BUTTON_LEFT:
			if event.pressed:
				_try_mouse_move()

func _handle_mouse_motion(event: InputEventMouseMotion) -> void:
	if _is_panning:
		if camera_mgr: camera_mgr.pan(event.relative)
	else:
		_update_hover_from_mouse(event.position)

func _handle_keyboard_input(event: InputEvent) -> void:
	if _use_networked_game:
		_handle_network_input(event)
		return
	if not _is_human_turn() or _is_human_moving:
		return
	if event.is_action_pressed(ACTION_MOVE_UP): _try_move(Vector2i(0, -1))
	elif event.is_action_pressed(ACTION_MOVE_DOWN): _try_move(Vector2i(0, 1))
	elif event.is_action_pressed(ACTION_MOVE_LEFT): _try_move(Vector2i(-1, 0))
	elif event.is_action_pressed(ACTION_MOVE_RIGHT): _try_move(Vector2i(1, 0))
	elif event.is_action_pressed(ACTION_ATTACK): _try_attack()
	elif event.is_action_pressed(ACTION_HEAL): _try_heal()
	elif event.is_action_pressed(ACTION_END_TURN): _end_human_turn()
	elif event.is_action_pressed(ACTION_TARGET_NEXT): _cycle_target()

func _try_move(direction: Vector2i) -> void:
	var player: PlayerUnit = null
	if turn_manager:
		player = turn_manager.get_active_player() as PlayerUnit
	if player and turn_manager.can_move(player):
		_attempt_move(player, direction)
		_clear_hover()

func _attempt_move(player: PlayerUnit, direction: Vector2i) -> bool:
	if player == null:
		return false
	var axial_pos: Vector2i = player.axial_position
	var target_axial: Vector2i = axial_pos + direction
	var in_play: bool = terrain.is_within_play_area(target_axial)
	var blocked: bool = world.is_blocked(target_axial, axial_pos)
	if not in_play or blocked:
		_log_system("Move blocked: target %s in_play=%s blocked=%s" % [target_axial, in_play, blocked])
		return false
	if not turn_manager.consume_move():
		_log_system("Move failed: no moves left for P%s" % player.player_id)
		return false
	world.set_blocked(axial_pos, false)
	player.set_axial_position(target_axial)
	player.position = terrain.axial_to_world(target_axial) + Vector3(0.0, 0.6, 0.0)
	world.set_blocked(target_axial, true)
	player.play_run()
	var mover_name: String = _player_log_name(player)
	var surroundings: String = _format_player_surroundings(player)
	if ui:
		ui.log_movement("%s - to {%s}" % [mover_name, surroundings])
		_log_system("Move ok: P%s -> %s (moves_left=%s)" % [player.player_id, target_axial, turn_manager.moves_left()])
	if _use_networked_game:
		if _network and player.player_id == _network.user_id:
			_auto_select_target(player)
	elif _is_human(player):
		_auto_select_target(player)
	_update_all_ui()
	return true

func _try_attack() -> void:
	var attacker: PlayerUnit = null
	if turn_manager:
		attacker = turn_manager.get_active_player() as PlayerUnit
	if attacker == null or not turn_manager.can_use_action(attacker):
		return
	var target: PlayerUnit = _get_current_target()
	var attacker_axial: Vector2i = attacker.axial_position
	if target == null or terrain.axial_distance(attacker_axial, target.axial_position) > 1:
		var targets: Array[PlayerUnit] = _get_adjacent_targets(attacker)
		if targets.is_empty():
			return
		target = targets[0]
		_set_target(target)
	_perform_attack(attacker, target)

func _perform_attack(attacker: PlayerUnit, target: PlayerUnit) -> void:
	attacker.play_attack()
	target.apply_damage(attacker.attack_damage)
	if ui:
		ui.log_combat("%s attacked %s -> %d/%d" % [_player_log_name(attacker), _player_log_name(target), target.health, target.max_health])
	if not target.is_alive():
		_handle_death(target)
	if turn_manager:
		turn_manager.end_turn()
	_update_all_ui()

func _try_heal() -> void:
	var player: PlayerUnit = null
	if turn_manager:
		player = turn_manager.get_active_player() as PlayerUnit
	if player and turn_manager.can_use_action(player):
		player.heal_self()
		if ui:
			var player_name: String = _player_log_name(player)
			ui.log_combat("%s healed %s -> %d/%d" % [player_name, player_name, player.health, player.max_health])
		if turn_manager:
			turn_manager.end_turn()
		_update_all_ui()

func _handle_death(player: PlayerUnit) -> void:
	if ui:
		ui.log_combat("%s was defeated!" % _player_log_name(player))
	world.spawn_death_effect(player.global_position)
	if turn_manager:
		turn_manager.remove_player(player)
	world.set_blocked(player.axial_position, false)
	if _get_current_target() == player:
		_set_target(null)
	_players.erase(player)
	player.queue_free()

func _on_active_player_changed(player: Node) -> void:
	var active: PlayerUnit = player as PlayerUnit
	if active:
		if ui:
			ui.log_turn("Active -> %s" % _player_log_name(active))
		if not _is_human(active):
			_run_ai_turn(active)
		else:
			_auto_select_target(active)
	_clear_hover()
	_update_all_ui()

func _run_ai_turn(player: PlayerUnit) -> void:
	await get_tree().create_timer(ai_action_delay).timeout
	if not turn_manager or (turn_manager.get_active_player() as PlayerUnit) != player:
		return
	var moves: int = 0
	while moves < 2 and turn_manager.can_move(player):
		var directions: Array[Vector2i] = MOVE_DIRECTIONS.duplicate()
		directions.shuffle()
		var moved: bool = false
		for d: Vector2i in directions:
			if _attempt_move(player, d):
				moved = true
				break
		if not moved:
			break
		moves += 1
		await get_tree().create_timer(ai_action_delay).timeout
	if turn_manager and (turn_manager.get_active_player() as PlayerUnit) == player and turn_manager.can_use_action(player):
		var target: PlayerUnit = _find_adjacent_target(player)
		if target:
			_perform_attack(player, target)
		else:
			_try_heal()

# --- Network ---

func _on_join_pressed() -> void:
	_attempt_network_connect()

func _attempt_network_connect() -> void:
	if _network == null:
		var network_singleton: GameNetworkClient = get_node_or_null("/root/GameNetwork") as GameNetworkClient
		if network_singleton:
			_network = network_singleton
			_connect_network_signals()
			_use_networked_game = true
		else:
			network_console_panel.visible = true
			_set_join_status("GameNetwork autoload is missing")
			if ui:
				ui.log_network("GameNetwork autoload is missing")
			return
	if join_button:
		join_button.disabled = true
	_set_join_status("Checking backend...")
	if network_console_panel:
		network_console_panel.visible = true
	if _network:
		_network.set_debug_heartbeat_enabled(true)
		_network.connect_to_game()
	if ui:
		ui.log_network("Join requested")

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
		if _network:
			_network.set_debug_heartbeat_enabled(network_console_panel.visible)
		_update_all_ui()

func _handle_network_input(event: InputEvent) -> void:
	if not _is_network_turn() or _network == null:
		return
	if event.is_action_pressed(ACTION_MOVE_UP):
		_network.send_command(String(NetworkProtocol.CMD_MOVE_N))
	elif event.is_action_pressed(ACTION_MOVE_DOWN):
		_network.send_command(String(NetworkProtocol.CMD_MOVE_S))
	elif event.is_action_pressed(ACTION_MOVE_LEFT):
		_network.send_command(String(NetworkProtocol.CMD_MOVE_SW))
	elif event.is_action_pressed(ACTION_MOVE_RIGHT):
		_network.send_command(String(NetworkProtocol.CMD_MOVE_SE))
	elif event.is_action_pressed(ACTION_MOVE_NW):
		_network.send_command(String(NetworkProtocol.CMD_MOVE_NW))
	elif event.is_action_pressed(ACTION_MOVE_NE):
		_network.send_command(String(NetworkProtocol.CMD_MOVE_NE))
	elif event.is_action_pressed(ACTION_MOVE_SW):
		_network.send_command(String(NetworkProtocol.CMD_MOVE_SW))
	elif event.is_action_pressed(ACTION_MOVE_SE):
		_network.send_command(String(NetworkProtocol.CMD_MOVE_SE))
	elif event.is_action_pressed(ACTION_ATTACK):
		var target_player: PlayerUnit = _get_current_target()
		if not _is_network_target_attackable(target_player):
			var attackable_targets: Array[PlayerUnit] = _get_network_attackable_targets()
			target_player = attackable_targets[0] if not attackable_targets.is_empty() else null
			_set_target(target_player)
		if target_player == null:
			if ui:
				ui.log_network("Attack blocked: no authoritative target in 1-hex range")
			return
		var target_username: String = ""
		if target_player.has_method("get"):
			var uname = target_player.get("backend_username")
			if typeof(uname) == TYPE_STRING and not (uname as String).is_empty():
				target_username = uname as String
		if target_username.is_empty():
			if ui:
				ui.log_network("Attack blocked: target username unavailable")
			return
		_network.send_command(String(NetworkProtocol.CMD_ATTACK), target_username)
	elif event.is_action_pressed(ACTION_HEAL):
		_network.send_command(String(NetworkProtocol.CMD_HEAL))
	elif event.is_action_pressed(ACTION_END_TURN):
		_network.send_command(String(NetworkProtocol.CMD_END_TURN))
	elif event.is_action_pressed(ACTION_TARGET_NEXT):
		_cycle_target()

func _on_network_snapshot_received(snapshot: Dictionary) -> void:
	_network_state_manager.apply_snapshot_metadata(_network_state, snapshot)
	_apply_backend_status_history(snapshot)
	_apply_network_turn_context(snapshot)
	var battlefield_payload: Dictionary = _dictionary_or_empty(snapshot.get(NetworkProtocol.KEY_BATTLEFIELD))
	var players_payload: Array = _array_or_empty(snapshot.get(NetworkProtocol.KEY_PLAYERS))
	var obstacles_payload: Array = _array_or_empty(snapshot.get(NetworkProtocol.KEY_OBSTACLES))
	var props_payload: Array = _array_or_empty(battlefield_payload.get(NetworkProtocol.KEY_PROPS))
	if ui:
		ui.log_network(
			"Snapshot players=%s obstacles=%s props=%s" % [
				players_payload.size(),
				obstacles_payload.size(),
				props_payload.size(),
			]
		)
	if _network_sync:
		_network_sync.handle_snapshot(snapshot)

func _on_network_update_received(update: Dictionary) -> void:
	_network_state_manager.apply_update_metadata(_network_state, update)
	_apply_backend_status_history(update)
	_apply_network_turn_context(update)
	var players_payload: Array = _array_or_empty(update.get(NetworkProtocol.KEY_PLAYERS))
	if ui:
		ui.log_network(
			"Update players=%s active=%s" % [
				players_payload.size(),
				int(update.get(NetworkProtocol.KEY_ACTIVE_TURN_USER_ID, _network_state.active_turn_user_id)),
			]
		)
	if _network_sync:
		_network_sync.handle_update(update)

func _on_network_snapshot_applied(active_turn_user_id: int) -> void:
	_network_state_manager.apply_snapshot_applied(_network_state, active_turn_user_id)
	_flush_pending_network_actions()
	if _network:
		_focus_camera_on_player(_get_player_by_id(_network.user_id))
	if join_panel:
		join_panel.visible = false
	if join_button:
		join_button.disabled = false
	_set_join_status("Joined #game")
	_update_presence_badge()
	_update_all_ui()

func _on_network_update_applied(active_turn_user_id: int) -> void:
	_network_state_manager.apply_update_applied(_network_state, active_turn_user_id)
	_flush_pending_network_actions()
	if _network:
		_focus_camera_on_player(_get_player_by_id(_network.user_id))
	_update_presence_badge()
	_update_all_ui()

func _on_network_players_changed(players: Array[Node3D]) -> void:
	_players.clear()
	for node: Node3D in players:
		var player: PlayerUnit = node as PlayerUnit
		if player:
			_players.append(player)
	_target_manager.refresh_target_visual(_players)

func _on_network_sync_validation_error(message: String) -> void:
	# TODO(backend P2): lazy collision validation/adjacency checks should be authoritative server-side.
	# TODO(backend P3): static obstacle layer should be provided in a canonical map payload.
	# TODO(backend P6): backend should auto-kick stale/invalid sessions from channels.
	# TODO(backend P7): backend should document/cache invalidation semantics for battlefield snapshots.
	if ui:
		ui.log_network("ERROR: %s" % message)
	_set_join_status("Sync error - check backend payload")
	if join_button:
		join_button.disabled = false
	_update_all_ui()

func _on_network_connection_state_changed(is_connected: bool) -> void:
	_network_state_manager.apply_connection_state(_network_state, is_connected)
	if not is_connected:
		_set_target(null)
	_update_presence_badge()
	_update_all_ui()

func _on_heartbeat_status_changed(ok: bool, latency_ms: int, missed_count: int) -> void:
	_network_state_manager.apply_heartbeat(_network_state, ok, latency_ms, missed_count)
	_update_all_ui()

func _on_network_error_received(msg: String) -> void:
	if ui:
		ui.log_network("Error: %s" % msg)
	if join_button:
		join_button.disabled = false
	_set_join_status(msg)
	_update_all_ui()

func _on_network_status_received(msg: String) -> void:
	if ui:
		ui.log_network(msg)
	if join_panel and join_panel.visible:
		_set_join_status(msg)
	_update_all_ui()

func _on_network_action_result_received(payload: Dictionary) -> void:
	var result: Dictionary = _network_state_manager.classify_action_result(
		_network_state,
		payload,
		Callable(self, "_resolve_action_username")
	)
	var kind: int = int(result.get("kind", NetworkStateManager.ActionResultKind.NORMAL))
	if kind == NetworkStateManager.ActionResultKind.FAILURE:
		_handle_network_action_failure(result)
		return
	if kind == NetworkStateManager.ActionResultKind.NPC_NOOP:
		_handle_network_action_noop(result)
		return
	if kind == NetworkStateManager.ActionResultKind.QUEUED_MOVE:
		_handle_network_action_queued_move()
		return
	_handle_network_action_logged(payload)

func _flush_pending_network_actions() -> void:
	var pending_actions: Array[Dictionary] = _network_state_manager.drain_pending_actions(_network_state)
	if pending_actions.is_empty():
		return
	for payload: Dictionary in pending_actions:
		_append_network_action_log(payload)

func _handle_network_action_failure(result: Dictionary) -> void:
	if ui:
		ui.log_system("%s failed %s: %s" % [
			str(result.get("executor_name", "Unknown")),
			str(result.get("action_type", "")),
			str(result.get("error_text", "Unknown error")),
		])
		ui.log_network("Action failed: %s by %s | %s" % [
			str(result.get("action_type", "")),
			str(result.get("executor_name", "Unknown")),
			str(result.get("error_text", "Unknown error")),
		])
	_update_all_ui()

func _handle_network_action_noop(result: Dictionary) -> void:
	if ui:
		ui.log_system("%s skipped action" % str(result.get("executor_name", "Unknown")))
	_update_all_ui()

func _handle_network_action_queued_move() -> void:
	_update_all_ui()

func _handle_network_action_logged(payload: Dictionary) -> void:
	_append_network_action_log(payload)
	_update_all_ui()

func _append_network_action_log(payload: Dictionary) -> void:
	if ui == null:
		return
	var action_type: String = str(payload.get(NetworkProtocol.KEY_ACTION_TYPE, ""))
	var executor_id: int = int(payload.get(NetworkProtocol.KEY_EXECUTOR_ID, 0))
	var target_id: int = int(payload.get(NetworkProtocol.KEY_TARGET_ID, 0))
	var executor_name: String = _resolve_action_username(payload, str(NetworkProtocol.KEY_EXECUTOR_USERNAME), executor_id)
	var target_name: String = _resolve_action_username(payload, str(NetworkProtocol.KEY_TARGET_USERNAME), target_id)
	if action_type.begins_with("move_"):
		var actor: PlayerUnit = _get_player_by_id(executor_id)
		ui.log_movement("%s - to {%s}" % [executor_name, _format_player_surroundings(actor)])
		return
	if action_type == String(NetworkProtocol.CMD_ATTACK):
		var target_health: int = int(payload.get("target_health", -1))
		var target_max_health: int = int(payload.get("target_max_health", -1))
		if target_health >= 0 and target_max_health > 0:
			ui.log_combat("%s attacked %s -> %d/%d" % [executor_name, target_name, target_health, target_max_health])
		else:
			ui.log_combat("%s attacked %s" % [executor_name, target_name])
		return
	if action_type == String(NetworkProtocol.CMD_HEAL):
		if target_name.is_empty():
			target_name = executor_name
		var healed_health: int = int(payload.get("target_health", payload.get("actor_health", -1)))
		var healed_max_health: int = int(payload.get("target_max_health", payload.get("actor_max_health", -1)))
		if healed_health >= 0 and healed_max_health > 0:
			ui.log_combat("%s healed %s -> %d/%d" % [executor_name, target_name, healed_health, healed_max_health])
		else:
			ui.log_combat("%s did heal" % executor_name)
		return
	if action_type == String(NetworkProtocol.CMD_NPC_NOOP):
		ui.log_system("%s skipped action" % executor_name)
		return
	ui.log_combat("%s did %s" % [executor_name, action_type])

func _resolve_action_username(payload: Dictionary, key: String, user_id: int) -> String:
	var explicit_name: String = ""
	var raw_name: Variant = payload.get(key, "")
	if typeof(raw_name) == TYPE_STRING:
		explicit_name = raw_name as String
	if not explicit_name.is_empty():
		return explicit_name
	var player: PlayerUnit = _get_player_by_id(user_id)
	if player:
		return _player_log_name(player)
	if user_id > 0:
		return "P%s" % user_id
	return "Unknown"

func _apply_backend_status_history(payload: Dictionary) -> void:
	if ui == null:
		return
	var history: Array = _array_or_empty(payload.get(NetworkProtocol.KEY_STATUS_HISTORY))
	if history.is_empty():
		return
	var lines: Array[String] = []
	for item: Variant in history:
		if typeof(item) != TYPE_DICTIONARY:
			continue
		var entry: Dictionary = item as Dictionary
		lines.append(_format_status_history_entry(entry))
	ui.set_status_history(lines)

func _apply_network_turn_context(payload: Dictionary) -> void:
	var context_result: Dictionary = _network_state_manager.apply_turn_context(_network_state, payload)
	if not bool(context_result.get("has_context", false)):
		if _get_current_target() != null:
			_set_target(null)
		return

	if _network == null:
		return

	var actor_user_id: int = int(context_result.get("actor_user_id", 0))
	if actor_user_id != _network.user_id:
		if _get_current_target() != null:
			_set_target(null)
		return

	var current_target: PlayerUnit = _get_current_target()
	if current_target != null and not _is_network_target_attackable(current_target):
		var turn_context: Dictionary = _dictionary_or_empty(context_result.get("turn_context"))
		var moved_out_of_range: bool = _network_state_manager.did_target_leave_surroundings(
			turn_context,
			current_target.player_id
		)
		_set_target(null)
		if ui:
			if moved_out_of_range:
				ui.log_network("Target moved out of 1-hex range")
			else:
				ui.log_network("Target no longer attackable")

func _format_status_history_entry(entry: Dictionary) -> String:
	var event_type: String = str(entry.get("type", "status"))
	if event_type == String(NetworkProtocol.MSG_ACTION_RESULT):
		var action_type: String = str(entry.get("action_type", ""))
		var executor: String = str(entry.get("executor_username", entry.get("executor_id", "?")))
		var message: String = str(entry.get("message", ""))
		var before_turn: String = _format_turn_id_value(entry.get("before_turn_user_id", "-"))
		var after_turn: String = _format_turn_id_value(entry.get("after_turn_user_id", "-"))
		return "%s %s | %s | turn %s -> %s" % [executor, action_type, message, before_turn, after_turn]
	return str(entry.get("message", "status"))

func _format_turn_id_value(value: Variant) -> String:
	if typeof(value) == TYPE_NIL:
		return "-"
	if typeof(value) == TYPE_INT:
		return str(int(value))
	if typeof(value) == TYPE_FLOAT:
		var number: float = float(value)
		if is_equal_approx(number, floor(number)):
			return str(int(number))
	return str(value)

func _dictionary_or_empty(value: Variant) -> Dictionary:
	if typeof(value) == TYPE_DICTIONARY:
		return value
	return {}

func _array_or_empty(value: Variant) -> Array:
	if typeof(value) == TYPE_ARRAY:
		return value
	return []

# --- UI and state helpers ---

func _is_online_presence() -> bool:
	return _network_state.is_ws_connected and _network_state.online_human_count > 0

func _update_presence_badge() -> void:
	if debug_menu:
		debug_menu.text = "Debug [%s]" % ("ONLINE" if _is_online_presence() else "OFFLINE")
	_render_join_status()

func _set_join_status(message: String) -> void:
	_network_state_manager.set_join_status(_network_state, message)
	_render_join_status()

func _render_join_status() -> void:
	if not join_status:
		return
	var heartbeat_text: String = "OK"
	if not _network_state.heartbeat_ok:
		heartbeat_text = "STALE (%s missed)" % _network_state.heartbeat_missed_count
	elif _network_state.heartbeat_latency_ms >= 0:
		heartbeat_text = "OK (%sms)" % _network_state.heartbeat_latency_ms
	var role_text: String = _local_role_text()
	var turn_text: String = "-"
	if _network_state.active_turn_user_id > 0:
		turn_text = str(_network_state.active_turn_user_id)
	join_status.text = "%s\nPresence: %s\nHeartbeat: %s\nRole: %s | Active Turn: %s" % [
		_network_state.join_status_message,
		"ONLINE" if _is_online_presence() else "OFFLINE",
		heartbeat_text,
		role_text,
		turn_text,
	]

func _player_log_name(player: PlayerUnit) -> String:
	if player == null:
		return "Unknown"
	return player.get_display_name()

func _local_role_text() -> String:
	if not _use_networked_game or _network == null:
		return "offline-human"
	var local_player: PlayerUnit = _get_player_by_id(_network.user_id)
	if local_player == null:
		return "unknown"
	if local_player.get_is_npc():
		return "npc"
	return "human"

func _format_player_surroundings(player: PlayerUnit) -> String:
	if player == null or world == null:
		return "unknown"
	var surrounding_names: Array[String] = world.get_adjacent_entity_names(player.axial_position, _players, player)
	if surrounding_names.is_empty():
		return "nothing nearby"
	return ", ".join(surrounding_names)

func _get_player_by_id(id: int) -> PlayerUnit:
	for p: PlayerUnit in _players:
		if p.player_id == id:
			return p
	return null

func _is_human(player: PlayerUnit) -> bool:
	return player != null and player.player_id == 1

func _is_human_turn() -> bool:
	var active: PlayerUnit = null
	if turn_manager:
		active = turn_manager.get_active_player() as PlayerUnit
	return _is_human(active)

func _is_network_turn() -> bool:
	return _network != null and (_network_state.active_turn_user_id == 0 or _network_state.active_turn_user_id == _network.user_id)

func _is_my_turn() -> bool:
	# Unified helper: can this client act right now?
	if _use_networked_game:
		return _is_network_turn()
	else:
		return _is_human_turn()

func _is_network_target_attackable(target: PlayerUnit) -> bool:
	if target == null or _network == null:
		return false
	if _network_state.active_turn_user_id != _network.user_id:
		return false
	return _network_state.attackable_target_ids.has(target.player_id)

func _get_network_attackable_targets() -> Array[PlayerUnit]:
	var candidates: Array[PlayerUnit] = []
	if _network == null:
		return candidates
	for player: PlayerUnit in _players:
		if player.player_id == _network.user_id:
			continue
		if not player.is_alive():
			continue
		if _network_state.attackable_target_ids.has(player.player_id):
			candidates.append(player)
	candidates.sort_custom(
		func(a: PlayerUnit, b: PlayerUnit) -> bool:
			if a.health == b.health:
				return a.player_id < b.player_id
			return a.health < b.health
	)
	return candidates

func _get_adjacent_targets(player: PlayerUnit) -> Array[PlayerUnit]:
	var targets: Array[PlayerUnit] = []
	var player_axial: Vector2i = player.axial_position
	for p: PlayerUnit in _players:
		if p != player and p.is_alive():
			if terrain.axial_distance(player_axial, p.axial_position) == 1:
				targets.append(p)
	targets.sort_custom(func(a: PlayerUnit, b: PlayerUnit) -> bool: return a.health < b.health)
	return targets

func _find_adjacent_target(player: PlayerUnit) -> PlayerUnit:
	var targets: Array[PlayerUnit] = _get_adjacent_targets(player)
	return targets[0] if not targets.is_empty() else null

func _auto_select_target(player: PlayerUnit) -> void:
	var targets: Array[PlayerUnit] = _get_adjacent_targets(player)
	_set_target(targets[0] if not targets.is_empty() else null)

func _set_target(target: PlayerUnit) -> void:
	_target_manager.set_target(target, _players)

func _get_current_target() -> PlayerUnit:
	return _target_manager.get_target(_players)

func _cycle_target() -> void:
	# Only allow targeting on this client's turn
	if not _is_my_turn():
		return
	var targets: Array[PlayerUnit] = []
	if _use_networked_game and _network:
		targets = _get_network_attackable_targets()
	else:
		var my_player: PlayerUnit = null
		if turn_manager:
			my_player = turn_manager.get_active_player() as PlayerUnit
		if my_player == null:
			return
		targets = _get_adjacent_targets(my_player)
	if targets.is_empty():
		_set_target(null)
		return
	_target_manager.cycle_target(targets, _players)

func _end_human_turn() -> void:
	if turn_manager:
		turn_manager.end_turn()
	_update_all_ui()

func _update_all_ui() -> void:
	if _use_networked_game and _network:
		var ids: Array[int] = []
		for p: PlayerUnit in _players:
			ids.append(p.player_id)
		ids.sort()
		if ui:
			var local_role: String = _local_role_text()
			var is_my_turn_now: bool = _network_state.active_turn_user_id > 0 and _network_state.active_turn_user_id == _network.user_id
			ui.update_turn_panel_online(ids, _network_state.active_turn_user_id, _players.size())
			ui.update_network_console(
				_network.base_url,
				_network.user_id,
				str(_network.channel_id),
				_network_state.active_turn_user_id,
				_is_online_presence(),
				_network_state.online_human_count,
				_network_state.heartbeat_ok,
				_network_state.heartbeat_latency_ms,
				_network_state.heartbeat_missed_count,
				local_role,
				is_my_turn_now
			)
	else:
		var active: Node = null
		if turn_manager:
			active = turn_manager.get_active_player()
		if ui:
			ui.update_turn_panel_offline(active, _get_current_target(), _players.size())
	if ui:
		ui.update_system_panel(lighting_rig)
	var active_id: int = -1
	if _use_networked_game:
		active_id = _network_state.active_turn_user_id
	elif turn_manager:
		var active_player: PlayerUnit = turn_manager.get_active_player() as PlayerUnit
		if active_player:
			active_id = active_player.player_id
	for p: PlayerUnit in _players:
		p.set_is_current_turn(p.player_id == active_id)

func _log_system(text: String) -> void:
	if ui and not text.is_empty():
		ui.log_system(text)

# --- Hover and mouse move ---

func _create_hover_marker() -> void:
	var mesh: CylinderMesh = CylinderMesh.new()
	var t_size: float = terrain.tile_size if terrain else 1.2
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
	# Allow hover when it's this client's turn (offline or networked)
	if not _is_my_turn() or _is_human_moving:
		_clear_hover()
		return
	if not camera_node:
		_clear_hover()
		return
	var origin: Vector3 = camera_node.project_ray_origin(screen_pos)
	var dir: Vector3 = camera_node.project_ray_normal(screen_pos)
	if abs(dir.y) < 0.0001:
		return
	var t: float = -origin.y / dir.y
	if t < 0:
		return
	var world_pos: Vector3 = origin + dir * t
	var axial: Vector2i = terrain.world_to_axial(world_pos)
	if not terrain.is_within_play_area(axial) or world.is_blocked(axial):
		_clear_hover()
		return
	_hover_axial = axial
	_hover_marker.position = terrain.axial_to_world(axial) + Vector3(0, 0.3, 0)
	_hover_marker.visible = true

func _clear_hover() -> void:
	if _hover_marker:
		_hover_marker.visible = false

func _try_mouse_move() -> void:
	if _hover_marker and _hover_marker.visible:
		var player: PlayerUnit = null
		if _use_networked_game and _network:
			player = _get_player_by_id(_network.user_id)
		elif turn_manager:
			player = turn_manager.get_active_player() as PlayerUnit
		if player == null:
			return
		var dist: int = terrain.axial_distance(player.axial_position, _hover_axial)
		if dist != 1:
			return
		var delta: Vector2i = _hover_axial - player.axial_position
		if _use_networked_game and _network:
			if delta == Vector2i(0, -1):
				_network.send_command(String(NetworkProtocol.CMD_MOVE_N))
			elif delta == Vector2i(1, -1):
				_network.send_command(String(NetworkProtocol.CMD_MOVE_NE))
			elif delta == Vector2i(1, 0):
				_network.send_command(String(NetworkProtocol.CMD_MOVE_SE))
			elif delta == Vector2i(0, 1):
				_network.send_command(String(NetworkProtocol.CMD_MOVE_S))
			elif delta == Vector2i(-1, 1):
				_network.send_command(String(NetworkProtocol.CMD_MOVE_SW))
			elif delta == Vector2i(-1, 0):
				_network.send_command(String(NetworkProtocol.CMD_MOVE_NW))
		else:
			_attempt_move(player, delta)

func _focus_camera_on_player(player: PlayerUnit) -> void:
	if player and camera_mgr:
		camera_mgr.focus_on_position(player.global_position)
