## Manages the game's UI elements, logging, and panels.
class_name GameUI
extends Node

const MAX_LOG_LINES: int = 6
const NETWORK_LOG_LINES: int = 12
const STATUS_HISTORY_LINES: int = 10

var turn_label: Label
var combat_label: Label
var movement_label: Label
var system_label: Label
var join_status: Label
var network_console_label: Label

var _combat_log: Array[String] = []
var _movement_log: Array[String] = []
var _turn_log: Array[String] = []
var _system_log: Array[String] = []
var _network_log: Array[String] = []
var _status_history_log: Array[String] = []

func log_combat(text: String) -> void:
	_append_log(_combat_log, text, MAX_LOG_LINES)
	update_combat_panel()

func log_movement(text: String) -> void:
	_append_log(_movement_log, text, MAX_LOG_LINES)
	update_movement_panel()

func log_turn(text: String) -> void:
	_append_log(_turn_log, text, MAX_LOG_LINES)

func log_system(text: String) -> void:
	_append_log(_system_log, text, STATUS_HISTORY_LINES)

func set_status_history(entries: Array[String]) -> void:
	_status_history_log.clear()
	for item: String in entries:
		_append_log(_status_history_log, item, STATUS_HISTORY_LINES)

func log_network(text: String) -> void:
	_append_log(_network_log, text, NETWORK_LOG_LINES)
	_log_to_file("network", text)

func update_turn_panel_offline(active: Node, target: Node, player_count: int) -> void:
	if turn_label == null: return
	var lines: Array[String] = ["Turn & Status"]
	if active:
		lines.append("Active Player: P%s" % active.get("player_id"))
		lines.append("Health: %s/%s" % [active.get("health"), active.get("max_health")])
		if target:
			lines.append("Target: P%s (%s/%s)" % [target.get("player_id"), target.get("health"), target.get("max_health")])
		else:
			lines.append("Target: -")
	else:
		lines.append("Active Player: -")
	lines.append("Players: %s" % player_count)
	lines.append("")
	lines.append("Turn Log:")
	if _turn_log.is_empty(): lines.append("No recent turns")
	else: lines.append_array(_turn_log)
	turn_label.text = "\n".join(lines)

func update_turn_panel_online(ids: Array, current_id: int, player_count: int) -> void:
	if turn_label == null: return
	var lines: Array[String] = ["Turn Carousel"]
	if ids.is_empty():
		lines.append("Previous: -")
		lines.append("Current: -")
		lines.append("Next: -")
	else:
		var active_id: int = current_id
		if active_id <= 0 or not ids.has(active_id): 
			active_id = ids[0] as int
		var index: int = ids.find(active_id)
		var prev_id: int = ids[(index - 1 + ids.size()) % ids.size()] as int
		var next_id: int = ids[(index + 1) % ids.size()] as int
		lines.append("Previous: %s" % prev_id)
		lines.append("Current: %s" % active_id)
		lines.append("Next: %s" % next_id)
	lines.append("Players: %s" % player_count)
	turn_label.text = "\n".join(lines)

func update_combat_panel() -> void:
	if combat_label == null: return
	var lines: Array[String] = ["Combat Log:"]
	if _combat_log.is_empty(): lines.append("No combat yet")
	else: lines.append_array(_combat_log)
	combat_label.text = "\n".join(lines)

func update_movement_panel() -> void:
	if movement_label == null: return
	var lines: Array[String] = ["Movement Log:"]
	if _movement_log.is_empty(): lines.append("No movement yet")
	else: lines.append_array(_movement_log)
	movement_label.text = "\n".join(lines)

func update_system_panel(rig: Node3D) -> void:
	if system_label == null: return
	var lines: Array[String] = ["System & Lighting"]
	if rig:
		lines.append("Dir Intensity: %0.2f" % (rig.get("directional_intensity") as float))
		lines.append("Point Intensity: %0.2f" % (rig.get("point_intensity") as float))
	else:
		lines.append("Lighting: -")
	lines.append("")
	lines.append("System Log:")
	if _system_log.is_empty(): lines.append("No system events")
	else: lines.append_array(_system_log)
	lines.append("")
	lines.append("WASD/LMB: Move | J: Attack | K: Heal | Space: End")
	system_label.text = "\n".join(lines)

func update_network_console(
	url: String,
	user_id: int,
	channel_id: String,
	active_turn: int,
	is_online: bool = false,
	human_count: int = 0,
	heartbeat_ok: bool = true,
	heartbeat_latency_ms: int = -1,
	heartbeat_missed_count: int = 0
) -> void:
	if network_console_label == null: return
	var presence_text: String = "ONLINE" if is_online else "OFFLINE"
	var heartbeat_text: String = "OK"
	if not heartbeat_ok:
		heartbeat_text = "STALE (%s missed)" % heartbeat_missed_count
	elif heartbeat_latency_ms >= 0:
		heartbeat_text = "OK (%sms)" % heartbeat_latency_ms
	var lines: Array[String] = [
		"Network Console",
		"URL: %s" % url,
		"User: %s | Channel: %s" % [user_id, channel_id],
		"Active Turn: %s" % active_turn,
		"Presence: %s" % presence_text,
		"Humans in channel: %s" % human_count,
		"WS Heartbeat: %s" % heartbeat_text,
	]
	lines.append("--- Connectivity ---")
	if _network_log.is_empty(): lines.append("(no events)")
	else: lines.append_array(_network_log)
	lines.append("--- Game Status ---")
	if not _status_history_log.is_empty():
		lines.append_array(_status_history_log)
	elif _system_log.is_empty():
		lines.append("(no status)")
	else:
		lines.append_array(_system_log)
	network_console_label.text = "\n".join(lines)

func _append_log(log: Array[String], text: String, max_lines: int) -> void:
	if text.is_empty(): return
	log.append(text)
	while log.size() > max_lines: log.pop_front()

func _log_to_file(source: String, text: String) -> void:
	if text.is_empty():
		return
	var logger: Node = get_node_or_null("/root/GameLogger")
	if logger and logger.has_method("log_line"):
		logger.call("log_line", source, text)
