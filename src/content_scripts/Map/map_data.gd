#https://ffhacktics.com/wiki/Maps/Mesh
class_name MapData
extends Resource

const TILE_SIDE_LENGTH: int = 28
const UNITS_PER_HEIGHT: int = 12
const SCALE: float = 1.0 / TILE_SIDE_LENGTH
const HEIGHT_SCALE: float = UNITS_PER_HEIGHT / (TILE_SIDE_LENGTH * 1.0)

var unique_name: String = "unique_name"
var display_name: String = "display_name"
var description: String = "description"

var is_initialized: bool = false


## Mirror CUSTOM0 centroid data in surface arrays.
## Returns the CUSTOM0 format flags to pass to add_surface_from_arrays().
static func mirror_custom0(surface_arrays: Array, center: Vector3, mirror_scale: Vector3, half_size: Vector3) -> int:
	if surface_arrays.size() <= Mesh.ARRAY_CUSTOM0 or surface_arrays[Mesh.ARRAY_CUSTOM0] == null:
		return 0
	var floats: PackedFloat32Array = surface_arrays[Mesh.ARRAY_CUSTOM0]
	for vi in range(floats.size() / 3):
		var base: int = vi * 3
		var c := Vector3(floats[base], floats[base + 1], floats[base + 2])
		c = (c - center) * mirror_scale + half_size
		floats[base] = c.x
		floats[base + 1] = c.y
		floats[base + 2] = c.z
	surface_arrays[Mesh.ARRAY_CUSTOM0] = floats
	# Godot needs explicit format flags for CUSTOM0 in add_surface_from_arrays()
	# RGB_FLOAT = 6, CUSTOM0 format shift = 13
	return (6 << 13)

var file_name: String = "default map file name"
var primary_mesh_data_record: MapFileRecord
var primary_texture_record: MapFileRecord
var other_data_record: MapFileRecord
var map_file_records: Array[MapFileRecord] = []

var mesh: ArrayMesh
var mesh_material: StandardMaterial3D
var albedo_texture: Texture2D
var albedo_texture_indexed: Texture2D
var st: SurfaceTool = SurfaceTool.new()
const TEXTURE_SIZE: Vector2i = Vector2i(256, 1024)

var num_text_tris: int = 0
var num_text_quads: int = 0
var num_black_tris: int = 0
var num_black_quads: int = 0

var text_tri_vertices: PackedVector3Array = []
var text_quad_vertices: PackedVector3Array = []
var black_tri_vertices: PackedVector3Array = []
var black_quad_vertices: PackedVector3Array = []

var text_tri_normals: PackedVector3Array = []
var text_quad_normals: PackedVector3Array = []

var tris_uvs: PackedVector2Array = []
var quads_uvs: PackedVector2Array = []
var tris_palettes: PackedInt32Array = []
var quads_palettes: PackedInt32Array = []

var texture_palettes: PackedColorArray = []
var texture_color_indices: PackedInt32Array = []

var background_gradient_top: Color = Color.DIM_GRAY
var background_gradient_bottom: Color = Color.BLACK

var map_width: int = 0 # width (x) in tiles
var map_length: int = 0 # length (y) in tiles
var terrain_tiles: Array[TerrainTile] = []

# texture animations
var has_texture_animations: bool = false
var texture_anim_instructions_bytes: Array[PackedByteArray] = []
var texture_animations_palette_frames: Array[PackedColorArray] = []
var texture_animations: Array[TextureAnimationData] = []

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
	var frame1_x: int 
	var palette_id_to_animate: int 
	var animation_starting_index: int 

func _init(map_file_name: String) -> void:
	file_name = map_file_name


func init_map() -> void:
	var map_gns_data: PackedByteArray = RomReader.get_file_data(file_name)
	init_map_data(map_gns_data)
	is_initialized = true


func init_map_data(gns_bytes: PackedByteArray) -> void:
	map_file_records = get_associated_files(gns_bytes)
	push_warning("MapChunkNodes Mesh File: " + primary_mesh_data_record.file_name)
	push_warning("MapChunkNodes Texture File: " + primary_texture_record.file_name)
	create_map(RomReader.get_file_data(primary_mesh_data_record.file_name), 
			RomReader.get_file_data(primary_texture_record.file_name))


func create_map(mesh_bytes: PackedByteArray, texture_bytes: PackedByteArray = []) -> void:
	var other_bytes: PackedByteArray = mesh_bytes
	if file_name == "MAP053.GNS": # handle special case
		other_bytes = RomReader.get_file_data(other_data_record.file_name)
		
	var primary_mesh_data_start: int = mesh_bytes.decode_u32(0x40)
	var texture_palettes_data_start: int = other_bytes.decode_u32(0x44)
	var lighting_data_start: int = other_bytes.decode_u32(0x64)
	var terrain_data_start: int = other_bytes.decode_u32(0x68)
	var texture_animation_instructions_data_start: int = other_bytes.decode_u32(0x6c)
	var palette_animation_frames_data_start: int = other_bytes.decode_u32(0x70)
	#var primary_mesh_data_end: int = texture_palettes_data_start if texture_palettes_data_start > 0 else 2147483647
	
	#var primary_mesh_data: PackedByteArray = mesh_bytes.slice(primary_mesh_data_start, primary_mesh_data_end)
	var primary_mesh_data: PackedByteArray = mesh_bytes.slice(primary_mesh_data_start)
	set_mesh_data(primary_mesh_data)
	
	if texture_palettes_data_start == 0:
		push_warning("No palette data found")
		pass
	else:
		var texture_palettes_data_end: int = texture_palettes_data_start + 512
		var texture_palettes_data: PackedByteArray = other_bytes.slice(texture_palettes_data_start, texture_palettes_data_end)
		texture_palettes = get_texture_palettes(texture_palettes_data)
	
	if lighting_data_start == 0:
		push_warning("No lighting data found")
		pass
	else:
		var lighting_data_length: int = 18 + 18 + 3 + 6 # 6 bytes for each directional light color, position, 3 bytes for ambient light color, 6 bytes for gradient colors
		var lighting_data_end: int = lighting_data_start + lighting_data_length
		var lighting_data: PackedByteArray = other_bytes.slice(lighting_data_length, lighting_data_end)
		set_gradient_colors(lighting_data.slice(-6))
	
	if terrain_data_start == 0:
		push_warning("No terrain data found")
		pass
	else:
		var terrain_data_length: int = 2 + (256 * 8 * 2)
		var terrain_data_end: int = terrain_data_start + terrain_data_length
		var terrain_data: PackedByteArray = other_bytes.slice(terrain_data_start, terrain_data_end)
		terrain_tiles = get_terrain(terrain_data)
	
	_create_mesh()
	
	albedo_texture = get_texture_all(texture_bytes)
	mesh_material = StandardMaterial3D.new()
	mesh_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mesh_material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	mesh_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	mesh_material.vertex_color_use_as_albedo = true
	mesh_material.set_texture(BaseMaterial3D.TEXTURE_ALBEDO, albedo_texture)
	mesh.surface_set_material(0, mesh_material)
	
	albedo_texture_indexed = get_texture_indexed_all(texture_bytes)
	
	# https://ffhacktics.com/wiki/Maps/Mesh#Texture_animation_instructions
	# animated texture data
	if texture_animation_instructions_data_start != 0:
		has_texture_animations = true
		texture_animations.resize(32)
		texture_anim_instructions_bytes.resize(32)
		for texture_anim_id: int in 32:
			var texture_animation: TextureAnimationData = TextureAnimationData.new()
			var texture_anim_bytes_start: int = texture_animation_instructions_data_start + (texture_anim_id * 20)
			var texture_anim_instruction_bytes: PackedByteArray = other_bytes.slice(texture_anim_bytes_start, texture_anim_bytes_start + 20)
			texture_anim_instructions_bytes[texture_anim_id] = texture_anim_instruction_bytes
			
			texture_animation.texture_anim_instruction_bytes = texture_anim_instruction_bytes
			
			texture_animation.canvas_y = texture_anim_instruction_bytes.decode_u8(2)
			texture_animation.canvas_width = texture_anim_instruction_bytes.decode_u8(4) * 4
			texture_animation.canvas_height = texture_anim_instruction_bytes.decode_u8(6)
			texture_animation.frame1_y = texture_anim_instruction_bytes.decode_u8(10)
			# UV animation: 0x01 repeat loop forward, 0x02 loop ping pong forward <-> backward, 0x05 script command, 0x15 script command
			# palette animation: 0x03 repeat loop forward, 0x04 loop ping pong forward <-> backward, 0x00 script command, 0x13 script command
			texture_animation.anim_technique = texture_anim_instruction_bytes.decode_u8(14) 
			texture_animation.num_frames = texture_anim_instruction_bytes.decode_u8(15)
			texture_animation.frame_duration = texture_anim_instruction_bytes.decode_u8(17) # 1/30ths of a second (ie. 2 frames)
			
			if texture_anim_instruction_bytes.decode_u8(1) == 0x03 and texture_anim_instruction_bytes.decode_u8(9) == 0x03:
				texture_animation.animation_type = 0 # UV animation
				texture_animation.texture_page = texture_anim_instruction_bytes.decode_u8(0) * 4 / 256
				texture_animation.canvas_x = texture_anim_instruction_bytes.decode_u8(0) * 4 % 256
				texture_animation.frame1_x = texture_anim_instruction_bytes.decode_u8(8) * 4 % 256
			elif (texture_anim_instruction_bytes.decode_u8(1) == 0x00 
					and texture_anim_instruction_bytes.decode_u8(2) == 0xe0
					and texture_anim_instruction_bytes.decode_u8(3) == 0x01):
				texture_animation.animation_type = 1 # palette animation
				texture_animation.palette_id_to_animate = texture_anim_instruction_bytes.decode_u8(0) >> 4
				texture_animation.animation_starting_index = texture_anim_instruction_bytes.decode_u8(8)
				
			texture_animations[texture_anim_id] = texture_animation
	
	if palette_animation_frames_data_start != 0:
		texture_animations_palette_frames.resize(16)
		for palette_frame_id: int in 16:
			var palette_frame_bytes_start: int = palette_animation_frames_data_start + (palette_frame_id * 32)
			var palette_frame_bytes: PackedByteArray = other_bytes.slice(palette_frame_bytes_start, palette_frame_bytes_start + 32)
			var palette_frame: PackedColorArray
			palette_frame.resize(16)
			for color_id: int in 16:
				var color_bits: int = palette_frame_bytes.decode_u16(color_id * 2)
				palette_frame[color_id] = color5_to_color8(color_bits)
			texture_animations_palette_frames[palette_frame_id] = palette_frame


func clear_map_data() -> void:
	mesh = null
	mesh_material = null
	albedo_texture = null
	
	num_text_tris = 0
	num_text_quads = 0
	num_black_tris = 0
	num_black_quads = 0
	
	text_tri_vertices = []
	text_quad_vertices = []
	black_tri_vertices = []
	black_quad_vertices = []
	
	text_tri_normals = []
	text_quad_normals = []
	
	tris_uvs = []
	quads_uvs = []
	tris_palettes = []
	quads_palettes = []
	
	texture_palettes = []
	texture_color_indices = []
	
	map_width = 0
	map_length = 0
	terrain_tiles = []


func _create_mesh() -> void:
	st.clear()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_custom_format(0, SurfaceTool.CUSTOM_RGB_FLOAT)

	# add textured tris
	for i: int in num_text_tris:
		var v0: Vector3 = text_tri_vertices[i * 3] * SCALE
		var v1: Vector3 = text_tri_vertices[i * 3 + 1] * SCALE
		var v2: Vector3 = text_tri_vertices[i * 3 + 2] * SCALE
		var centroid: Vector3 = (v0 + v1 + v2) / 3.0
		var centroid_color := Color(centroid.x, centroid.y, centroid.z, 0.0)
		for vertex_index: int in 3:
			var index: int = (i*3) + vertex_index
			st.set_normal(text_tri_normals[index] * SCALE)
			st.set_uv(tris_uvs[index])
			st.set_color(Color.WHITE)
			st.set_custom(0, centroid_color)
			st.add_vertex(text_tri_vertices[index] * SCALE)

	# add black tris
	for i: int in num_black_tris:
		var v0: Vector3 = black_tri_vertices[i * 3] * SCALE
		var v1: Vector3 = black_tri_vertices[i * 3 + 1] * SCALE
		var v2: Vector3 = black_tri_vertices[i * 3 + 2] * SCALE
		var centroid: Vector3 = (v0 + v1 + v2) / 3.0
		var centroid_color := Color(centroid.x, centroid.y, centroid.z, 0.0)
		for vertex_index: int in 3:
			var index: int = (i*3) + vertex_index
			st.set_color(Color.BLACK)
			st.set_custom(0, centroid_color)
			st.add_vertex(black_tri_vertices[index] * SCALE)

	# add textured quads
	for i: int in num_text_quads:
		var quad_start: int = i * 4
		var quad_end: int = (i + 1) * 4
		var quad_vertices: PackedVector3Array = text_quad_vertices.slice(quad_start, quad_end)
		var quad_normals: PackedVector3Array = text_quad_normals.slice(quad_start, quad_end)
		var quad_uvs: PackedVector2Array = quads_uvs.slice(quad_start, quad_end)
		var centroid: Vector3 = (quad_vertices[0] + quad_vertices[1] + quad_vertices[2] + quad_vertices[3]) * SCALE / 4.0
		var centroid_color := Color(centroid.x, centroid.y, centroid.z, 0.0)

		for vert_index: int in [0, 1, 2]:
			st.set_normal(quad_normals[vert_index] * SCALE) # TODO why is there error on MAP105 "terminate"
			st.set_uv(quad_uvs[vert_index])
			st.set_color(Color.WHITE)
			st.set_custom(0, centroid_color)
			st.add_vertex(quad_vertices[vert_index] * SCALE)

		for vert_index: int in [3, 2, 1]:
			st.set_normal(quad_normals[vert_index] * SCALE)
			st.set_uv(quad_uvs[vert_index])
			st.set_color(Color.WHITE)
			st.set_custom(0, centroid_color)
			st.add_vertex(quad_vertices[vert_index] * SCALE)

	# add black quads
	for i: int in num_black_quads:
		var quad_start: int = i * 4
		var quad_end: int = (i + 1) * 4
		var quad_vertices: PackedVector3Array = black_quad_vertices.slice(quad_start, quad_end)
		var centroid: Vector3 = (quad_vertices[0] + quad_vertices[1] + quad_vertices[2] + quad_vertices[3]) * SCALE / 4.0
		var centroid_color := Color(centroid.x, centroid.y, centroid.z, 0.0)

		for vert_index: int in [0, 1, 2]:
			st.set_color(Color.BLACK)
			st.set_custom(0, centroid_color)
			st.add_vertex(quad_vertices[vert_index] * SCALE)

		for vert_index: int in [3, 2, 1]:
			st.set_color(Color.BLACK)
			st.set_custom(0, centroid_color)
			st.add_vertex(quad_vertices[vert_index] * SCALE)

	mesh = st.commit()


func set_mesh_data(primary_mesh_data: PackedByteArray) -> void:
	num_text_tris = primary_mesh_data.decode_u16(0)
	num_text_quads = primary_mesh_data.decode_u16(2)
	num_black_tris = primary_mesh_data.decode_u16(4)
	num_black_quads = primary_mesh_data.decode_u16(6)
	
	var text_tris_vertices_data_length: int = num_text_tris * 2 * 3 * 3
	var text_quad_vertices_data_length: int = num_text_quads * 2 * 3 * 4
	var black_tris_vertices_data_length: int = num_black_tris * 2 * 3 * 3
	var black_quads_vertices_data_length: int = num_black_quads * 2 * 3 * 4
	var tris_uvs_data_length: int = num_text_tris * 10
	var quad_uvs_data_length: int = num_text_quads * 12
	
	var text_quad_vertices_start: int = 8 + text_tris_vertices_data_length
	var black_tris_vertices_start: int = text_quad_vertices_start + text_quad_vertices_data_length
	var black_quads_vertices_start: int = black_tris_vertices_start + black_tris_vertices_data_length
	var text_tri_normals_start: int = black_quads_vertices_start + black_quads_vertices_data_length
	var text_quad_normals_start: int = text_tri_normals_start + text_tris_vertices_data_length
	var tris_uvs_start: int = text_quad_normals_start + text_quad_vertices_data_length
	var quads_uvs_start: int = tris_uvs_start + tris_uvs_data_length
	
	text_tri_vertices = get_vertices(primary_mesh_data.slice(8, text_quad_vertices_start), num_text_tris * 3)
	text_quad_vertices = get_vertices(primary_mesh_data.slice(text_quad_vertices_start, black_tris_vertices_start), num_text_quads * 4)
	black_tri_vertices = get_vertices(primary_mesh_data.slice(black_tris_vertices_start, black_quads_vertices_start), num_black_tris * 3)
	black_quad_vertices = get_vertices(primary_mesh_data.slice(black_quads_vertices_start, text_tri_normals_start), num_black_quads * 4)
	
	text_tri_normals = get_normals(primary_mesh_data.slice(text_tri_normals_start, text_quad_normals_start), num_text_tris * 3)
	text_quad_normals = get_normals(primary_mesh_data.slice(text_quad_normals_start, tris_uvs_start), num_text_quads * 4)
	
	#tris_uvs = get_uvs(primary_mesh_data.slice(tris_uvs_start, quads_uvs_start), num_text_tris, false)
	#quads_uvs = get_uvs(primary_mesh_data.slice(quads_uvs_start, quads_uvs_start + quad_uvs_data_length), num_text_quads, true)
	tris_uvs = get_uvs_all_palettes(primary_mesh_data.slice(tris_uvs_start, quads_uvs_start), num_text_tris, false)
	quads_uvs = get_uvs_all_palettes(primary_mesh_data.slice(quads_uvs_start, quads_uvs_start + quad_uvs_data_length), num_text_quads, true)


func get_vertices(vertex_bytes: PackedByteArray, num_vertices: int) -> PackedVector3Array:
	var vertices: PackedVector3Array = []
	
	for vertex_index: int in num_vertices:
		var byte_index: int = vertex_index * 6
		var x: int = vertex_bytes.decode_s16(byte_index)
		var y: int = vertex_bytes.decode_s16(byte_index + 2)
		var z: int = vertex_bytes.decode_s16(byte_index + 4)
		
		var vertex: Vector3 = Vector3(x, y, z)
		vertices.append(vertex)
	
	return vertices


func get_normals(normals_bytes: PackedByteArray, num_vertices: int) -> PackedVector3Array:
	var normals: PackedVector3Array = []
	
	for vertex_index: int in num_vertices:
		var byte_index: int = vertex_index * 6
		var x: float = normals_bytes.decode_s16(byte_index) / 4096.0
		var y: float = normals_bytes.decode_s16(byte_index + 2) / 4096.0 
		var z: float = normals_bytes.decode_s16(byte_index + 4) / 4096.0
		
		var normal: Vector3 = Vector3(x, y, z)
		normals.append(normal)
	
	return normals


func get_uvs(uvs_bytes: PackedByteArray, num_polys: int, is_quad: bool = false) -> PackedVector2Array:
	var uvs: PackedVector2Array = []
	
	var data_length: int = 10
	if is_quad:
		data_length = 12
	
	for poly_index: int in num_polys:
		var byte_index: int = poly_index * data_length
		
		var texture_page: int = uvs_bytes.decode_u8(byte_index + 6) & 0b11 # two right most bits are texture page
		var v_offset: int = texture_page * 256
		var palette_index: int = uvs_bytes.decode_u8(byte_index + 2)
		
		# u and v need to be percentage, ie. u / width and v / height
		var au: float = uvs_bytes.decode_u8(byte_index) / 256.0
		var av: float = (uvs_bytes.decode_u8(byte_index + 1) + v_offset) / float(TEXTURE_SIZE.y)
		var bu: float = uvs_bytes.decode_u8(byte_index + 4) / 256.0
		var bv: float = (uvs_bytes.decode_u8(byte_index + 5) + v_offset) / float(TEXTURE_SIZE.y)
		var cu: float = uvs_bytes.decode_u8(byte_index + 8) / 256.0
		var cv: float = (uvs_bytes.decode_u8(byte_index + 9) + v_offset) / float(TEXTURE_SIZE.y)
		
		var auv: Vector2 = Vector2(au, av)
		var buv: Vector2 = Vector2(bu, bv)
		var cuv: Vector2 = Vector2(cu, cv)
		uvs.append(auv)
		uvs.append(buv)
		uvs.append(cuv)
		
		if is_quad:
			var du: float = uvs_bytes.decode_u8(byte_index + 10) / 256.0
			var dv: float = (uvs_bytes.decode_u8(byte_index + 11) + v_offset) / float(TEXTURE_SIZE.y)
			
			var duv: Vector2 = Vector2(du, dv)
			uvs.append(duv)
			quads_palettes.append(palette_index)
		else:
			tris_palettes.append(palette_index)
	
	return uvs


func get_uvs_all_palettes(uvs_bytes: PackedByteArray, num_polys: int, is_quad: bool = false) -> PackedVector2Array:
	var uvs: PackedVector2Array = []
	var num_palettes: int = 16
	
	var data_length: int = 10
	if is_quad:
		data_length = 12
	
	for poly_index: int in num_polys:
		var byte_index: int = poly_index * data_length
		
		var texture_page: int = uvs_bytes.decode_u8(byte_index + 6) & 0b11 # two right most bits are texture page
		var v_offset: int = texture_page * 256
		var palette_index: int = uvs_bytes.decode_u8(byte_index + 2)
		var x_offset: int = palette_index * 256
		
		# u and v need to be percentage, ie. u / width and v / height
		var au: float = (uvs_bytes.decode_u8(byte_index) + x_offset) / float(TEXTURE_SIZE.x * num_palettes)
		var av: float = (uvs_bytes.decode_u8(byte_index + 1) + v_offset) / float(TEXTURE_SIZE.y)
		var bu: float = (uvs_bytes.decode_u8(byte_index + 4) + x_offset) / float(TEXTURE_SIZE.x * num_palettes)
		var bv: float = (uvs_bytes.decode_u8(byte_index + 5) + v_offset) / float(TEXTURE_SIZE.y)
		var cu: float = (uvs_bytes.decode_u8(byte_index + 8) + x_offset) / float(TEXTURE_SIZE.x * num_palettes)
		var cv: float = (uvs_bytes.decode_u8(byte_index + 9) + v_offset) / float(TEXTURE_SIZE.y)
		
		var auv: Vector2 = Vector2(au, av)
		var buv: Vector2 = Vector2(bu, bv)
		var cuv: Vector2 = Vector2(cu, cv)
		uvs.append(auv)
		uvs.append(buv)
		uvs.append(cuv)
		
		if is_quad:
			var du: float = (uvs_bytes.decode_u8(byte_index + 10) + x_offset) / float(TEXTURE_SIZE.x * num_palettes)
			var dv: float = (uvs_bytes.decode_u8(byte_index + 11) + v_offset) / float(TEXTURE_SIZE.y)
			
			var duv: Vector2 = Vector2(du, dv)
			uvs.append(duv)
			quads_palettes.append(palette_index)
		else:
			tris_palettes.append(palette_index)
	
	return uvs


func get_texture_palettes(texture_palettes_bytes: PackedByteArray) -> PackedColorArray:
	var new_texture_palettes: PackedColorArray = []
	var num_colors: int = 256 # 16 palettes of 16 colors each
	new_texture_palettes.resize(num_colors)
	
	for i: int in num_colors:
		#var color: Color = Color.BLACK
		var color_bits: int = texture_palettes_bytes.decode_u16(i * 2)
		new_texture_palettes[i] = color5_to_color8(color_bits)
	
	return new_texture_palettes


func color5_to_color8(color_bits: int) -> Color:
	var color: Color = Color.BLACK
	color.a8 = (color_bits & 0b1000_0000_0000_0000) >> 15 # first bit is alpha (if bit is zero, color is transparent)
	color.b8 = (color_bits & 0b0111_1100_0000_0000) >> 10 # then 5 bits each: blue, green, red
	color.g8 = (color_bits & 0b0000_0011_1110_0000) >> 5
	color.r8 = color_bits & 0b0000_0000_0001_1111
	
	# convert 5 bit channels to 8 bit
	color.a8 = 255 * color.a8 # first bit is alpha (if bit is one, color is opaque)
	#color.a8 = 255 # TODO use alpha correctly?
	color.b8 = roundi(255 * (color.b8 / float(31))) # then 5 bits each: blue, green, red
	color.g8 = roundi(255 * (color.g8 / float(31)))
	color.r8 = roundi(255 * (color.r8 / float(31)))
	
	# if R == G == B == A == 0, then the color is transparent. 
	if (color == Color(0, 0, 0, 0)):
		color.a8 = 0
	#if (i % 16) == 0:
		#color.a8 = 0
	else:
		color.a8 = 255
	
	return color


func get_texture_color_indices(texture_bytes: PackedByteArray) -> PackedInt32Array:
	var new_color_indicies: PackedInt32Array = []
	var bits_per_pixel: int = 4
	new_color_indicies.resize(texture_bytes.size() * 2)
	
	for i: int in new_color_indicies.size():
		var pixel_offset: int = (i * bits_per_pixel)/8
		var byte: int = texture_bytes.decode_u8(pixel_offset)
		
		if i % 2 == 1: # get 4 leftmost bits
			new_color_indicies[i] = byte >> 4
		else:
			new_color_indicies[i] = byte & 0b0000_1111 # get 4 rightmost bits
	
	return new_color_indicies


func get_texture_pixel_colors(palette_id: int = 0) -> PackedColorArray:
	var new_pixel_colors: PackedColorArray = []
	var new_size: int = TEXTURE_SIZE.x * TEXTURE_SIZE.y
	new_pixel_colors.resize(new_size)
	new_pixel_colors.fill(Color.BLACK)
	for i: int in new_size:
		new_pixel_colors[i] = texture_palettes[texture_color_indices[i] + (16 * palette_id)]
	
	return new_pixel_colors


func get_texture_rgba8_image(palette_id: int = 0, pixel_colors: PackedColorArray = []) -> Image:
	var image: Image = Image.create_empty(TEXTURE_SIZE.x, TEXTURE_SIZE.y, false, Image.FORMAT_RGBA8)
	if pixel_colors.is_empty():
		pixel_colors = get_texture_pixel_colors(palette_id)
	
	for x: int in TEXTURE_SIZE.x:
		for y: int in TEXTURE_SIZE.y:
			var color: Color = pixel_colors[x + (y * TEXTURE_SIZE.x)]
			var color8: Color = Color8(color.r8, color.g8, color.b8, color.a8) # use Color8 function to prevent issues with format conversion changing color by 1/255
			image.set_pixel(x,y, color8) # spr stores pixel data left to right, top to bottm
	
	return image


func get_texture(texture_bytes: PackedByteArray, palette_id: int = 0) -> Texture2D:
	texture_color_indices = get_texture_color_indices(texture_bytes)
	
	#var unique_palettes: Dictionary = {}
	#for palette_index: int in tris_palettes:
		#unique_palettes[palette_index] = 1
	#push_warning("Tris palettes: " + str(unique_palettes.keys()))
	#
	#unique_palettes.clear()
	#for palette_index: int in quads_palettes:
		#unique_palettes[palette_index] = 1
	#push_warning("Quads palettes: " + str(unique_palettes.keys()))
	
	return ImageTexture.create_from_image(get_texture_rgba8_image(palette_id))


func get_texture_indexed_all(texture_bytes: PackedByteArray) -> ImageTexture:
	var num_palettes: int = 16
	var colors_per_palette: int = 16
	var image_width: int = TEXTURE_SIZE.x * num_palettes
	var image_indexed: Image = Image.create_empty(image_width, TEXTURE_SIZE.y, false, Image.FORMAT_RGBA8)
	texture_color_indices = get_texture_color_indices(texture_bytes)
	
	for x: int in TEXTURE_SIZE.x:
		for y: int in TEXTURE_SIZE.y:
			for palette_id: int in num_palettes:
				var new_color: Color = Color.from_rgba8(texture_color_indices[(TEXTURE_SIZE.x * y) + x] + (palette_id * colors_per_palette), 0, 0, 1)
				image_indexed.set_pixel(x + (palette_id * TEXTURE_SIZE.x), y, new_color)
	
	return ImageTexture.create_from_image(image_indexed)


func get_texture_color_indices_all(color_indices: PackedInt32Array) -> PackedInt32Array:
	var new_color_indicies: PackedInt32Array = []
	var num_palettes: int = 16
	var colors_per_palette: int = 16
	
	for row_index: int in (color_indices.size() / TEXTURE_SIZE.x):
		var row_start_index: int = row_index * TEXTURE_SIZE.x
		var row_end_index: int = row_start_index + TEXTURE_SIZE.x
		var row_indices: PackedInt32Array = color_indices.slice(row_start_index, row_end_index)
		
		for palette_index: int in num_palettes:
			var row_indices_adjusted: PackedInt32Array = []
			row_indices_adjusted.resize(TEXTURE_SIZE.x)
			row_indices_adjusted.fill(palette_index * colors_per_palette)
			
			for i: int in TEXTURE_SIZE.x:
				row_indices_adjusted[i] += row_indices[i]
			
			new_color_indicies.append_array(row_indices_adjusted)
	
	return new_color_indicies


func get_texture_pixel_colors_all() -> PackedColorArray:
	var new_pixel_colors: PackedColorArray = []
	var num_palettes: int = 16
	var new_size: int = TEXTURE_SIZE.x * TEXTURE_SIZE.y * num_palettes
	new_pixel_colors.resize(new_size)
	new_pixel_colors.fill(Color.BLACK)
	
	var texture_color_indices_all: PackedInt32Array = get_texture_color_indices_all(texture_color_indices)
	
	for i: int in new_size:
		new_pixel_colors[i] = texture_palettes[texture_color_indices_all[i]]
	
	return new_pixel_colors


func get_texture_rgba8_image_all() -> Image:
	var num_palettes: int = 16
	var image_width: int = TEXTURE_SIZE.x * num_palettes
	var image: Image = Image.create_empty(image_width, TEXTURE_SIZE.y, false, Image.FORMAT_RGBA8)
	var pixel_colors: PackedColorArray = get_texture_pixel_colors_all()
	
	for x: int in image_width:
		for y: int in TEXTURE_SIZE.y:
			var color: Color = pixel_colors[x + (y * image_width)]
			var color8: Color = Color8(color.r8, color.g8, color.b8, color.a8) # use Color8 function to prevent issues with format conversion changing color by 1/255
			image.set_pixel(x,y, color8) # spr stores pixel data left to right, top to bottm
	
	return image


func get_texture_all(texture_bytes: PackedByteArray) -> Texture2D:
	texture_color_indices = get_texture_color_indices(texture_bytes)
	
	var image: Image = get_texture_rgba8_image_all()
	return ImageTexture.create_from_image(image)


### new_palette should have 16 colors
func get_texture_pixel_colors_new_palette(new_palette: PackedColorArray) -> PackedColorArray:
	var new_pixel_colors: PackedColorArray = []
	var new_size: int = TEXTURE_SIZE.x * TEXTURE_SIZE.y
	new_pixel_colors.resize(new_size)
	new_pixel_colors.fill(Color.BLACK)
	for i: int in new_size:
		new_pixel_colors[i] = new_palette[texture_color_indices[i]]
	
	return new_pixel_colors


func swap_palette(palette_id: int, new_palette: PackedColorArray, map: MapChunkNodes) -> void:
	var new_pixel_colors: PackedColorArray = get_texture_pixel_colors_new_palette(new_palette)
	var new_color_image: Image = get_texture_rgba8_image(0, new_pixel_colors)
	
	var new_texture_image: Image = albedo_texture.get_image()
	new_texture_image.blit_rect(new_color_image, Rect2i(Vector2i.ZERO, new_color_image.get_size()), Vector2i(palette_id * TEXTURE_SIZE.x, 0))
	var new_texture: ImageTexture = ImageTexture.create_from_image(new_texture_image)
	
	var new_mesh_material: Material = mesh.surface_get_material(0)
	new_mesh_material.set_texture(BaseMaterial3D.TEXTURE_ALBEDO, new_texture)
	#mesh.surface_set_material(0, new_mesh_material)
	map.mesh_instance.mesh.surface_set_material(0, new_mesh_material)


func animate_palette(texture_anim: TextureAnimationData, map: MapChunkNodes, anim_fps: float) -> void:
	var frame_id: int = 0
	var dir: int = 1
	var colors_per_palette: int = 16
	
	var map_shader_material: ShaderMaterial = map.mesh_instance.material_override as ShaderMaterial
	while frame_id < texture_anim.num_frames:
		if not is_instance_valid(map):
			break
		
		var new_anim_palette_id: int = frame_id + texture_anim.animation_starting_index
		var new_palette: PackedColorArray = texture_animations_palette_frames[new_anim_palette_id]
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


func animate_uv(texture_anim: TextureAnimationData, map: MapChunkNodes, anim_idx: int, anim_fps: float) -> void:
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


# https://ffhacktics.com/wiki/Maps/Mesh#Terrain
func get_terrain(terrain_bytes: PackedByteArray) -> Array[TerrainTile]:
	map_width = terrain_bytes.decode_u8(0)
	map_length = terrain_bytes.decode_u8(1)
	
	var tile_data_length: int = 8
	var new_terrain_tiles: Array[TerrainTile] = []
	new_terrain_tiles.clear()
	for layer: int in [0, 1]:
		for z: int in map_length:
			for x: int in map_width:
				var tile_index: int = x + (z * map_width)
				var tile_data_start: int = 2 + (tile_index * tile_data_length) + (layer * 256 * 8) # each layer has space for 256 tiles, each tile data is 8 bytes
				var tile_data: PackedByteArray = terrain_bytes.slice(tile_data_start, tile_data_start + tile_data_length)
				
				var tile: TerrainTile = TerrainTile.new()
				tile.layer = layer
				tile.location = Vector2i(x, z)
				tile.surface_type_id = tile_data.decode_u8(0) & 0b0011_1111 # right 6 bits are the surface type
				tile.height_bottom = tile_data.decode_u8(2) # For sloped tiles, the height of the bottom of the slope
				tile.depth = tile_data.decode_u8(3) >> 5 # left 3 bits are bepth
				tile.slope_height = tile_data.decode_u8(3) & 0b1_1111 # right 5 bits are difference between the height at the top and the height at the bottom
				tile.slope_type_id = tile_data.decode_u8(4)
				tile.thickness = tile_data.decode_u8(5) & 0b1_1111 # right 5 bits are thickness height below the bottom of slope
				tile.no_stand_select = tile_data.decode_u8(6) >> 7 # leftmost bit, Can Walk/Cursor through this tile but not stand on it or select it. 
				tile.shading = (tile_data.decode_u8(6) & 0b0000_1100) >> 2 # 2 bits, Terrain Tile Shading. 0 = Normal, 1 = Dark, 2 = Darker, 3 = Darkest
				tile.no_walk = (tile_data.decode_u8(6) & 0b0000_0010) >> 1 # Can't walk on this tile 
				tile.no_cursor = tile_data.decode_u8(6) & 0b1 # rightmost bit, Can't move cursor to this tile 
				
				tile.default_camera_position_id = tile_data.decode_u8(7)
				
				tile.height_mid = tile.height_bottom + (tile.slope_height / 2.0)
				
				new_terrain_tiles.append(tile)
	
	return new_terrain_tiles


func set_gradient_colors(gradient_color_bytes: PackedByteArray) -> void:
	var top_red: int = gradient_color_bytes.decode_u8(0)
	var top_green: int = gradient_color_bytes.decode_u8(1)
	var top_blue: int = gradient_color_bytes.decode_u8(2)
	
	var bot_red: int = gradient_color_bytes.decode_u8(3)
	var bot_green: int = gradient_color_bytes.decode_u8(4)
	var bot_blue: int = gradient_color_bytes.decode_u8(5)
	
	background_gradient_top = Color8(top_red, top_green, top_blue)
	background_gradient_bottom = Color8(bot_red, bot_green, bot_blue)


func get_associated_files(gns_bytes: PackedByteArray) -> Array[MapFileRecord]:
	var gns_record_length: int = 20
	var new_map_records: Array[MapFileRecord] = []
	
	if file_name == "MAP053.GNS":
		return handle_map053(gns_bytes)
	
	var num_files: int = -1
	for temp_file_name: String in RomReader.file_records.keys():
		if temp_file_name.contains(file_name.trim_suffix(".GNS")):
			num_files += 1
	
	for record_index: int in num_files:
		var record_data: PackedByteArray = gns_bytes.slice(record_index * gns_record_length, (record_index + 1) * gns_record_length)
		var new_map_file_record: MapFileRecord = MapFileRecord.new(record_data)
		new_map_records.append(new_map_file_record)
		
		if new_map_file_record.file_type_indicator == 0x2e01: # MAP053's mesh data is in the 0x2f01 resource
			primary_mesh_data_record = new_map_file_record
			other_data_record = primary_mesh_data_record
		elif primary_mesh_data_record == null and new_map_file_record.file_type_indicator == 0x2f01:
			primary_mesh_data_record = new_map_file_record
			other_data_record = primary_mesh_data_record
	
	if is_instance_valid(primary_mesh_data_record):
		for record: MapFileRecord in new_map_records:
			if record.file_type_indicator == 0x1701:
				if record.time_weather == primary_mesh_data_record.time_weather and record.arrangement == primary_mesh_data_record.arrangement:
					primary_texture_record = record
	
	return new_map_records


func handle_map053(gns_bytes: PackedByteArray) -> Array[MapFileRecord]:
	var gns_record_length: int = 20
	var new_map_records: Array[MapFileRecord] = []
	
	var num_files: int = -1
	for temp_file_name: String in RomReader.file_records.keys():
		if temp_file_name.contains(file_name.trim_suffix(".GNS")):
			num_files += 1
	
	for record_index: int in num_files:
		var record_data: PackedByteArray = gns_bytes.slice(record_index * gns_record_length, (record_index + 1) * gns_record_length)
		var new_map_file_record: MapFileRecord = MapFileRecord.new(record_data)
		new_map_records.append(new_map_file_record)
		
		# MAP053's mesh data is in the 0x2f01 resource
		if new_map_file_record.file_type_indicator == 0x2f01: 
			primary_mesh_data_record = new_map_file_record
		
		# MAP053's palette, lighting, and terrain data is in the 0x2e01 resource
		if new_map_file_record.file_type_indicator == 0x2e01:
			other_data_record = new_map_file_record
	
	if is_instance_valid(primary_mesh_data_record):
		for record: MapFileRecord in new_map_records:
			if record.file_type_indicator == 0x1701:
				if record.time_weather == primary_mesh_data_record.time_weather and record.arrangement == primary_mesh_data_record.arrangement:
					primary_texture_record = record
	
	return new_map_records
