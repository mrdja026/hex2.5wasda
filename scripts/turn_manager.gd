## Manages the turn-based logic, including player registration and action tracking.
extends Node

signal active_player_changed(player: Node)

const MAX_PLAYERS: int = 10
const MOVES_PER_TURN: int = 2

var _players: Array[Node] = []
var _active_index: int = -1
var _moves_left: int = 0
var _action_available: bool = true

func register_player(player: Node) -> bool:
	if _players.size() >= MAX_PLAYERS:
		return false
	if _players.has(player):
		return false
	_players.append(player)
	return true

func remove_player(player: Node) -> void:
	var index: int = _players.find(player)
	if index == -1:
		return
	_players.remove_at(index)
	if _players.is_empty():
		_active_index = -1
		return
	if index < _active_index:
		_active_index -= 1
	elif index == _active_index:
		if _active_index >= _players.size():
			_active_index = 0
		_reset_turn_state()
		_emit_active_changed()

func start_turns() -> void:
	if _players.is_empty():
		return
	_active_index = 0
	_reset_turn_state()
	_emit_active_changed()

func get_active_player() -> Node:
	if _active_index < 0 or _active_index >= _players.size():
		return null
	return _players[_active_index]

func can_act(player: Node) -> bool:
	return player != null and player == get_active_player()

func can_move(player: Node) -> bool:
	return can_act(player) and _action_available and _moves_left > 0

func can_use_action(player: Node) -> bool:
	return can_act(player) and _action_available

func consume_move() -> bool:
	if _moves_left <= 0:
		return false
	_moves_left -= 1
	return true

func end_turn() -> void:
	if _players.is_empty():
		return
	_active_index = (_active_index + 1) % _players.size()
	_reset_turn_state()
	_emit_active_changed()

func player_count() -> int:
	return _players.size()

func moves_left() -> int:
	return _moves_left

func action_available() -> bool:
	return _action_available

func _emit_active_changed() -> void:
	active_player_changed.emit(get_active_player())

func _reset_turn_state() -> void:
	_moves_left = MOVES_PER_TURN
	_action_available = true
