class_name SequencerOpAdsrDecay
## FFT analog: smd_op_c9_adsr_mode @ LAB_8001627C
##                (opcode 0xC9)
##
## Pass D2 — was misidentified as "decay" in the original music
## binding. FFT's 0xC9 is the ADSR2-high mode selector (stores byte
## at slot+0x5c) per the disassembly. Mirrors shared/opcodes/
## adsr_mode_c9.gd.

const _SS = preload("res://addons/exmateria_sound/runtime/shared/slot_state.gd")
const _Trace = preload("res://addons/exmateria_sound/runtime/effect_sound/trace_writer.gd")


static func apply(_sequencer, ts, params) -> void:
	if ts.ctx == null:
		return
	var byte: int = (params[0] if params.size() > 0 else 0) & 0xFF
	ts.ctx.slot.byte_5c = byte
	ts.ctx.slot.walker_flag_word |= _SS.WALKER_FLAG_ADSR2_HIGH
	# iter-56 diag — confirm music 0xC9 dispatch fires + capture byte
	# value so we can see if byte_5c reaches the walker. The
	# probe_adsr2_register 100% divergence on MUSIC_50 looks like
	# byte_5c is staying at 0 (mode 0x100) when PCSX has it = 7 (mode
	# 0x300). See MUSIC_ITER56_QUIET_CLUSTER_ADSR2_MODE.md.
	_Trace.emit("music_c9_adsr_mode", {
		"byte": byte,
		"slot_idx": ts.ctx.slot.slot_idx,
		"track_idx": ts.track_idx,
	})
