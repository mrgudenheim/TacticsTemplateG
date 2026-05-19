class_name MapData
extends Resource

@export var unique_name: String = ""
@export var display_name: String = "[map display name]"
@export var description: String = "[map description]"

@export var terrain_tiles: Array[TerrainTile] = []
@export var palettes: PackedColorArray = []
@export var texture_animations: Array[TextureAnimation] = []
@export var palette_animation_frames: Array[PackedColorArray] = []


static func init_from_fft_map_data(fft_map_data: FftMapData) -> MapData:
	var new_map_data: MapData = MapData.new()
	
	new_map_data.unique_name = fft_map_data.unique_name
	new_map_data.display_name = fft_map_data.display_name
	new_map_data.description = fft_map_data.description
	
	new_map_data.terrain_tiles = fft_map_data.terrain_tiles.duplicate(true)
	new_map_data.palettes = fft_map_data.texture_palettes.duplicate()
	for fft_texture_animation: FftMapData.TextureAnimationData in fft_map_data.texture_animations:
		var new_texture_anim: TextureAnimation = TextureAnimation.new(fft_texture_animation)
		new_map_data.texture_animations.append(new_texture_anim)
	
	new_map_data.palette_animation_frames = fft_map_data.texture_animations_palette_frames.duplicate()

	return new_map_data
