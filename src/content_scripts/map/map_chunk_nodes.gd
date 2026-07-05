class_name MapChunkNodes
extends StaticBody3D

const MAP_SCENE: PackedScene = preload("uid://buljw4afjva1d")

@export var mesh_instance: MeshInstance3D
@export var collision_shape: CollisionShape3D
@export var map_shader: Shader
var map_data: MapData


static func instantiate() -> MapChunkNodes:
	return MAP_SCENE.instantiate()


func play_animations(local_map_data: MapData) -> void:
	if local_map_data.texture_animations.is_empty():
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
	
	var texture_size: Vector2 = GameData.get_texture(local_map_data.unique_name).get_size()
	# var num_palettes: float = 16.0
	for anim_id: int in num_texture_animations:
		var texture_animation: TextureAnimation = local_map_data.texture_animations[anim_id]
		if texture_animation.animation_type == TextureAnimation.AnimType.UV:
			canvas_positions[anim_id] = Vector2(texture_animation.canvas_position.x / texture_size.x, 
					(texture_animation.canvas_position.y) / texture_size.y)
			canvas_sizes[anim_id] = Vector2(texture_animation.canvas_size.x / texture_size.x,
					texture_animation.canvas_size.y / texture_size.y)
			frame_positions[anim_id] = Vector2(texture_animation.frame1_position.x / texture_size.x, 
					(texture_animation.frame1_position.y) / texture_size.y)
	
	var map_shader_material: ShaderMaterial = mesh_instance.material_override as ShaderMaterial
	map_shader_material.set_shader_parameter("canvas_pos", canvas_positions)
	map_shader_material.set_shader_parameter("canvas_size", canvas_sizes)
	map_shader_material.set_shader_parameter("frame_pos", frame_positions)
	map_shader_material.set_shader_parameter("frame_idx", frame_idxs)
	
	# start animations
	var anim_fps: float = 59.0 # TODO why does 59 look too fast?
	for anim_id: int in num_texture_animations:
		var texture_animation: TextureAnimation = local_map_data.texture_animations[anim_id]
		if texture_animation.is_script_animation:
			continue
		if texture_animation.animation_type == TextureAnimation.AnimType.PALETTE: # if palette animation
			local_map_data.animate_palette(texture_animation, self, anim_fps)
		elif texture_animation.animation_type == TextureAnimation.AnimType.UV: # if uv animation
			local_map_data.animate_uv(texture_animation, self, anim_id, anim_fps)


func set_mesh_shader(texture: Texture2D, texture_palettes: PackedColorArray, terrain_tiles: Array[TerrainTile]) -> void:
	var new_mesh_material: ShaderMaterial = ShaderMaterial.new()
	new_mesh_material.shader = map_shader
	new_mesh_material.set_shader_parameter("albedo_texture_color_indicies", texture)
	new_mesh_material.set_shader_parameter("palettes_colors", texture_palettes)
	
	var tiles_center: Vector2 = MapData.get_tiles_center(terrain_tiles.filter(func(tile: TerrainTile) -> bool: return tile.no_walk == 0))
	tiles_center += (Vector2.ONE * 0.5)
	new_mesh_material.set_shader_parameter("center_xy", tiles_center)
	mesh_instance.material_override = new_mesh_material
