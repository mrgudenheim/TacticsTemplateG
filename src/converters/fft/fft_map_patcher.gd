class_name FftMapPatcher
extends RefCounted


static func get_adjusted_mesh_file(fft_map_data: FftMapData, mirror_quadrants: PackedVector2Array, cropped_rect: Rect2i) -> PackedByteArray:
	var adjusted_map_data: FftMapData = get_adjusted_map_data(fft_map_data, mirror_quadrants, cropped_rect)
	var adjusted_map_mesh_file: PackedByteArray = get_fft_mesh_file(adjusted_map_data)
	return adjusted_map_mesh_file


static func get_fft_mesh_file(fft_map_data: FftMapData, remove_untextured_polygons: bool = true, keep_polygon_render_flags: bool = false) -> PackedByteArray:
	var primary_mesh_data_start: int = 0xc4
	var primary_mesh_bytes: PackedByteArray = []
	var primary_mesh_header: PackedByteArray = []
	primary_mesh_header.resize(8)
	primary_mesh_header.fill(0)
	primary_mesh_header.encode_u16(0, fft_map_data.num_text_tris)
	primary_mesh_header.encode_u16(2, fft_map_data.num_text_quads)
	if not remove_untextured_polygons:
		primary_mesh_header.encode_u16(4, fft_map_data.num_black_tris)
		primary_mesh_header.encode_u16(6, fft_map_data.num_black_quads)

	# Encode vertex coordinates (6 bytes per vertex)
	var primary_mesh_textured_tri_vertices: PackedByteArray = encode_vertices(fft_map_data.text_tri_vertices)
	var primary_mesh_textured_quad_vertices: PackedByteArray = encode_vertices(fft_map_data.text_quad_vertices)
	var primary_mesh_black_tri_vertices: PackedByteArray = []
	var primary_mesh_black_quad_vertices: PackedByteArray = []
	if not remove_untextured_polygons:
		primary_mesh_black_tri_vertices = encode_vertices(fft_map_data.black_tri_vertices)
		primary_mesh_black_quad_vertices = encode_vertices(fft_map_data.black_quad_vertices)
	
	# Encode normal vectors (6 bytes per vertex)
	var primary_mesh_textured_tri_normals: PackedByteArray = encode_normals(fft_map_data.text_tri_normals)
	var primary_mesh_textured_quad_normals: PackedByteArray = encode_normals(fft_map_data.text_quad_normals)
	
	primary_mesh_bytes.append_array(primary_mesh_header)
	primary_mesh_bytes.append_array(primary_mesh_textured_tri_vertices)
	primary_mesh_bytes.append_array(primary_mesh_textured_quad_vertices)
	primary_mesh_bytes.append_array(primary_mesh_black_tri_vertices)
	primary_mesh_bytes.append_array(primary_mesh_black_quad_vertices)
	primary_mesh_bytes.append_array(primary_mesh_textured_tri_normals)
	primary_mesh_bytes.append_array(primary_mesh_textured_quad_normals)
	primary_mesh_bytes.append_array(fft_map_data.tris_texture_bytes)
	primary_mesh_bytes.append_array(fft_map_data.quads_texture_bytes)
	primary_mesh_bytes.append_array(fft_map_data.untextured_polygon_bytes)
	primary_mesh_bytes.append_array(fft_map_data.textured_polygon_tile_bytes)

	# texture palettes - handled in create_map()
	# lighting and gradient - handled in create_map()
	# terrain tiles - handled in get_adjusted_map_data()

	# texture animation instructions
	var full_texture_anim_instruction_bytes: PackedByteArray = []
	for texture_anim_instructions: PackedByteArray in fft_map_data.texture_anim_instructions_bytes:
		full_texture_anim_instruction_bytes.append_array(texture_anim_instructions)

	# palette animation instructions - handled in create_map()
	# texture palettes grayscale - handled in create_map()
	# TODO mesh animation instructions
	# TODO animated meshes 1 - 8

	# polygon render flags
	var polygon_render_flags_bytes: PackedByteArray = []
	if keep_polygon_render_flags:
		polygon_render_flags_bytes.append_array(fft_map_data.unknown_render_bytes)
		polygon_render_flags_bytes.append_array(fft_map_data.textured_tris_flags)
		polygon_render_flags_bytes.append_array(fft_map_data.textured_quads_flags)
		polygon_render_flags_bytes.append_array(fft_map_data.black_tris_flags)
		polygon_render_flags_bytes.append_array(fft_map_data.black_quads_flags)
	else:
		polygon_render_flags_bytes.resize(896 + 1024 + 1536 + 128 + 512)
		polygon_render_flags_bytes.fill(0)

	# header
	var next_section_start: int = 0
	var header_bytes: PackedByteArray = []
	header_bytes.resize(0xc4)
	header_bytes.fill(0)
	header_bytes.encode_u32(0x40, primary_mesh_data_start)
	next_section_start += primary_mesh_data_start
	
	next_section_start += primary_mesh_bytes.size()
	var texture_palettes_data_start: int = next_section_start
	header_bytes.encode_u32(0x44, texture_palettes_data_start)
	
	next_section_start += fft_map_data.texture_palette_bytes.size()
	var lighting_data_start: int = next_section_start
	header_bytes.encode_u32(0x64, lighting_data_start)
	
	next_section_start += fft_map_data.lighting_and_gradient_bytes.size()
	var terrain_data_start: int = next_section_start
	header_bytes.encode_u32(0x68, terrain_data_start)
	
	next_section_start += fft_map_data.terrain_data_bytes.size()
	var texture_animation_instructions_data_start: int = next_section_start
	if full_texture_anim_instruction_bytes.size() == 0:
		texture_animation_instructions_data_start = 0
	header_bytes.encode_u32(0x6c, texture_animation_instructions_data_start)
	
	next_section_start += full_texture_anim_instruction_bytes.size()
	var palette_animation_frames_data_start: int = next_section_start
	if fft_map_data.palette_animation_bytes.size() == 0:
		palette_animation_frames_data_start = 0
	header_bytes.encode_u32(0x70, palette_animation_frames_data_start)
	
	next_section_start += fft_map_data.palette_animation_bytes.size()
	var palettes_grayscale_start: int = next_section_start
	header_bytes.encode_u32(0x7c, palettes_grayscale_start)
	
	var mesh_animation_instructions_start: int = 0
	header_bytes.encode_u32(0x8c, mesh_animation_instructions_start)

	var animated_mesh_1_start: int = 0
	header_bytes.encode_u32(0x90, animated_mesh_1_start)
	var animated_mesh_2_start: int = 0
	header_bytes.encode_u32(0x94, animated_mesh_2_start)
	var animated_mesh_3_start: int = 0
	header_bytes.encode_u32(0x98, animated_mesh_3_start)
	var animated_mesh_4_start: int = 0
	header_bytes.encode_u32(0x9c, animated_mesh_4_start)
	var animated_mesh_5_start: int = 0
	header_bytes.encode_u32(0xa0, animated_mesh_5_start)
	var animated_mesh_6_start: int = 0
	header_bytes.encode_u32(0xa4, animated_mesh_6_start)
	var animated_mesh_7_start: int = 0
	header_bytes.encode_u32(0xa8, animated_mesh_7_start)
	var animated_mesh_8_start: int = 0
	header_bytes.encode_u32(0xac, animated_mesh_8_start)

	next_section_start += fft_map_data.texture_palette_grayscale_bytes.size()
	var polygon_render_flags_start: int = next_section_start
	header_bytes.encode_u32(0xb0, polygon_render_flags_start)

	# full file
	var mesh_file_bytes: PackedByteArray = []
	mesh_file_bytes.append_array(header_bytes)
	mesh_file_bytes.append_array(primary_mesh_bytes)
	mesh_file_bytes.append_array(fft_map_data.texture_palette_bytes)
	mesh_file_bytes.append_array(fft_map_data.lighting_and_gradient_bytes)
	mesh_file_bytes.append_array(fft_map_data.terrain_data_bytes)
	mesh_file_bytes.append_array(full_texture_anim_instruction_bytes)
	mesh_file_bytes.append_array(fft_map_data.palette_animation_bytes)
	mesh_file_bytes.append_array(fft_map_data.texture_palette_grayscale_bytes)
	# TODO mesh animation instructions
	# TODO animated meshes 1 - 8
	mesh_file_bytes.append_array(polygon_render_flags_bytes)

	return mesh_file_bytes


## Encodes an array of 3D vertices into signed 16-bit integer byte representation (6 bytes per vertex).
static func encode_vertices(vertices: PackedVector3Array) -> PackedByteArray:
	var encoded_bytes: PackedByteArray = []
	var number_of_vertices: int = vertices.size()
	encoded_bytes.resize(number_of_vertices * 6)
	
	for vertex_index: int in number_of_vertices:
		var byte_index: int = vertex_index * 6
		var vertex_coordinates: Vector3 = vertices[vertex_index]
		encoded_bytes.encode_s16(byte_index, roundi(vertex_coordinates.x))
		encoded_bytes.encode_s16(byte_index + 2, roundi(vertex_coordinates.y))
		encoded_bytes.encode_s16(byte_index + 4, roundi(vertex_coordinates.z))
	
	return encoded_bytes


## Encodes an array of 3D normal vectors into signed 16-bit integer byte representation (scale factor 4096.0; 12-bit).
static func encode_normals(normals: PackedVector3Array) -> PackedByteArray:
	var encoded_bytes: PackedByteArray = []
	var number_of_normals: int = normals.size()
	encoded_bytes.resize(number_of_normals * 6)
	
	for normal_index: int in number_of_normals:
		var byte_index: int = normal_index * 6
		var normal_vector: Vector3 = normals[normal_index]
		encoded_bytes.encode_s16(byte_index, roundi(normal_vector.x * 4096.0))
		encoded_bytes.encode_s16(byte_index + 2, roundi(normal_vector.y * 4096.0))
		encoded_bytes.encode_s16(byte_index + 4, roundi(normal_vector.z * 4096.0))
	
	return encoded_bytes


static func get_rotated_fft_map_data(
	original_map_data: FftMapData, 
	rotation_steps_clockwise: int = 1
) -> FftMapData:
	var rotation_steps: int = posmod(rotation_steps_clockwise, 4)
	if rotation_steps == 0:
		return original_map_data.duplicate_deep()
	
	var rotated_map_data: FftMapData = original_map_data.duplicate_deep()
	var original_width: int = original_map_data.map_width
	var original_length: int = original_map_data.map_length
	
	# Determine new map dimensions
	var new_width: int = original_width 
	if rotation_steps % 2 != 0:
		new_width = original_length
	var new_length: int = original_length
	if rotation_steps % 2 != 0:
		new_length = original_width
	rotated_map_data.map_width = new_width
	rotated_map_data.map_length = new_length
	
	# Terrain Tiles Matrix Re-indexing (both Layer 0 and Layer 1)
	rotated_map_data.terrain_data_bytes.fill(0)
	rotated_map_data.terrain_data_bytes.encode_u8(0, new_width)
	rotated_map_data.terrain_data_bytes.encode_u8(1, new_length)
	
	for layer_index: int in [0, 1]:
		for tile_z: int in original_length:
			for tile_x: int in original_width:
				var old_tile_index: int = tile_x + (tile_z * original_width)
				var old_byte_start: int = 2 + (old_tile_index * FftMapData.BYTES_PER_TERRAIN_TILE) + (layer_index * 256 * FftMapData.BYTES_PER_TERRAIN_TILE)
				var tile_data: PackedByteArray = original_map_data.terrain_data_bytes.slice(old_byte_start, old_byte_start + FftMapData.BYTES_PER_TERRAIN_TILE)
				
				# Map old (tile_x, tile_z) to (new_tile_x, new_tile_z) with North = +Z
				var new_tile_x: int = tile_x
				var new_tile_z: int = tile_z
				match rotation_steps:
					1: # 90 degrees Clockwise: (tile_z, original_width - 1 - tile_x)
						new_tile_x = tile_z
						new_tile_z = (original_width - 1) - tile_x
					2: # 180 degrees Clockwise: (original_width - 1 - tile_x, original_length - 1 - tile_z)
						new_tile_x = (original_width - 1) - tile_x
						new_tile_z = (original_length - 1) - tile_z
					3: # 270 degrees Clockwise: (original_length - 1 - tile_z, tile_x)
						new_tile_x = (original_length - 1) - tile_z
						new_tile_z = tile_x
				
				var new_tile_index: int = new_tile_x + (new_tile_z * new_width)
				var new_byte_start: int = 2 + (new_tile_index * FftMapData.BYTES_PER_TERRAIN_TILE) + (layer_index * 256 * FftMapData.BYTES_PER_TERRAIN_TILE)
				
				# Adjust slope type and camera rotation trigger ID
				var new_slope_type: int = rotate_slope_type(tile_data.decode_u8(4), rotation_steps)
				var new_camera_flags: int = rotate_camera_flags(tile_data.decode_u8(7), rotation_steps)
				tile_data.encode_u8(4, new_slope_type)
				tile_data.encode_u8(7, new_camera_flags)
				
				for byte_offset: int in FftMapData.BYTES_PER_TERRAIN_TILE:
					rotated_map_data.terrain_data_bytes[new_byte_start + byte_offset] = tile_data[byte_offset]
	rotated_map_data.terrain_tiles = rotated_map_data.get_terrain(rotated_map_data.terrain_data_bytes)
	
	# Transform Mesh Vertices & Normals (North = +Z)
	var x_translation_offset: float = 0.0
	if rotation_steps == 3:
		x_translation_offset = original_length * FftMapData.TILE_SIDE_LENGTH
	elif rotation_steps == 2:
		x_translation_offset = original_width * FftMapData.TILE_SIDE_LENGTH

	var z_translation_offset: float = 0.0
	if rotation_steps == 1:
		z_translation_offset = original_width * FftMapData.TILE_SIDE_LENGTH
	elif rotation_steps == 2:
		z_translation_offset = original_length * FftMapData.TILE_SIDE_LENGTH
	rotate_vertices_and_normals(rotated_map_data.text_tri_vertices, rotated_map_data.text_tri_normals, rotation_steps, x_translation_offset, z_translation_offset)
	rotate_vertices_and_normals(rotated_map_data.text_quad_vertices, rotated_map_data.text_quad_normals, rotation_steps, x_translation_offset, z_translation_offset)
	rotate_vertices_and_normals(rotated_map_data.black_tri_vertices, [], rotation_steps, x_translation_offset, z_translation_offset)
	rotate_vertices_and_normals(rotated_map_data.black_quad_vertices, [], rotation_steps, x_translation_offset, z_translation_offset)
	
	# Map Polygons to Terrain Tiles
	associate_polygons_to_terrain_tiles(rotated_map_data)
	
	# Transform Polygon Render Properties
	rotate_render_flags_block(rotated_map_data.textured_tris_flags, rotated_map_data.num_text_tris, rotation_steps)
	rotate_render_flags_block(rotated_map_data.textured_quads_flags, rotated_map_data.num_text_quads, rotation_steps)
	rotate_render_flags_block(rotated_map_data.black_tris_flags, rotated_map_data.num_black_tris, rotation_steps)
	rotate_render_flags_block(rotated_map_data.black_quads_flags, rotated_map_data.num_black_quads, rotation_steps)

	return rotated_map_data


## Rotates a terrain slope type ID clockwise by rotation_steps (90 degree increments)
static func rotate_slope_type(slope_type_id: int, rotation_steps: int) -> int:
	var current_slope: int = slope_type_id
	for step_index: int in posmod(rotation_steps, 4):
		match current_slope:
			# Ramps
			0x85: current_slope = 0x52
			0x52: current_slope = 0x25
			0x25: current_slope = 0x58
			0x58: current_slope = 0x85
			# Low Corners (Convex)
			0x41: current_slope = 0x11
			0x11: current_slope = 0x14
			0x14: current_slope = 0x44
			0x44: current_slope = 0x41
			# High Corners (Concave)
			0x96: current_slope = 0x66
			0x66: current_slope = 0x69
			0x69: current_slope = 0x99
			0x99: current_slope = 0x96
			_: current_slope = current_slope # Flat (0x00) or unrecognized
	return current_slope


## Rotates an 8-bit terrain camera auto-rotation flag byte clockwise by rotation_steps.
## Bits 0xf0 represent Top views (NW, SW, SE, NE), and Bits 0x0f represent Bottom views (NW, SW, SE, NE).
static func rotate_camera_flags(camera_flags: int, rotation_steps_clockwise: int) -> int:
	var rotation_steps: int = posmod(rotation_steps_clockwise, 4)
	if rotation_steps == 0:
		return camera_flags

	# Extract Top (high nibble, bits 0xf0) and Bottom (low nibble, bits 0x0f) camera flags
	var top_camera_flags: int = (camera_flags >> 4) & 0x0f
	var bottom_camera_flags: int = camera_flags & 0x0f

	# Rotate both 4-bit nibbles clockwise (1-bit left circular shift per 90 degree step)
	var rotated_top_flags: int = ((top_camera_flags << rotation_steps) | (top_camera_flags >> (4 - rotation_steps))) & 0x0f
	var rotated_bottom_flags: int = ((bottom_camera_flags << rotation_steps) | (bottom_camera_flags >> (4 - rotation_steps))) & 0x0f

	return (rotated_top_flags << 4) | rotated_bottom_flags


## Rotates a block of 16-bit render flags in-place
static func rotate_render_flags_block(
	flags_bytes: PackedByteArray, 
	polygon_count: int, 
	rotation_steps: int
) -> void:
	rotation_steps = posmod(rotation_steps, 4)
	for polygon_index: int in polygon_count:
		var byte_offset: int = polygon_index * 2
		var original_flags: int = flags_bytes.decode_u16(byte_offset)
		var rotated_flags: int = rotate_render_flags(original_flags, rotation_steps)
		flags_bytes.encode_u16(byte_offset, rotated_flags)


## Rotates a 16-bit polygon render property flag clockwise by rotation_steps
static func rotate_render_flags(render_flags: int, rotation_steps: int) -> int:
	rotation_steps = posmod(rotation_steps, 4)
	if rotation_steps == 0:
		return render_flags
	
	# Preserve non-directional bits (bit 15: unlit, bit 14, bit 1, bit 0)
	var updated_flags: int = render_flags & 0xc003
	
	# 4 Primary diagonal bits (bits 13..10)
	var diagonal_flags: int = (render_flags >> 10) & 0x0f
	var rotated_diagonals: int = ((diagonal_flags >> rotation_steps) | (diagonal_flags << (4 - rotation_steps))) & 0x0f
	updated_flags |= (rotated_diagonals << 10)
	
	# 8 Secondary intermediate bits (bits 9..2)
	var shift_amount: int = (2 * rotation_steps) % 8
	var intermediate_flags: int = (render_flags >> 2) & 0xff
	var rotated_intermediates: int = ((intermediate_flags >> shift_amount) | (intermediate_flags << (8 - shift_amount))) & 0xff
	updated_flags |= (rotated_intermediates << 2)
	
	return updated_flags


## Rotates packed vertex coordinates and normal vectors in-place
static func rotate_vertices_and_normals(
	vertices: PackedVector3Array, 
	normals: PackedVector3Array, 
	rotation_steps: int, 
	x_translation_offset: float, 
	z_translation_offset: float
) -> void:
	rotation_steps = posmod(rotation_steps, 4)
	
	for vertex_index: int in vertices.size():
		var original_vertex: Vector3 = vertices[vertex_index]
		var rotated_vertex: Vector3 = original_vertex
		
		match rotation_steps:
			1: # 90 degrees Clockwise
				rotated_vertex.x = original_vertex.z + x_translation_offset
				rotated_vertex.z = -original_vertex.x + z_translation_offset
			2: # 180 degrees Clockwise
				rotated_vertex.x = -original_vertex.x + x_translation_offset
				rotated_vertex.z = -original_vertex.z + z_translation_offset
			3: # 270 degrees Clockwise
				rotated_vertex.x = -original_vertex.z + x_translation_offset
				rotated_vertex.z = original_vertex.x + z_translation_offset
		
		vertices[vertex_index] = rotated_vertex
		
		if not normals.is_empty() and vertex_index < normals.size():
			var original_normal: Vector3 = normals[vertex_index]
			var rotated_normal: Vector3 = original_normal

			match rotation_steps:
				1:
					rotated_normal.x = original_normal.z
					rotated_normal.z = -original_normal.x
				2:
					rotated_normal.x = -original_normal.x
					rotated_normal.z = -original_normal.z
				3:
					rotated_normal.x = -original_normal.z
					rotated_normal.z = original_normal.x
			normals[vertex_index] = rotated_normal


## Updates the 2-byte (Z, Level, X) textured polygon terrain coordinate lookup table
## based on the newly transformed polygon vertices.
static func associate_polygons_to_terrain_tiles(map_data: FftMapData) -> void:
	var total_textured_polygons: int = map_data.num_text_tris + map_data.num_text_quads
	var updated_bytes: PackedByteArray = []
	updated_bytes.resize(total_textured_polygons * 2)
	
	var quads_byte_start: int = map_data.num_text_tris * 2
	
	# Process textured triangles
	var triangle_bytes: PackedByteArray = get_polygon_tile_bytes(
		map_data.text_tri_vertices, 
		FftMapData.NUM_VERTICIES_PER_TRI, 
		map_data.textured_polygon_tile_bytes, 
		0
	)
	
	# Process textured quads
	var quad_bytes: PackedByteArray = get_polygon_tile_bytes(
		map_data.text_quad_vertices, 
		FftMapData.NUM_VERTICIES_PER_QUAD, 
		map_data.textured_polygon_tile_bytes, 
		quads_byte_start
	)
	
	map_data.textured_polygon_tile_bytes = triangle_bytes
	map_data.textured_polygon_tile_bytes.append_array(quad_bytes)


## Gets the 2-byte tile coordinate entries for a collection of polygon vertices.
## vertices_per_polygon: 3 for triangles, 4 for quadrilaterals.
static func get_polygon_tile_bytes(
	vertices: PackedVector3Array, 
	vertices_per_polygon: int, 
	existing_tile_bytes: PackedByteArray = [], 
	existing_byte_read_offset: int = 0
) -> PackedByteArray:
	if vertices.is_empty() or vertices_per_polygon <= 0:
		return PackedByteArray()
	
	@warning_ignore("integer_division")
	var polygon_count: int = vertices.size() / vertices_per_polygon
	var result_bytes: PackedByteArray = []
	result_bytes.resize(polygon_count * 2)
	
	var divisor: float = float(vertices_per_polygon)
	for polygon_index: int in polygon_count:
		var vertex_offset: int = polygon_index * vertices_per_polygon
		var centroid: Vector3 = Vector3.ZERO
		for vertex_index: int in vertices_per_polygon:
			centroid += vertices[vertex_offset + vertex_index]
		centroid /= divisor
		
		# Read existing height level bit if available
		var source_read_offset: int = existing_byte_read_offset + (polygon_index * 2)
		var height_level: int = 0
		if source_read_offset < existing_tile_bytes.size():
			height_level = existing_tile_bytes[source_read_offset] & 0x01
		
		encode_polygon_tile_bytes(result_bytes, polygon_index * 2, centroid, height_level)
	
	return result_bytes


## Encodes a polygon's centroid into the 2-byte FFT tile coordinate format in destination_bytes at byte_offset.
## If the centroid sits on a vertical seam, writes [254, 255] to disable movement highlighting.
static func encode_polygon_tile_bytes(
	destination_bytes: PackedByteArray, 
	byte_offset: int, 
	centroid: Vector3, 
	height_level: int = 0
) -> void:
	var rounded_x: int = roundi(centroid.x)
	var rounded_z: int = roundi(centroid.z)
	
	# Vertical polygons (skirt/wall boundaries) are flagged with [254, 255] to prevent movement highlighting
	if rounded_x % FftMapData.TILE_SIDE_LENGTH == 0 or rounded_z % FftMapData.TILE_SIDE_LENGTH == 0:
		destination_bytes.encode_u8(byte_offset, 254) # tile_z = 127, height_level = 0
		destination_bytes.encode_u8(byte_offset + 1, 255)
	else:
		@warning_ignore("integer_division")
		var tile_x: int = rounded_x / FftMapData.TILE_SIDE_LENGTH
		@warning_ignore("integer_division")
		var tile_z: int = rounded_z / FftMapData.TILE_SIDE_LENGTH
		var byte_zero: int = (tile_z << 1) | height_level
		destination_bytes.encode_u8(byte_offset, byte_zero)
		destination_bytes.encode_u8(byte_offset + 1, tile_x)


static func get_adjusted_map_data(original_fft_map_data: FftMapData, quadrants: PackedVector2Array, cropped_rect: Rect2i) -> FftMapData:
	var mirrored_maps: Dictionary[Vector2i, FftMapData] = get_mirrored_expanded_map_data(original_fft_map_data, quadrants, true)

	var new_fft_map_data: FftMapData = get_cropped_map_data(cropped_rect, mirrored_maps)
	return new_fft_map_data


static func get_cropped_map_data(cropped_rect: Rect2i, mirrored_map_data: Dictionary[Vector2i, FftMapData]) -> FftMapData:
	var new_fft_map_data: FftMapData = mirrored_map_data.values()[0].duplicate_deep()
	new_fft_map_data.tris_texture_bytes = []
	new_fft_map_data.quads_texture_bytes = []
	new_fft_map_data.text_tri_vertices = []
	new_fft_map_data.text_tri_normals = []
	new_fft_map_data.text_quad_vertices = []
	new_fft_map_data.text_quad_normals = []
	new_fft_map_data.black_tri_vertices = []
	new_fft_map_data.black_quad_vertices = []
	var original_map_size: Vector2i = Vector2i(new_fft_map_data.map_width, new_fft_map_data.map_length)
	new_fft_map_data.map_width = cropped_rect.size.x
	new_fft_map_data.map_length = cropped_rect.size.y

	var vertex_translation: Vector3 = Vector3(-cropped_rect.position.x, 0, -cropped_rect.position.y) * FftMapData.TILE_SIDE_LENGTH

	var new_map_textured_tri_index: int = 0
	var new_map_black_tri_index: int = 0
	var new_map_textured_quad_index: int = 0
	var new_map_black_quad_index: int = 0

	var textured_tri_tile_bytes: PackedByteArray = []
	var textured_quad_tile_bytes: PackedByteArray = []
	
	for mirrored_map_quadrant: Vector2i in mirrored_map_data.keys():
		var mirrored_map: FftMapData = mirrored_map_data[mirrored_map_quadrant]

		var quadrant_start_position: Vector2i = Vector2i.ZERO # bottom left corner of map
		quadrant_start_position.x = mirrored_map.map_width * mirrored_map_quadrant.x
		quadrant_start_position.y = mirrored_map.map_length * mirrored_map_quadrant.y
		var mirrored_map_rect: Rect2i = Rect2i(quadrant_start_position, Vector2i(original_map_size))
		var cropped_intersection: Rect2i = cropped_rect.intersection(mirrored_map_rect)
		
		# get polygon data
		var cropped_polygon_rect: Rect2i = cropped_intersection.grow_individual(0, 0, 1, 1) # include polygons along bottom and right borders
		cropped_polygon_rect.position = cropped_polygon_rect.position * FftMapData.TILE_SIDE_LENGTH
		cropped_polygon_rect.size = cropped_polygon_rect.size * FftMapData.TILE_SIDE_LENGTH
		
		# add textured tris
		for tri_index: int in mirrored_map.num_text_tris:
			var tri_verticies: Array[Vector3i] = []
			var tri_normals: PackedVector3Array = []
			var polygon_in_bounds: bool = true
			for vertex_index: int in FftMapData.NUM_VERTICIES_PER_TRI:
				var total_index: int = (tri_index * FftMapData.NUM_VERTICIES_PER_TRI) + vertex_index
				var new_vertex: Vector3i = Vector3i(mirrored_map.text_tri_vertices[total_index].round())
				tri_verticies.append(new_vertex)
				tri_normals.append(mirrored_map.text_tri_normals[total_index])

				if not cropped_polygon_rect.has_point(Vector2i(new_vertex.x, new_vertex.z)):
					polygon_in_bounds = false
			
			if not polygon_in_bounds:
				continue

			var centroid: Vector3 = Vector3.ZERO
			for vertex_index: int in FftMapData.NUM_VERTICIES_PER_TRI:
				var new_map_total_index: int = (new_map_textured_tri_index * FftMapData.NUM_VERTICIES_PER_TRI) + vertex_index
				if new_fft_map_data.text_tri_vertices.size() > new_map_total_index - 1:
					new_fft_map_data.text_tri_vertices.resize(new_map_total_index + 1)
					new_fft_map_data.text_tri_normals.resize(new_map_total_index + 1)
				var translated_vertex: Vector3 = Vector3(tri_verticies[vertex_index]) + vertex_translation
				centroid += translated_vertex
				new_fft_map_data.text_tri_vertices[new_map_total_index] = translated_vertex
				new_fft_map_data.text_tri_normals[new_map_total_index] = Vector3(tri_normals[vertex_index])
			new_map_textured_tri_index += 1
			var tri_texture_bytes_start: int = tri_index * FftMapData.TEXTURE_BYTES_PER_TRI
			var polygon_texture_bytes: PackedByteArray = mirrored_map.tris_texture_bytes.slice(tri_texture_bytes_start, tri_texture_bytes_start + FftMapData.TEXTURE_BYTES_PER_TRI)
			new_fft_map_data.tris_texture_bytes.append_array(polygon_texture_bytes)

			# Centroid calculation and tile coordinates encoding
			centroid = centroid / 3.0
			var polygon_tile_offset: int = textured_tri_tile_bytes.size()
			textured_tri_tile_bytes.resize(polygon_tile_offset + 2)
			encode_polygon_tile_bytes(textured_tri_tile_bytes, polygon_tile_offset, centroid, 0)
			
		# add black tris
		for tri_index: int in mirrored_map.num_black_tris:
			var tri_verticies: Array[Vector3i] = []
			var polygon_in_bounds: bool = true
			for vertex_index: int in FftMapData.NUM_VERTICIES_PER_TRI:
				var total_index: int = (tri_index * FftMapData.NUM_VERTICIES_PER_TRI) + vertex_index
				var new_vertex: Vector3i = Vector3i(mirrored_map.black_tri_vertices[total_index].round())
				tri_verticies.append(new_vertex)

				if not cropped_polygon_rect.has_point(Vector2i(new_vertex.x, new_vertex.z)):
					polygon_in_bounds = false
					break
			
			if not polygon_in_bounds:
				continue
			
			for vertex_index: int in FftMapData.NUM_VERTICIES_PER_TRI:
				var new_map_total_index: int = (new_map_black_tri_index * FftMapData.NUM_VERTICIES_PER_TRI) + vertex_index
				if new_fft_map_data.black_tri_vertices.size() > new_map_total_index - 1:
					new_fft_map_data.black_tri_vertices.resize(new_map_total_index + 1)
				new_fft_map_data.black_tri_vertices[new_map_total_index] = Vector3(tri_verticies[vertex_index]) + vertex_translation
			new_map_black_tri_index += 1

		# add textured quads
		for quad_index: int in mirrored_map.num_text_quads:
			var quad_verticies: Array[Vector3i] = []
			var quad_normals: PackedVector3Array = []
			var polygon_in_bounds: bool = true
			for vertex_index: int in FftMapData.NUM_VERTICIES_PER_QUAD:
				var total_index: int = (quad_index * FftMapData.NUM_VERTICIES_PER_QUAD) + vertex_index
				var new_vertex: Vector3i = Vector3i(mirrored_map.text_quad_vertices[total_index].round())
				quad_verticies.append(new_vertex)
				quad_normals.append(mirrored_map.text_quad_normals[total_index])

				if not cropped_polygon_rect.has_point(Vector2i(new_vertex.x, new_vertex.z)):
					polygon_in_bounds = false
			
			if not polygon_in_bounds:
				continue

			var centroid: Vector3 = Vector3.ZERO
			for vertex_index: int in FftMapData.NUM_VERTICIES_PER_QUAD:
				var new_map_total_index: int = (new_map_textured_quad_index * FftMapData.NUM_VERTICIES_PER_QUAD) + vertex_index
				if new_fft_map_data.text_quad_vertices.size() > new_map_total_index - 1:
					new_fft_map_data.text_quad_vertices.resize(new_map_total_index + 1)
					new_fft_map_data.text_quad_normals.resize(new_map_total_index + 1)
				var translated_vertex: Vector3 = Vector3(quad_verticies[vertex_index]) + vertex_translation
				centroid += translated_vertex
				new_fft_map_data.text_quad_vertices[new_map_total_index] = translated_vertex
				new_fft_map_data.text_quad_normals[new_map_total_index] = Vector3(quad_normals[vertex_index])
			new_map_textured_quad_index += 1
			var quad_texture_bytes_start: int = quad_index * FftMapData.TEXTURE_BYTES_PER_QUAD
			var polygon_texture_bytes: PackedByteArray = mirrored_map.quads_texture_bytes.slice(quad_texture_bytes_start, quad_texture_bytes_start + FftMapData.TEXTURE_BYTES_PER_QUAD)
			new_fft_map_data.quads_texture_bytes.append_array(polygon_texture_bytes)

			# Centroid calculation and tile coordinates encoding
			centroid = centroid / 4.0
			var polygon_tile_offset: int = textured_quad_tile_bytes.size()
			textured_quad_tile_bytes.resize(polygon_tile_offset + 2)
			encode_polygon_tile_bytes(textured_quad_tile_bytes, polygon_tile_offset, centroid, 0)

		# add black quads
		for quad_index: int in mirrored_map.num_black_quads:
			var quad_verticies: Array[Vector3i] = []
			var polygon_in_bounds: bool = true
			
			for vertex_index: int in FftMapData.NUM_VERTICIES_PER_QUAD:
				var total_index: int = (quad_index * FftMapData.NUM_VERTICIES_PER_QUAD) + vertex_index
				var new_vertex: Vector3i = Vector3i(mirrored_map.black_quad_vertices[total_index].round())
				quad_verticies.append(new_vertex)

				if not cropped_polygon_rect.has_point(Vector2i(new_vertex.x, new_vertex.z)):
					polygon_in_bounds = false
					break
			
			if not polygon_in_bounds:
				continue
			
			for vertex_index: int in FftMapData.NUM_VERTICIES_PER_QUAD:
				var new_map_total_index: int = (new_map_black_quad_index * FftMapData.NUM_VERTICIES_PER_QUAD) + vertex_index
				if new_fft_map_data.black_quad_vertices.size() > new_map_total_index - 1:
					new_fft_map_data.black_quad_vertices.resize(new_map_total_index + 1)
				new_fft_map_data.black_quad_vertices[new_map_total_index] = Vector3(quad_verticies[vertex_index]) + vertex_translation
			new_map_black_quad_index += 1

		# get terrain data
		var cropped_terrain_rect: Rect2i = cropped_intersection.grow_individual(0, 0, 0, 0) # grow rect so terrain tiles on edge are included
		# cropped_terrain_rect.position = cropped_terrain_rect.position - Vector2i(0, 1) # shift rect so points on the top are not included and so points on the bottom are included
		for layer: int in [0, 1]:
			for z: int in mirrored_map.map_length:
				for x: int in mirrored_map.map_width:
					var relative_position: Vector2i = Vector2i(x, z) + quadrant_start_position
					if cropped_terrain_rect.has_point(relative_position):
						var tile_index: int = x + (z * mirrored_map.map_width)
						var tile_data_start: int = 2 + (tile_index * FftMapData.BYTES_PER_TERRAIN_TILE) + (layer * 256 * FftMapData.BYTES_PER_TERRAIN_TILE) # each layer has space for 256 tiles, each tile data is 8 bytes
						var tile_data: PackedByteArray = mirrored_map.terrain_data_bytes.slice(tile_data_start, tile_data_start + FftMapData.BYTES_PER_TERRAIN_TILE)

						var final_tile_position: Vector2i = relative_position - cropped_rect.position
						var final_tile_index: int = final_tile_position.x + (final_tile_position.y * cropped_rect.size.x)
						var final_tile_byte_start: int = 2 + (final_tile_index * FftMapData.BYTES_PER_TERRAIN_TILE) + (layer * 256 * FftMapData.BYTES_PER_TERRAIN_TILE)

						for byte_index: int in FftMapData.BYTES_PER_TERRAIN_TILE:
							new_fft_map_data.terrain_data_bytes[final_tile_byte_start + byte_index] = tile_data[byte_index]
	new_fft_map_data.terrain_data_bytes.encode_u8(0, new_fft_map_data.map_width)
	new_fft_map_data.terrain_data_bytes.encode_u8(1, new_fft_map_data.map_length)

	var total_tiles: int = new_fft_map_data.map_width * new_fft_map_data.map_length
	if total_tiles > 256:
		push_warning("Total tiles > 256: " + str(new_fft_map_data.map_width) + " x " + str(new_fft_map_data.map_length) + " = " + str(total_tiles))

	new_fft_map_data.num_text_tris = new_map_textured_tri_index
	new_fft_map_data.num_black_tris = new_map_black_tri_index
	new_fft_map_data.num_text_quads = new_map_textured_quad_index
	new_fft_map_data.num_black_quads = new_map_black_quad_index

	if new_fft_map_data.num_text_tris > 360:
		push_warning("Total textured tris > 360: " + str(new_fft_map_data.num_text_tris))
	if new_fft_map_data.num_black_tris > 64:
		push_warning("Total black tris > 64: " + str(new_fft_map_data.num_black_tris))
	if new_fft_map_data.num_text_quads > 710:
		push_warning("Total textured quads > 710: " + str(new_fft_map_data.num_text_quads))
	if new_fft_map_data.num_black_quads > 256:
		push_warning("Total black quads > 256: " + str(new_fft_map_data.num_black_quads))

	new_fft_map_data.untextured_polygon_bytes.resize((4 * new_fft_map_data.num_black_tris) + (4 * new_fft_map_data.num_black_quads))
	new_fft_map_data.untextured_polygon_bytes.fill(0)

	new_fft_map_data.textured_polygon_tile_bytes = []
	new_fft_map_data.textured_polygon_tile_bytes.append_array(textured_tri_tile_bytes)
	new_fft_map_data.textured_polygon_tile_bytes.append_array(textured_quad_tile_bytes)

	return new_fft_map_data


static func get_mirrored_expanded_map_data(original_fft_map_data: FftMapData, quadrants: PackedVector2Array, set_depth_zero: bool = false) -> Dictionary[Vector2i, FftMapData]:
	var mirrored_map_data: Dictionary[Vector2i, FftMapData] = {}
	
	for quadrant: Vector2 in quadrants:
		var adjusted_quadrant: Vector2i = Vector2i(roundi(quadrant.x), roundi(quadrant.y))
		var mirrored_fft_map_data: FftMapData = get_mirror_fft_map_data(original_fft_map_data, adjusted_quadrant, set_depth_zero)
		mirrored_map_data[adjusted_quadrant] = mirrored_fft_map_data
	
	return mirrored_map_data


static func get_mirror_fft_map_data(original_fft_map_data: FftMapData, adjusted_quadrant: Vector2i, set_depth_zero: bool = false) -> FftMapData:
	var mirrored_fft_map: FftMapData = original_fft_map_data.duplicate_deep()
	mirrored_fft_map.terrain_data_bytes.fill(0)

	var mirror_scale: Vector3 = Vector3.ONE
	if adjusted_quadrant.x % 2 != 0:
		mirror_scale.x = -1.0
	if adjusted_quadrant.y % 2 != 0:
		mirror_scale.z = -1.0
	
	var map_translation: Vector3 = Vector3.ZERO
	map_translation.x = adjusted_quadrant.x * mirrored_fft_map.map_width
	map_translation.z = adjusted_quadrant.y * mirrored_fft_map.map_length
	if mirror_scale.x == -1.0:
		map_translation.x = (adjusted_quadrant.x + 1) * mirrored_fft_map.map_width # extra adjustment due to implicit translation due to scaling
	if mirror_scale.z == -1.0:
		map_translation.z = (adjusted_quadrant.y + 1) * mirrored_fft_map.map_length # extra adjustment due to implicit translation due to scaling

	var reverse_winding: bool = false
	if mirror_scale == Vector3(-1.0, 1.0, 1.0) or mirror_scale == Vector3(1.0, 1.0, -1.0):
		reverse_winding = true
	
	# add textured tris
	for tri_index: int in mirrored_fft_map.num_text_tris:
		var texture_bytes_start: int = tri_index * FftMapData.TEXTURE_BYTES_PER_TRI
		var original_texture_bytes: PackedByteArray = mirrored_fft_map.tris_texture_bytes.slice(texture_bytes_start, texture_bytes_start + FftMapData.TEXTURE_BYTES_PER_TRI)

		for vertex_index: int in FftMapData.NUM_VERTICIES_PER_TRI:
			var total_index: int = (tri_index * FftMapData.NUM_VERTICIES_PER_TRI) + vertex_index
			var mirror_index: int = total_index
			if reverse_winding and [0, 2].has(vertex_index):
				mirror_index = (tri_index * FftMapData.NUM_VERTICIES_PER_TRI) + FftMapData.NUM_VERTICIES_PER_TRI - 1 - vertex_index
			mirrored_fft_map.text_tri_vertices[mirror_index] = (original_fft_map_data.text_tri_vertices[total_index] * mirror_scale) + (map_translation * FftMapData.TILE_SIDE_LENGTH)
			mirrored_fft_map.text_tri_normals[mirror_index] = original_fft_map_data.text_tri_normals[total_index] * mirror_scale
			
			# reverse winding UVs
			if reverse_winding and vertex_index == 1:
				mirrored_fft_map.tris_texture_bytes[texture_bytes_start + 8] = original_texture_bytes[0]
				mirrored_fft_map.tris_texture_bytes[texture_bytes_start + 9] = original_texture_bytes[1]
			elif reverse_winding and vertex_index == 2:
				mirrored_fft_map.tris_texture_bytes[texture_bytes_start + 0] = original_texture_bytes[8]
				mirrored_fft_map.tris_texture_bytes[texture_bytes_start + 1] = original_texture_bytes[9]

	# add black tris
	for tri_index: int in mirrored_fft_map.num_black_tris:
		for vertex_index: int in FftMapData.NUM_VERTICIES_PER_TRI:
			var total_index: int = (tri_index * FftMapData.NUM_VERTICIES_PER_TRI) + vertex_index
			var mirror_index: int = total_index
			if reverse_winding and [0, 2].has(vertex_index):
				mirror_index = (tri_index * FftMapData.NUM_VERTICIES_PER_TRI) + FftMapData.NUM_VERTICIES_PER_TRI - 1 - vertex_index
			mirrored_fft_map.black_tri_vertices[mirror_index] = (original_fft_map_data.black_tri_vertices[total_index] * mirror_scale) + (map_translation * FftMapData.TILE_SIDE_LENGTH)

	# add textured quads
	for quad_index: int in mirrored_fft_map.num_text_quads:
		var texture_bytes_start: int = quad_index * FftMapData.TEXTURE_BYTES_PER_QUAD
		var original_texture_bytes: PackedByteArray = mirrored_fft_map.quads_texture_bytes.slice(texture_bytes_start, texture_bytes_start + FftMapData.TEXTURE_BYTES_PER_QUAD)
		
		for vertex_index: int in FftMapData.NUM_VERTICIES_PER_QUAD:
			var total_index: int = (quad_index * FftMapData.NUM_VERTICIES_PER_QUAD) + vertex_index
			var mirror_index: int = total_index
			if reverse_winding and [1, 2].has(vertex_index):
				mirror_index = (quad_index * FftMapData.NUM_VERTICIES_PER_QUAD) + FftMapData.NUM_VERTICIES_PER_QUAD - 1 - vertex_index
			mirrored_fft_map.text_quad_vertices[mirror_index] = (original_fft_map_data.text_quad_vertices[total_index] * mirror_scale) + (map_translation * FftMapData.TILE_SIDE_LENGTH)
			mirrored_fft_map.text_quad_normals[mirror_index] = original_fft_map_data.text_quad_normals[total_index] * mirror_scale

			# reverse winding UVs
			if reverse_winding and vertex_index == 1:
				mirrored_fft_map.quads_texture_bytes[texture_bytes_start + 8] = original_texture_bytes[4]
				mirrored_fft_map.quads_texture_bytes[texture_bytes_start + 9] = original_texture_bytes[5]
			elif reverse_winding and vertex_index == 2:
				mirrored_fft_map.quads_texture_bytes[texture_bytes_start + 4] = original_texture_bytes[8]
				mirrored_fft_map.quads_texture_bytes[texture_bytes_start + 5] = original_texture_bytes[9]

	# add black quads
	for quad_index: int in mirrored_fft_map.num_black_quads:
		for vertex_index: int in FftMapData.NUM_VERTICIES_PER_QUAD:
			var total_index: int = (quad_index * FftMapData.NUM_VERTICIES_PER_QUAD) + vertex_index
			var mirror_index: int = total_index
			if reverse_winding and [1, 2].has(vertex_index):
				mirror_index = (quad_index * FftMapData.NUM_VERTICIES_PER_QUAD) + FftMapData.NUM_VERTICIES_PER_QUAD - 1 - vertex_index
			mirrored_fft_map.black_quad_vertices[mirror_index] = (original_fft_map_data.black_quad_vertices[total_index] * mirror_scale) + (map_translation * FftMapData.TILE_SIDE_LENGTH)

	# mirror terrain_tile data
	for layer: int in [0, 1]:
		for z: int in original_fft_map_data.map_length:
			for x: int in original_fft_map_data.map_width:
				var tile_index: int = x + (z * original_fft_map_data.map_width)
				var tile_data_start: int = 2 + (tile_index * FftMapData.BYTES_PER_TERRAIN_TILE) + (layer * 256 * FftMapData.BYTES_PER_TERRAIN_TILE) # first 2 bytes are width and length, each layer has space for 256 tiles, each tile data is 8 bytes
				var tile_data: PackedByteArray = original_fft_map_data.terrain_data_bytes.slice(tile_data_start, tile_data_start + FftMapData.BYTES_PER_TERRAIN_TILE)

				var mirrored_tile_index: int = tile_index
				var mirrored_x: int = x
				var mirrored_z: int = z
				var slope_type: int = tile_data.decode_u8(4) # https://ffhacktics.com/wiki/Slope_Type
				if mirror_scale.x == -1.0:
					mirrored_x = -x + mirrored_fft_map.map_width - 1
					if slope_type == 0x52:
						slope_type = 0x58
					elif slope_type == 0x58:
						slope_type = 0x52
					elif slope_type == 0x41:
						slope_type = 0x44
					elif slope_type == 0x44:
						slope_type = 0x41
					elif slope_type == 0x11:
						slope_type = 0x14
					elif slope_type == 0x14:
						slope_type = 0x11
					elif slope_type == 0x96:
						slope_type = 0x99
					elif slope_type == 0x99:
						slope_type = 0x96
					elif slope_type == 0x66:
						slope_type = 0x69
					elif slope_type == 0x69:
						slope_type = 0x66

				if mirror_scale.z == -1.0:
					mirrored_z = -z + mirrored_fft_map.map_length - 1
					if slope_type == 0x25:
						slope_type = 0x85
					elif slope_type == 0x85:
						slope_type = 0x25
					elif slope_type == 0x41:
						slope_type = 0x11
					elif slope_type == 0x11:
						slope_type = 0x41
					elif slope_type == 0x44:
						slope_type = 0x14
					elif slope_type == 0x14:
						slope_type = 0x44
					elif slope_type == 0x96:
						slope_type = 0x66
					elif slope_type == 0x66:
						slope_type = 0x96
					elif slope_type == 0x99:
						slope_type = 0x69
					elif slope_type == 0x69:
						slope_type = 0x99
				
				mirrored_tile_index = mirrored_x + (mirrored_z * original_fft_map_data.map_width)

				var new_tile_data: PackedByteArray = tile_data.duplicate()
				# optionally zero out all depth
				if set_depth_zero:
					var depth: int = tile_data.decode_u8(3) >> 5 # left 3 bits are depth
					var height: int = tile_data.decode_u8(2)
					new_tile_data.encode_u8(2, height + depth)
					new_tile_data.encode_u8(3, tile_data.decode_u8(3) & 0x1F) # left 3 bits are depth, set to 0, keep right 5 bits

				# mirror slope type
				new_tile_data.encode_u8(4, slope_type)

				# TODO mirror camera rotate?
				# tile.default_camera_position_id = tile_data.decode_u8(7)

				var new_tile_bytes_start: int = 2 + (mirrored_tile_index * FftMapData.BYTES_PER_TERRAIN_TILE) + (layer * 256 * FftMapData.BYTES_PER_TERRAIN_TILE)
				for byte_index: int in FftMapData.BYTES_PER_TERRAIN_TILE:
					mirrored_fft_map.terrain_data_bytes[new_tile_bytes_start + byte_index] = new_tile_data[byte_index]
	mirrored_fft_map.terrain_data_bytes.encode_u8(0, mirrored_fft_map.map_width)
	mirrored_fft_map.terrain_data_bytes.encode_u8(1, mirrored_fft_map.map_length)
	
	# TODO delete overlapping polygons at seams?

	return mirrored_fft_map

