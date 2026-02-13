## Manages the hexagonal terrain generation, materials, and coordinate conversion.
class_name HexTerrain
extends Node3D

@export var play_radius: int = 32
@export var buffer_thickness: int = 0
@export var board_width: int = 10
@export var board_height: int = 10
@export var tile_size: float = 1.2
@export var tile_height: float = 0.2
@export var mountain_height_multiplier: float = 2.8
@export var base_color: Color = Color(0.18, 0.45, 0.2)
@export var highlight_color: Color = Color(0.12, 0.32, 0.16)
@export var blend_scale: float = 0.6
@export var detail_scale: float = 1.2
@export var detail_strength: float = 0.18
@export var mountain_base_color: Color = Color(0.2, 0.22, 0.24)
@export var mountain_highlight_color: Color = Color(0.33, 0.34, 0.36)
@export var mountain_blend_scale: float = 1.1
@export var mountain_detail_scale: float = 2.2
@export var mountain_detail_strength: float = 0.35
@export var border_color: Color = Color(0.05, 0.05, 0.05)
@export var mountain_border_color: Color = Color(0.15, 0.15, 0.15)
@export var mountain_peak_color: Color = Color(0.3, 0.3, 0.32)
@export var mountain_peak_secondary_color: Color = Color(0.24, 0.25, 0.28)

var _terrain_material: ShaderMaterial
var _mountain_material: ShaderMaterial
var _mountain_peak_material: StandardMaterial3D
var _mountain_peak_secondary_material: StandardMaterial3D
var _tiles: Array[MeshInstance3D] = []
var _play_axials: Array[Vector2i] = []
var _buffer_axials: Array[Vector2i] = []
var _play_axial_lookup: Dictionary = {}
var _total_radius: int = 0

func _ready() -> void:
	pass

func build() -> void:
	_clear_tiles()
	_ensure_materials()
	_update_shader_params()
	_total_radius = _get_total_radius()
	_play_axials.clear()
	_buffer_axials.clear()
	_play_axial_lookup.clear()

	for row: int in range(board_height):
		for col: int in range(board_width):
			var axial: Vector2i = _offset_to_centered_axial(col, row)
			var height: float = tile_height
			var tile: MeshInstance3D = _create_tile(false, axial, height)
			tile.position = axial_to_world(axial, height)
			add_child(tile)
			_tiles.append(tile)
			_play_axials.append(axial)
			_play_axial_lookup[axial] = true

func configure_from_backend_map(map_data: Dictionary) -> void:
	var width: int = int(map_data.get("width", board_width))
	var height: int = int(map_data.get("height", board_height))
	if width <= 0:
		width = 10
	if height <= 0:
		height = 10
	if board_width == width and board_height == height and not _tiles.is_empty():
		return
	board_width = width
	board_height = height
	build()

func axial_to_world(axial: Vector2i, height: float = tile_height) -> Vector3:
	var q: float = float(axial.x)
	var r: float = float(axial.y)
	var x: float = tile_size * 1.5 * q
	var z: float = tile_size * sqrt(3.0) * (r + q * 0.5)
	return Vector3(x, height * 0.5, z)

func axial_distance(a: Vector2i, b: Vector2i) -> int:
	var dq: int = a.x - b.x
	var dr: int = a.y - b.y
	var ds: int = -a.x - a.y - (-b.x - b.y)
	return max(abs(dq), max(abs(dr), abs(ds)))

func world_to_axial(world_pos: Vector3) -> Vector2i:
	var qf: float = (2.0 / 3.0) * world_pos.x / tile_size
	var rf: float = (-1.0 / 3.0) * world_pos.x / tile_size + (sqrt(3.0) / 3.0) * world_pos.z / tile_size
	return _cube_round(qf, rf)

func is_within_bounds(axial: Vector2i) -> bool:
	return _play_axial_lookup.has(axial)

func is_within_play_area(axial: Vector2i) -> bool:
	return is_within_bounds(axial)

func update_shader_params() -> void:
	_update_shader_params()

func get_all_axials() -> Array[Vector2i]:
	var axials: Array[Vector2i] = _play_axials.duplicate()
	axials.append_array(_buffer_axials)
	return axials

func get_play_axials() -> Array[Vector2i]:
	return _play_axials.duplicate()

func get_buffer_axials() -> Array[Vector2i]:
	return _buffer_axials.duplicate()

func get_tile_height(axial: Vector2i) -> float:
	if buffer_thickness > 0 and axial_distance(Vector2i.ZERO, axial) > play_radius:
		return tile_height * mountain_height_multiplier
	return tile_height

func _offset_to_centered_axial(col: int, row: int) -> Vector2i:
	var q: int = col - int((row - (row & 1)) / 2)
	var r: int = row
	var center_col: int = int(board_width / 2)
	var center_row: int = int(board_height / 2)
	var center_q: int = center_col - int((center_row - (center_row & 1)) / 2)
	var center_r: int = center_row
	return Vector2i(q - center_q, r - center_r)

func _cube_round(qf: float, rf: float) -> Vector2i:
	var sf: float = -qf - rf
	var qi: int = int(round(qf))
	var ri: int = int(round(rf))
	var si: int = int(round(sf))
	var q_diff: float = abs(float(qi) - qf)
	var r_diff: float = abs(float(ri) - rf)
	var s_diff: float = abs(float(si) - sf)
	if q_diff > r_diff and q_diff > s_diff:
		qi = -ri - si
	elif r_diff > s_diff:
		ri = -qi - si
	return Vector2i(qi, ri)

func _create_tile(is_buffer: bool, _axial: Vector2i, height: float) -> MeshInstance3D:
	var mesh: CylinderMesh = CylinderMesh.new()
	mesh.top_radius = tile_size
	mesh.bottom_radius = tile_size
	mesh.height = height
	mesh.radial_segments = 6
	mesh.rings = 1

	var tile: MeshInstance3D = MeshInstance3D.new()
	tile.mesh = mesh
	tile.material_override = _mountain_material if is_buffer else _terrain_material
	tile.rotation.y = deg_to_rad(30.0)
	var border: MeshInstance3D = _create_border(is_buffer, height)
	tile.add_child(border)
	if is_buffer:
		_add_mountain_detail(tile, _axial, height)
	return tile

func _ensure_materials() -> void:
	var shader: Shader = preload("res://shaders/hex_terrain.gdshader")
	if _terrain_material == null:
		_terrain_material = ShaderMaterial.new()
		_terrain_material.shader = shader
	if _mountain_material == null:
		_mountain_material = ShaderMaterial.new()
		_mountain_material.shader = shader
	if _mountain_peak_material == null:
		_mountain_peak_material = StandardMaterial3D.new()
		_mountain_peak_material.roughness = 0.9
	if _mountain_peak_secondary_material == null:
		_mountain_peak_secondary_material = StandardMaterial3D.new()
		_mountain_peak_secondary_material.roughness = 0.95
	_mountain_peak_material.albedo_color = mountain_peak_color
	_mountain_peak_secondary_material.albedo_color = mountain_peak_secondary_color

func _create_border(is_buffer: bool, height: float) -> MeshInstance3D:
	var surface: SurfaceTool = SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_LINES)
	surface.set_color(mountain_border_color if is_buffer else border_color)
	var y: float = height * 0.5 + 0.01
	for i: int in range(6):
		var angle: float = deg_to_rad(60.0 * float(i))
		var next_angle: float = deg_to_rad(60.0 * float(i + 1))
		var a: Vector3 = Vector3(cos(angle), y, sin(angle)) * tile_size
		var b: Vector3 = Vector3(cos(next_angle), y, sin(next_angle)) * tile_size
		surface.add_vertex(a)
		surface.add_vertex(b)
	var mesh: ArrayMesh = surface.commit()
	var border: MeshInstance3D = MeshInstance3D.new()
	border.mesh = mesh
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.vertex_color_use_as_albedo = true
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	border.material_override = material
	border.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return border

func _add_mountain_detail(tile: MeshInstance3D, axial: Vector2i, height: float) -> void:
	if tile == null:
		return
	var main_peak: MeshInstance3D = _create_mountain_peak(axial, height, 1, false)
	tile.add_child(main_peak)
	if _hash01(axial, 4) > 0.35:
		var secondary_peak: MeshInstance3D = _create_mountain_peak(axial, height, 2, true)
		tile.add_child(secondary_peak)

func _create_mountain_peak(axial: Vector2i, base_height: float, seed_val: int, secondary: bool) -> MeshInstance3D:
	var mesh: CylinderMesh = CylinderMesh.new()
	var scale_val: float = lerp(0.65, 1.0, _hash01(axial, seed_val))
	var radius: float = tile_size * (0.3 if secondary else 0.5) * scale_val
	var height: float = tile_size * (0.65 if secondary else 1.05) * (0.8 + 0.4 * _hash01(axial, seed_val + 11))
	mesh.top_radius = 0.0
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.radial_segments = 6
	var peak: MeshInstance3D = MeshInstance3D.new()
	peak.mesh = mesh
	peak.material_override = _mountain_peak_secondary_material if secondary else _mountain_peak_material
	var offset: Vector3 = _peak_offset(axial, seed_val, tile_size * 0.25)
	peak.position = Vector3(offset.x, base_height * 0.5 + height * 0.5, offset.z)
	peak.rotation.y = deg_to_rad(_hash01(axial, seed_val + 31) * 360.0)
	return peak

func _peak_offset(axial: Vector2i, seed_val: int, max_offset: float) -> Vector3:
	var ox: float = (_hash01(axial, seed_val + 101) * 2.0 - 1.0) * max_offset
	var oz: float = (_hash01(axial, seed_val + 202) * 2.0 - 1.0) * max_offset
	return Vector3(ox, 0.0, oz)

func _hash01(axial: Vector2i, seed_val: int) -> float:
	var n: float = float(axial.x * 127.1 + axial.y * 311.7 + seed_val * 74.7)
	var s: float = sin(n) * 43758.5453
	return s - floor(s)

func _update_shader_params() -> void:
	_apply_shader_params(_terrain_material, base_color, highlight_color, blend_scale, detail_scale, detail_strength)
	_apply_shader_params(_mountain_material, mountain_base_color, mountain_highlight_color, mountain_blend_scale, mountain_detail_scale, mountain_detail_strength)

func _apply_shader_params(material: ShaderMaterial, base: Color, highlight: Color, blend: float, detail: float, strength: float) -> void:
	if material == null:
		return
	material.set_shader_parameter("base_color", base)
	material.set_shader_parameter("highlight_color", highlight)
	material.set_shader_parameter("blend_scale", blend)
	material.set_shader_parameter("detail_scale", detail)
	material.set_shader_parameter("detail_strength", strength)

func _clear_tiles() -> void:
	for tile: MeshInstance3D in _tiles:
		if is_instance_valid(tile):
			tile.queue_free()
	_tiles.clear()
	_play_axials.clear()
	_buffer_axials.clear()
	_play_axial_lookup.clear()

func _get_total_radius() -> int:
	return max(play_radius, 0)
