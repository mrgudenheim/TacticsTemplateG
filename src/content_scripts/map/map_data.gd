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
		await Engine.get_main_loop().create_timer(texture_anim.frame_duration * 30 / anim_fps).timeout
		if texture_anim.anim_technique == TextureAnimation.AnimTechnique.LOOP_FORWARD:
			frame_id += dir
			frame_id = frame_id % texture_anim.num_frames
		elif texture_anim.anim_technique == TextureAnimation.AnimTechnique.LOOP_PING_PONG: # loop back and forth
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

		await Engine.get_main_loop().create_timer(texture_anim.frame_duration * 30 / anim_fps).timeout
		if texture_anim.anim_technique == TextureAnimation.AnimTechnique.LOOP_FORWARD: # loop forward
			frame_id += dir
			frame_id = frame_id % texture_anim.num_frames
		elif texture_anim.anim_technique == TextureAnimation.AnimTechnique.LOOP_PING_PONG: # loop back and forth
			if frame_id == texture_anim.num_frames - 1:
				dir = -1
			elif frame_id == 0:
				dir = 1
			frame_id += dir


## flags polygons in map mesh to hide (by shader) when they are closer to the camera)
## primarily used for walls
func flag_polygons_to_hide() -> void:
	# var move_tiles: Array[TerrainTile] = terrain_tiles.filter(func(tile: TerrainTile) -> bool: return tile.no_walk or tile.no_cursor)

	var row_mins: Dictionary[int, Vector2] = {}
	var row_maxes: Dictionary[int, Vector2] = {}
	var column_mins: Dictionary[int, Vector2] = {}
	var column_maxes: Dictionary[int, Vector2] = {}

	var total_min: Vector2 = Vector2(999, 999)
	var total_max: Vector2 = Vector2(-999, -999)

	# for each row, get min_x and edge height, max_x and edge height
	for tile: TerrainTile in terrain_tiles:
		if tile.no_walk or tile.no_cursor:
			continue
		
		# if first tile considered in the row
		if not row_mins.has(tile.y):
			row_mins[tile.y] = Vector2(tile.x, tile.height_bottom)
			row_maxes[tile.y] = Vector2(tile.x + 1.0, tile.height_bottom)
		else:
			if tile.x < row_mins[tile.y].x:
				row_mins[tile.y] = Vector2(tile.x, tile.height_bottom)
			elif tile.x == row_mins[tile.y].x and tile.height_bottom > row_mins[tile.y].y:
				row_mins[tile.y] = Vector2(tile.x, tile.height_bottom)
			
			var tile_upper_bound: float = tile.x + 1.0
			if tile_upper_bound > row_maxes[tile.y].x:
				row_maxes[tile.y] = Vector2(tile_upper_bound, tile.height_bottom)
			elif tile_upper_bound == row_maxes[tile.y].x and tile.height_bottom > row_maxes[tile.y].y:
				row_maxes[tile.y] = Vector2(tile_upper_bound, tile.height_bottom)


		# if first tile considered in the column
		if not column_mins.has(tile.x):
			column_mins[tile.x] = Vector2(tile.y, tile.height_bottom)
			column_maxes[tile.x] = Vector2(tile.y + 1.0, tile.height_bottom)
		else:
			if tile.y < column_mins[tile.x].x:
				column_mins[tile.x] = Vector2(tile.y, tile.height_bottom)
			elif tile.y == column_mins[tile.x].x and tile.height_bottom > column_mins[tile.x].y:
				column_mins[tile.x] = Vector2(tile.y, tile.height_bottom)

			var tile_upper_bound: float = tile.y + 1.0
			if tile_upper_bound > column_maxes[tile.x].x:
				column_maxes[tile.x] = Vector2(tile_upper_bound, tile.height_bottom)
			elif tile_upper_bound == column_maxes[tile.x].x and tile.height_bottom > column_maxes[tile.x].y:
				column_maxes[tile.x] = Vector2(tile_upper_bound, tile.height_bottom)

		total_min.x = column_mins.keys().min()
		total_min.y = row_mins.keys().min()
		total_max.x = column_mins.keys().max() + 1.0
		total_max.y = row_mins.keys().max() + 1.0

	var surface_arrays: Array = mesh.surface_get_arrays(0)
	var mesh_centroids: Array = surface_arrays[Mesh.ARRAY_CUSTOM0]
	var mesh_custom1: PackedFloat32Array = []
	mesh_custom1.resize(mesh_centroids.size())
	mesh_custom1.fill(0)

	@warning_ignore("integer_division")
	var num_verticies: int = mesh_custom1.size() / 4
	for vertex_idx: int in range(num_verticies):
		var x_index: int = vertex_idx * 4
		var centroid: Vector3 = Vector3(mesh_centroids[x_index], mesh_centroids[x_index + 1], mesh_centroids[x_index + 2])
		var polygon_row: int = floori(centroid.z)
		var polygon_column: int = floori(centroid.x)
		var flag_hidden: bool = false
		
		# outer quadrants
		if centroid.x < total_min.x and centroid.z < total_min.y:
			flag_hidden = true
		elif centroid.x < total_min.x and centroid.z > total_max.y:
			flag_hidden = true
		elif centroid.x > total_max.x and centroid.z < total_min.y:
			flag_hidden = true
		elif centroid.x > total_max.x and centroid.z > total_max.y:
			flag_hidden = true
		elif row_mins.has(polygon_row) and column_mins.has(polygon_column):
			# row bounds
			if centroid.x < row_mins[polygon_row].x and centroid.y > row_mins[polygon_row].y:
				flag_hidden = true
			elif centroid.x > row_maxes[polygon_row].x and centroid.y > row_maxes[polygon_row].y:
				flag_hidden = true
			# column bounds
			elif centroid.z < column_mins[polygon_column].x and centroid.y > column_mins[polygon_column].y:
				flag_hidden = true
			elif centroid.z > column_maxes[polygon_column].x and centroid.y > column_maxes[polygon_column].y:
				flag_hidden = true

		if flag_hidden:
			mesh_custom1[x_index] = 1.0
			mesh_custom1[x_index + 1] = 1.0
			mesh_custom1[x_index + 2] = 1.0
			mesh_custom1[x_index + 3] = 1.0
	surface_arrays[Mesh.ARRAY_CUSTOM1] = mesh_custom1
	var format_flags: int = Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM1_SHIFT


func get_transformed_tiles(translation: Vector2 = Vector2.ZERO, scale: Vector2 = Vector2.ONE, rotation_degrees: float = 0.0) -> Array[TerrainTile]:
	var mirrored_tiles: Array[TerrainTile] = []

	var tiles_center: Vector2 = get_tiles_center(terrain_tiles)	
	var tile_transform: Transform2D = get_transform2d(tiles_center, scale, translation, rotation_degrees)
	
	for tile: TerrainTile in terrain_tiles:
		if tile.no_cursor == 1:
			continue

		var transformed_tile: TerrainTile = tile.duplicate()
		transformed_tile.location = Vector2i((tile_transform * Vector2(tile.location)).round())
		transformed_tile.rotation_degrees += rotation_degrees
		
		if transformed_tile.rotation_degrees == 90.0 or transformed_tile.rotation_degrees == 270.0:
			transformed_tile.tile_scale.x *= scale.y
			transformed_tile.tile_scale.z *= scale.x
		else:
			transformed_tile.tile_scale.x *= scale.x
			transformed_tile.tile_scale.z *= scale.y
		
		# transformed_tile.height_mid = transformed_tile.height_bottom + (transformed_tile.slope_height / 2.0)
		mirrored_tiles.append(transformed_tile)
	
	return mirrored_tiles


static func get_transform2d(
	tiles_pivot: Vector2, 
	scale: Vector2 = Vector2.ONE, 
	translation: Vector2 = Vector2.ZERO, 
	rotation_degrees: float = 0.0
) -> Transform2D:	
	var transform: Transform2D = Transform2D.IDENTITY
	transform = transform.translated(-tiles_pivot)
	transform = transform.rotated(deg_to_rad(rotation_degrees))
	transform = transform.scaled(scale)
	transform = transform.translated(tiles_pivot + translation)

	return transform


static func get_tiles_center(tile_array: Array[TerrainTile]) -> Vector2:
	var min_tile_location: Vector2i = Vector2i.ZERO
	var max_tile_location: Vector2i = Vector2i.ZERO
	for tile: TerrainTile in tile_array:
		if tile.location.x > max_tile_location.x:
			max_tile_location.x = tile.location.x
		if tile.location.y > max_tile_location.y:
			max_tile_location.y = tile.location.y
		
		if tile.location.x < min_tile_location.x:
			min_tile_location.x = tile.location.x
		if tile.location.y < min_tile_location.y:
			min_tile_location.y = tile.location.y
	
	var tiles_center: Vector2 = (max_tile_location -  min_tile_location) / 2.0
	return tiles_center


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
