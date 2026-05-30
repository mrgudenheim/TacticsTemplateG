class_name MapData
extends Resource

@export var unique_name: String = ""
@export var display_name: String = "[map display name]"
@export var description: String = "[map description]"

@export var terrain_tiles: Array[TerrainTile] = []
@export var palettes: PackedColorArray = []
@export var texture_animations: Array[TextureAnimation] = []
@export var palette_animation_frames: Array[PackedColorArray] = []

var mesh: Mesh

static func init_from_fft_map_data(fft_map_data: FftMapData) -> MapData:
	var new_map_data: MapData = MapData.new()
	
	new_map_data.unique_name = fft_map_data.unique_name
	new_map_data.display_name = fft_map_data.display_name
	new_map_data.description = fft_map_data.description
	
	new_map_data.terrain_tiles = fft_map_data.terrain_tiles.duplicate(true)
	new_map_data.palettes = fft_map_data.texture_palettes.duplicate()
	for fft_texture_animation: FftMapData.TextureAnimationData in fft_map_data.texture_animations:
		var new_texture_anim: TextureAnimation = TextureAnimation.new(fft_texture_animation)
		if new_texture_anim.animation_type == TextureAnimation.AnimType.OTHER:
			continue
		new_map_data.texture_animations.append(new_texture_anim)
	
	new_map_data.palette_animation_frames = fft_map_data.texture_animations_palette_frames.duplicate()

	return new_map_data


func animate_palette(texture_anim: TextureAnimation, map: MapChunkNodes, anim_fps: float) -> void:
	var frame_id: int = 0
	var dir: int = 1
	var colors_per_palette: int = 16

	var map_shader_material: ShaderMaterial = map.mesh_instance.material_override as ShaderMaterial
	while frame_id < texture_anim.num_frames:
		if not is_instance_valid(map):
			break

		var new_anim_palette_id: int = frame_id + texture_anim.animation_starting_index
		var new_palette: PackedColorArray = palette_animation_frames[new_anim_palette_id]
		var new_texture_palette: PackedColorArray = map_shader_material.get_shader_parameter("palettes_colors")
		for color_id: int in colors_per_palette:
			new_texture_palette[color_id + (texture_anim.palette_id_to_animate * colors_per_palette)] = new_palette[color_id]
		map_shader_material.set_shader_parameter("palettes_colors", new_texture_palette)

		#map.mesh.mesh = mesh
		await Engine.get_main_loop().create_timer(texture_anim.frame_duration / anim_fps).timeout
		if texture_anim.anim_technique == 0x3: # loop forward
			frame_id += dir
			frame_id = frame_id % texture_anim.num_frames
		elif texture_anim.anim_technique == 0x4: # loop back and forth
			if frame_id == texture_anim.num_frames - 1:
				dir = -1
			elif frame_id == 0:
				dir = 1
			frame_id += dir


func animate_uv(texture_anim: TextureAnimation, map: MapChunkNodes, anim_idx: int, anim_fps: float) -> void:
	var frame_id: int = 0
	var dir: int = 1

	var map_shader_material: ShaderMaterial = map.mesh_instance.material_override as ShaderMaterial
	while frame_id < texture_anim.num_frames:
		if not is_instance_valid(map):
			break

		var frame_idxs: PackedFloat32Array = map_shader_material.get_shader_parameter("frame_idx")
		frame_idxs[anim_idx] = float(frame_id)
		map_shader_material.set_shader_parameter("frame_idx", frame_idxs)

		await Engine.get_main_loop().create_timer(texture_anim.frame_duration / anim_fps).timeout
		if texture_anim.anim_technique == 0x1: # loop forward
			frame_id += dir
			frame_id = frame_id % texture_anim.num_frames
		elif texture_anim.anim_technique == 0x2: # loop back and forth
			if frame_id == texture_anim.num_frames - 1:
				dir = -1
			elif frame_id == 0:
				dir = 1
			frame_id += dir


func get_transformed_tiles(translation: Vector2 = Vector2.ZERO, scale: Vector2 = Vector2.ONE, rotation_degrees: float = 0.0) -> Array[TerrainTile]:
	var mirrored_tiles: Array[TerrainTile] = []
	var min_tile_location: Vector2i = Vector2i.ZERO
	var max_tile_location: Vector2i = Vector2i.ZERO
	for tile: TerrainTile in terrain_tiles:
		if tile.location.x > max_tile_location.x:
			max_tile_location.x = tile.location.x
		if tile.location.y > max_tile_location.y:
			max_tile_location.y = tile.location.y
		
		if tile.location.x < min_tile_location.x:
			min_tile_location.x = tile.location.x
		if tile.location.y < min_tile_location.y:
			min_tile_location.y = tile.location.y
	
	var tiles_center: Vector2 = (max_tile_location -  min_tile_location) / 2.0
	
	var tile_transform: Transform2D = Transform2D.IDENTITY
	tile_transform = tile_transform.translated(-tiles_center)
	tile_transform = tile_transform.rotated(deg_to_rad(rotation_degrees))
	tile_transform = tile_transform.scaled(scale)
	tile_transform = tile_transform.translated(tiles_center + translation)
	
	for tile: TerrainTile in terrain_tiles:
		if tile.no_cursor == 1:
			continue

		var transformed_tile: TerrainTile = tile.duplicate()
		transformed_tile.location = Vector2i((tile_transform * Vector2(tile.location)).round())
		transformed_tile.tile_scale.x *= scale.x
		transformed_tile.tile_scale.z *= scale.y
		transformed_tile.rotation_degrees += rotation_degrees
		# transformed_tile.height_mid = transformed_tile.height_bottom + (transformed_tile.slope_height / 2.0)
		mirrored_tiles.append(transformed_tile)
	
	return mirrored_tiles


class TextureAnimationData:
	var texture_anim_instruction_bytes: PackedByteArray = []
	var animation_type: int = -1 # error
	var canvas_y: int
	var canvas_width: int
	var canvas_height: int
	var frame1_y: int
	# UV animation: 0x01 repeat loop forward, 0x02 loop ping pong forward <-> backward, 0x05 script command, 0x15 script command
	# palette animation: 0x03 repeat loop forward, 0x04 loop ping pong forward <-> backward, 0x00 script command, 0x13 script command
	var anim_technique: int
	var num_frames: int
	var frame_duration: int # 1/30ths of a second (ie. 2 frames)
	var texture_page: int
	var canvas_x: int
	var frame1_texture_page: int
	var frame1_x: int
	var palette_id_to_animate: int
	var animation_starting_index: int
