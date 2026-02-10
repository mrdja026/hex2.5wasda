extends Node3D
class_name HexTerrain

@export var grid_radius: int = 4
@export var tile_size: float = 1.2
@export var tile_height: float = 0.2
@export var base_color: Color = Color(0.18, 0.45, 0.2)
@export var highlight_color: Color = Color(0.12, 0.32, 0.16)
@export var blend_scale: float = 0.6
@export var border_color: Color = Color(0.05, 0.05, 0.05)

var _shader_material: ShaderMaterial
var _tiles: Array[MeshInstance3D] = []

func _ready() -> void:
	build()

func build() -> void:
	_clear_tiles()
	_ensure_material()
	_update_shader_params()

	for q in range(-grid_radius, grid_radius + 1):
		var r_start: int = max(-grid_radius, -q - grid_radius)
		var r_end: int = min(grid_radius, -q + grid_radius)
		for r in range(r_start, r_end + 1):
			var tile: MeshInstance3D = _create_tile()
			tile.position = axial_to_world(Vector2i(q, r))
			add_child(tile)
			_tiles.append(tile)

func axial_to_world(axial: Vector2i) -> Vector3:
	var q: float = float(axial.x)
	var r: float = float(axial.y)
	var x: float = tile_size * 1.5 * q
	var z: float = tile_size * sqrt(3.0) * (r + q * 0.5)
	return Vector3(x, tile_height * 0.5, z)

func axial_distance(a: Vector2i, b: Vector2i) -> int:
	var dq: int = a.x - b.x
	var dr: int = a.y - b.y
	var ds: int = -a.x - a.y - (-b.x - b.y)
	return max(abs(dq), max(abs(dr), abs(ds)))

func world_to_axial(world: Vector3) -> Vector2i:
	var qf: float = (2.0 / 3.0) * world.x / tile_size
	var rf: float = (-1.0 / 3.0) * world.x / tile_size + (sqrt(3.0) / 3.0) * world.z / tile_size
	return _cube_round(qf, rf)

func is_within_bounds(axial: Vector2i) -> bool:
	return axial_distance(Vector2i.ZERO, axial) <= grid_radius

func update_shader_params() -> void:
	_update_shader_params()

func get_all_axials() -> Array[Vector2i]:
	var axials: Array[Vector2i] = []
	for q in range(-grid_radius, grid_radius + 1):
		var r_start: int = max(-grid_radius, -q - grid_radius)
		var r_end: int = min(grid_radius, -q + grid_radius)
		for r in range(r_start, r_end + 1):
			axials.append(Vector2i(q, r))
	return axials

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

func _create_tile() -> MeshInstance3D:
	var mesh: CylinderMesh = CylinderMesh.new()
	mesh.top_radius = tile_size
	mesh.bottom_radius = tile_size
	mesh.height = tile_height
	mesh.radial_segments = 6
	mesh.rings = 1

	var tile: MeshInstance3D = MeshInstance3D.new()
	tile.mesh = mesh
	tile.material_override = _shader_material
	tile.rotation.y = deg_to_rad(30.0)
	var border: MeshInstance3D = _create_border()
	tile.add_child(border)
	return tile

func _ensure_material() -> void:
	if _shader_material:
		return
	var shader: Shader = preload("res://shaders/hex_terrain.gdshader")
	_shader_material = ShaderMaterial.new()
	_shader_material.shader = shader

func _create_border() -> MeshInstance3D:
	var surface: SurfaceTool = SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_LINES)
	surface.set_color(border_color)
	var y: float = tile_height * 0.5 + 0.01
	for i in range(6):
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

func _update_shader_params() -> void:
	if not _shader_material:
		return
	_shader_material.set_shader_parameter("base_color", base_color)
	_shader_material.set_shader_parameter("highlight_color", highlight_color)
	_shader_material.set_shader_parameter("blend_scale", blend_scale)

func _clear_tiles() -> void:
	for tile in _tiles:
		if is_instance_valid(tile):
			tile.queue_free()
	_tiles.clear()
