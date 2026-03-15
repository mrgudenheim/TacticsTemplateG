class_name VisualEffectData

# https://ffhacktics.com/wiki/Effect_File_Format
# https://ffhacktics.com/wiki/Effect_Files
# https://ffhacktics.com/wiki/Effect_Data

var is_initialized: bool = false
var file_name: String = "effect file name"
var vfx_id: int = 0
var ability_names: String = ""

var header_start: int = 0
var section_offsets: PackedInt32Array = []

var num_frameset_groups: int = 0
var frameset_group_offsets: PackedInt32Array = []
var frameset_groups_num_framesets: PackedInt32Array = []
var framesets: Array[VfxFrameSet] = []
var animations: Array[VfxAnimation] = []
var num_curves: int = 0
var curves_bytes: Array[PackedByteArray] = []
var curves: Array[PackedFloat64Array] = []
var time_scale_curve: PackedByteArray = []

class VfxFrameSet:
	var flags: int = 0 # unused
	var num_frames: int = 0
	var frameset: Array[VfxFrame] = []

class VfxFrame:
	var vram_bytes: PackedByteArray = []
	var palette_id: int = 0 
	var semi_transparency_mode: int = 0
	var image_color_depth: int = 0 # 0 = 4bpp, 1 = 8bpp
	var semi_transparency_on: bool = true
	var frame_width_signed: bool = false
	var frame_height_signed: bool = false
	var texture_page: int = 0
	
	var top_left_uv: Vector2i = Vector2i.ZERO
	var uv_width: int = 0
	var uv_height: int = 0
	var top_left_xy: Vector2i = Vector2i.ZERO
	var top_right_xy: Vector2i = Vector2i.ZERO
	var bottom_left_xy: Vector2i = Vector2i.ZERO
	var bottom_right_xy: Vector2i = Vector2i.ZERO
	var quad_vertices: PackedVector3Array = []
	var quad_uvs_pixels: PackedVector2Array = []
	var quad_uvs: PackedVector2Array = []

class VfxAnimation:
	var animation_frames: Array[VfxAnimationFrame]
	var screen_offset: Vector2i

class VfxAnimationFrame:
	var frameset_id: int
	var duration: int
	var byte_02: int # depth mode

	# Depth Modes
	# Mode 0: Z >> 2 (standard depth-based)
	# Mode 1: Z >> 2 - 8 (pulled forward)
	# Mode 2: Fixed at 8 (very front)
	# Mode 3: Fixed at 0x17E (very back)
	# Mode 4: Fixed at 0x10 (near front)
	# Mode 5: Z >> 2 - 0x10 (strongly forward)

# 128 bytes, 25 keyframes
class EmitterTimeline:
	var bytes: PackedByteArray = []
	var times: PackedInt32Array = []
	var emitter_ids: PackedInt32Array = []
	var action_flags: PackedByteArray = []
	var num_keyframes: int = 0

	var keyframes: Array[EmitterKeyframe] = []
	var has_unknown_flags: bool = false

	func _init(new_bytes: PackedByteArray):
		bytes = new_bytes
		# Layout: 25×u16 times (0x00), 25×u8 emitter_ids (0x31), 25×u16 action_flags (0x4A), u16 num_kf (0x7E)
		action_flags = bytes.slice(0x4A, 0x4A + 50)
		num_keyframes = bytes.decode_s16(0x7E)

		for idx in 25:
			var time: int = bytes.decode_u16(idx * 2)
			times.append(time)

			var emitter_id: int = bytes.decode_u8(0x31 + idx)
			emitter_ids.append(emitter_id)

			var action_flag: int = action_flags.decode_u16(idx * 2)
			# if not [0, 0x1000, 0x2000, 0x3000, 0x4000, 0x5000, 0x6000, 0x7000].has(action_flag):
			# 	has_unknown_flags = true
				# push_warning(action_flag)
			
			var new_keyframe: EmitterKeyframe = EmitterKeyframe.new()
			new_keyframe.time = time
			new_keyframe.emitter_id = emitter_id
			new_keyframe.flags = action_flags.slice(idx * 2, (idx + 1) * 2)
			new_keyframe.display_damage = action_flag & 0x1000 == 0x1000
			new_keyframe.status_change = action_flag & 0x2000 == 0x2000
			new_keyframe.target_animation = action_flag & 0x4000 == 0x4000
			new_keyframe.use_global_target = action_flag & 0x0800 == 0x0800
			new_keyframe.callback_slot = ((action_flag & 0x0700) >> 8) - 1 # will give -1 if not using callback
			new_keyframe.animation_param = action_flag & 0x00FF

			new_keyframe.unused_flag_80 = action_flag & 0x8000 == 0x8000

			keyframes.append(new_keyframe)

class EmitterKeyframe:
	var time: int = -1 # frames
	var emitter_id: int = -1
	var flags: PackedByteArray = []
	var display_damage: bool = false
	var status_change: bool = false
	var target_animation: bool = false
	var use_global_target: bool = false
	var callback_slot: int = -1
	var animation_param: int = 0
	var unused_flag_80: bool = false

var script_bytes: PackedByteArray = []
var emitter_control_bytes: PackedByteArray = []
var emitters: Array[VfxEmitter] = []

## Particle header fields (from 0x14-byte header at start of EMITTER_DATA section)
var gravity_raw: Vector3i = Vector3i.ZERO  ## raw s32 values
var gravity: Vector3 = Vector3.ZERO        ## converted: / ACCEL_DIVISOR with Y-flip
var inertia_threshold: int = 0             ## raw s32, used directly in physics formula
var timer_data_header_bytes: PackedByteArray = []
var timer_data_bytes: PackedByteArray = []
var phase1_duration: int = -1
var child_spawn_delay: int = -1
var phase2_offset: int = -1

var child_emitter_timelines: Array[EmitterTimeline] = []
var phase1_emitter_timelines: Array[EmitterTimeline] = []
var phase2_emitter_timelines: Array[EmitterTimeline] = []

var vfx_spr: Spr
var texture: Texture2D
var image_color_depth: int = 0 # 8bpp or 4bpp

# SINGLE - camera will point at the targeted location
# SEQUENTIAL - camera will move between each each target
# MULTI - camera will point at a single location, but make sure all targets are in view
enum camera_focus {SINGLE, SEQUENTIAL, MULTI} 

var sound_effects
var partical_effects

enum VfxSections {
	FRAMES = 0,
	ANIMATION = 1,
	VFX_SCRIPT = 2,
	EMITTER_DATA = 3,
	CURVES = 4,
	TIME_SCALE_CURVE = 5, # optional
	EFFECT_FLAGS = 6,
	TIMELINES = 7,
	SOUND_EFFECTS = 8,
	TEXTURE = 9,
	}


func get_curve(index: int) -> VfxCurve:
	if index < 0 or index >= curves.size():
		return null
	return VfxCurve.new(curves[index], index)


func _init(new_file_name: String = "") -> void:
	file_name = new_file_name
	vfx_id = new_file_name.trim_suffix(".BIN").trim_prefix("E").to_int()


func init_from_file() -> void:
	var vfx_bytes: PackedByteArray = RomReader.get_file_data(file_name)

	if vfx_bytes.size() == 0:
		push_warning(file_name + ": zero bytes in file. Skipping.")
		return
	
	#### header data
	header_start = RomReader.battle_bin_data.ability_vfx_header_offsets[vfx_id]
	var entry_size = 4
	var num_entries = 10
	var data_bytes: PackedByteArray = vfx_bytes.slice(header_start, header_start + (entry_size * num_entries))
	section_offsets.resize(num_entries)
	for id: int in num_entries:
		section_offsets[id] = data_bytes.decode_u32(id * entry_size) + header_start
	
	#### frame data (and image color depth)
	var section_num = VfxSections.FRAMES
	var section_start: int = section_offsets[section_num]
	data_bytes = vfx_bytes.slice(section_start, section_offsets[section_num + 1])
	
	num_frameset_groups = data_bytes.decode_u32(0)
	var initial_offset: int = 4
	for group_idx: int in num_frameset_groups:
		var group_offset: int = data_bytes.decode_u16(initial_offset + (group_idx * 2))
		frameset_group_offsets.append(group_offset)

	initial_offset += num_frameset_groups * 2
	var frame_sets_data_start: int = data_bytes.decode_u16(initial_offset) + 4
	var num_frame_sets: int = (frame_sets_data_start - initial_offset) / 2

	var framesets_so_far: int = 0
	for group_idx: int in num_frameset_groups:
		if group_idx > 0:
			frameset_groups_num_framesets[group_idx - 1] = (frameset_group_offsets[group_idx] - frameset_group_offsets[group_idx - 1]) / 2
			framesets_so_far += frameset_groups_num_framesets[group_idx - 1]
		
		frameset_groups_num_framesets.append(num_frame_sets - framesets_so_far)

	framesets.resize(num_frame_sets)
	var frame_set_offsets: PackedInt32Array = []
	frame_set_offsets.resize(num_frame_sets)
	
	for id: int in num_frame_sets:
		var offset: int = data_bytes.decode_u16(initial_offset + (2 * id)) + 4
		if offset == 4:
			num_frame_sets -= 1
			frame_set_offsets.resize(num_frame_sets)
			framesets.resize(num_frame_sets)
			continue
		frame_set_offsets[id] = offset
	
	# image color depth from first frame in first frame_set
	if data_bytes.decode_u8(frame_set_offsets[0]) & 0x80 == 0 and data_bytes.decode_u8(0) == 1:
		image_color_depth = 4
	else:
		image_color_depth = 8
	
	# frame sets
	for frame_set_id: int in num_frame_sets:
		var frame_set: VfxFrameSet = VfxFrameSet.new()
		
		var next_section_start: int = data_bytes.size()
		if frame_set_id < num_frame_sets - 1:
			next_section_start = frame_set_offsets[frame_set_id + 1]
		
		var frame_set_bytes: PackedByteArray = data_bytes.slice(frame_set_offsets[frame_set_id], next_section_start)
		var num_frames: int = frame_set_bytes.decode_u16(2)
		frame_set.num_frames = num_frames
		var frame_data_length: int = 0x18
		# var num_frames: int = (frame_set_bytes.size() - 4) / frame_data_length
		frame_set.frameset.resize(num_frames)
		for frame_id: int in num_frames:
			var frame_bytes: PackedByteArray = frame_set_bytes.slice(4 + (frame_id * frame_data_length))
			if frame_bytes.is_empty(): # E509
				push_warning(file_name + "frameset " + str(frame_set_id) + " does not have bytes for a frame, clearing frameset")
				frame_set.frameset.clear()
				break
			
			var new_frame: VfxFrame = VfxFrame.new()
			new_frame.vram_bytes = frame_bytes.slice(0, 4)
			new_frame.palette_id = new_frame.vram_bytes[0] & 0x0f
			new_frame.semi_transparency_mode = (new_frame.vram_bytes[0] & 0x60) >> 5
			new_frame.image_color_depth = 4 + ((new_frame.vram_bytes[0] & 0x80) >> 5)
			new_frame.semi_transparency_on = (new_frame.vram_bytes[1] & 0x02) == 0x02
			new_frame.frame_width_signed = (new_frame.vram_bytes[1] & 0x10) == 0x10
			new_frame.frame_height_signed = (new_frame.vram_bytes[1] & 0x20) == 0x20
			new_frame.texture_page = new_frame.vram_bytes.decode_u16(2)
			
			var top_left_u: int = frame_bytes.decode_u8(4)
			var top_left_v: int = frame_bytes.decode_u8(5)
			new_frame.top_left_uv = Vector2i(top_left_u, top_left_v)
			
			if new_frame.frame_width_signed:
				new_frame.uv_width = frame_bytes.decode_s8(6)
			else:
				new_frame.uv_width = frame_bytes.decode_u8(6)
			if new_frame.frame_height_signed:
				new_frame.uv_height = frame_bytes.decode_s8(7)
			else:
				new_frame.uv_height = frame_bytes.decode_u8(7)
			#new_frame.uv_width = frame_bytes.decode_s8(6)
			#new_frame.uv_height = frame_bytes.decode_s8(7)
			var top_left_x: int = frame_bytes.decode_s16(8)
			var top_left_y: int = frame_bytes.decode_s16(0xa)
			new_frame.top_left_xy = Vector2i(top_left_x, top_left_y)
			var top_right_x: int = frame_bytes.decode_s16(0xc)
			var top_right_y: int = frame_bytes.decode_s16(0xe)
			new_frame.top_right_xy = Vector2i(top_right_x, top_right_y)
			var bottom_left_x: int = frame_bytes.decode_s16(0x10)
			var bottom_left_y: int = frame_bytes.decode_s16(0x12)
			new_frame.bottom_left_xy = Vector2i(bottom_left_x, bottom_left_y)
			var bottom_right_x: int = frame_bytes.decode_s16(0x14)
			var bottom_right_y: int = frame_bytes.decode_s16(0x16)
			new_frame.bottom_right_xy = Vector2i(bottom_right_x, bottom_right_y)
			var vertices_xy: PackedVector2Array = []
			vertices_xy.append(new_frame.top_left_xy)
			vertices_xy.append(new_frame.top_right_xy)
			vertices_xy.append(new_frame.bottom_left_xy)
			vertices_xy.append(new_frame.bottom_right_xy)
			
			new_frame.quad_uvs_pixels.append(Vector2(top_left_u, top_left_v)) # top left
			new_frame.quad_uvs_pixels.append(Vector2((top_left_u + new_frame.uv_width), top_left_v)) # top right
			new_frame.quad_uvs_pixels.append(Vector2(top_left_u, (top_left_v + new_frame.uv_height))) # bottom left
			new_frame.quad_uvs_pixels.append(Vector2((top_left_u + new_frame.uv_width), (top_left_v + new_frame.uv_height))) # bottom right
			
			for vertex_idx: int in vertices_xy.size():
				new_frame.quad_vertices.append(Vector3(vertices_xy[vertex_idx].x, -vertices_xy[vertex_idx].y, 0) * MapData.SCALE)
			
			frame_set.frameset[frame_id] = new_frame
		
		framesets[frame_set_id] = frame_set
	
	
	### animation data
	section_num = VfxSections.ANIMATION
	section_start = section_offsets[section_num]
	data_bytes = vfx_bytes.slice(section_start, section_offsets[section_num + 1])
	
	var num_animations: int = data_bytes.decode_u32(0)
	animations.resize(num_animations)
	for anim_id: int in num_animations:
		var anim_start_offset: int = data_bytes.decode_u16(4 + (anim_id * 2)) + 4
		var anim_end: int = data_bytes.size()
		if anim_id < num_animations - 1:
			anim_end = data_bytes.decode_u16(4 + ((anim_id + 1) * 2)) + 4
		
		var anim_bytes: PackedByteArray = data_bytes.slice(anim_start_offset, anim_end)
		var animation: VfxAnimation = VfxAnimation.new()
		
		# Variable-length opcode parsing
		var byte_index: int = 0
		while byte_index < anim_bytes.size():
			var opcode: int = anim_bytes.decode_u8(byte_index)
			if opcode <= 0x7F:
				# FRAME: 3 bytes (frameset_id, duration, depth_mode)
				if byte_index + 3 > anim_bytes.size():
					break
				var anim_frame_data := VfxAnimationFrame.new()
				anim_frame_data.frameset_id = opcode
				anim_frame_data.duration = anim_bytes.decode_s8(byte_index + 1)
				anim_frame_data.byte_02 = anim_bytes.decode_u8(byte_index + 2)
				animation.animation_frames.append(anim_frame_data)
				byte_index += 3
			elif opcode == 0x81:
				# LOOP: 1 byte — store as marker, stop parsing
				var anim_frame_data := VfxAnimationFrame.new()
				anim_frame_data.frameset_id = 0x81
				animation.animation_frames.append(anim_frame_data)
				break
			elif opcode == 0x82:
				# SET_OFFSET: 5 bytes (opcode, s16 x, s16 y)
				if byte_index + 5 > anim_bytes.size():
					break
				animation.screen_offset = Vector2i(
					anim_bytes.decode_s16(byte_index + 1),
					anim_bytes.decode_s16(byte_index + 3))
				byte_index += 5
			elif opcode == 0x83:
				# ADD_OFFSET: 3 bytes (opcode, s8 dx, s8 dy)
				if byte_index + 3 > anim_bytes.size():
					break
				var anim_frame_data := VfxAnimationFrame.new()
				anim_frame_data.frameset_id = 0x83
				anim_frame_data.duration = anim_bytes.decode_s8(byte_index + 1)
				anim_frame_data.byte_02 = anim_bytes.decode_u8(byte_index + 2)
				animation.animation_frames.append(anim_frame_data)
				byte_index += 3
			else:
				# Unknown opcode, skip 1 byte
				byte_index += 1
		
		animations[anim_id] = animation
	
	
	### script data
	section_num = VfxSections.VFX_SCRIPT
	section_start = section_offsets[section_num]
	script_bytes = vfx_bytes.slice(section_start, section_offsets[section_num + 1])
	
	# TODO extract relevant data from effect script;
	
	### emitter control data
	section_num = VfxSections.EMITTER_DATA
	section_start = section_offsets[section_num]
	emitter_control_bytes = vfx_bytes.slice(section_start, section_offsets[section_num + 1])

	# Particle header (0x14 bytes): constant, emitter_count, gravity (3x s32), inertia_threshold (s32)
	var num_emitters: int = emitter_control_bytes.decode_u16(2)
	gravity_raw = Vector3i(
		emitter_control_bytes.decode_s32(0x04),
		emitter_control_bytes.decode_s32(0x08),
		emitter_control_bytes.decode_s32(0x0C))
	gravity = Vector3(
		gravity_raw.x / VfxEmitter.ACCEL_DIVISOR,
		-gravity_raw.y / VfxEmitter.ACCEL_DIVISOR,
		gravity_raw.z / VfxEmitter.ACCEL_DIVISOR)
	inertia_threshold = emitter_control_bytes.decode_s32(0x10)
	emitters.resize(num_emitters)
	
	for emitter_id: int in num_emitters:
		var emitter_data_start: int = 0x14 + (196 * emitter_id)
		var emitter_data_bytes: PackedByteArray = emitter_control_bytes.slice(emitter_data_start, emitter_data_start + 196)
		var emitter: VfxEmitter = VfxEmitter.new(emitter_data_bytes, self)
		
		# emitter.anim_index = emitter_data_bytes.decode_u8(1)
		# emitter.motion_type_flag = emitter_data_bytes.decode_u8(2)
		# emitter.animation_target_flag = emitter_data_bytes.decode_u8(3)
		# emitter.frameset_group_index = emitter_data_bytes.decode_u8(4)
		# emitter.byte_05 = emitter_data_bytes.decode_u8(5)
		# emitter.color_masking_motion_flags = emitter_data_bytes.decode_u8(6)
		# emitter.byte_07 = emitter_data_bytes.decode_u8(7)
		
		# emitter.start_position = Vector3i(emitter_data_bytes.decode_s16(0x14), -emitter_data_bytes.decode_s16(0x16), emitter_data_bytes.decode_s16(0x18))
		# emitter.end_position = Vector3i(emitter_data_bytes.decode_s16(0x1a), -emitter_data_bytes.decode_s16(0x1c), emitter_data_bytes.decode_s16(0x1e))
		
		emitters[emitter_id] = emitter
	
	# Curves
	section_num = VfxSections.CURVES
	section_start = section_offsets[section_num]
	var next_section_start = section_offsets[section_num + 1]
	if next_section_start == 0:
		next_section_start = section_offsets[section_num + 2] # skip timing speed curve if it doesn't exist
	var curve_section_bytes = vfx_bytes.slice(section_start, next_section_start)

	num_curves = curve_section_bytes.decode_u32(0)
	curves_bytes.resize(num_curves)
	curves.resize(num_curves)
	var curve_length = 0xA0 # 160 bytes
	for curve_idx in num_curves:
		var curve_data_start: int = 4 + (curve_idx * curve_length)
		var curve_data_end: int = curve_data_start + curve_length
		curves_bytes[curve_idx] = curve_section_bytes.slice(curve_data_start, curve_data_end)

		var new_curve: PackedFloat64Array = []
		new_curve.resize(curve_length)
		for byte_idx: int in curve_length:
			new_curve[byte_idx] = curves_bytes[curve_idx][byte_idx] / 255.0 # convert to percentage
		curves[curve_idx] = new_curve

	# Timing Curve
	section_num = VfxSections.TIME_SCALE_CURVE
	section_start = section_offsets[section_num]
	if section_start != 0: # skip this section if it doesn't exist
		time_scale_curve = vfx_bytes.slice(section_start, section_offsets[section_num + 1])

	### TODO timer header data
	section_num = VfxSections.EFFECT_FLAGS
	section_start = section_offsets[section_num]
	timer_data_header_bytes = vfx_bytes.slice(section_start, section_offsets[section_num + 1])
	
	# Phase timing read below from TIMELINES section header (not EFFECT_FLAGS)
	child_spawn_delay = timer_data_header_bytes.decode_u16(6)

	### TODO timeline data
	section_num = VfxSections.TIMELINES
	section_start = section_offsets[section_num]
	timer_data_bytes = vfx_bytes.slice(section_start, section_offsets[section_num + 1])
	
	# Phase timing from TIMELINES section header (matches godot-learning)
	phase1_duration = timer_data_bytes.decode_u16(4)
	var target_switching_delay: int = timer_data_bytes.decode_u16(6)
	phase2_offset = timer_data_bytes.decode_u16(10)
	
	# TODO 5 emitter timing sections, 0x80 long each
	for emitter_timing_section_id: int in 5:
		var emitter_timing_data_start: int = 0x0c + (emitter_timing_section_id * 0x80)

		var new_timeline: EmitterTimeline = EmitterTimeline.new(timer_data_bytes.slice(emitter_timing_data_start, emitter_timing_data_start + 0x80))
		child_emitter_timelines.append(new_timeline)

		# var times: PackedInt32Array = []
		# times.resize(25)
		# var emitter_ids: PackedInt32Array = []
		# emitter_ids.resize(times.size())
		# for time_index: int in times.size():
		# 	var time: int = timer_data_bytes.decode_u16(emitter_timing_data_start + (time_index * 2))
		# 	times[time_index] = time
		# 	var emitter_id: int = timer_data_bytes.decode_u8(emitter_timing_data_start + 0x32 + time_index)
		# 	emitter_ids[time_index] = emitter_id
		# 	if emitter_id - 1 >= emitters.size():
		# 		push_warning(file_name + ": time_index " + str(time_index) + "; emitter " + str(emitter_id - 1) + "/" + str(emitters.size()))
		# 	elif emitter_id > 0:
		# 		if emitters[emitter_id - 1].start_time == 0 and time < 0x200: # TODO can an emitter be started multiple times? Ex. Cure E001 2nd timing section
		# 			emitters[emitter_id - 1].start_time = time # TODO figure out special 'times' of 0x257, 0x0258, and 0x0259
	
	# Parent Phase1 Emitters
	for emitter_timing_section_id: int in 5:
		var emitter_timing_data_start: int = 0x82A + (emitter_timing_section_id * 0x80)

		var new_timeline: EmitterTimeline = EmitterTimeline.new(timer_data_bytes.slice(emitter_timing_data_start, emitter_timing_data_start + 0x80))
		phase1_emitter_timelines.append(new_timeline)

	# Phase2 Emitters
	for emitter_timing_section_id: int in 5:
		var emitter_timing_data_start: int = 0xAAA + (emitter_timing_section_id * 0x80)

		var new_timeline: EmitterTimeline = EmitterTimeline.new(timer_data_bytes.slice(emitter_timing_data_start, emitter_timing_data_start + 0x80))
		phase2_emitter_timelines.append(new_timeline)


	#### image and palette data
	section_num = VfxSections.TEXTURE
	section_start = section_offsets[section_num]
	data_bytes = vfx_bytes.slice(section_start)
	
	var palette_bytes: PackedByteArray = []
	if image_color_depth == 8:
		palette_bytes = data_bytes.slice(0, 512)
	elif image_color_depth == 4:
		palette_bytes = data_bytes.slice(512, 1024)
	else:
		push_warning(file_name + " image_color_depth not set")
	
	vfx_spr = Spr.new(file_name)
	vfx_spr.bits_per_pixel = image_color_depth
	vfx_spr.pixel_data_start = 1024 + 4
	vfx_spr.num_colors = 256
	var image_size_bytes: PackedByteArray = data_bytes.slice(1024, 1024 + 4)
	if image_color_depth == 8 and image_size_bytes[2] == 0x01 and image_size_bytes[3] == 0x01:
		vfx_spr.width = 256
		vfx_spr.height = 256
	else:
		vfx_spr.height = image_size_bytes[1] * 2
		vfx_spr.width = 1024 / image_color_depth
	
	vfx_spr.has_compressed = false
	vfx_spr.num_pixels = vfx_spr.width * vfx_spr.height
	vfx_spr.set_palette_data(palette_bytes)
	vfx_spr.color_indices = vfx_spr.set_color_indices(data_bytes.slice(1024 + 4))
	
	# TODO fix transparency - some frames should be opaque, like summons (Odin), some should just be less transparent, like songs and some geomancy (waterfall)
	
	#vfx_spr.color_palette[vfx_spr.color_indices[0]].a8 = 0 # set background color (ie. color of top left pixel) as transparent
	
	vfx_spr.set_pixel_colors()
	vfx_spr.spritesheet = vfx_spr.get_rgba8_image()
	
	texture = ImageTexture.create_from_image(vfx_spr.spritesheet)
	
	# set frame uvs based on spr
	for frameset_idx: int in framesets.size():
		for frame_idx: int in framesets[frameset_idx].frameset.size():
			var vfx_frame: VfxFrame = framesets[frameset_idx].frameset[frame_idx]
			vfx_frame.quad_uvs.resize(vfx_frame.quad_uvs_pixels.size())
			for vert_idx: int in vfx_frame.quad_uvs_pixels.size():
				vfx_frame.quad_uvs[vert_idx] = Vector2(vfx_frame.quad_uvs_pixels[vert_idx].x / float(vfx_spr.width), 
					vfx_frame.quad_uvs_pixels[vert_idx].y / float(vfx_spr.height))
	
	is_initialized = true


func get_frame_mesh(composite_frame_idx: int, frame_idx: int = 0) -> ArrayMesh:
	var vfx_frame: VfxFrame = framesets[composite_frame_idx].frameset[frame_idx]
	
	# TODO use object pooling and just adjust the vertex positions
	var st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	
	for vert_index: int in [0, 1, 2]:
		#st.set_normal(quad_normals[vert_index] * SCALE)
		st.set_uv(vfx_frame.quad_uvs[vert_index])
		st.set_color(Color.WHITE)
		st.add_vertex(vfx_frame.quad_vertices[vert_index])
	
	for vert_index: int in [2, 1, 3]:
		#st.set_normal(quad_normals[vert_index] * SCALE)
		st.set_uv(vfx_frame.quad_uvs[vert_index])
		st.set_color(Color.WHITE)
		st.add_vertex(vfx_frame.quad_vertices[vert_index])
	
	st.generate_normals()
	var mesh: ArrayMesh = st.commit()
	
	var mesh_material: StandardMaterial3D
	var albedo_texture: Texture2D = texture
	mesh_material = StandardMaterial3D.new()
	mesh_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mesh_material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	#mesh_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	mesh_material.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	#mesh_material.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
	mesh_material.render_priority = 1
	mesh_material.vertex_color_use_as_albedo = true
	
	
	# TODO maybe byte 1, bit 0x02 turns semi-transparency on or off?
	# Mostly (only?) affects Summon's creature and texture squares, meteor, pitfall, carve model, local quake, small bomb, empty black squares on some others
	#var semi_transparency_on = ((vfx_frame.vram_bytes[1] & 0x02) >> 1) == 1
	if vfx_frame.semi_transparency_on:
		#var semi_transparency_mode = (vfx_frame.vram_bytes[0] & 0x60) >> 5 # TODO maybe byte 0, bit 0x60 is semi-transparency mode?
		if vfx_frame.semi_transparency_mode == 0: # 0.5 back + 0.5 forward
			#albedo_texture = ImageTexture.create_from_image(image_mode_0)
			mesh_material.albedo_color = Color(1, 1, 1, 0.5)
			mesh_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			mesh_material.blend_mode = BaseMaterial3D.BLEND_MODE_MIX
		elif vfx_frame.semi_transparency_mode == 1: # 1 back + 1 forward
			#albedo_texture = ImageTexture.create_from_image(vfx_spr.spritesheet)
			#albedo_texture = ImageTexture.create_from_image(image_mode_0)
			#mesh_material.albedo_color = Color(0.75, 0.75, 0.75, 1)
			mesh_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			mesh_material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		elif vfx_frame.semi_transparency_mode == 2: # 1 back - 1 forward
			#albedo_texture = ImageTexture.create_from_image(vfx_spr.spritesheet)
			mesh_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			mesh_material.blend_mode = BaseMaterial3D.BLEND_MODE_SUB
		elif vfx_frame.semi_transparency_mode == 3: # 1 back + 0.25 forward
			#albedo_texture = ImageTexture.create_from_image(image_mode_3)
			mesh_material.albedo_color = Color(0.25, 0.25, 0.25, 1)
			mesh_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			mesh_material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
			#mesh_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
			#mesh_material.alpha_scissor_threshold = 0.01
	else:
		mesh_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
		mesh_material.alpha_scissor_threshold = 0.5
	
	mesh_material.set_texture(BaseMaterial3D.TEXTURE_ALBEDO, albedo_texture)
	mesh.surface_set_material(0, mesh_material)
	
	return mesh
