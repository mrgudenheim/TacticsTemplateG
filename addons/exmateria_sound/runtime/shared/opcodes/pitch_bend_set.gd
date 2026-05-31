class_name SharedOpPitchBendSet
## FFT analog: smd_set_pitch_bend @ 0x800162B4
##                (opcode 0xD0)

const _CH = preload("res://addons/exmateria_sound/runtime/shared/channel_state.gd")
const _SS = preload("res://addons/exmateria_sound/runtime/shared/slot_state.gd")
const _Trace = preload("res://addons/exmateria_sound/runtime/effect_sound/trace_writer.gd")
const _ProbeCounters = preload("res://addons/exmateria_sound/runtime/effect_sound/probes/probe_counters.gd")
const _LfoStepCalc = preload("res://addons/exmateria_sound/runtime/shared/helpers/lfo_step_calc.gd")
const _LfoPrng = preload("res://addons/exmateria_sound/runtime/shared/helpers/lfo_prng.gd")


static func apply(_dispatcher, channel: _CH, slot: _SS, op: SMDOpcodes.OpcodeEvent, _voice_writes: bool) -> void:
	## Opcode 0xD0 — smd_set_pitch_bend at PC 0x800162B4. FFT does:
	##   lbu  v0, 0x0(a0)           ; byte
	##   sll  v0, v0, 0x18           ; byte << 24
	##   sra  v0, v0, 0x13           ; sb * 32 (sign-preserving)
	##   ori  v1, v1, 0x200          ; chan_word_1 |= 0x200
	##   sh   v0, 0x86(a2)           ; chan+0x86 := sb * 32 (ABSOLUTE SET)
	## D0 writes chan+0x86 (Godot channel.word_86), a field distinct from
	## chan+0x84 (slot.fine_tune, set by 0xAC). Both are read at Note
	## dispatch (smd_note_state_setup PC 0x80015430/0x80015444 with
	## s0=chan_base+2): `lh a0, 0x82(s0)` reads chan+0x84 (finetune),
	## `lh v1, 0x84(s0)` reads chan+0x86 (this field). Sum lands in
	## chan+0x80..0x83 via the `sw v0, 0x7e(s0)` at PC 0x8001545C.
	## Earlier history conflated chan+0x86 with slot.fine_tune (the
	## chan+0x84 finetune field) — but cure_4 voice 20's D0 0xC8 followed
	## by AC 0x83 then a Note had its D0 contribution destroyed by AC's
	## fine_tune overwrite, dropping −1792 from the pitch baseline
	## (the +1792 = +7-semitone perfect-fifth bug).
	_ProbeCounters.opcode_d0_pitch_bend += 1
	_Trace.emit("opcode_d0_pitch_bend", {
		"call_index": _ProbeCounters.opcode_d0_pitch_bend,
		"d0_byte": (op.params[0] if op.params.size() > 0 else 0) & 0xFF,
	})
	if op.params.size() > 0:
		var p_d0: int = op.params[0] & 0xFF
		if p_d0 >= 0x80: p_d0 -= 0x100
		# Sign-extend to s16 to match FFT's `sh` halfword store.
		var word_86_new: int = (p_d0 * 32) & 0xFFFF
		if word_86_new >= 0x8000: word_86_new -= 0x10000
		channel.word_86 = word_86_new
		channel.channel_word_1 |= _SS.CHAN1_PITCH_PRESTAGE
		slot.walker_flag_word |= _SS.WALKER_FLAG_PITCH
