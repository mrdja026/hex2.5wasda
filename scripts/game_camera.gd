## Manages the camera's movement, zooming, and positioning.
class_name GameCamera
extends Node

var camera: Camera3D
var pan_speed: float = 0.03
var zoom_step: float = 1.0
var zoom_min: float = 8.0
var zoom_max: float = 40.0

var _camera_forward: Vector3 = Vector3.ZERO
var _camera_focus_distance: float = 0.0

func setup(p_camera: Camera3D, island_center: Vector3) -> void:
	camera = p_camera
	_cache_offset(island_center)

func pan(delta: Vector2) -> void:
	if camera == null: return
	var right: Vector3 = camera.global_transform.basis.x
	var forward: Vector3 = -camera.global_transform.basis.z
	right.y = 0.0
	forward.y = 0.0
	var move: Vector3 = (right.normalized() * delta.x + forward.normalized() * delta.y) * pan_speed
	camera.global_position += move

func zoom(delta: float) -> void:
	if camera == null: return
	camera.size = clamp(camera.size + delta, zoom_min, zoom_max)

func focus_on_position(world_pos: Vector3) -> void:
	if camera == null: return
	camera.global_position = world_pos + _camera_forward * _camera_focus_distance

func _cache_offset(island_center: Vector3) -> void:
	if camera == null: return
	_camera_forward = -camera.global_transform.basis.z.normalized()
	_camera_focus_distance = (camera.global_position - island_center).dot(_camera_forward)
