## Manages the physical game world, including props, terrain blocking, and effects.
# class_name GameWorld
extends Node3D

@onready var _rng: RandomNumberGenerator = RandomNumberGenerator.new()

var terrain: Node3D
var props_container: Node3D

var _blocked_axials: Dictionary = {}
var _prop_labels: Dictionary = {}
var _tree_trunk_material: StandardMaterial3D
var _tree_leaf_material: StandardMaterial3D
var _rock_primary_material: StandardMaterial3D
var _rock_secondary_material: StandardMaterial3D
var _blood_decal_texture: Texture2D

const HEX_DIRECTIONS: Array[Vector2i] = [
	Vector2i(1, 0),
	Vector2i(1, -1),
	Vector2i(0, -1),
	Vector2i(-1, 0),
	Vector2i(-1, 1),
	Vector2i(0, 1)
]

func setup(p_terrain: Node3D, p_props_container: Node3D) -> void:
	terrain = p_terrain
	props_container = p_props_container
	_rng.randomize()

func clear_state() -> void:
	if props_container != null:
		for child: Node in props_container.get_children():
			child.queue_free()
	_prop_labels.clear()
	_blocked_axials.clear()
	register_buffer_tiles()

func register_buffer_tiles() -> void:
	_blocked_axials.clear()
	if terrain == null:
		return
	var buffer_axials: Array = terrain.call("get_buffer_axials")
	for axial: Vector2i in buffer_axials:
		_blocked_axials[axial] = true

func is_blocked(axial: Vector2i, exclude_pos: Vector2i = Vector2i(-999, -999)) -> bool:
	if _blocked_axials.has(axial):
		if exclude_pos == axial:
			return false
		return true
	return false

func set_blocked(axial: Vector2i, blocked: bool) -> void:
	if blocked:
		_blocked_axials[axial] = true
	else:
		_blocked_axials.erase(axial)

func spawn_initial_props(tree_count: int, rock_count: int) -> void:
	if props_container == null or terrain == null:
		return
	var available: Array = terrain.call("get_play_axials")
	var interior: Array[Vector2i] = []
	var play_radius: int = terrain.get("play_radius")
	var interior_radius: int = max(play_radius - 1, 1)
	for axial: Vector2i in available:
		if (terrain.call("axial_distance", Vector2i.ZERO, axial) as int) <= interior_radius:
			interior.append(axial)
	interior.shuffle()
	var counts: Dictionary = {"trees": 0, "rocks": 0}
	var total_props: int = tree_count + rock_count
	var cluster_sizes: Array[int] = _build_cluster_sizes(total_props)
	for cluster_size: int in cluster_sizes:
		if interior.is_empty():
			break
		var center: Vector2i = interior.pop_back()
		_place_prop_cluster(center, cluster_size, interior_radius, counts, tree_count, rock_count)

func spawn_buffer_props(tree_count: int, rock_count: int, max_props: int) -> void:
	if props_container == null or terrain == null:
		return
	var buffer_axials: Array = terrain.call("get_buffer_axials")
	buffer_axials.shuffle()
	var placed_trees: int = 0
	var placed_rocks: int = 0
	var total_allowed: int = min(tree_count + rock_count, max_props)
	for axial: Vector2i in buffer_axials:
		if _prop_labels.has(axial):
			continue
		if placed_trees + placed_rocks >= total_allowed:
			break
		if placed_trees < tree_count and placed_rocks < rock_count:
			if _rng.randi_range(0, 1) == 0:
				_place_buffer_prop(_create_tree(), axial, "Tree")
				placed_trees += 1
			else:
				_place_buffer_prop(_create_rock(), axial, "Rock")
				placed_rocks += 1
			continue
		if placed_trees < tree_count:
			_place_buffer_prop(_create_tree(), axial, "Tree")
			placed_trees += 1
			continue
		if placed_rocks < rock_count:
			_place_buffer_prop(_create_rock(), axial, "Rock")
			placed_rocks += 1

func spawn_death_effect(pos: Vector3) -> void:
	var particles: GPUParticles3D = GPUParticles3D.new()
	particles.one_shot = true
	particles.amount = 24
	particles.lifetime = 0.6
	particles.explosiveness = 0.9
	var process_mat: ParticleProcessMaterial = ParticleProcessMaterial.new()
	process_mat.gravity = Vector3(0.0, -6.0, 0.0)
	process_mat.initial_velocity_min = 2.0
	process_mat.initial_velocity_max = 5.0
	process_mat.direction = Vector3(0.0, 1.0, 0.0)
	process_mat.spread = 45.0
	process_mat.color = Color(0.7, 0.0, 0.0, 1.0)
	particles.process_material = process_mat
	particles.position = pos + Vector3(0.0, 0.5, 0.0)
	add_child(particles)
	particles.emitting = true
	var decal: Decal = Decal.new()
	decal.extents = Vector3(0.6, 0.2, 0.6)
	decal.set_texture(Decal.TEXTURE_ALBEDO, _get_blood_decal_texture())
	decal.position = Vector3(pos.x, 0.05, pos.z)
	add_child(decal)
	get_tree().create_timer(1.0).timeout.connect(func() -> void: if is_instance_valid(particles): particles.queue_free())

func get_adjacent_entity_names(origin: Vector2i, players: Array, exclude: Node) -> Array[String]:
	var names: Array[String] = []
	for other: Node3D in players:
		if other == exclude:
			continue
		if not other.call("is_alive"):
			continue
		var other_axial: Vector2i = other.get("axial_position")
		if (terrain.call("axial_distance", origin, other_axial) as int) == 1:
			names.append("P%s" % other.get("player_id"))
	for axial: Vector2i in _prop_labels:
		if (terrain.call("axial_distance", origin, axial) as int) == 1:
			names.append(_prop_labels[axial] as String)
	names.sort()
	return names

func create_tree() -> Node3D: return _create_tree()
func create_rock() -> Node3D: return _create_rock()

func spawn_network_prop(prop_type: String, axial: Vector2i, is_blocking: bool) -> void:
	if props_container == null or terrain == null:
		return
	if _prop_labels.has(axial):
		return
	var prop: Node3D = _create_tree() if prop_type == "tree" else _create_rock()
	place_prop(prop, axial, false)
	_prop_labels[axial] = "Tree" if prop_type == "tree" else "Rock"
	if is_blocking:
		_blocked_axials[axial] = true

func place_prop(prop: Node3D, axial: Vector2i, randomize_transform: bool) -> void:
	if prop == null or terrain == null: return
	props_container.add_child(prop)
	var height: float = terrain.call("get_tile_height", axial)
	prop.position = terrain.call("axial_to_world", axial, height)
	if randomize_transform:
		prop.rotation.y = deg_to_rad(_rng.randi_range(0, 359))
		prop.scale = Vector3.ONE * _rng.randf_range(0.85, 1.15)
	else:
		prop.rotation = Vector3.ZERO
		prop.scale = Vector3.ONE

func set_prop_label(axial: Vector2i, label: String) -> void:
	_prop_labels[axial] = label

func remove_prop_at(axial: Vector2i) -> void:
	_prop_labels.erase(axial)

func _build_cluster_sizes(total: int) -> Array[int]:
	var sizes: Array[int] = []
	var remaining: int = total
	while remaining > 0:
		var size: int = 3 + _rng.randi_range(0, 2)
		if size > remaining: size = remaining
		sizes.append(size)
		remaining -= size
	return sizes

func _place_prop_cluster(center: Vector2i, size: int, interior_radius: int, counts: Dictionary, max_trees: int, max_rocks: int) -> void:
	var candidates: Array[Vector2i] = [center]
	for direction: Vector2i in HEX_DIRECTIONS:
		candidates.append(center + direction)
	candidates.shuffle()
	var placed: int = 0
	for axial: Vector2i in candidates:
		if placed >= size: break
		if (terrain.call("axial_distance", Vector2i.ZERO, axial) as int) > interior_radius: continue
		if is_blocked(axial): continue
		if (counts["trees"] as int) >= max_trees and (counts["rocks"] as int) >= max_rocks: break
		var place_tree: bool = false
		if (counts["trees"] as int) < max_trees and (counts["rocks"] as int) < max_rocks:
			place_tree = _rng.randi_range(0, 1) == 0
		elif (counts["trees"] as int) < max_trees:
			place_tree = true
		if place_tree:
			place_prop(_create_tree(), axial, true)
			_prop_labels[axial] = "Tree"
			counts["trees"] = (counts["trees"] as int) + 1
		else:
			place_prop(_create_rock(), axial, true)
			_prop_labels[axial] = "Rock"
			counts["rocks"] = (counts["rocks"] as int) + 1
		_blocked_axials[axial] = true
		placed += 1

func _place_buffer_prop(prop: Node3D, axial: Vector2i, label: String) -> void:
	if prop == null: return
	place_prop(prop, axial, true)
	_prop_labels[axial] = label

func _create_tree() -> Node3D:
	var tree: Node3D = Node3D.new()
	var trunk_mesh: CylinderMesh = CylinderMesh.new()
	trunk_mesh.top_radius = 0.12
	trunk_mesh.bottom_radius = 0.18
	trunk_mesh.height = 1.0
	trunk_mesh.radial_segments = 6
	var trunk: MeshInstance3D = MeshInstance3D.new()
	trunk.mesh = trunk_mesh
	trunk.material_override = _get_tree_trunk_material()
	trunk.position = Vector3(0, 0.5, 0)
	tree.add_child(trunk)
	var tier_count: int = 4 + _rng.randi_range(0, 3)
	for i: int in range(tier_count):
		var tier_mesh: CylinderMesh = CylinderMesh.new()
		var tier_height: float = 0.18 + float(i) * 0.02
		var tier_radius: float = 0.55 - float(i) * 0.07
		tier_mesh.height = tier_height
		tier_mesh.top_radius = tier_radius * 0.18
		tier_mesh.bottom_radius = tier_radius
		tier_mesh.radial_segments = 6
		var tier: MeshInstance3D = MeshInstance3D.new()
		tier.mesh = tier_mesh
		tier.material_override = _get_tree_leaf_material()
		tier.position = Vector3(0.0, 0.9 + float(i) * 0.18, 0.0)
		tier.rotation.y = deg_to_rad(_rng.randi_range(0, 359))
		tree.add_child(tier)
	return tree

func _create_rock() -> Node3D:
	var rock: Node3D = Node3D.new()
	var shard_count: int = 2 + _rng.randi_range(0, 4)
	for i: int in range(shard_count):
		var shard_mesh: CylinderMesh = CylinderMesh.new()
		var h: float = 0.45 + _rng.randf_range(0.0, 0.45)
		var r: float = 0.18 + _rng.randf_range(0.0, 0.12)
		shard_mesh.top_radius = r * 0.1
		shard_mesh.bottom_radius = r
		shard_mesh.height = h
		shard_mesh.radial_segments = 6
		var shard: MeshInstance3D = MeshInstance3D.new()
		shard.mesh = shard_mesh
		shard.material_override = _get_rock_secondary_material() if _rng.randi_range(0, 4) == 0 else _get_rock_primary_material()
		shard.position = Vector3(_rng.randf_range(-0.25, 0.25), h * 0.5, _rng.randf_range(-0.25, 0.25))
		shard.rotation_degrees = Vector3(_rng.randf_range(-12.0, 12.0), _rng.randf_range(0.0, 360.0), _rng.randf_range(-12.0, 12.0))
		rock.add_child(shard)
	return rock

func _get_tree_trunk_material() -> StandardMaterial3D:
	if _tree_trunk_material == null:
		_tree_trunk_material = StandardMaterial3D.new()
		_tree_trunk_material.albedo_color = Color(0.35, 0.22, 0.12)
	return _tree_trunk_material

func _get_tree_leaf_material() -> StandardMaterial3D:
	if _tree_leaf_material == null:
		_tree_leaf_material = StandardMaterial3D.new()
		_tree_leaf_material.albedo_color = Color(0.14, 0.36, 0.2)
	return _tree_leaf_material

func _get_rock_primary_material() -> StandardMaterial3D:
	if _rock_primary_material == null:
		_rock_primary_material = StandardMaterial3D.new()
		_rock_primary_material.albedo_color = Color(0.36, 0.33, 0.3)
		_rock_primary_material.roughness = 0.95
	return _rock_primary_material

func _get_rock_secondary_material() -> StandardMaterial3D:
	if _rock_secondary_material == null:
		_rock_secondary_material = StandardMaterial3D.new()
		_rock_secondary_material.albedo_color = Color(0.28, 0.25, 0.22)
		_rock_secondary_material.roughness = 0.98
	return _rock_secondary_material

func _get_blood_decal_texture() -> Texture2D:
	if _blood_decal_texture != null: return _blood_decal_texture
	var size: int = 64
	var image: Image = Image.create(size, size, false, Image.FORMAT_RGBA8)
	image.fill(Color(0,0,0,0))
	var center: Vector2 = Vector2(size * 0.5, size * 0.5)
	var base_r: float = size * 0.35
	for y: int in range(size):
		for x: int in range(size):
			var dist: float = center.distance_to(Vector2(x, y))
			var r: float = base_r + _rng.randf_range(-3.0, 3.0)
			if dist <= r:
				var alpha: float = (1.0 - dist / r) * _rng.randf_range(0.6, 1.0)
				image.set_pixel(x, y, Color(0.5, 0, 0, alpha))
	_blood_decal_texture = ImageTexture.create_from_image(image)
	return _blood_decal_texture
