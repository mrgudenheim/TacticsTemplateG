class_name Spr
extends Bmp

var is_initialized: bool = false

const PORTRAIT_HEIGHT: int = 32 # pixels

var spritesheet: Image
var has_compressed: bool = true
var is_sp2: bool = false
var sp2s: Dictionary = {}
var shp_name: String = ""
var seq_name: String = ""
var sprite_id: int = 0

var shp_id: int = 0
var seq_id: int = 0
var flying_flag: int = 0
var graphic_height: int = 0


func _init(new_file_name: String) -> void:
	file_name = new_file_name
	bits_per_pixel = 4
	palette_data_start = 0
	pixel_data_start = num_colors * 2 # after 256 color palette, 2 bytes per color - 1 bit for alpha, followed by 5 bits per channel (B,G,R)
	width = 256 # pixels
	height = 488
	if file_name.get_extension() == "SP2":
		height = 256
		is_sp2 = true
		has_compressed = false
	elif file_name == "OTHER.SPR":
		num_colors = 512
		has_compressed = false
	elif (file_name.contains("WEP") 
		or file_name.contains("EFF")
		or ["10M", "10W", 
			"20M", "20W", 
			"40M", "40W", 
			"60M", "60W", 
			"CYOMON1", "CYOMON2", "CYOMON3", "CYOMON4", 
			"DAMI", 
			"FURAIA", 
			"ITEM"].has(file_name.get_basename())
		):
			has_compressed = false
	num_pixels = width * height


func get_sub_spr(new_name: String, start_pixel: int, end_pixel: int) -> Spr:
	var sub_spr: Spr = Spr.new(new_name)
	sub_spr.file_name = new_name
	sub_spr.color_palette = color_palette
	sub_spr.color_indices = color_indices.slice(start_pixel, end_pixel)
	sub_spr.set_pixel_colors()
	sub_spr.spritesheet = sub_spr.get_rgba8_image()
	
	return sub_spr


func set_data(spr_file: PackedByteArray = RomReader.get_file_data(file_name), overwrite: bool = false) -> void:
	if is_initialized and not overwrite:
		return
	
	var num_palette_bytes: int = num_colors * 2
	var palette_bytes: PackedByteArray = spr_file.slice(0, num_palette_bytes)
	@warning_ignore("integer_division")
	var num_bytes_top: int = (width * 256) /2
	var top_pixels_bytes: PackedByteArray = spr_file.slice(num_palette_bytes, num_palette_bytes + num_bytes_top)
	@warning_ignore("integer_division")
	var num_bytes_portrait_rows: int = (width * PORTRAIT_HEIGHT) /2
	var portrait_rows_pixels: PackedByteArray = spr_file.slice(num_palette_bytes + num_bytes_top, num_palette_bytes + num_bytes_top + num_bytes_portrait_rows)
	var spr_compressed_bytes: PackedByteArray = spr_file.slice(0x9200) if has_compressed else PackedByteArray()
	var spr_decompressed_bytes: PackedByteArray = decompress(spr_compressed_bytes)
	
	var spr_total_decompressed_bytes: PackedByteArray = []
	spr_total_decompressed_bytes.append_array(top_pixels_bytes)
	spr_total_decompressed_bytes.append_array(spr_decompressed_bytes)
	spr_total_decompressed_bytes.append_array(portrait_rows_pixels)
	
	set_palette_data(palette_bytes)
	color_indices = set_color_indices(spr_total_decompressed_bytes)
	set_pixel_colors()
	spritesheet = get_rgba8_image()
	
	if not is_sp2:
		set_sp2s()
	
	is_initialized = true


func set_palette_data(palette_bytes: PackedByteArray) -> void:
	color_palette.resize(num_colors)
	for i: int in num_colors:
		var color: Color = Color.BLACK
		var color_bits: int = palette_bytes.decode_u16(palette_data_start + (i*2))
		var alpha_bit: int = (color_bits & 0b1000_0000_0000_0000) >> 15 # first bit is alpha
		#color.a8 = 1 - () # first bit is alpha (if bit is zero, color is opaque)
		var b5: int = (color_bits & 0b0111_1100_0000_0000) >> 10 # then 5 bits each: blue, green, red
		var g5: int = (color_bits & 0b0000_0011_1110_0000) >> 5
		var r5: int = color_bits & 0b0000_0000_0001_1111
		
		# convert 5 bit channels to 8 bit
		#color.a8 = 255 * color.a8 # first bit is alpha (if bit is zero, color is opaque)
		color.a8 = 255 # TODO use alpha correctly
		color.b8 = roundi(255 * (b5 / 31.0)) # then 5 bits each: blue, green, red
		color.g8 = roundi(255 * (g5 / 31.0))
		color.r8 = roundi(255 * (r5 / 31.0))
		
		# psx transparency: https://www.psxdev.net/forum/viewtopic.php?t=953
		# TODO use Material3D blend mode Add for mode 1 or 3, where brightness builds up from a dark background instead of normal "mix" transparency
		if color == Color.BLACK:
			color.a8 = 0
		#elif alpha_bit == 1:
			#color.a8 = roundi(color.v * 255)
			#color.a8 = 127
			#color.a8 = 255
			#if color.v < 0.5:
				#color.a8 = roundi(color.v * 255)
			#color.a8 = 127 + roundi(color.v * 255)
		
		# if first color in 16 color palette is black, treat it as transparent
		if (i % 16 == 0
			and color == Color.BLACK):
				color.a8 = 0
		color_palette[i] = color


func set_color_indices(pixel_bytes: PackedByteArray) -> Array[int]:
	var new_color_indicies: Array[int] = []
	@warning_ignore("integer_division")
	new_color_indicies.resize(pixel_bytes.size() * (8 / bits_per_pixel))
	
	for i: int in new_color_indicies.size():
		@warning_ignore("integer_division")
		var pixel_offset: int = (i * bits_per_pixel) / 8
		var byte: int = pixel_bytes.decode_u8(pixel_offset)
		
		if bits_per_pixel == 4:
			if i % 2 == 1: # get 4 leftmost bits
				new_color_indicies[i] = byte >> 4
			else:
				new_color_indicies[i] = byte & 0b0000_1111 # get 4 rightmost bits
		elif bits_per_pixel == 8:
			new_color_indicies[i] = byte
	
	return new_color_indicies


func set_pixel_colors(palette_id: int = 0) -> void:
	var new_pixel_colors: PackedColorArray = []
	var new_size: int = color_indices.size()
	var err: int = new_pixel_colors.resize(new_size)
	#pixel_colors.resize(color_indices.size())
	new_pixel_colors.fill(Color.BLACK)
	for i: int in color_indices.size():
		new_pixel_colors[i] = color_palette[color_indices[i] + (16 * palette_id)]
	
	pixel_colors = new_pixel_colors


func get_rgba8_image() -> Image:
	@warning_ignore("integer_division")
	height = color_indices.size() / width
	var image:Image = Image.create_empty(width, height, false, Image.FORMAT_RGBA8)
	for x: int in width:
		for y: int in height:
			var color:Color = pixel_colors[x + (y * width)]
			var color8:Color = Color8(color.r8, color.g8, color.b8, color.a8) # use Color8 function to prevent issues with format conversion changing color by 1/255
			image.set_pixel(x,y, color8) # spr stores pixel data left to right, top to bottm
	
	return image


func decompress(compressed_bytes: PackedByteArray) -> PackedByteArray:
	var num_pixels_compressed: int = 200 * width if has_compressed else 0
	
	var decompressed_bytes: PackedByteArray = []
	@warning_ignore("integer_division")
	decompressed_bytes.resize(num_pixels_compressed / 2)
	decompressed_bytes.fill(0)
	
	var half_byte_data: PackedByteArray = []
	half_byte_data.resize(compressed_bytes.size() * 2)
	half_byte_data.fill(0)
	
	var decompressed_full_bytes: PackedByteArray = []
	decompressed_full_bytes.resize(num_pixels_compressed)
	decompressed_full_bytes.fill(0)
	
	# get half bytes
	for i: int in compressed_bytes.size():
		var byte: int = compressed_bytes.decode_u8(i)
		half_byte_data[i * 2] = byte >> 4 # get 4 leftmost bits
		half_byte_data[(i * 2) + 1] = byte & 0b0000_1111 # get 4 rightmost bits
	
	# decompress
	var half_byte_index: int = 0
	var decompressed_full_byte_index: int = 0
	while half_byte_index < half_byte_data.size():
		var half_byte: int = half_byte_data[half_byte_index]
		if half_byte != 0:
			decompressed_full_bytes[decompressed_full_byte_index] = half_byte_data[half_byte_index]
			half_byte_index += 1
			decompressed_full_byte_index += 1
			continue
		elif half_byte_index + 1 < half_byte_data.size(): # if 0, start compressed area
			var next_half: int = half_byte_data[half_byte_index + 1]
			var num_zeroes: int = next_half
			
			if next_half == 0:
				# TODO fix decompression of sprites expanded from ShiShi
				# handle expanded sprite format from ShiShi that has extra 0s at end of file
				if half_byte_index + 2 >= half_byte_data.size():
					break
				#elif half_byte_data[half_byte_index + 2] == 0:
					#break
				num_zeroes = half_byte_data[half_byte_index + 2]
				decompressed_full_byte_index += num_zeroes
				half_byte_index += 3
			elif next_half == 7:
				num_zeroes = half_byte_data[half_byte_index + 2] + (half_byte_data[half_byte_index + 3] << 4)
				decompressed_full_byte_index += num_zeroes
				half_byte_index += 4
			elif next_half == 8:
				num_zeroes = half_byte_data[half_byte_index + 2] + (half_byte_data[half_byte_index + 3] << 4) + (half_byte_data[half_byte_index + 4] << 8)
				decompressed_full_byte_index += num_zeroes
				half_byte_index += 5
			else:
				decompressed_full_byte_index += num_zeroes
				half_byte_index += 2
		else:
			half_byte_index += 1
	
	# full bytes to half bytes
	@warning_ignore("integer_division")
	for index: int in decompressed_full_bytes.size() / 2:
		decompressed_bytes[index] = decompressed_full_bytes[index * 2] << 4
		decompressed_bytes[index] = decompressed_bytes[index] | decompressed_full_bytes[(index * 2) + 1]
	
	return decompressed_bytes


func set_sp2s() -> void:
	var sp2_name_base: String = file_name.get_basename()
	if sp2_name_base == "TETSU":
		sp2_name_base = "IRON"
	
	# handle ROMs with sprs expanded by ShiShi
	var sp2_name: String = sp2_name_base + ".SP2"
	if RomReader.file_records.has(sp2_name):
		var sp2_spr: Spr = Spr.new(sp2_name)
		sp2_spr.set_sp2_data(self)
		sp2s[sp2_name] = sp2_spr
		
		# append sp2 image data to base spr
		color_indices.append_array(sp2_spr.color_indices)
	
	# handle vanilla sp2s
	for file_num: int in range(2,6):
		sp2_name = sp2_name_base + str(file_num) + ".SP2"
		if RomReader.file_records.has(sp2_name):
			var sp2_spr: Spr = Spr.new(sp2_name)
			sp2_spr.set_sp2_data(self)
			sp2s[sp2_name] = sp2_spr
			
			# append sp2 image data to base spr
			color_indices.append_array(sp2_spr.color_indices)
	
	# handle TETSU case in ROMs with sprs expanded by ShiShi
	for file_num: int in range(2,6):
		sp2_name = sp2_name_base + "_" + str(file_num) + ".SP2"
		if RomReader.file_records.has(sp2_name):
			var sp2_spr: Spr = Spr.new(sp2_name)
			sp2_spr.set_sp2_data(self)
			sp2s[sp2_name] = sp2_spr
			
			# append sp2 image data to base spr
			color_indices.append_array(sp2_spr.color_indices)
	
	set_pixel_colors()
	spritesheet = get_rgba8_image()


func set_sp2_data(base_spr: Spr) -> void:
	var sp2_data: PackedByteArray = RomReader.get_file_data(file_name)
	color_indices = set_color_indices(sp2_data)
	color_palette = base_spr.color_palette
	set_pixel_colors()
	spritesheet = get_rgba8_image()


func set_spritesheet_data(new_sprite_id: int) -> void:
	if file_name == "OTHER.SPR":
		shp_name = "OTHER.SHP"
		seq_name = "OTHER.SEQ"
		return
	
	sprite_id = new_sprite_id
	shp_id = RomReader.battle_bin_data.spritesheet_shp_id[sprite_id]
	seq_id = RomReader.battle_bin_data.spritesheet_seq_id[sprite_id]
	flying_flag = RomReader.battle_bin_data.spritesheet_flying[sprite_id]
	graphic_height = RomReader.battle_bin_data.spritesheet_graphic_height[sprite_id]
	
	match shp_id:
		0:
			shp_name = "TYPE1.SHP"
		1:
			shp_name = "TYPE2.SHP"
		2:
			shp_name = "CYOKO.SHP"
		3:
			shp_name = "MON.SHP"
		4:
			shp_name = "OTHER.SHP"
		5:
			shp_name = "MON.SHP" # RUKA
		6:
			shp_name = "ARUTE.SHP"
		7:
			shp_name = "KANZEN.SHP"
	
	match seq_id:
		0:
			seq_name = "TYPE1.SEQ"
		1:
			seq_name = "TYPE3.SEQ"
		2:
			seq_name = "CYOKO.SEQ"
		3:
			seq_name = "MON.SEQ"
		4:
			seq_name = "OTHER.SEQ"
		5:
			seq_name = "RUKA.SEQ"
		6:
			seq_name = "ARUTE.SHP"
		7:
			seq_name = "KANZEN.SEQ"


func create_frame_grid(anim_ptr_idx: int = 0, other_idx: int = 0, wep_v_offset: int = 0, submerged_depth: int = 0, different_shp_name: String = "") -> Image:
	if different_shp_name == "":
		different_shp_name = shp_name
	var shp: Shp = RomReader.shps_array[RomReader.file_records[different_shp_name].type_index]
	if not shp.is_initialized:
		shp.set_data_from_shp_bytes(RomReader.get_file_data(shp_name))
	var num_cells_wide: int = 16
	var num_cells_tall: int = 16 + (16 * sp2s.size())
	if shp.frames.size() > 256: # WEP has more frames (related to the frame offsets per item type)
		num_cells_tall = 32
	
	var cell_width: int = shp.frame_size.x
	var cell_height: int = shp.frame_size.y
	
	var frame_grid: Image = Image.create_empty(cell_width * num_cells_wide, cell_height * num_cells_tall, false, Image.FORMAT_RGBA8)
	
	for sp2_id: int in sp2s.size() + 1:
		if sp2s.size() == 4: # handle hardcoded offsets for STEEL GIANT (aka TETSU.SPR)
			for ptr_idx: int in Shp.constant_sp2_files.keys():
				if Shp.constant_sp2_files[ptr_idx] == sp2_id:
					anim_ptr_idx = ptr_idx
			if file_name != "TETSU.SPR": # handle sp2s renamed/reordered by ShiShi
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
		
		for frame_idx: int in shp.frames.size():
			var cell_x: int = frame_idx % num_cells_wide
			@warning_ignore("integer_division")
			var cell_y: int = (frame_idx / num_cells_wide) + (16 * sp2_id)
			
			var frame_image: Image = shp.get_assembled_frame(frame_idx, spritesheet, anim_ptr_idx, other_idx, wep_v_offset, submerged_depth)
			frame_grid.blit_rect(frame_image, Rect2i(0, 0, frame_image.get_size().x, frame_image.get_size().y), Vector2i(cell_x * cell_width, cell_y * cell_height))
	
	return frame_grid


func create_frame_grid_texture(palette_idx: int = 0, anim_ptr_idx: int = 0, other_idx: int = 0, wep_v_offset: int = 0, submerged_depth: int = 0, different_shp_name: String = "") -> ImageTexture:
	set_pixel_colors(palette_idx)
	spritesheet = get_rgba8_image()
	
	var new_texture: ImageTexture = ImageTexture.create_from_image(create_frame_grid(anim_ptr_idx, other_idx, wep_v_offset, submerged_depth, different_shp_name))
	return new_texture
