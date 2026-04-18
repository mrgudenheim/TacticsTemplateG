class_name VfxAnimator
extends RefCounted
## Animation driver — bakes VfxAnimation opcodes into frame-by-frame lookup
## Reads from VisualEffectData.VfxAnimation (binary-parsed) instead of JSON opcodes

class BakedFrame:
	var frameset: int
	var depth_mode: int
	var offset: Vector2
	var is_terminal: bool

	func _init(p_frameset: int, p_depth_mode: int, p_offset: Vector2, p_is_terminal: bool) -> void:
		frameset = p_frameset
		depth_mode = p_depth_mode
		offset = p_offset
		is_terminal = p_is_terminal

var vfx_data: VisualEffectData
var baked_animations: Array = []  # [emitter_index] → Array[BakedFrame]


func initialize(data: VisualEffectData) -> void:
	vfx_data = data
	_bake_animations()


func _bake_animation_for_emitter(emitter: VfxEmitter) -> Array:
	# Use raw animation (pre-offset) and apply frameset group offset only to normal frames
	if emitter.anim_index < 0 or emitter.anim_index >= vfx_data.animations.size():
		return []

	var raw_anim: VisualEffectData.VfxAnimation = vfx_data.animations[emitter.anim_index]

	# Compute frameset group offset (same logic as visual_effect_data.gd init)
	var frameset_offset: int = 0
	for idx: int in emitter.frameset_group_index:
		frameset_offset += vfx_data.frameset_groups_num_framesets[idx]

	var frames: Array[BakedFrame] = []
	var current_offset := Vector2(raw_anim.screen_offset)

	for anim_frame: VisualEffectData.VfxAnimationFrame in raw_anim.animation_frames:
		if anim_frame.frameset_id == VfxConstants.AnimOpcode.ADD_OFFSET:
			# ADD_OFFSET: duration=dx, byte_02=dy (sign-extend dy from u8)
			var dy: int = anim_frame.byte_02
			if dy > 127:
				dy -= 256
			current_offset += Vector2(anim_frame.duration, dy)

		elif anim_frame.frameset_id == VfxConstants.AnimOpcode.LOOP:
			# LOOP: mark end of animation, handled in tick()
			pass

		elif anim_frame.frameset_id <= VfxConstants.MAX_FRAMESET_ID:
			# Normal FRAME — apply frameset group offset
			var frameset: int = anim_frame.frameset_id + frameset_offset
			var duration: int = anim_frame.duration
			var depth_mode: int = anim_frame.byte_02

			# Handle signed duration: if negative, convert to unsigned
			if duration < 0:
				duration += 256

			# FFT decrements frame_timer by 2 each game frame
			# display_frames = duration / 2; duration=0 is terminal
			var is_terminal: bool = (duration == 0)
			var display_frames: int = maxi(1, duration >> 1)

			for _i in range(display_frames):
				frames.append(BakedFrame.new(
					frameset, depth_mode, current_offset,
					is_terminal and (_i == display_frames - 1)))

		# frameset_id >= 0x80 but not 0x81 or 0x83: skip unknown opcodes

	return frames


func _bake_animations() -> void:
	baked_animations.clear()

	# Bake per-emitter — uses raw animation with correct frameset group offset
	for emitter: VfxEmitter in vfx_data.emitters:
		baked_animations.append(_bake_animation_for_emitter(emitter))


func tick(particle: VfxParticleData) -> void:
	if particle.animation_held:
		return

	var emitter_idx: int = particle.emitter_index
	if emitter_idx < 0 or emitter_idx >= baked_animations.size():
		return

	var frames: Array[BakedFrame] = baked_animations[emitter_idx]
	if frames.is_empty():
		return

	particle.anim_frame = clampi(particle.anim_time, 0, frames.size() - 1)

	var frame: BakedFrame = frames[particle.anim_frame]
	particle.anim_offset = frame.offset
	particle.current_frameset = frame.frameset
	particle.current_depth_mode = frame.depth_mode

	if frame.is_terminal:
		if particle.lifetime == -1:
			particle.animation_complete = true
		else:
			particle.animation_held = true
		return

	particle.anim_time += 1

	if particle.anim_time >= frames.size():
		particle.anim_time = 0


func get_animation_duration(emitter_index: int) -> int:
	if emitter_index < 0 or emitter_index >= baked_animations.size():
		return 0
	return baked_animations[emitter_index].size()
