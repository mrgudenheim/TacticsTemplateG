class_name SequencerOpEndbar
## FFT analog: smd_end_bar @ FUN_800158F8 (opcode 0x90).
##
## KNOWN BUG (iter-53 investigation, not yet fixed): per the FFT disasm
## at PC 0x800158F8-1C, 0x90 is a CONDITIONAL loop-back, NOT an
## unconditional track terminator:
##
##   ram:800158f8  lw    v0, 0x1c(a2)       ; v0 = chan+0x1C (loop_point)
##   ram:80015900  beq   v0, zero, REAL_END ; if loop_point == 0, terminate
##   ram:80015908  move  a3, v0             ; ELSE: stream pointer = loop_point
##   ram:8001590c  lhu   v0, 0x28(a2)       ; v0 = chan+0x28 (loop_counter)
##   ram:80015914  addiu v0, v0, 0x1        ; loop_counter++
##   ram:80015918  sh    v0, 0x28(a2)       ; commit
##   ram:8001591c  j     RETURN             ; resume at loop_point
##
## loop_point is set by opcode 0x91 (smd_loop) at PC 0x800159E4
## (Godot mirror: sequencer/opcodes/loop.gd).
##
## This handler should check `ts.loop_point` and loop-back if set —
## MUSIC_30 (and other tracks with a 0x91 Loop followed by 0x90
## EndBar) silence after ~3.8s on Godot because of this missing path,
## producing the library-wide MUSIC_30 cos_dist 0.19 + 30% RMS deficit.
## Fix needs careful loop_point off-by-one verification (advance_track.
## gd:138-139's end-of-events fallback uses loop_point + 1; that may or
## may not be the right offset here). See
## smd-player/docs/MUSIC_ITER53_ENDBAR_LOOP_BACK.md for the disasm
## trail; the fix lands once the index convention is confirmed against
## live trace data.


static func apply(_sequencer, ts, _params) -> void:
	# iter-53: FFT smd_end_bar loop-back path (PC 0x80015908-1C).
	# If a prior 0x91 Loop dispatched and set ts.loop_point, resume
	# bytecode at loop_point — the event index right AFTER 0x91 (loop.gd
	# captures event_idx post-increment). NO `+ 1` here: FFT's chan+0x1C
	# is the byte AFTER 0x91, and the Godot event_idx analogue is
	# loop_point exactly. See
	# smd-player/docs/MUSIC_ITER53_ENDBAR_LOOP_BACK.md.
	if ts.loop_point >= 0:
		ts.event_idx = ts.loop_point
		return
	# FFT FALL_THROUGH at PC 0x80015924-CC — actual termination when no
	# 0x91 was dispatched.
	if ts.current_note >= 0:
		ts.end_bar_pending = true
	else:
		ts.done = true
	# Pass 7.D.d — clear channel_word_0 so the advance_lfo gate at
	# PC 0x800174D0 disarms after the track ends. SFX endbar does the
	# same via FFT LAB_800159CC. ts.done is also checked separately in
	# Sequencer.tick / MusicSlotPool.active_slots (filter), so this is
	# a defense-in-depth disarm for downstream consumers.
	if ts.ctx != null:
		ts.ctx.channel.channel_word_0 = 0
