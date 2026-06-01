class_name UnitSpritesheetData
extends Resource

@export var unique_name: String = ""
@export var shp_name: String = ""
@export var seq_name: String = ""
@export var is_flying: bool = false
@export var graphic_height: int = 0
@export var color_palette: PackedColorArray = []


func _init(spr: Spr = null) -> void:
	if spr == null:
		return
	
	unique_name = spr.file_name.get_basename().to_lower().trim_suffix(".spr")
	shp_name = spr.shp_name.to_lower().trim_suffix(".shp")
	seq_name = spr.seq_name.to_lower().trim_suffix(".seq")
	is_flying = spr.flying_flag != 0
	graphic_height = spr.graphic_height
	color_palette = spr.color_palette


func get_texture() -> Texture2D:
	return GameData.textures[unique_name]


func get_shp() -> Shp:
	return GameData.shps[shp_name]


func get_seq() -> Seq:
	return GameData.seqs[seq_name]


func create_frame_grid(anim_ptr_idx: int = 0, other_idx: int = 0, wep_v_offset: int = 0, submerged_depth: int = 0, different_shp_name: String = "") -> Image:
	if different_shp_name == "":
		different_shp_name = shp_name
	if not get_shp().is_initialized:
		push_error(shp_name + " not initialized")
	var num_sp2s: int = min(0, (get_texture().get_height() - 488)) / 256
	var num_cells_wide: int = 16
	var num_cells_tall: int = 16 + (16 * num_sp2s)
	if get_shp().frames.size() > 256: # WEP has more frames (related to the frame offsets per item type)
		num_cells_tall = 32
	
	var cell_width: int = get_shp().frame_size.x
	var cell_height: int = get_shp().frame_size.y
	
	var frame_grid: Image = Image.create_empty(cell_width * num_cells_wide, cell_height * num_cells_tall, false, Image.FORMAT_RGBA8)
	var index_image: Image = get_texture().get_image()
	
	for sp2_id: int in num_sp2s + 1:
		if num_sp2s == 4: # handle hardcoded offsets for STEEL GIANT (aka TETSU.SPR)
			for ptr_idx: int in Shp.CONSTANT_SP2_FILES.keys():
				if Shp.CONSTANT_SP2_FILES[ptr_idx] == sp2_id:
					anim_ptr_idx = ptr_idx
			if unique_name != "tetsu": # handle sp2s renamed/reordered by ShiShi
				if [230, 231].has(anim_ptr_idx): # Destroy (electric fist)
					anim_ptr_idx += 4
				elif [232, 233].has(anim_ptr_idx): # Compress (hammer)
					anim_ptr_idx += 4
				elif [234, 235].has(anim_ptr_idx): # Dispose (canon)
					anim_ptr_idx += -2
				elif [236, 237].has(anim_ptr_idx): # Crush (drill)
					anim_ptr_idx += -6
		else:
			anim_ptr_idx = Shp.SP2_START_ANIMATION_ID * sp2_id
		
		for frame_idx: int in get_shp().frames.size():
			var cell_x: int = frame_idx % num_cells_wide
			@warning_ignore("integer_division")
			var cell_y: int = (frame_idx / num_cells_wide) + (16 * sp2_id)
			
			var frame_image: Image = get_shp().get_assembled_frame(frame_idx, index_image, anim_ptr_idx, other_idx, wep_v_offset, submerged_depth)
			frame_grid.blit_rect(frame_image, Rect2i(0, 0, frame_image.get_size().x, frame_image.get_size().y), Vector2i(cell_x * cell_width, cell_y * cell_height))
	
	return frame_grid


func create_frame_grid_texture(palette_idx: int = 0, anim_ptr_idx: int = 0, other_idx: int = 0, wep_v_offset: int = 0, submerged_depth: int = 0, different_shp_name: String = "") -> ImageTexture:	
	var new_texture: ImageTexture = ImageTexture.create_from_image(create_frame_grid(anim_ptr_idx, other_idx, wep_v_offset, submerged_depth, different_shp_name))
	return new_texture
