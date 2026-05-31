class_name SharedOpRest
## FFT analog: smd_rest @ 0x80015874
##                (jumptable @ 0x80028B0C)

const _CH = preload("res://addons/exmateria_sound/runtime/shared/channel_state.gd")
const _SS = preload("res://addons/exmateria_sound/runtime/shared/slot_state.gd")
const _Trace = preload("res://addons/exmateria_sound/runtime/effect_sound/trace_writer.gd")
const _ProbeCounters = preload("res://addons/exmateria_sound/runtime/effect_sound/probes/probe_counters.gd")


static func apply(_dispatcher, channel: _CH, slot: _SS,
		op: SMDOpcodes.OpcodeEvent, _voice_writes: bool) -> void:
	## Rest — opcode 0x80
	_ProbeCounters.opcode_rest += 1
	_Trace.emit("opcode_rest", {
		"call_index": _ProbeCounters.opcode_rest,
		"rest_byte": (op.params[0] if op.params.size() > 0 else 0) & 0xFF,
	})
	channel.channel_word_0 |= _SS.CHAN0_KON_ARM
	# FFT smd_rest at PC 0x80015884 `ori v1, v1, 0x2; sh v1, 0x2(a2)`
	# — Rest sets chan_word_1 bit 0x2. Drained by FUN_80017118 at
	# PC 0x800173A0 (`andi v0, s1, 0x2; beq v0, zero, LAB_800173b8`
	# decides whether to also read chan+0x34 into s5 accumulator).
	# Without this, probe_fun80017118_clear's chan_word_1_pre_clear
	# is missing bit 0x2 on Rest-dispatch cadences.
	channel.channel_word_1 |= 0x2
	# Rest's param[0] holds the rest duration in the same
	# encoding as Note delta_time bytes.
	# 16-bit halfword (FFT `smd_rest` at PC 0x8001587c —
	# `sh v0, 0x74(a2)` from `lbu` payload).
	channel.note_duration = _decode_rest_duration(op) & 0xFFFF
	# Per-Note auto-KOFF when a Rest opcode is dispatched mid-
	# stream. FFT's per-tick KOFF dispatcher at L80014EEC issues
	# `jal FUN_8001acf0(a0=0, a1=mask)` for each sound channel
	# that has slot+0x10 bit 0x2 set; that bit is set when a
	# Note's duration drains and the next opcode is a Rest
	# (silence period). Without this, voices sustain across
	# Rest gaps mid-stream and the next Note's KON re-keys an
	# already-sustained voice.
	# Per probe_kon_koff_accumulator side-by-side trace, FFT fires
	# KOFF on silent driver voices too (PCSX cad 349 KOFF v20). The
	# previous `not is_silent_driver and not has_silent_overlay` gate
	# was Godot-specific and prevented these KOFFs from matching FFT.
	# Keep only the double-KOFF guard: skip if drain-KOFF already
	# fired this tick for the prior Note (avoids redundant
	# duration_drain_pre_rest + rest_0x80 at the same sub_tick).
	if (slot.flag_word & _SS.FLAG_KOFF_PENDING) == 0:
		slot.flag_word |= _SS.FLAG_KOFF_PENDING


static func _decode_rest_duration(op: SMDOpcodes.OpcodeEvent) -> int:
	# FFT's Rest 0x80 handler at LAB_80015874 stores chan+0x74 = raw
	# operand byte directly (`lbu v0, 0x0(a0); sh v0, 0x74(a2)`). No
	# DELTA_TIME_TABLE lookup. Godot's cadence_body decrements
	# note_duration ONCE per call before the walker, mirroring FFT's
	# FUN_80015138 drain that runs before FUN_80015324 in the same
	# per-channel tick. So storing `raw` here gives the same
	# observable timing as FFT.
	if op.params.size() == 0:
		return 0
	return op.params[0] & 0xFF
