class_name SequencerOpPitchLfoDepth
## FFT analog: smd_op_d7_pitch_lfo_depth @ LAB_800165ac
##                (opcode 0xD7)
##
## Pass 7.D.d — writes channel.lfo_sub_depth[0] for the GDScript LFO
## engine. Mirrors shared/opcodes/pitch_lfo_depth.gd. The previous
## mixer.set_voice_pitch_lfo_depth call into C++ is dropped — Godot
## music's LFO is GDScript-side now.

const _Trace = preload("res://addons/exmateria_sound/runtime/effect_sound/trace_writer.gd")
const _ProbeCounters = preload("res://addons/exmateria_sound/runtime/effect_sound/probes/probe_counters.gd")


static func apply(_sequencer, ts, params) -> void:
	if ts.ctx == null:
		return
	if params.size() == 0 or params[0] == 0xff:
		return
	# Pairs with PCSX probe_callstack_d7_dispatch_music.lua BP @ 0x800165AC.
	# Emit BEFORE the divisor==0 early-return so the call_index matches FFT
	# (which also passes the BP before any 0-check, since FFT divides v0=256
	# by v1=param+1 unconditionally — divisor=0 cannot occur because the
	# 0xff guard above pre-empts the only way v1 wraps to 0).
	_ProbeCounters.opcode_d7_pitch_lfo_depth += 1
	_Trace.emit("opcode_d7_pitch_lfo_depth", {
		"call_index": _ProbeCounters.opcode_d7_pitch_lfo_depth,
		"param": params[0] & 0xFF,
		"channel_idx": ts.ctx.channel.channel_idx,
	})
	var divisor: int = (params[0] + 1) & 0xFF
	if divisor == 0:
		return
	var depth: int = 0x100 / divisor
	# Iter-37 Bug A: FFT PC 0x800165D4 stores to chan+0xFA (depth_reload /
	# our depth_delta) BEFORE PC 0x800165D8 stores to chan+0xF8 (depth).
	# Previously only the depth store was mirrored, leaving depth_delta at
	# its default (256) — first per-tick fade-in tick produced depth+256
	# (>= 0x100), tripping the no-scale branch and skipping the 32-tick ramp.
	ts.ctx.channel.lfo_sub_depth_delta[0] = depth
	ts.ctx.channel.lfo_sub_depth[0] = depth
