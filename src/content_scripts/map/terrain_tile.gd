class_name TerrainTile
extends Resource

enum SlopeType {
	FLAT,
	RAMP,
	HIGH_CORNERS,
	LOW_CORNERS,
}

const SLOPE_TYPE_CODE: Dictionary[SlopeType, int] = {
	SlopeType.FLAT : 00,
	SlopeType.RAMP : 0x85,
	SlopeType.HIGH_CORNERS : 0x99,
	SlopeType.LOW_CORNERS : 0x44,
}


# https://ffhacktics.com/wiki/Maps/Mesh#Terrain
@export var layer: int = 0
@export var location: Vector2i = Vector2i.ZERO
@export var surface_type_id: int = 0
@export var height_bottom: int = 0 # For sloped tiles, the height of the bottom of the slope
@export var depth: int = 0
@export var slope_height: int = 0 # difference between the height at the top and the height at the bottom
@export var slope_type_id: int = 0
@export var slope_type: SlopeType = SlopeType.FLAT
@export var thickness: int = 0 # used for calculating ceiling: https://ffhacktics.com/wiki/Calculate_Tile_Ceiling
@export var no_stand_select: int = 0 # Can Walk/Cursor through this tile but not stand on it or select it. 
@export var shading: int = 0 # Terrain Tile Shading. 0 = Normal, 1 = Dark, 2 = Darker, 3 = Darkest
@export var no_walk: int = 0 # Can't walk on this tile 
@export var no_cursor: int = 0 # Can't move cursor to this tile 

@export var default_camera_position_id: int = 0 # Controls which angles the camera will auto-rotate to when a unit enters this tile. 

@export var height_mid: float = height_bottom + (slope_height / 2.0)
var tile_scale: Vector3 = Vector3.ONE
@export var rotation_degrees: float = 0.0


func get_world_position(use_bottom_height: bool = false) -> Vector3:
	var height_position: float = height_mid + depth
	if use_bottom_height:
		height_position = height_bottom + depth
	var tile_position: Vector3 = Vector3(location.x, height_position, location.y)
	var tile_world_position: Vector3 = tile_position * Vector3(1, FftMapData.HEIGHT_SCALE, 1)
	tile_world_position += Vector3(0.5, 0, 0.5)
	
	return tile_world_position


# https://ffhacktics.com/wiki/Slope_Type
func get_tile_mesh() -> MeshInstance3D:
	var new_tile_mesh_instance: MeshInstance3D = MeshInstance3D.new()
	var mesh: ArrayMesh = GameData.map_tile_meshes[slope_type]
	new_tile_mesh_instance.mesh = mesh
	new_tile_mesh_instance.scale = tile_scale
	if slope_height != 0:
		new_tile_mesh_instance.scale.y *= slope_height * FftMapData.HEIGHT_SCALE
	new_tile_mesh_instance.rotation_degrees.y += rotation_degrees
	return new_tile_mesh_instance


static func get_normalized_slope_mesh(new_slope_type: int, scale: Vector3 = Vector3.ONE) -> ArrayMesh:
	var st_tile: SurfaceTool = SurfaceTool.new()
	st_tile.begin(Mesh.PRIMITIVE_TRIANGLES)
	
	# side types: 0 = low, 1 = sloped, 2 = high
	var side_types: PackedInt32Array = []
	side_types.resize(4)
	side_types[0] = (new_slope_type >> 6) & 0x03	# north
	side_types[1] = new_slope_type & 0x03 			# east
	side_types[2] = (new_slope_type >> 4) & 0x03	# south
	side_types[3] = (new_slope_type >> 2) & 0x03	# west
	
	var tri_seam_offset: int = 0
	var vertex_heights: PackedInt32Array = []
	vertex_heights.resize(4)
	vertex_heights.fill(0)
	if new_slope_type != 0:
		for side_index: int in side_types.size():
			if side_types[side_index] == 2: # high edges
				vertex_heights[(side_index + 1) % 4] = 1
				vertex_heights[(side_index + 2) % 4] = 1
				if side_types[(side_index + 1) % 4] == 2: # high corner
					vertex_heights[side_index] = 0 # opposite corner is low
					tri_seam_offset = (side_index + 1) % 2
			elif side_types[side_index] == 0: # low edges
				vertex_heights[(side_index + 1) % 4] = 0
				vertex_heights[(side_index + 2) % 4] = 0
				if side_types[(side_index + 1) % 4] == 0: # low corner
					vertex_heights[side_index] = 1 # opposite corner is high
					tri_seam_offset = side_index % 2	
	
	var tile_side_length: float = 1.0
	var quad_vertices: PackedVector3Array = [
		Vector3(-tile_side_length / 2, 0, -tile_side_length / 2),
		Vector3(-tile_side_length / 2, 0, tile_side_length / 2),
		Vector3(tile_side_length / 2, 0, tile_side_length / 2),
		Vector3(tile_side_length / 2, 0, -tile_side_length / 2),
	]
	for vertex_index: int in quad_vertices.size():
		quad_vertices[vertex_index] += Vector3.UP * vertex_heights[vertex_index]
		quad_vertices[vertex_index] *= scale
	
	var quad_uvs: PackedVector2Array = [
		Vector2(0, 0),
		Vector2(0, 1),
		Vector2(1, 1),
		Vector2(1, 0),
	]
	var quad_colors: PackedColorArray
	quad_colors.resize(4)
	quad_colors.fill(Color.WHITE)
	
	for vert_index: int in [0, 1, 2]:
		#st_tile.set_normal(quad_normals[vert_index]) # TODO why is there error on MAP105 "terminate"
		var offset_index: int = (vert_index + tri_seam_offset) % 4
		st_tile.set_uv(quad_uvs[offset_index])
		st_tile.set_color(Color.WHITE)
		st_tile.add_vertex(quad_vertices[offset_index])
	
	for vert_index: int in [0, 2, 3]:
		#st_tile.set_normal(quad_normals[vert_index])
		var offset_index: int = (vert_index + tri_seam_offset) % 4
		st_tile.set_uv(quad_uvs[offset_index])
		st_tile.set_color(Color.WHITE)
		st_tile.add_vertex(quad_vertices[offset_index])
	
	st_tile.generate_normals()
	var slope_mesh: ArrayMesh = st_tile.commit()

	return slope_mesh
