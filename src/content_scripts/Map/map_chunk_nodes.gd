class_name MapChunkNodes
extends StaticBody3D

const map_scene: PackedScene = preload("res://src/content_scripts/Map/map_chunk_nodes.tscn")

@export var mesh_instance: MeshInstance3D
@export var collision_shape: CollisionShape3D
@export var map_shader: Shader
var map_data: MapData


static func instantiate() -> MapChunkNodes:
	return map_scene.instantiate()


func play_animations(local_map_data: MapData) -> void:
	if not local_map_data.has_texture_animations:
		return
	
	# set up shader parameters for uv_animations
	var canvas_positions: PackedVector2Array = []
	var canvas_sizes: PackedVector2Array = []
	var frame_positions: PackedVector2Array = []
	var frame_idxs: PackedFloat32Array = []
	
	var num_texture_animations: int = local_map_data.texture_animations.size()
	canvas_positions.resize(num_texture_animations)
	canvas_sizes.resize(num_texture_animations)
	frame_positions.resize(num_texture_animations)
	frame_idxs.resize(num_texture_animations)
	
	var num_palettes: float = 16.0
	for anim_id: int in num_texture_animations:
		if [0x01, 0x02, 0x05, 0x15].has(local_map_data.texture_animations[anim_id].anim_technique):
			canvas_positions[anim_id] = Vector2(local_map_data.texture_animations[anim_id].canvas_x / float(MapData.TEXTURE_SIZE.x * num_palettes), 
					(local_map_data.texture_animations[anim_id].canvas_y + (256 * local_map_data.texture_animations[anim_id].texture_page)) / float(MapData.TEXTURE_SIZE.y))
			canvas_sizes[anim_id] = Vector2(local_map_data.texture_animations[anim_id].canvas_width / float(MapData.TEXTURE_SIZE.x * num_palettes),
					local_map_data.texture_animations[anim_id].canvas_height / float(MapData.TEXTURE_SIZE.y))
			frame_positions[anim_id] = Vector2(local_map_data.texture_animations[anim_id].frame1_x / float(MapData.TEXTURE_SIZE.x * num_palettes), 
					(local_map_data.texture_animations[anim_id].frame1_y + (256 * local_map_data.texture_animations[anim_id].frame1_texture_page)) / float(MapData.TEXTURE_SIZE.y))
	
	var map_shader_material: ShaderMaterial = mesh_instance.material_override as ShaderMaterial
	map_shader_material.set_shader_parameter("canvas_pos", canvas_positions)
	map_shader_material.set_shader_parameter("canvas_size", canvas_sizes)
	map_shader_material.set_shader_parameter("frame_pos", frame_positions)
	map_shader_material.set_shader_parameter("frame_idx", frame_idxs)
	
	# start animations
	var anim_fps: float = 45.0 # TODO why does 59 look too fast?
	for anim_id: int in num_texture_animations:
		if [0x03, 0x04].has(local_map_data.texture_animations[anim_id].anim_technique): # if palette animation
			local_map_data.animate_palette(local_map_data.texture_animations[anim_id], self, anim_fps)
		elif [0x01, 0x02].has(local_map_data.texture_animations[anim_id].anim_technique): # if uv animation
			local_map_data.animate_uv(local_map_data.texture_animations[anim_id], self, anim_id, anim_fps)


func set_mesh_shader(texture: Texture2D, texture_palettes: PackedColorArray) -> void:
	var new_mesh_material: ShaderMaterial = ShaderMaterial.new()
	new_mesh_material.shader = map_shader
	new_mesh_material.set_shader_parameter("albedo_texture_color_indicies", texture)
	new_mesh_material.set_shader_parameter("palettes_colors", texture_palettes)
	mesh_instance.material_override = new_mesh_material
