## Tracks and mutates current target selection by player id.
class_name TargetManager
extends RefCounted

const PlayerUnit = preload("res://scripts/player_unit.gd")

var _target_player_id: int = 0

func get_target(players: Array[PlayerUnit]) -> PlayerUnit:
	return _find_player(players, _target_player_id)

func set_target(target: PlayerUnit, players: Array[PlayerUnit]) -> void:
	var target_id: int = 0
	if target != null:
		target_id = target.player_id
	_set_target_id(target_id, players)

func clear_target(players: Array[PlayerUnit]) -> void:
	_set_target_id(0, players)

func cycle_target(candidates: Array[PlayerUnit], players: Array[PlayerUnit]) -> PlayerUnit:
	if candidates.is_empty():
		clear_target(players)
		return null
	var current_target: PlayerUnit = get_target(players)
	var index: int = candidates.find(current_target)
	var next_target: PlayerUnit = candidates[(index + 1) % candidates.size()]
	set_target(next_target, players)
	return next_target

func target_id() -> int:
	return _target_player_id

func refresh_target_visual(players: Array[PlayerUnit]) -> void:
	var target: PlayerUnit = get_target(players)
	if target == null and _target_player_id != 0:
		_target_player_id = 0
		return
	if target != null:
		target.set_targeted(true)

func _set_target_id(target_player_id: int, players: Array[PlayerUnit]) -> void:
	if _target_player_id == target_player_id:
		return
	var current_target: PlayerUnit = _find_player(players, _target_player_id)
	if current_target != null:
		current_target.set_targeted(false)
	_target_player_id = target_player_id
	var next_target: PlayerUnit = _find_player(players, _target_player_id)
	if next_target != null:
		next_target.set_targeted(true)

func _find_player(players: Array[PlayerUnit], player_id: int) -> PlayerUnit:
	if player_id <= 0:
		return null
	for player: PlayerUnit in players:
		if player.player_id == player_id:
			return player
	return null
