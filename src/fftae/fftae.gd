class_name FFTae
extends Control

static var ae: FFTae
#static var rom: PackedByteArray = []
static var global_fft_animation: FftAnimation = FftAnimation.new()

@export var ui_manager: UiManager
@export var preview_manager: PreviewManager
@export var load_rom_dialog: FileDialog
@export var load_file_dialog: FileDialog
@export var save_xml_button: Button
@export var save_xml_dialog: FileDialog
@export var save_seq_button: Button
@export var save_seq_dialog: FileDialog
@export var save_frame_grid_button: Button
@export var save_frame_grid_dialog: FileDialog
@export var save_gif_button: Button
@export var save_gif_dialog: FileDialog
@export var is_recording_gif: bool = false
var gif_exporter: GIFExporter
var gif_frames: Array[Image] = []
var gif_delays: PackedFloat32Array = []
var gif_frame_nums: PackedInt32Array = []

@export var animation_list_container: VBoxContainer
@export var animation_list_row_tscn: PackedScene
@export var opcode_list_container: GridContainer
@export var frame_list_container: VBoxContainer
@export var frame_list_row_tscn: PackedScene

# https://en.wikipedia.org/wiki/CD-ROM#CD-ROM_XA_extension
const bytes_per_sector: int = 2352
const bytes_per_sector_header: int = 24
const bytes_per_sector_footer: int = 280
const data_bytes_per_sector: int = 2048

# load gif exporter module and quantization module that you want to use
const GIFExporter = preload("res://addons/gdgifexporter/exporter.gd")
const MedianCutQuantization = preload("res://addons/gdgifexporter/quantization/median_cut.gd")


var seq: Seq:
	get:
		var file_name: String = ui_manager.seq_options.get_item_text(ui_manager.seq_options.selected)
		
		var new_seq: Seq = RomReader.seqs_array[RomReader.file_records[file_name].type_index]
		if not new_seq.is_initialized:
			new_seq.set_data_from_seq_bytes(RomReader.get_file_data(new_seq.file_name))
		
		return new_seq


var shp: Shp:
	get:
		var file_name: String = ui_manager.shp_options.get_item_text(ui_manager.shp_options.selected)
		
		var new_shp: Shp = RomReader.shps_array[RomReader.file_records[file_name].type_index]
		if not new_shp.is_initialized:
			new_shp.set_data_from_shp_bytes(RomReader.get_file_data(new_shp.file_name))
		
		return new_shp


var spr: Spr:
	get:
		#var file_name: String = ui_manager.sprite_options.get_item_text(ui_manager.sprite_options.selected)
		var sprite_file_index: int = ui_manager.sprite_options.selected
		var new_spr: Spr = RomReader.sprs[sprite_file_index]
		if not new_spr.is_initialized:
			new_spr.set_data(RomReader.get_file_data(ui_manager.sprite_options.get_item_text(sprite_file_index)))
			if new_spr.file_name == "OTHER.SPR":
				new_spr.set_spritesheet_data(0)
			elif new_spr.file_name != "WEP.SPR" and new_spr.file_name != "EFF.SPR":
				new_spr.set_spritesheet_data(RomReader.spr_file_name_to_id[new_spr.file_name])
		
		return new_spr


func _ready() -> void:
	ae = self
	RomReader.rom_loaded.connect(initialize_ui)


func _on_load_rom_pressed() -> void:
	load_rom_dialog.visible = true


func _on_load_rom_dialog_file_selected(path: String) -> void:
	RomReader.on_load_rom_dialog_file_selected(path)


func initialize_ui() -> void:
	for record: FileRecord in RomReader.file_records.values():
		#push_warning(record.to_string())
		match record.name.get_extension():
			"SPR":
				ui_manager.sprite_options.add_item(record.name)
			"SHP":
				ui_manager.shp_options.add_item(record.name)
			"SEQ":
				ui_manager.seq_options.add_item(record.name)
			"SP2":
				# SP2 handled by Spr
				pass
			_:
				#push_warning(record.name + ": File extension not recognized")
				pass
	
	#push_warning("Time to get file records (ms): " + str(Time.get_ticks_msec() - start_time))
	#cache_associated_files()
	#push_warning("Time to cache files (ms): " + str(Time.get_ticks_msec() - start_time))
	preview_manager.enable_ui()
	preview_manager.initialize()
	
	ui_manager.enable_ui()
	
	save_xml_button.disabled = false
	save_seq_button.disabled = false
	save_frame_grid_button.disabled = false
	save_gif_button.disabled = false
	
	# try to load defaults
	UiManager.option_button_select_text(ui_manager.seq_options, "TYPE1.SEQ")
	UiManager.option_button_select_text(ui_manager.shp_options, "TYPE1.SHP")
	UiManager.option_button_select_text(ui_manager.sprite_options, "RAMUZA.SPR")
	
	_on_seq_file_options_item_selected(ui_manager.seq_options.selected)
	#_on_shp_file_options_item_selected(ui_manager.shp_options.selected)
	
	ui_manager.pointer_index_spinbox.value = 6 # default to walking animation
	#ui_manager.preview_viewport.sprite_primary.texture = ImageTexture.create_from_image(spr.spritesheet)
	
	var background_image: Image = shp.create_blank_frame(Color.BLACK)
	#preview_manager.unit.animation_manager.unit_sprites_manager.sprite_background.texture = ImageTexture.create_from_image(background_image)
	#sprite_background.texture = ImageTexture.create_from_image(background_image)
	
	var new_fft_animation: FftAnimation = preview_manager.unit.animation_manager.get_animation_from_globals()
	
	preview_manager.unit.animation_manager.start_animation(new_fft_animation, preview_manager.unit.animation_manager.unit_sprites_manager.sprite_primary, preview_manager.animation_is_playing, true)
	#ui_manager.preview_viewport.camera_control._update_viewport_transform()
	
	#push_warning("Time to process ROM (ms): " + str(Time.get_ticks_msec() - start_time))


func _on_load_seq_pressed() -> void:
	load_file_dialog.visible = true


func _on_save_as_xml_pressed() -> void:
	save_xml_dialog.visible = true


func _on_save_as_seq_pressed() -> void:
	save_seq_dialog.visible = true


func _on_load_file_dialog_file_selected(path: String) -> void:
	seq = Seq.new(path.get_file())
	seq.set_data_from_seq_file(path)
	ui_manager.on_seq_data_loaded(seq)
	save_xml_button.disabled = false
	save_seq_button.disabled = false
	
	populate_animation_list(animation_list_container, seq)
	populate_opcode_list(opcode_list_container, ui_manager.animation_name_options.selected)


func _on_save_xml_dialog_file_selected(path: String) -> void:
	var xml_complete: String = get_xml()
	
	# clean up file name
	if path.get_slice(".", -2).to_lower() == path.get_slice(".", -1).to_lower():
		path = path.trim_suffix(path.get_slice(".", -1))
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var save_file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	save_file.store_string(xml_complete)


func get_xml() -> String:
	var xml_header: String = '<?xml version="1.0" encoding="utf-8" ?>\n<Patches>'
	var xml_patch_name: String = '<Patch name="' + ui_manager.patch_name + '">'
	var xml_author: String = '<Author>' + ui_manager.patch_author + '</Author>'
	
	var files_changed: PackedStringArray = []
	var xml_files: PackedStringArray = []
	for seq_file: Seq in RomReader.seqs_array:
	#for file_name: String in seqs.keys():
		var seq_temp: Seq = RomReader.seqs_array[RomReader.file_records[seq_file.file_name].type_index]
		var seq_bytes: PackedByteArray = seq_temp.get_seq_bytes()
		if RomReader.get_file_data(seq_file.file_name) == seq_bytes or not seq_file.is_initialized:
			continue
		
		var file: String = seq_temp.file_name
		files_changed.append(file)
		var xml_size_location_start: String = '<Location offset="%08x" ' % (RomReader.file_records[file].record_location_offset + FileRecord.OFFSET_SIZE - bytes_per_sector_header)
		xml_size_location_start += ('sector="%x">' % RomReader.file_records[file].record_location_sector)
		var file_size_hex: String = '%08x' % seq_temp.toal_length
		var file_size_hex_bytes: PackedStringArray = [
			file_size_hex.substr(0,2),
			file_size_hex.substr(2,2),
			file_size_hex.substr(4,2),
			file_size_hex.substr(6,2),
			]
		var bytes_size: String = file_size_hex_bytes[3] + file_size_hex_bytes[2] + file_size_hex_bytes[1] + file_size_hex_bytes[0] # little-endian
		bytes_size += file_size_hex_bytes[0] + file_size_hex_bytes[1] + file_size_hex_bytes[2] + file_size_hex_bytes[3] # big-endian
		var xml_size_location_end: String = '</Location>'
		
		var bytes: String = seq_bytes.hex_encode()
		var location_start: int = 0
		var xml_location_start: String = '<Location offset="%08x" ' % location_start
		xml_location_start += 'file="BATTLE_' + file.trim_suffix(".SEQ") + '_SEQ">'
		var xml_location_end: String = '</Location>'
		
		xml_files.append_array(PackedStringArray([
			"<!-- " + file + " ISO 9660 file size (both endian) -->",
			xml_size_location_start,
			bytes_size,
			xml_size_location_end,
			"<!-- " + file + " data -->",
			xml_location_start,
			bytes,
			xml_location_end,
			]))
	
	# set default description as list of changed files
	var xml_description: String = '<Description> The following files were editing with FFT Animation Edtior: ' + ", ".join(files_changed) + '</Description>'
	if not ui_manager.patch_description_edit.text.is_empty():
		xml_description = '<Description>' + ui_manager.patch_description + '</Description>'
	
	var xml_end: String = '</Patch>\n</Patches>'
	
	var xml_parts: PackedStringArray = [
		xml_header,
		xml_patch_name,
		xml_author,
		xml_description,
		"\n".join(xml_files),
		xml_end,
	]
	
	var xml_complete: String = "\n".join(xml_parts)
	
	return xml_complete


func _on_save_seq_dialog_file_selected(path: String) -> void:
	seq.write_seq(path)


func clear_grid_container(grid: GridContainer, rows_to_keep: int) -> void:
	var children_to_keep: int = rows_to_keep * grid.columns
	var initial_children: int = grid.get_child_count()
	for child_index: int in initial_children:
		var reverse_child_index: int = initial_children - 1 - child_index
		if reverse_child_index >= children_to_keep:
			var child: Node = grid.get_child(reverse_child_index)
			grid.remove_child(child)
			child.queue_free()
		else:
			break


func populate_animation_list(animations_list_parent: VBoxContainer, seq_local: Seq) -> void:
	for child: Node in animations_list_parent.get_children():
		animations_list_parent.remove_child(child)
		child.queue_free()
	
	ui_manager.current_animation_slots = seq_local.sequence_pointers.size()
	
	var time_left_in_frame: bool = true
	get_tree().create_timer(0.017).timeout.connect(func() -> void: time_left_in_frame = false)
	
	for index: int in seq_local.sequence_pointers.size():
		var pointer: int = seq_local.sequence_pointers[index]
		var sequence: Sequence = seq_local.sequences[pointer]
		var description: String = sequence.seq_name
		var opcodes: String = sequence.to_string_hex("\n")
		
		var row_ui: AnimationRow = animation_list_row_tscn.instantiate()
		animations_list_parent.add_child(row_ui)
		animations_list_parent.add_child(HSeparator.new())
		
		row_ui.pointer_id = index
		row_ui.anim_id_spinbox.max_value = seq_local.sequences.size() - 1
		row_ui.anim_id = pointer
		row_ui.description = description
		row_ui.opcodes_text = opcodes
		
		row_ui.anim_id_spinbox.value_changed.connect(
			func(new_value: int) -> void: 
				seq_local.sequence_pointers[index] = new_value
				var new_sequence: Sequence = seq_local.sequences[new_value]
				row_ui.description = new_sequence.seq_name
				row_ui.opcodes_text = new_sequence.to_string_hex("\n")
				)
		
		row_ui.button.pressed.connect(
			func() -> void: 
				ui_manager.pointer_index_spinbox.value = row_ui.get_index() / 2 # ignore HSepators
				ui_manager.animation_id_spinbox.value = row_ui.anim_id
				)
		
		# let frame finish rendering to improve responsiveness
		if not time_left_in_frame:
			await get_tree().process_frame
			time_left_in_frame = true
			get_tree().create_timer(0.017).timeout.connect(func() -> void: time_left_in_frame = false)


func populate_opcode_list(opcode_grid_parent: GridContainer, seq_id: int) -> void:
	clear_grid_container(opcode_grid_parent, 1) # keep header row
	
	for seq_part_index: int in seq.sequences[seq_id].seq_parts.size():
		var id_label: Label = Label.new()
		id_label.text = str(seq_part_index)
		id_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		opcode_grid_parent.add_child(id_label)
		
		var opcode_options: OpcodeOptionButton = OpcodeOptionButton.new()
		opcode_options.add_item("LoadFrameAndWait")
		for opcode_name: String in Seq.opcode_parameters_by_name.keys():
			opcode_options.add_item(opcode_name)
		
		opcode_options.seq_id = seq_id
		opcode_options.seq_part_id = seq_part_index
		opcode_options.seq_part = seq.sequences[seq_id].seq_parts[seq_part_index]
		opcode_grid_parent.add_child(opcode_options)
		for opcode_options_index: int in opcode_options.item_count:
			if opcode_options.get_item_text(opcode_options_index) == seq.sequences[seq_id].seq_parts[seq_part_index].opcode_name:
				opcode_options.select(opcode_options_index)
				opcode_options.item_selected.emit(opcode_options_index)
				break
		
		# update param spinboxes starting value
		for param_index: int in seq.sequences[seq_id].seq_parts[seq_part_index].parameters.size():
			opcode_options.param_spinboxes[param_index].value = seq.sequences[seq_id].seq_parts[seq_part_index].parameters[param_index]


func populate_frame_list(frame_list_parent: VBoxContainer, shp_local: Shp) -> void:
	for child: Node in frame_list_parent.get_children():
		frame_list_parent.remove_child(child)
		child.queue_free()
	
	#ui_manager.current_animation_slots = shp_local.frames.size()
	
	var counter: int = 0
	
	for frame_index: int in shp_local.frame_pointers.size():
		var pointer: int = shp_local.frame_pointers[frame_index]
		var frame: FrameData = shp_local.frames[frame_index]
		
		var row_ui: FrameRow = frame_list_row_tscn.instantiate()
		frame_list_parent.add_child(row_ui)
		frame_list_parent.add_child(HSeparator.new())
		
		row_ui.frame_id = frame_index
		row_ui.frame_rotation = frame.y_rotation
		row_ui.subframes_text = frame.get_subframes_string()
		
		var preview_image_size: Vector2i = Vector2i(120, 120)
		var preview_image: Image = shp_local.create_blank_frame(Color.BLACK, preview_image_size)
		var assembled_frame: Image = shp_local.get_assembled_frame(frame_index, spr.spritesheet, ui_manager.animation_id_spinbox.value, preview_manager.other_type_options.selected, preview_manager.unit.primary_weapon.wep_frame_v_offset, preview_manager.submerged_depth_options.selected, Vector2i(60, 60), 15)
		assembled_frame.resize(preview_image_size.x, preview_image_size.y, Image.INTERPOLATE_NEAREST)
		preview_image.blend_rect(assembled_frame, Rect2i(Vector2i.ZERO, preview_image_size), Vector2i.ZERO)
		row_ui.preview_rect.texture = ImageTexture.create_from_image(preview_image)
		row_ui.preview_rect.rotation_degrees = frame.y_rotation
		
		# let frame finish rendering to improve responsiveness
		counter += 1
		if counter >= 10:
			await get_tree().process_frame
			counter = 0


func draw_assembled_frame(frame_index: int) -> void:
	var assembled_image: Image = shp.get_assembled_frame(frame_index, spr.spritesheet, ui_manager.animation_id_spinbox.value, preview_manager.other_type_options.selected, preview_manager.unit.primary_weapon.wep_frame_v_offset, preview_manager.submerged_depth_options.selected)
	preview_manager.unit.animation_manager.unit_sprites_manager.set_primary_texture(ImageTexture.create_from_image(assembled_image))
	var image_rotation: float = shp.get_frame(frame_index, preview_manager.submerged_depth_options.selected).y_rotation
	(preview_manager.unit.animation_manager.unit_sprites_manager.sprite_primary.get_parent() as Node2D).rotation_degrees = image_rotation


func _on_animation_option_button_item_selected(index: int) -> void:
	var sequence: Sequence = seq.sequences[index]
	ui_manager.row_spinbox.max_value = sequence.seq_parts.size() - 1
	populate_opcode_list(opcode_list_container, index)


func _on_insert_opcode_pressed() -> void:
	var seq_part_id: int = ui_manager.row_spinbox.value
	var seq_id: int = ui_manager.animation_name_options.selected
	
	#var previous_length: int = seq.sequences[seq_id].length
	# set up seq_part
	var new_seq_part: SeqPart = SeqPart.new()
	new_seq_part.parameters.resize(2)
	new_seq_part.parameters.fill(0)
	
	seq.sequences[ui_manager.animation_name_options.selected].seq_parts.insert(seq_part_id, new_seq_part)
	seq.sequences[ui_manager.animation_name_options.selected].update_length()
	ui_manager.current_bytes = seq.toal_length
	_on_animation_option_button_item_selected(seq_id)


func _on_delete_opcode_pressed() -> void:
	var seq_part_id: int = ui_manager.row_spinbox.value
	var seq_id: int = ui_manager.animation_name_options.selected
	#var previous_length: int = seq.sequences[seq_id].length
	
	seq.sequences[ui_manager.animation_name_options.selected].seq_parts.remove_at(seq_part_id)
	seq.sequences[ui_manager.animation_name_options.selected].update_length()
	ui_manager.current_bytes = seq.toal_length
	_on_animation_option_button_item_selected(seq_id)


func _on_new_animation_pressed() -> void:
	# create new sequence with initial opcode LoadFrameAndWait(0,0)
	var new_seq: Sequence = Sequence.new()
	new_seq.seq_name = "New Animation"
	var initial_seq_part: SeqPart = SeqPart.new()
	initial_seq_part.parameters.append(0)
	initial_seq_part.parameters.append(0)
	new_seq.seq_parts.append(initial_seq_part)
	seq.sequences.append(new_seq)
	
	seq.sequence_pointers.append(seq.sequences.size() - 1) # add pointer to the new sequence
	populate_animation_list(animation_list_container, seq)
	ui_manager.update_animation_description_options(seq)
	
	ui_manager.animation_id_spinbox.max_value = seq.sequences.size() - 1
	ui_manager.animation_id_spinbox.value = seq.sequences.size() - 1
	populate_opcode_list(opcode_list_container, ui_manager.animation_id_spinbox.value)


func _on_delete_animation_pressed() -> void:
	seq.sequences.remove_at(ui_manager.animation_id_spinbox.value)
	ui_manager.animation_id_spinbox.max_value = seq.sequences.size() - 1
	for pointer_index: int in seq.sequence_pointers.size():
		if seq.sequence_pointers[pointer_index] >= ui_manager.animation_id_spinbox.max_value:
			seq.sequence_pointers[pointer_index] = 0
	populate_animation_list(animation_list_container, seq)
	ui_manager.update_animation_description_options(seq)
	populate_opcode_list(opcode_list_container, ui_manager.animation_id_spinbox.value)


func _on_add_pointer_pressed() -> void:
	seq.sequence_pointers.append(0)
	ui_manager.pointer_index_spinbox.max_value = seq.sequence_pointers.size() - 1
	populate_animation_list(animation_list_container, seq)


func _on_delete_pointer_pressed() -> void:
	seq.sequence_pointers.remove_at(ui_manager.pointer_index_spinbox.value)
	ui_manager.pointer_index_spinbox.max_value = seq.sequence_pointers.size() - 1
	populate_animation_list(animation_list_container, seq)


func _on_seq_file_options_item_selected(index: int, select_shp: bool = true) -> void:
	var type: String = ui_manager.seq_options.get_item_text(index)
	
	if RomReader.file_records.has(type):
		ui_manager.max_bytes = ceil(RomReader.file_records[type].size / float(data_bytes_per_sector)) * data_bytes_per_sector as int
	
	animation_list_container.get_parent().get_parent().get_parent().name = seq.file_name + " Animations"
	
	ui_manager.patch_description_edit.placeholder_text = type + " edited with FFT Animation Editor"
	ui_manager.patch_name_edit.placeholder_text = type + "_animation_edit"
	
	ui_manager.current_animation_slots = seq.sequence_pointers.size()
	ui_manager.max_animation_slots = seq.section2_length / 4
	ui_manager.current_bytes = seq.toal_length
	
	ui_manager.animation_id_spinbox.max_value = seq.sequences.size() - 1
	ui_manager.animation_id_spinbox.editable = true
	
	ui_manager.pointer_index_spinbox.max_value = seq.sequence_pointers.size() - 1
	
	ui_manager.update_animation_description_options(seq)
	
	populate_animation_list(animation_list_container, seq)
	ui_manager.pointer_index_spinbox.value = 0
	populate_opcode_list(opcode_list_container, ui_manager.animation_name_options.selected)
	
	UiManager.option_button_select_text(ui_manager.shp_options, seq.shp_name)
	ui_manager.shp_options.item_selected.emit(ui_manager.shp_options.selected)
	preview_manager.unit.animation_manager.global_seq = RomReader.seqs_array[index]
	preview_manager.unit.animation_manager._on_animation_changed()


func _on_shp_file_options_item_selected(index: int) -> void:
	frame_list_container.get_parent().get_parent().get_parent().name = shp.file_name + " Frames"
	populate_frame_list(frame_list_container, shp)
	preview_manager.unit.animation_manager.global_shp = RomReader.shps_array[index]
	preview_manager.unit.animation_manager._on_animation_changed()


func _on_sprite_options_item_selected(index: int) -> void:
	#ui_manager.preview_viewport.sprite_primary.texture = ImageTexture.create_from_image(spr.spritesheet)
	#populate_frame_list(frame_list_container, shp)
	UiManager.option_button_select_text(ui_manager.seq_options, spr.seq_name)
	ui_manager.seq_options.item_selected.emit(ui_manager.seq_options.selected)
	#UiManager.option_button_select_text(ui_manager.shp_options, spr.shp_name)
	#ui_manager.shp_options.item_selected.emit(ui_manager.shp_options.selected)
	
	preview_manager.unit.set_sprite_by_file_idx(index)
	preview_manager.unit.animation_manager._on_animation_changed()


func _on_animation_rewrite_check_toggled(toggled_on: bool) -> void:
	Seq.load_opcode_data(toggled_on)
	populate_opcode_list(opcode_list_container, ui_manager.animation_id_spinbox.value)


func _on_save_frame_grid_pressed() -> void:
	save_frame_grid_dialog.visible = true


func _on_save_frame_grid_dialog_file_selected(path: String) -> void:
	var frame_grid: Image = preview_manager.unit.animation_manager.unit_sprites_manager.sprite_primary.texture.get_image()
	frame_grid.save_png(path)
	
	save_frame_grid_dialog.visible = false


func _on_save_animation_gif_pressed() -> void:
	save_gif_dialog.visible = true


func on_save_gif_toggled(toggled_on: bool) -> void:
	if not toggled_on:
		save_gif_dialog.visible = true
	else:
		start_recoding_gif()


# TODO allow recording complete ability animations, ie. including the starting and charging animations
func start_recoding_gif() -> void:
	gif_frames.clear()
	gif_delays.clear()
	gif_frame_nums.clear()
	
	is_recording_gif = true
	push_warning("start recording gif")
	preview_manager.unit.animation_manager.is_framerate_dependent = true
	preview_manager.unit.animation_manager.animation_completed.connect(end_recording_gif)
	preview_manager.unit.animation_manager.animation_loop_completed.connect(end_recording_gif)
	preview_manager.unit.animation_manager.animation_frame_loaded.connect(add_gif_frame)
	if preview_manager.is_playing_check.button_pressed:
		preview_manager.is_playing_check.toggled.emit(true)
	else:
		preview_manager.is_playing_check.button_pressed = true # sends out signal that starts the animation
	
	#preview_manager.unit.animation_manager.animation_completed.connect(func(): push_warning("animation_completed"))


func add_gif_frame(delay_sec: float, frame_num: int) -> void:
	await get_tree().process_frame # wait for render texture to update
	if gif_frame_nums.has(frame_num): # if multiple animations have have a new frame, only save one image, with the shortest delay
		gif_delays[-1] = minf(gif_delays[-1], delay_sec)
		return
	
	gif_frame_nums.append(frame_num)
	gif_delays.append(delay_sec)
	if frame_num == 0:
		await get_tree().process_frame # wait extra for starting frame - why?
	
	var preview_image: Image = preview_manager.preview_viewport2.get_texture().get_image()
	gif_frames.append(preview_image)


func end_recording_gif() -> void:
	push_warning("end recording gif")
	await get_tree().process_frame # wait for last frame to be added
	gif_exporter = GIFExporter.new(preview_manager.preview_rect.texture.get_width(), preview_manager.preview_rect.texture.get_height())
	
	preview_manager.unit.animation_manager.animation_speed = 59
	
	for idx: int in gif_frames.size():
		gif_exporter.add_frame(gif_frames[idx], gif_delays[idx], MedianCutQuantization)
	gif_frames.clear()
	gif_delays.clear()
	gif_frame_nums.clear()
	
	if preview_manager.unit.animation_manager.animation_frame_loaded.is_connected(add_gif_frame):
		preview_manager.unit.animation_manager.animation_frame_loaded.disconnect(add_gif_frame)
	preview_manager.unit.animation_manager.animation_completed.disconnect(end_recording_gif)
	preview_manager.unit.animation_manager.animation_loop_completed.disconnect(end_recording_gif)
	is_recording_gif = false
	save_gif_button.button_pressed = false


func _on_save_gif_dialog_file_selected(path: String) -> void:
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	# save data stream into file
	file.store_buffer(gif_exporter.export_file_data())
	file.close()
	
	save_frame_grid_dialog.visible = false
