## Owns network state transitions derived from server payloads.
class_name NetworkStateManager
extends RefCounted

const NetworkGameState = preload("res://scripts/network_game_state.gd")
const NetworkProtocol = preload("res://scripts/network_protocol.gd")

enum ActionResultKind {
	FAILURE,
	NPC_NOOP,
	QUEUED_MOVE,
	NORMAL,
}

func count_human_players(players_data: Array) -> int:
	var count: int = 0
	for item: Variant in players_data:
		if typeof(item) != TYPE_DICTIONARY:
			continue
		var entry: Dictionary = item
		if bool(entry.get("is_npc", false)):
			continue
		count += 1
	return count

func apply_snapshot_metadata(state: NetworkGameState, snapshot: Dictionary) -> void:
	state.online_human_count = count_human_players(_array_or_empty(snapshot.get(NetworkProtocol.KEY_PLAYERS)))

func apply_update_metadata(state: NetworkGameState, update: Dictionary) -> void:
	state.online_human_count = count_human_players(_array_or_empty(update.get(NetworkProtocol.KEY_PLAYERS)))

func apply_snapshot_applied(state: NetworkGameState, active_turn_user_id: int) -> void:
	state.active_turn_user_id = active_turn_user_id

func apply_update_applied(state: NetworkGameState, active_turn_user_id: int) -> void:
	state.active_turn_user_id = active_turn_user_id

func apply_connection_state(state: NetworkGameState, is_connected: bool) -> void:
	state.is_ws_connected = is_connected
	if is_connected:
		return
	state.online_human_count = 0
	state.heartbeat_ok = false
	state.heartbeat_latency_ms = -1
	state.heartbeat_missed_count = 0
	state.pending_actions.clear()
	state.attackable_target_ids.clear()

func apply_heartbeat(state: NetworkGameState, ok: bool, latency_ms: int, missed_count: int) -> void:
	state.heartbeat_ok = ok
	state.heartbeat_latency_ms = latency_ms
	state.heartbeat_missed_count = missed_count

func set_join_status(state: NetworkGameState, message: String) -> void:
	state.join_status_message = message

func classify_action_result(
	state: NetworkGameState,
	payload: Dictionary,
	resolve_username: Callable,
) -> Dictionary:
	if payload.has(NetworkProtocol.KEY_ACTIVE_TURN_USER_ID):
		state.active_turn_user_id = int(payload.get(NetworkProtocol.KEY_ACTIVE_TURN_USER_ID, state.active_turn_user_id))
	var action_type: String = str(payload.get(NetworkProtocol.KEY_ACTION_TYPE, ""))
	var executor_id: int = int(payload.get(NetworkProtocol.KEY_EXECUTOR_ID, 0))
	var executor_name: String = "Unknown"
	if resolve_username.is_valid():
		executor_name = str(resolve_username.call(payload, str(NetworkProtocol.KEY_EXECUTOR_USERNAME), executor_id))

	if not bool(payload.get(NetworkProtocol.KEY_SUCCESS, false)):
		return {
			"kind": ActionResultKind.FAILURE,
			"action_type": action_type,
			"executor_name": executor_name,
			"error_text": _extract_error_text(payload),
		}

	if action_type == String(NetworkProtocol.CMD_NPC_NOOP):
		return {
			"kind": ActionResultKind.NPC_NOOP,
			"executor_name": executor_name,
		}

	if action_type.begins_with("move_"):
		state.pending_actions.append(payload.duplicate(true))
		return {
			"kind": ActionResultKind.QUEUED_MOVE,
		}

	return {
		"kind": ActionResultKind.NORMAL,
	}

func drain_pending_actions(state: NetworkGameState) -> Array[Dictionary]:
	if state.pending_actions.is_empty():
		return []
	var pending_actions: Array[Dictionary] = []
	for pending_payload: Dictionary in state.pending_actions:
		pending_actions.append(pending_payload.duplicate(true))
	state.pending_actions.clear()
	return pending_actions

func apply_turn_context(state: NetworkGameState, payload: Dictionary) -> Dictionary:
	state.attackable_target_ids.clear()
	var raw_context: Variant = payload.get(NetworkProtocol.KEY_TURN_CONTEXT)
	if typeof(raw_context) != TYPE_DICTIONARY:
		return {
			"has_context": false,
			"actor_user_id": 0,
			"turn_context": {},
		}
	var turn_context: Dictionary = raw_context
	var actor_user_id: int = int(turn_context.get(NetworkProtocol.KEY_ACTOR_USER_ID, 0))
	for value: Variant in _array_or_empty(turn_context.get(NetworkProtocol.KEY_ATTACKABLE_TARGET_IDS)):
		state.attackable_target_ids[int(value)] = true
	return {
		"has_context": true,
		"actor_user_id": actor_user_id,
		"turn_context": turn_context,
	}

func did_target_leave_surroundings(turn_context: Dictionary, target_user_id: int) -> bool:
	var diff_data: Variant = turn_context.get(NetworkProtocol.KEY_SURROUNDINGS_DIFF)
	if typeof(diff_data) != TYPE_DICTIONARY:
		return false
	var diff: Dictionary = diff_data
	var removed: Array = _array_or_empty(diff.get(NetworkProtocol.KEY_REMOVED))
	var target_entity_id: String = "player:%s" % target_user_id
	for item: Variant in removed:
		if typeof(item) != TYPE_DICTIONARY:
			continue
		var entry: Dictionary = item
		if str(entry.get(NetworkProtocol.KEY_ENTITY_ID, "")) == target_entity_id:
			return true
	return false

func _extract_error_text(payload: Dictionary) -> String:
	var error_obj: Variant = payload.get(NetworkProtocol.KEY_ERROR)
	if typeof(error_obj) == TYPE_DICTIONARY:
		var error_data: Dictionary = error_obj
		var error_text: String = str(error_data.get(NetworkProtocol.KEY_MESSAGE, ""))
		if not error_text.is_empty():
			return error_text
	var message: String = str(payload.get(NetworkProtocol.KEY_MESSAGE, ""))
	if message.is_empty():
		return "Unknown error"
	return message

func _array_or_empty(value: Variant) -> Array:
	if typeof(value) == TYPE_ARRAY:
		return value
	return []
