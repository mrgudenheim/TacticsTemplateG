extends RefCounted
## Handles animation playback for effect particles
##
## Processes animation opcodes (SET_OFFSET, FRAME, LOOP) and updates
## particle animation state each tick.
## Vault: [[Effect Animation Sequences]]
## Vault: [[Effect Frame Pacing]]
## Vault: [[Particle Depth Mode]]
## Vault: [[Sprite Offset vs Vertex Position]]

const EffectsDebug = preload("res://addons/exmateria_effects/install/EffectsDebug.gd")
const EffectData = preload("res://addons/exmateria_effects/file_model/EffectData.gd")
const Particle = preload("res://addons/exmateria_effects/particles/Particle.gd")

var effect_data: EffectData

# Baked animation data: [anim_index] -> Array of {frameset, duration, depth_mode, offset}
var baked_animations: Array = []


func initialize(data: EffectData) -> void:
	"""Initialize animator with effect data and bake animations."""
	effect_data = data
	_bake_animations()


func _bake_animations() -> void:
	"""Pre-process animations into frame-by-frame lookup.

	Expands opcodes into arrays where each entry represents one frame of playback:
	  baked_animations[anim_index][frame] = {frameset, depth_mode, offset, is_terminal}

	FFT's frame_timer decrements by 2 each game frame, so:
	  - duration=20 displays for 10 frames (20/2)
	  - duration=2 displays for 1 frame (2/2)
	  - duration=0 displays for 1 frame, then triggers terminal behavior
	"""
	baked_animations.clear()

	for anim in effect_data.animations:
		var frames: Array = []
		var current_offset := Vector2.ZERO

		for opcode in anim.get("opcodes", []):
			var op_type: String = opcode.get("type", "")

			match op_type:
				"SET_OFFSET":
					current_offset = Vector2(
						opcode.get("x", 0),
						opcode.get("y", 0)
					)

				"ADD_OFFSET":
					current_offset += Vector2(
						opcode.get("dx", 0),
						opcode.get("dy", 0)
					)

				"FRAME":
					var frameset: int = opcode.get("frameset", 0)
					var duration: int = opcode.get("duration", 1)
					var depth_mode: int = opcode.get("depth_mode", 0)

					# FFT decrements frame_timer by 2 each game frame
					# So display_frames = ceil(duration / 2) — the ROM seeds
					# frame_timer = duration and advances only once `timer -= 2`
					# leaves a sign-extended value < 1, so an ODD duration gets the
					# extra call (255 -> 128 frames, not 127). Even durations, which
					# are 21,032 of the corpus's 21,043 FRAME opcodes, are unchanged.
					# duration=0 is terminal: display 1 frame, then stop
					var is_terminal: bool = (duration == 0)
					var display_frames: int = maxi(1, (duration + 1) >> 1)

					for _i in range(display_frames):
						frames.append({
							"frameset": frameset,
							"depth_mode": depth_mode,
							"offset": current_offset,
							"is_terminal": is_terminal and (_i == display_frames - 1)
						})

				"LOOP":
					# Mark end of animation - handled in tick()
					pass

		baked_animations.append(frames)

	# Debug output
	if EffectsDebug.iteration() and baked_animations.size() > 0:
		print("ParticleAnimator: Baked %d animations" % baked_animations.size())
		for i in range(mini(2, baked_animations.size())):
			print("  Animation %d: %d frames" % [i, baked_animations[i].size()])


func tick(particle: Particle) -> void:
	"""Advance particle animation by one frame.

	Updates particle.anim_time, anim_frame, and anim_offset.
	Handles terminal frames (from duration=0 opcodes):
	  - lifetime=-1: Signal death for next cleanup
	  - lifetime>0: Hold on frame until natural death

	Important: We set anim_frame BEFORE incrementing anim_time so that
	the current frame is rendered before advancing to the next. This
	ensures frame 0 is rendered on spawn and the last frame is visible
	before the particle dies.
	"""
	# If held on terminal frame, don't advance
	if particle.animation_held:
		return

	var anim_idx: int = particle.anim_index
	if anim_idx < 0 or anim_idx >= baked_animations.size():
		return

	var frames: Array = baked_animations[anim_idx]
	if frames.is_empty():
		return

	# Set frame index from CURRENT time (before incrementing)
	# This ensures the current frame is rendered before we advance
	particle.anim_frame = particle.anim_time

	# Apply offset from current frame, and write the renderer-facing derivations
	# (frameset_idx, depth_mode) onto the particle. Keeping these on the particle
	# lets EffectParticleRenderer read its inputs without reaching into the
	# animator at draw time.
	var frame_data: Dictionary = frames[particle.anim_frame]
	particle.anim_offset = frame_data.get("offset", Vector2.ZERO)
	particle.frameset_idx = frame_data.get("frameset", 0) + particle.frameset_group_offset
	particle.depth_mode = frame_data.get("depth_mode", 0)

	# Check if this is a terminal frame (from duration=0 opcode)
	if frame_data.get("is_terminal", false):
		if particle.lifetime == -1:
			# Animation-driven: signal death for next cleanup
			particle.animation_complete = true
		else:
			# Fixed lifetime: hold on this frame until death
			particle.animation_held = true
		return  # Don't advance past terminal frame

	# Advance time for next tick
	particle.anim_time += 1

	# Handle looping (only reached if no terminal frame)
	if particle.anim_time >= frames.size():
		particle.anim_time = 0


func get_animation_duration(anim_index: int) -> int:
	"""Get total frame count for an animation."""
	if anim_index < 0 or anim_index >= baked_animations.size():
		return 0
	return baked_animations[anim_index].size()
