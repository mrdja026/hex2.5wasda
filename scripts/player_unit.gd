## Represents a unit in the game, managing its health, model, and animations.
class_name PlayerUnit
extends Node3D

signal health_changed(current: int, maximum: int)

@export var player_id: int = 0
@export var axial_position: Vector2i = Vector2i.ZERO
@export var max_health: int = 10
@export var health: int = 10
@export var attack_damage: int = 3
@export var heal_amount: int = 2
@export var health_bar_offset: Vector3 = Vector3(0.0, 1.6, 0.0)
@export var backend_username: String = ""  # Backend username (for network targeting)

@onready var model: Node3D = $Model
@onready var animation_player: AnimationPlayer = $AnimationPlayer

var _meshes: Array[MeshInstance3D] = []
var _base_material: StandardMaterial3D
var _outline_material: ShaderMaterial
var _health_bar: Node3D
var _health_back: MeshInstance3D
var _health_fill: MeshInstance3D
var _health_label: Label3D
var _turn_marker: Label3D
var _is_targeted: bool = false
var _has_npc_flag: bool = false
var _is_npc: bool = false

const BAR_WIDTH: float = 0.8
const BAR_HEIGHT: float = 0.08

func _ready() -> void:
	health = clamp(health, 0, max_health)
	_cache_meshes()
	_apply_color()
	_ensure_animations()
	_ensure_health_bar()
	_ensure_turn_marker()
	_update_health_bar()
	_play_idle()

func set_axial_position(axial: Vector2i) -> void:
	axial_position = axial

func set_is_npc(value: bool) -> void:
	_has_npc_flag = true
	_is_npc = value
	_apply_color()

func set_is_current_turn(enabled: bool) -> void:
	if _turn_marker == null:
		return
	_turn_marker.visible = enabled

func apply_damage(amount: int) -> void:
	if amount <= 0:
		return
	health = max(health - amount, 0)
	_update_health_bar()
	health_changed.emit(health, max_health)

func heal_self() -> void:
	health = min(health + heal_amount, max_health)
	_update_health_bar()
	health_changed.emit(health, max_health)

func set_health(current: int, maximum: int) -> void:
	max_health = max(maximum, 1)
	health = clamp(current, 0, max_health)
	_update_health_bar()
	health_changed.emit(health, max_health)

func play_attack() -> void:
	if animation_player.has_animation("attack"):
		animation_player.play("attack")

func play_run() -> void:
	if animation_player.has_animation("run"):
		animation_player.play("run")

func set_targeted(enabled: bool) -> void:
	_is_targeted = enabled
	_apply_outline(enabled)

func is_alive() -> bool:
	return health > 0

func _apply_color() -> void:
	if model == null:
		return
	if _base_material == null:
		_base_material = StandardMaterial3D.new()
		_base_material.roughness = 0.9
	if _has_npc_flag:
		_base_material.albedo_color = Color(0.2, 0.45, 0.9) if _is_npc else Color(0.9, 0.2, 0.2)
	else:
		_base_material.albedo_color = Color(0.9, 0.2, 0.2) if player_id == 1 else Color(0.2, 0.45, 0.9)
	for mesh: MeshInstance3D in _meshes:
		mesh.material_override = _base_material
	_apply_outline(_is_targeted)

func _cache_meshes() -> void:
	_meshes.clear()
	if model == null:
		return
	for child: Node in model.get_children():
		if child is MeshInstance3D:
			_meshes.append(child as MeshInstance3D)

func _ensure_health_bar() -> void:
	if has_node("HealthBar"):
		_health_bar = get_node("HealthBar") as Node3D
		_health_back = _health_bar.get_node("Back") as MeshInstance3D
		_health_fill = _health_bar.get_node("Fill") as MeshInstance3D
		_health_label = _health_bar.get_node("Label") as Label3D
		return
	_health_bar = Node3D.new()
	_health_bar.name = "HealthBar"
	_health_bar.position = health_bar_offset
	add_child(_health_bar)
	var back_mesh: QuadMesh = QuadMesh.new()
	back_mesh.size = Vector2(BAR_WIDTH, BAR_HEIGHT)
	_health_back = MeshInstance3D.new()
	_health_back.name = "Back"
	_health_back.mesh = back_mesh
	var back_mat: StandardMaterial3D = StandardMaterial3D.new()
	back_mat.albedo_color = Color(0.0, 0.0, 0.0, 0.6)
	back_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	back_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	back_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_health_back.material_override = back_mat
	_health_bar.add_child(_health_back)
	var fill_mesh: QuadMesh = QuadMesh.new()
	fill_mesh.size = Vector2(BAR_WIDTH, BAR_HEIGHT)
	_health_fill = MeshInstance3D.new()
	_health_fill.name = "Fill"
	_health_fill.mesh = fill_mesh
	var fill_mat: StandardMaterial3D = StandardMaterial3D.new()
	fill_mat.albedo_color = Color(0.2, 0.85, 0.2)
	fill_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fill_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	fill_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_health_fill.material_override = fill_mat
	_health_fill.position = Vector3(0.0, 0.0, 0.01)
	_health_bar.add_child(_health_fill)
	_health_label = Label3D.new()
	_health_label.name = "Label"
	_health_label.text = ""
	_health_label.font_size = 20
	_health_label.position = Vector3(0.0, 0.12, 0.02)
	_health_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_health_bar.add_child(_health_label)

func _ensure_turn_marker() -> void:
	if has_node("TurnMarker"):
		_turn_marker = get_node("TurnMarker") as Label3D
		return
	_turn_marker = Label3D.new()
	_turn_marker.name = "TurnMarker"
	_turn_marker.text = "*"
	_turn_marker.font_size = 36
	_turn_marker.position = health_bar_offset + Vector3(0.0, 0.35, 0.0)
	_turn_marker.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_turn_marker.modulate = Color(1.0, 0.9, 0.2, 1.0)
	_turn_marker.visible = false
	add_child(_turn_marker)

func _update_health_bar() -> void:
	if _health_fill == null or _health_label == null:
		return
	var ratio: float = 0.0
	if max_health > 0:
		ratio = float(health) / float(max_health)
	ratio = clamp(ratio, 0.0, 1.0)
	_health_fill.scale = Vector3(ratio, 1.0, 1.0)
	var offset: float = -BAR_WIDTH * 0.5 + BAR_WIDTH * ratio * 0.5
	_health_fill.position = Vector3(offset, 0.0, 0.01)
	_health_label.text = "%s/%s" % [health, max_health]

func _apply_outline(enabled: bool) -> void:
	if _meshes.is_empty():
		return
	if _outline_material == null:
		_outline_material = _get_outline_material()
	for mesh: MeshInstance3D in _meshes:
		var material := mesh.material_override as BaseMaterial3D
		if material == null:
			continue
		material.next_pass = _outline_material if enabled else null

func _get_outline_material() -> ShaderMaterial:
	var shader: Shader = preload("res://shaders/outline.gdshader")
	var material: ShaderMaterial = ShaderMaterial.new()
	material.shader = shader
	material.set_shader_parameter("outline_color", Color(0.0, 0.0, 0.0, 1.0))
	material.set_shader_parameter("outline_size", 0.05)
	return material

func _ensure_animations() -> void:
	if animation_player == null:
		return
	var callback: Callable = _on_animation_finished
	if animation_player.animation_finished.is_connected(callback) == false:
		animation_player.animation_finished.connect(callback)
	var library: AnimationLibrary
	if animation_player.has_animation_library(""):
		library = animation_player.get_animation_library("")
	else:
		library = AnimationLibrary.new()
		animation_player.add_animation_library("", library)
	if not library.has_animation("idle"):
		library.add_animation("idle", _build_idle_animation())
	if not library.has_animation("run"):
		library.add_animation("run", _build_run_animation())
	if not library.has_animation("attack"):
		library.add_animation("attack", _build_attack_animation())

func _build_idle_animation() -> Animation:
	var anim: Animation = Animation.new()
	anim.length = 0.1
	anim.loop_mode = Animation.LOOP_LINEAR
	return anim

func _build_run_animation() -> Animation:
	var anim: Animation = Animation.new()
	anim.length = 0.4
	anim.loop_mode = Animation.LOOP_NONE
	var arm_l: int = anim.add_track(Animation.TYPE_VALUE)
	anim.track_set_path(arm_l, NodePath("Model/ArmL:rotation_degrees"))
	anim.track_insert_key(arm_l, 0.0, Vector3(30.0, 0.0, 0.0))
	anim.track_insert_key(arm_l, 0.2, Vector3(-30.0, 0.0, 0.0))
	anim.track_insert_key(arm_l, 0.4, Vector3(30.0, 0.0, 0.0))
	var arm_r: int = anim.add_track(Animation.TYPE_VALUE)
	anim.track_set_path(arm_r, NodePath("Model/ArmR:rotation_degrees"))
	anim.track_insert_key(arm_r, 0.0, Vector3(-30.0, 0.0, 0.0))
	anim.track_insert_key(arm_r, 0.2, Vector3(30.0, 0.0, 0.0))
	anim.track_insert_key(arm_r, 0.4, Vector3(-30.0, 0.0, 0.0))
	var leg_l: int = anim.add_track(Animation.TYPE_VALUE)
	anim.track_set_path(leg_l, NodePath("Model/LegL:rotation_degrees"))
	anim.track_insert_key(leg_l, 0.0, Vector3(-20.0, 0.0, 0.0))
	anim.track_insert_key(leg_l, 0.2, Vector3(20.0, 0.0, 0.0))
	anim.track_insert_key(leg_l, 0.4, Vector3(-20.0, 0.0, 0.0))
	var leg_r: int = anim.add_track(Animation.TYPE_VALUE)
	anim.track_set_path(leg_r, NodePath("Model/LegR:rotation_degrees"))
	anim.track_insert_key(leg_r, 0.0, Vector3(20.0, 0.0, 0.0))
	anim.track_insert_key(leg_r, 0.2, Vector3(-20.0, 0.0, 0.0))
	anim.track_insert_key(leg_r, 0.4, Vector3(20.0, 0.0, 0.0))
	return anim

func _build_attack_animation() -> Animation:
	var anim: Animation = Animation.new()
	anim.length = 0.3
	anim.loop_mode = Animation.LOOP_NONE
	var arm_r: int = anim.add_track(Animation.TYPE_VALUE)
	anim.track_set_path(arm_r, NodePath("Model/ArmR:rotation_degrees"))
	anim.track_insert_key(arm_r, 0.0, Vector3(0.0, 0.0, 0.0))
	anim.track_insert_key(arm_r, 0.1, Vector3(-70.0, 0.0, 0.0))
	anim.track_insert_key(arm_r, 0.3, Vector3(0.0, 0.0, 0.0))
	return anim

func _on_animation_finished(anim_name: StringName) -> void:
	if anim_name == &"run" or anim_name == &"attack":
		_play_idle()

func _play_idle() -> void:
	if animation_player.has_animation("idle"):
		animation_player.play("idle")
