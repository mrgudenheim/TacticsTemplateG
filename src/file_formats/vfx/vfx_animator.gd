class_name VfxAnimator
extends RefCounted
## Animation driver — bakes VfxAnimation opcodes into frame-by-frame lookup
## Reads from VisualEffectData.VfxAnimation (binary-parsed) instead of JSON opcodes

var vfx_data: VisualEffectData
# Indexed by emitter index — each emitter's animation has frameset group offset already applied
var baked_animations: Array = []  # [emitter_index][frame] = {frameset, depth_mode, offset, is_terminal}


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

	var frames: Array = []
	var current_offset := Vector2(raw_anim.screen_offset)

	for anim_frame: VisualEffectData.VfxAnimationFrame in raw_anim.animation_frames:
		if anim_frame.frameset_id == 0x83:
			# ADD_OFFSET: duration=dx, byte_02=dy (sign-extend dy from u8)
			var dy: int = anim_frame.byte_02
			if dy > 127:
				dy -= 256
			current_offset += Vector2(anim_frame.duration, dy)

		elif anim_frame.frameset_id == 0x81:
			# LOOP: mark end of animation, handled in tick()
			pass

		elif anim_frame.frameset_id < 0x80:
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
				frames.append({
					"frameset": frameset,
					"depth_mode": depth_mode,
					"offset": current_offset,
					"is_terminal": is_terminal and (_i == display_frames - 1)
				})

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

	var frames: Array = baked_animations[emitter_idx]
	if frames.is_empty():
		return

	particle.anim_frame = particle.anim_time

	var frame_data: Dictionary = frames[particle.anim_frame]
	particle.anim_offset = frame_data.get("offset", Vector2.ZERO)
	particle.current_frameset = frame_data.get("frameset", 0)
	particle.current_depth_mode = frame_data.get("depth_mode", 0)

	if frame_data.get("is_terminal", false):
		if particle.lifetime == -1:
			particle.animation_complete = true
		else:
			particle.animation_held = true
		return

	particle.anim_time += 1

	if particle.anim_time >= frames.size():
		particle.anim_time = 0


func get_current_frameset(particle: VfxParticleData) -> int:
	var emitter_idx: int = particle.emitter_index
	if emitter_idx < 0 or emitter_idx >= baked_animations.size():
		return 0

	var frames: Array = baked_animations[emitter_idx]
	if frames.is_empty():
		return 0

	var frame_idx: int = clampi(particle.anim_frame, 0, frames.size() - 1)
	return frames[frame_idx].get("frameset", 0)


func get_current_depth_mode(particle: VfxParticleData) -> int:
	var emitter_idx: int = particle.emitter_index
	if emitter_idx < 0 or emitter_idx >= baked_animations.size():
		return 0

	var frames: Array = baked_animations[emitter_idx]
	if frames.is_empty():
		return 0

	var frame_idx: int = clampi(particle.anim_frame, 0, frames.size() - 1)
	return frames[frame_idx].get("depth_mode", 0)


func get_animation_duration(emitter_index: int) -> int:
	if emitter_index < 0 or emitter_index >= baked_animations.size():
		return 0
	return baked_animations[emitter_index].size()
