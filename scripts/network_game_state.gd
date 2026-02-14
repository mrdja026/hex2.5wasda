## Mutable state container for networked game session UI and turn data.
class_name NetworkGameState
extends RefCounted

var active_turn_user_id: int = 0
var pending_actions: Array[Dictionary] = []
var attackable_target_ids: Dictionary = {}

var is_ws_connected: bool = false
var online_human_count: int = 0
var heartbeat_ok: bool = true
var heartbeat_latency_ms: int = -1
var heartbeat_missed_count: int = 0
var join_status_message: String = "Offline"

func clear_runtime_state() -> void:
	active_turn_user_id = 0
	pending_actions.clear()
	attackable_target_ids.clear()
	is_ws_connected = false
	online_human_count = 0
	heartbeat_ok = false
	heartbeat_latency_ms = -1
	heartbeat_missed_count = 0
	join_status_message = "Offline"
