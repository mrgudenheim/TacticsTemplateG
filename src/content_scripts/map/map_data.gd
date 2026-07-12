class_name MapData
extends Resource

enum DirectionFlag {
	NORTH = 1,
	EAST = 2,
	SOUTH = 4,
	WEST = 8,
}

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
	
	var tile_heights: Dictionary[Vector2i, PackedFloat32Array] = {}

	# for each row, get min_x and edge height, max_x and edge height
	for tile: TerrainTile in terrain_tiles:
		if tile.no_walk or tile.no_cursor:
			continue
		
		var tile_height_position: float = get_tile_height_position(tile)
		
		if tile_heights.has(tile.location):
			tile_heights[tile.location].append(tile_height_position)
		else:
			tile_heights[tile.location] = [tile_height_position]
		
		# if first tile considered in the row
		if not row_mins.has(tile.location.y):
			row_mins[tile.location.y] = Vector2(tile.location.x, tile_height_position)
			row_maxes[tile.location.y] = Vector2(tile.location.x, tile_height_position)
		else:
			if tile.location.x < row_mins[tile.location.y].x:
				row_mins[tile.location.y] = Vector2(tile.location.x, tile_height_position)
			elif tile.location.x == row_mins[tile.location.y].x and tile_height_position > row_mins[tile.location.y].y:
				row_mins[tile.location.y] = Vector2(tile.location.x, tile_height_position)
			
			if tile.location.x > row_maxes[tile.location.y].x:
				row_maxes[tile.location.y] = Vector2(tile.location.x, tile_height_position)
			elif tile.location.x == row_maxes[tile.location.y].x and tile_height_position > row_maxes[tile.location.y].y:
				row_maxes[tile.location.y] = Vector2(tile.location.x, tile_height_position)

		# if first tile considered in the column
		if not column_mins.has(tile.location.x):
			column_mins[tile.location.x] = Vector2(tile.location.y, tile_height_position)
			column_maxes[tile.location.x] = Vector2(tile.location.y, tile_height_position)
		else:
			if tile.location.y < column_mins[tile.location.x].x:
				column_mins[tile.location.x] = Vector2(tile.location.y, tile_height_position)
			elif tile.location.y == column_mins[tile.location.x].x and tile_height_position > column_mins[tile.location.x].y:
				column_mins[tile.location.x] = Vector2(tile.location.y, tile_height_position)

			if tile.location.y > column_maxes[tile.location.x].x:
				column_maxes[tile.location.x] = Vector2(tile.location.y, tile_height_position)
			elif tile.location.y == column_maxes[tile.location.x].x and tile_height_position > column_maxes[tile.location.x].y:
				column_maxes[tile.location.x] = Vector2(tile.location.y, tile_height_position)

	for location: Vector2i in tile_heights.keys():
		tile_heights[location].sort()

	var surface_arrays: Array = mesh.surface_get_arrays(0)
	var mesh_centroids: PackedFloat32Array = surface_arrays[Mesh.ARRAY_CUSTOM0]

	@warning_ignore("integer_division")
	var num_verticies: int = mesh_centroids.size() / 4
	for vertex_idx: int in range(num_verticies):
		var x_index: int = vertex_idx * 4
		var centroid: Vector3 = Vector3(mesh_centroids[x_index], mesh_centroids[x_index + 1], mesh_centroids[x_index + 2])
		var polygon_row: int = floori(centroid.z)
		var polygon_column: int = floori(centroid.x)
		var flag_hidden: bool = false
		var hidden_bitflags: int = 0
		
		# if on edge between tiles:
		# check each potential neighbor to find if it is a valid tile
		# use highest height among valid neighbors for cutoff to hide polygons
		# if neither are valid, always flag
		var height_cutoff: float = -9999.9
		var max_height_cutoff: float = 9999.9
		var is_row_edge: bool = is_equal_approx(centroid.z, roundi(centroid.z))
		var is_column_edge: bool = is_equal_approx(centroid.x, roundi(centroid.x))
		
		# fix polygons whose centroid happen to fall at intersection of row and column edge (ex. a wall that is two tile wide)
		if is_column_edge and is_row_edge:
			var vertex: Vector3 = surface_arrays[Mesh.ARRAY_VERTEX][vertex_idx]
			if vertex.z != centroid.z:
				is_row_edge = false
			if vertex.x != centroid.x:
				is_column_edge = false
		
		if is_column_edge:
			polygon_column = roundi(centroid.x)
			
			var location_a: Vector2i = Vector2i(polygon_column, polygon_row)
			var location_b: Vector2i = Vector2i(polygon_column - 1, polygon_row)
			if tile_heights.has(location_a) and tile_heights.has(location_b):
				height_cutoff = max(tile_heights[location_a][0], tile_heights[location_b][-1])
			elif not tile_heights.has(location_a) and tile_is_partial_internal(location_a, row_mins, row_maxes, column_mins, column_maxes):
				height_cutoff = max_height_cutoff # don't hide impassable tiles in the middle of the battlefield
			elif not tile_heights.has(location_b) and tile_is_partial_internal(location_b, row_mins, row_maxes, column_mins, column_maxes):
				height_cutoff = max_height_cutoff # don't hide impassable tiles in the middle of the battlefield
				polygon_column = polygon_column - 1
			elif tile_heights.has(location_a):
				height_cutoff = tile_heights[location_a][-1]
			elif tile_heights.has(location_b):
				height_cutoff = tile_heights[location_b][-1]
				polygon_column = polygon_column - 1
			elif column_mins.keys().has(location_b.x): # wall on outer EAST and WEST borders should be treated the same, ie. as inside the map
				polygon_column = polygon_column - 1
		elif is_row_edge:
			polygon_row = roundi(centroid.z)
			
			var location_a: Vector2i = Vector2i(polygon_column, polygon_row)
			var location_b: Vector2i = Vector2i(polygon_column, polygon_row - 1)
			if tile_heights.has(location_a) and tile_heights.has(location_b):
				height_cutoff = max(tile_heights[location_a][-1], tile_heights[location_b][-1])
			elif not tile_heights.has(location_a) and tile_is_partial_internal(location_a, row_mins, row_maxes, column_mins, column_maxes):
				height_cutoff = max_height_cutoff # don't hide impassable tiles in the middle of the battlefield
			elif not tile_heights.has(location_b) and tile_is_partial_internal(location_b, row_mins, row_maxes, column_mins, column_maxes):
				height_cutoff = max_height_cutoff # don't hide impassable tiles in the middle of the battlefield
				polygon_row = polygon_row - 1
			elif tile_heights.has(location_a):
				height_cutoff = tile_heights[location_a][-1]
			elif tile_heights.has(location_b):
				height_cutoff = tile_heights[location_b][-1]
				polygon_row = polygon_row - 1
			elif row_mins.keys().has(location_b.y):  # wall on outer NORTH and SOUTH borders should be treated the same, ie. as inside the map
				polygon_row = polygon_row - 1
		else:
			var tile_location: Vector2i = Vector2i(polygon_column, polygon_row)
			if tile_heights.has(tile_location):
				height_cutoff = tile_heights[tile_location][-1] # get highest
			elif tile_is_partial_internal(tile_location, row_mins, row_maxes, column_mins, column_maxes):
				height_cutoff = max_height_cutoff # don't hide impassable tiles in the middle of the battlefield
		
		if centroid.y > (height_cutoff + 0.01):
			var tile_location: Vector2i = Vector2i(polygon_column, polygon_row)
			hidden_bitflags = get_tile_hidden_bitflags(tile_location, row_mins, row_maxes, column_mins, column_maxes)
			flag_hidden = true

		if flag_hidden:
			#mesh_centroids[x_index] = centroid.x
			#mesh_centroids[x_index + 1] = centroid.y
			#mesh_centroids[x_index + 2] = centroid.z
			mesh_centroids[x_index + 3] = float(hidden_bitflags)
	surface_arrays[Mesh.ARRAY_CUSTOM0] = mesh_centroids
	var format_flags: int = Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT
	var new_mesh: ArrayMesh = ArrayMesh.new()
	new_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, surface_arrays, [], {}, format_flags)
	mesh = new_mesh


func tile_is_internal(
	tile_location: Vector2i,
	row_mins: Dictionary[int, Vector2],
	row_maxes: Dictionary[int, Vector2],
	column_mins: Dictionary[int, Vector2],
	column_maxes: Dictionary[int, Vector2]
) -> bool:
	if not row_mins.has(tile_location.y) or not column_mins.has(tile_location.x):
		return false
	
	return (tile_location.x > row_mins[tile_location.y].x
		and tile_location.x < row_maxes[tile_location.y].x
		and tile_location.y > column_mins[tile_location.x].x
		and tile_location.y < column_maxes[tile_location.x].x)


func tile_is_partial_internal(
	tile_location: Vector2i,
	row_mins: Dictionary[int, Vector2],
	row_maxes: Dictionary[int, Vector2],
	column_mins: Dictionary[int, Vector2],
	column_maxes: Dictionary[int, Vector2]
) -> bool:
	if not row_mins.has(tile_location.y) or not column_mins.has(tile_location.x):
		return false
	
	return ((tile_location.x > row_mins[tile_location.y].x and tile_location.x < row_maxes[tile_location.y].x)
		or (tile_location.y > column_mins[tile_location.x].x and tile_location.y < column_maxes[tile_location.x].x))


func get_tile_hidden_bitflags(
	tile_location: Vector2i,
	row_mins: Dictionary[int, Vector2],
	row_maxes: Dictionary[int, Vector2],
	column_mins: Dictionary[int, Vector2],
	column_maxes: Dictionary[int, Vector2]
) -> int:
	var hidden_bitflags: int = 0
	if row_mins.has(tile_location.y):
		if tile_location.x < row_mins[tile_location.y].x:
			hidden_bitflags |= DirectionFlag.WEST
		elif tile_location.x > row_maxes[tile_location.y].x:
			hidden_bitflags |= DirectionFlag.EAST
	else:
		if tile_location.y < row_mins.keys().min():
			hidden_bitflags |= DirectionFlag.SOUTH
		elif tile_location.y > row_mins.keys().max():
			hidden_bitflags |= DirectionFlag.NORTH
	
	if column_mins.has(tile_location.x):
		if tile_location.y < column_mins[tile_location.x].x:
			hidden_bitflags |= DirectionFlag.SOUTH
		elif tile_location.y > column_maxes[tile_location.x].x:
			hidden_bitflags |= DirectionFlag.NORTH
	else:
		if tile_location.x < column_mins.keys().min():
			hidden_bitflags |= DirectionFlag.WEST
		elif tile_location.x > column_mins.keys().max():
			hidden_bitflags |= DirectionFlag.EAST

	return hidden_bitflags


func sort_tiles_descending_height(tile_a: TerrainTile, tile_b: TerrainTile) -> bool:
	var tile_a_total_height: int = tile_a.height_bottom + tile_a.depth + tile_a.slope_height
	var tile_b_total_height: int = tile_b.height_bottom + tile_b.depth + tile_b.slope_height
	return tile_a_total_height > tile_b_total_height


func get_tile_height_position(tile: TerrainTile) -> float:
	return (tile.height_bottom + tile.slope_height + tile.depth) * FftMapData.HEIGHT_SCALE


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
