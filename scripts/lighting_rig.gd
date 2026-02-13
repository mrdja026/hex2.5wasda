## Manages the lighting setup, including a directional light and a point light.
class_name LightingRig
extends Node3D

@export var directional_color: Color = Color(1.0, 0.98, 0.95)
@export var directional_intensity: float = 1.2
@export var directional_rotation_degrees: Vector3 = Vector3(-45.0, 45.0, 0.0)

@export var point_color: Color = Color(0.9, 0.95, 1.0)
@export var point_intensity: float = 1.8
@export var point_position: Vector3 = Vector3(0.0, 6.0, 0.0)

@onready var directional_light: DirectionalLight3D = $DirectionalLight3D
@onready var point_light: OmniLight3D = $OmniLight3D

func _ready() -> void:
	apply_lighting()

func apply_lighting() -> void:
	if directional_light:
		directional_light.light_color = directional_color
		directional_light.light_energy = directional_intensity
		directional_light.rotation_degrees = directional_rotation_degrees
	if point_light:
		point_light.light_color = point_color
		point_light.light_energy = point_intensity
		point_light.position = point_position
