class_name SharedOpAdsr1HighArm
## FFT analog: FUN_80015FB4 @ 0x80015FB4
##                (opcode 0xB5)

const _CH = preload("res://addons/exmateria_sound/runtime/shared/channel_state.gd")
const _SS = preload("res://addons/exmateria_sound/runtime/shared/slot_state.gd")
const _Trace = preload("res://addons/exmateria_sound/runtime/effect_sound/trace_writer.gd")
const _ProbeCounters = preload("res://addons/exmateria_sound/runtime/effect_sound/probes/probe_counters.gd")
const _LfoStepCalc = preload("res://addons/exmateria_sound/runtime/shared/helpers/lfo_step_calc.gd")
const _LfoPrng = preload("res://addons/exmateria_sound/runtime/shared/helpers/lfo_prng.gd")


static func apply(_dispatcher, channel: _CH, slot: _SS, op: SMDOpcodes.OpcodeEvent, voice_writes: bool) -> void:
	## Opcode 0xB5 — FUN_80015FB4 at jumptable 0x80028BE0. 1 param.
	## Misnamed historically as "adsr1_high_arm"; the actual FFT body adds
	## the operand to the per-slot noise_clock storage (slot+0x1E) mod
	## 64, pushes the new rate to the SPU via FUN_80019D88, OR's the
	## voice's bit into entity+0x6c (re-asserts noise mode), and sets
	## walker_flag_word |= 0x10. Disasm (PC 0x80015FD0-0x80016014):
	##   lbu  v0, 0x0(s1)       ; operand byte
	##   lhu  v1, 0x1e(s0)      ; current noise_clock
	##   addu v0, v0, v1
	##   andi v0, v0, 0x3f
	##   sh   v0, 0x1e(s0)      ; write back
	##   jal  FUN_80019D88      ; SPU noise-rate update
	##   lw   v0, 0x6c(s0)
	##   lw   v1, 0x34(s2)
	##   or   v0, v0, v1
	##   sw   v0, 0x6c(s0)      ; entity+0x6c |= chan+0x34
	##   lhu  v1, 0x4(s2)
	##   ori  v1, v1, 0x10
	##   sh   v1, 0x4(s2)       ; walker_flag_word |= 0x10
	##
	## cure_4 voice 18 fires this 14× (cad 31, 46, 61, ... 227, every ~15
	## cad), each with operand=0xFE (-2 unsigned), stepping noise_clock
	## 63 → 61 → ... → 35. That's the audible "descending noise pitch" in
	## the first-note phase. Without this handler doing the noise_clock
	## add, Godot's noise stays pinned at 63 and sounds flat. See cure_4
	## v18 first-note investigation.
	_ProbeCounters.diag_walker_flag_adsr1_high_set += 1
	_Trace.emit("walker_flag_adsr1_high_set", {
		"call_index": _ProbeCounters.diag_walker_flag_adsr1_high_set,
		"channel_idx": channel.channel_idx,
		"source": "op_b5",
		"slot_flag_word_pre": slot.walker_flag_word & 0xFFFF,
	})
	if voice_writes:
		var operand: int = (op.params[0] if op.params.size() > 0 else 0) & 0xFF
		slot.noise_clock_value = (slot.noise_clock_value + operand) & 0x3F
		slot.noise_pending = slot.noise_clock_value
	slot.walker_flag_word |= _SS.WALKER_FLAG_ADSR1_HIGH
