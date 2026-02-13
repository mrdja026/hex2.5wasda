## Applies authoritative server snapshots/updates to the local rendered world.
## The client MUST NOT locally seed/simulate authoritative state while connected.
## P4 (Wrap plan): Validates snapshot/update payload shape, emits error on critical failure.
## P5 (Wrap plan): Reads grid_max_index from snapshot (TODO: backend must add snapshot.map.grid_max_index).
## TODO (backend P2): Keep collision checks/adjacency authoritative and lazy at command-processing time.
## TODO (backend P3): Expose static obstacle layers in canonical snapshot payloads.
## TODO (backend P6): Auto-kick stale/invalid sessions from channels.
## TODO (backend P7): Document cache invalidation and snapshot consistency guarantees.
class_name NetworkSync
extends Node

const HexTerrain = preload("res://scripts/hex_terrain.gd")
const GameWorld = preload("res://scripts/game_world.gd")
const GameUI = preload("res://scripts/game_ui.gd")
const PlayerUnit = preload("res://scripts/player_unit.gd")

signal snapshot_applied(active_turn_user_id: int)
signal update_applied(active_turn_user_id: int)
signal players_changed(players: Array[Node3D])
signal battlefield_changed()
signal validation_error(message: String)

# P5: Default small-arena dimensions
const DEFAULT_BACKEND_GRID_MAX_INDEX: float = 9.0
const DEFAULT_BACKEND_MAP_WIDTH: int = 10
const DEFAULT_BACKEND_MAP_HEIGHT: int = 10

var _terrain: HexTerrain
var _world: GameWorld
var _player_container: Node3D
var _player_scene: PackedScene
var _ui: GameUI

var _network_players_by_id: Dictionary = {}
var _players: Array[Node3D] = []
var _backend_grid_max_index: float = DEFAULT_BACKEND_GRID_MAX_INDEX
var _backend_map_width: int = DEFAULT_BACKEND_MAP_WIDTH
var _backend_map_height: int = DEFAULT_BACKEND_MAP_HEIGHT

func setup(terrain: HexTerrain, world: GameWorld, player_container: Node3D, player_scene: PackedScene, ui: GameUI) -> void:
	_terrain = terrain
	_world = world
	_player_container = player_container
	_player_scene = player_scene
	_ui = ui

func get_players() -> Array[Node3D]:
	return _players

func handle_snapshot(snapshot: Dictionary) -> void:
	# P4: Validate critical snapshot fields
	if not _validate_snapshot(snapshot):
		return
	
	var active_turn_id: int = int(snapshot.get("active_turn_user_id", 0))
	var players_payload: Array = snapshot.get("players", []) as Array
	
	# P5: Read grid_max_index from snapshot.map if backend provides it
	_update_grid_max_index(snapshot)
	if _terrain and snapshot.has("map") and typeof(snapshot.get("map")) == TYPE_DICTIONARY:
		_terrain.configure_from_backend_map(snapshot.get("map") as Dictionary)
	
	var battlefield_payload: Dictionary = {}
	var raw_battlefield: Variant = snapshot.get("battlefield", {})
	if typeof(raw_battlefield) == TYPE_DICTIONARY:
		battlefield_payload = raw_battlefield as Dictionary
	
	if _world:
		_world.clear_state()
	
	if battlefield_payload.is_empty():
		_sync_obstacles(snapshot.get("obstacles", []) as Array)
	else:
		_sync_battlefield(battlefield_payload)
	
	_sync_players(players_payload, true)
	snapshot_applied.emit(active_turn_id)
	battlefield_changed.emit()

func handle_update(update: Dictionary) -> void:
	# P4: Validate critical update fields
	if not _validate_update(update):
		return
	
	var active_turn_id: int = int(update.get("active_turn_user_id", 0))
	var players_payload: Array = update.get("players", []) as Array
	_sync_players(players_payload, false)
	update_applied.emit(active_turn_id)

# --- P4: Payload Validation ---

func _validate_snapshot(snapshot: Dictionary) -> bool:
	var errors: Array[String] = []
	
	if not snapshot.has("players"):
		errors.append("Missing required field: players")
	elif typeof(snapshot.get("players")) != TYPE_ARRAY:
		errors.append("Invalid type for players (expected Array)")
	
	if not snapshot.has("active_turn_user_id"):
		errors.append("Missing required field: active_turn_user_id")
	
	# battlefield or obstacles must be present
	if not snapshot.has("battlefield") and not snapshot.has("obstacles"):
		errors.append("Missing both battlefield and obstacles (expected at least one)")
	
	if not errors.is_empty():
		var msg: String = "Snapshot validation failed: %s" % ", ".join(errors)
		if _ui:
			_ui.log_network("ERROR: %s" % msg)
		validation_error.emit(msg)
		return false
	
	return true

func _validate_update(update: Dictionary) -> bool:
	var errors: Array[String] = []
	
	if not update.has("active_turn_user_id"):
		errors.append("Missing required field: active_turn_user_id")
	
	if not update.has("players"):
		errors.append("Missing required field: players")
	elif typeof(update.get("players")) != TYPE_ARRAY:
		errors.append("Invalid type for players (expected Array)")
	
	if not errors.is_empty():
		var msg: String = "Update validation failed: %s" % ", ".join(errors)
		if _ui:
			_ui.log_network("ERROR: %s" % msg)
		validation_error.emit(msg)
		return false
	
	return true

# --- P5: Dynamic Grid Size ---

func _update_grid_max_index(snapshot: Dictionary) -> void:
	_backend_map_width = DEFAULT_BACKEND_MAP_WIDTH
	_backend_map_height = DEFAULT_BACKEND_MAP_HEIGHT
	_backend_grid_max_index = DEFAULT_BACKEND_GRID_MAX_INDEX
	if snapshot.has("map"):
		var map_data: Variant = snapshot.get("map")
		if typeof(map_data) == TYPE_DICTIONARY:
			var map_dict: Dictionary = map_data as Dictionary
			if map_dict.has("width"):
				_backend_map_width = int(map_dict.get("width", DEFAULT_BACKEND_MAP_WIDTH))
			if map_dict.has("height"):
				_backend_map_height = int(map_dict.get("height", DEFAULT_BACKEND_MAP_HEIGHT))
			if map_dict.has("grid_max_index"):
				_backend_grid_max_index = float(map_dict.get("grid_max_index", DEFAULT_BACKEND_GRID_MAX_INDEX))
			else:
				_backend_grid_max_index = float(max(_backend_map_width, _backend_map_height) - 1)
	if _ui:
		_ui.log_network("Map size read from snapshot: %sx%s" % [_backend_map_width, _backend_map_height])

# --- Battlefield syncing ---

func _sync_battlefield(battlefield: Dictionary) -> void:
	if _world == null:
		return
	
	var rendered_props: int = 0
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
		_world.spawn_network_prop(prop_type, axial, is_blocking)
		rendered_props += 1
	# TODO(TD-Buffer): Optional backend buffer metadata is currently ignored until buffer-zone rules are redesigned.
	
	if _ui:
		_ui.log_network("Battlefield rendered props=%s" % rendered_props)

func _sync_obstacles(data: Array) -> void:
	if _world == null:
		return
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
		_world.set_blocked(axial, true)

# --- Player syncing ---

func _sync_players(data: Array, is_full_sync: bool) -> void:
	if _terrain == null or _player_container == null or _player_scene == null:
		return
	
	var seen_ids: Dictionary = {}
	for item: Variant in data:
		if typeof(item) != TYPE_DICTIONARY:
			continue
		var entry: Dictionary = item as Dictionary
		var user_id: int = int(entry.get("user_id", 0))
		if user_id <= 0:
			continue
		seen_ids[user_id] = true
		
		var player: PlayerUnit = _network_players_by_id.get(user_id) as PlayerUnit
		var is_new_player: bool = false
		if player == null or not is_instance_valid(player):
			player = _player_scene.instantiate() as PlayerUnit
			if player == null:
				continue
			player.player_id = user_id
			_player_container.add_child(player)
			_network_players_by_id[user_id] = player
			is_new_player = true
		
		var next_axial: Vector2i = _extract_axial_from_payload(entry)
		var previous_axial: Vector2i = player.axial_position
		if _world and not is_new_player and previous_axial != next_axial:
			_world.set_blocked(previous_axial, false)
		
		player.set_axial_position(next_axial)
		player.position = _terrain.axial_to_world(next_axial) + Vector3(0, 0.6, 0)
		player.set_health(int(entry.get("health", 10)), int(entry.get("max_health", 10)))
		if entry.has("is_npc"):
			player.set_is_npc(bool(entry.get("is_npc", false)))
		var username: String = str(entry.get("username", ""))
		var display_name: String = str(entry.get("display_name", username))
		player.set_backend_identity(username, display_name)
		
		if _world:
			_world.set_blocked(next_axial, true)
	
	if is_full_sync:
		for key: Variant in _network_players_by_id.keys():
			var tracked_id: int = int(key)
			if seen_ids.has(tracked_id):
				continue
			var stale_player: PlayerUnit = _network_players_by_id.get(tracked_id) as PlayerUnit
			if stale_player != null and is_instance_valid(stale_player):
				var stale_axial: Vector2i = stale_player.axial_position
				if _world:
					_world.set_blocked(stale_axial, false)
				stale_player.queue_free()
			_network_players_by_id.erase(tracked_id)
	
	_players.clear()
	for value: Variant in _network_players_by_id.values():
		var current_player: PlayerUnit = value as PlayerUnit
		if current_player != null and is_instance_valid(current_player):
			_players.append(current_player)
	
	players_changed.emit(_players)

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

# --- Backend mapping ---

func _map_backend_position_to_world_axial(backend_position: Vector2i) -> Vector2i:
	if _terrain == null:
		return backend_position
	var row: int = backend_position.y
	var col: int = backend_position.x
	var q: int = col - int((row - (row & 1)) / 2)
	var r: int = row
	var center_col: int = int(_backend_map_width / 2)
	var center_row: int = int(_backend_map_height / 2)
	var center_q: int = center_col - int((center_row - (center_row & 1)) / 2)
	var center_r: int = center_row
	var mapped: Vector2i = Vector2i(q - center_q, r - center_r)
	if _terrain.is_within_bounds(mapped):
		return mapped
	return _nearest_world_axial(mapped)

func _nearest_world_axial(axial: Vector2i) -> Vector2i:
	if _terrain == null:
		return axial
	var world_axials: Array[Vector2i] = _terrain.get_all_axials()
	if world_axials.is_empty():
		return Vector2i.ZERO
	var best: Vector2i = world_axials[0]
	var best_distance: int = _terrain.axial_distance(axial, best)
	for candidate: Vector2i in world_axials:
		var distance: int = _terrain.axial_distance(axial, candidate)
		if distance < best_distance:
			best = candidate
			best_distance = distance
	return best
