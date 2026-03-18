class_name TrapMeshPool
extends Node3D
## Manages MeshInstance3D pool lifecycle for TRAP particle rendering.

const POOL_INITIAL_SIZE: int = 512
const POOL_GROWTH: int = 128
const OFFSCREEN_POS := Vector3(0, -10000, 0)

var meshes: Array[MeshInstance3D] = []
var materials: Array[ShaderMaterial] = []
var particle_mesh_map: Dictionary[int, PackedInt32Array] = {} # uid -> PackedInt32Array
var opaque_shader: Shader
var blend_shaders: Array[Shader] = []
var texture_size: Vector2 = Vector2(256, 144)

var _shared_quad: QuadMesh
var _pool_size: int = 0
var _free_mesh_indices: Array[int] = []
var _palette_textures: Dictionary[int, Texture2D] = {} # palette_id -> Texture2D
var _z_bias: float = 0.001
var is_initialized: bool = false


func initialize() -> void:
	var trap_data: TrapEffectData = RomReader.trap_effect_data
	if trap_data.texture == null:
		return

	_shared_quad = QuadMesh.new()
	_shared_quad.size = Vector2(1.0, 1.0)

	opaque_shader = preload("res://src/file_formats/vfx/shaders/effect_particle_opaque.gdshader")
	blend_shaders = [
		preload("res://src/file_formats/vfx/shaders/effect_particle_mode0.gdshader"),
		preload("res://src/file_formats/vfx/shaders/effect_particle_mode1.gdshader"),
		preload("res://src/file_formats/vfx/shaders/effect_particle_mode2.gdshader"),
		preload("res://src/file_formats/vfx/shaders/effect_particle_mode3.gdshader"),
	]

	texture_size = Vector2(trap_data.trap_spr.width, trap_data.trap_spr.height)
	_palette_textures[0] = trap_data.texture

	_grow_pool(POOL_INITIAL_SIZE)
	_free_mesh_indices.clear()
	for i in range(_pool_size):
		_free_mesh_indices.append(i)

	is_initialized = true


func set_z_bias(value: float) -> void:
	_z_bias = value
	for mat: ShaderMaterial in materials:
		mat.set_shader_parameter("z_bias", value)


func get_palette_texture(palette_id: int) -> Texture2D:
	if _palette_textures.has(palette_id):
		return _palette_textures[palette_id]
	var trap_data: TrapEffectData = RomReader.trap_effect_data
	var tex: Texture2D = trap_data.get_palette_texture(palette_id)
	_palette_textures[palette_id] = tex
	return tex


func borrow_mesh_index() -> int:
	if _free_mesh_indices.is_empty():
		var old_size: int = _pool_size
		_grow_pool(_pool_size + POOL_GROWTH)
		for i in range(old_size, _pool_size):
			_free_mesh_indices.append(i)
	return _free_mesh_indices.pop_back()


func return_mesh(mi: int) -> void:
	meshes[mi].visible = false
	meshes[mi].position = OFFSCREEN_POS
	_free_mesh_indices.append(mi)


func release_all_meshes() -> void:
	for uid: int in particle_mesh_map:
		var mesh_indices: PackedInt32Array = particle_mesh_map[uid]
		for mi in mesh_indices:
			return_mesh(mi)
	particle_mesh_map.clear()


func _grow_pool(new_size: int) -> void:
	if new_size <= _pool_size:
		return
	for _i in range(new_size - _pool_size):
		var mesh_instance := MeshInstance3D.new()
		mesh_instance.mesh = _shared_quad
		mesh_instance.visible = false
		mesh_instance.position = OFFSCREEN_POS

		var mat := ShaderMaterial.new()
		mat.shader = opaque_shader
		mat.render_priority = 1
		mat.set_shader_parameter("z_bias", _z_bias)
		if not _palette_textures.is_empty():
			mat.set_shader_parameter("effect_texture", _palette_textures[0])
			mat.set_shader_parameter("texture_size", texture_size)
		mesh_instance.material_override = mat
		materials.append(mat)

		add_child(mesh_instance)
		meshes.append(mesh_instance)
	_pool_size = new_size
