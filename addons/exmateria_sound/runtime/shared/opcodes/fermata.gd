class_name SharedOpFermata
## FFT analog: smd_fermata @ LAB_8001589C
##                (jumptable @ 0x80028B10)

const _CH = preload("res://addons/exmateria_sound/runtime/shared/channel_state.gd")
const _SS = preload("res://addons/exmateria_sound/runtime/shared/slot_state.gd")
const _Trace = preload("res://addons/exmateria_sound/runtime/effect_sound/trace_writer.gd")
const _ProbeCounters = preload("res://addons/exmateria_sound/runtime/effect_sound/probes/probe_counters.gd")


static func apply(_dispatcher, channel: _CH, _slot: _SS,
		op: SMDOpcodes.OpcodeEvent, _voice_writes: bool) -> void:
	## opcode 0x81 — Fermata. Per FFT disasm LAB_8001589c
	## (jumptable @0x80028B10):
	##   lhu  v0, 0x0(a2)   ; v0 = channel_word_0
	##   lbu  v1, 0x0(a0)   ; v1 = param byte
	##   ori  v0, v0, 0x100 ; set CHAN0_PITCH_REQ
	##   sh   v0, 0x0(a2)   ; store back
	##   addiu v0, a0, 0x1  ; advance opcode_ptr by 1 param
	##   sh   v1, 0x74(a2)  ; (delay slot) slot+0x74
	##                       (note_duration) = param
	## Effect: extends the current Note's playing time to `param`
	## sub_ticks (overwrites note_duration).
	var param: int = (op.params[0] if op.params.size() > 0 else 0) & 0xFF
	_ProbeCounters.opcode_fermata += 1
	_Trace.emit("opcode_fermata", {
		"call_index": _ProbeCounters.opcode_fermata,
		"byte": param,
		"chan_word_0_pre": channel.channel_word_0 & 0xFFFF,
	})
	channel.note_duration = param
	channel.channel_word_0 |= _SS.CHAN0_PITCH_REQ
	# FFT smd_dispatcher_post_handler at PC 0x80015698-0x80015714 runs
	# after every terminator opcode (Note / Rest / Fermata — those that
	# set chan_word_0 bits 0x100/0x400 and thus trigger the walker exit
	# at PC 0x80015510). It re-derives chan+0x78 (idle_timeout) from the
	# just-set chan+0x74 (note_duration) + chan+0x76 (byte_76) + chan+0x7A
	# (byte_7A) using the same case selector as the Note handler's
	# `_note_compute_durations`. Without this, idle_timeout holds whatever
	# the prior Note set it to (e.g., 11 from Note dt=12), drains over ~11
	# body fires after walker exit, and fires the PC 0x800152F0 KOFF
	# (chan_word_1 |= 0x2) prematurely. On flare V18 this fires KOFF at
	# cad 299 vs PCSX cad 683, cutting the second sustain phase from 441
	# cadences to ~55. See FLARE_VOICE_18_AMPLITUDE_DEFICIT.md.
	# probe_per_channel_tick_entry@cad=274 confirms PCSX has chan+0x78=164
	# (= param-1 for byte_7A=15) AFTER Fermata at cad 272 dispatches with
	# param=165; Godot pre-fix had chan+0x78=11 (the leftover from the
	# prior Note's idle init).
	var v1: int = param
	var a0_signed: int = channel.byte_76 + param
	if a0_signed <= 0:
		# Alt path (FFT PC 0x800156b4-c8): byte_76 += chan+0x74_low_byte;
		# v1 = note_duration + a0 = 2*note_duration + signed_byte_76.
		var new_b76: int = (channel.byte_76 + (param & 0xFF)) & 0xFF
		if new_b76 >= 0x80: new_b76 -= 0x100
		channel.byte_76 = new_b76
		v1 = (param + a0_signed) & 0xFFFF
	var idle: int
	match channel.byte_7A:
		15:
			idle = v1 - 1
		16:
			idle = v1
		_:
			# FFT PC 0x800156f4-700: a0 = (v1 * byte_7A) >> 4.
			idle = (v1 * channel.byte_7A) >> 4
	# FFT PC 0x80015708-10: idle == 0 → idle = 1.
	if (idle & 0xFFFF) == 0:
		idle = 1
	channel.note_duration = v1 & 0xFFFF
	channel.idle_timeout = idle & 0xFFFF
