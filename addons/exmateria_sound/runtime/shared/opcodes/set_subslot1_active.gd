class_name SharedOpSetSubslot1Active
## FFT analog: smd_op_e6 @ LAB_8001686C
##                (opcode 0xE6)

const _CH = preload("res://addons/exmateria_sound/runtime/shared/channel_state.gd")
const _SS = preload("res://addons/exmateria_sound/runtime/shared/slot_state.gd")
const _Trace = preload("res://addons/exmateria_sound/runtime/effect_sound/trace_writer.gd")
const _ProbeCounters = preload("res://addons/exmateria_sound/runtime/effect_sound/probes/probe_counters.gd")
const _LfoStepCalc = preload("res://addons/exmateria_sound/runtime/shared/helpers/lfo_step_calc.gd")
const _LfoPrng = preload("res://addons/exmateria_sound/runtime/shared/helpers/lfo_prng.gd")


static func apply(_dispatcher, channel: _CH, slot: _SS, op: SMDOpcodes.OpcodeEvent, _voice_writes: bool) -> void:
	## Opcode 0xE6 — FFT smd_op_set_ch11E_bit0 at PC 0x8001686C
	## (jumptable 0x80028CA4). 0 params. Read-modify-write:
	##   lhu v0, 0x11e(a2)
	##   ori v0, v0, 0x1
	##   sh  v0, 0x11e(a2)
	## = set chan+0x11e bit 0 (sub-slot 1 active). Used to re-arm
	## sub-slot 1 without rebuilding the LFO step/period state.
	## Mirrors the existing _op_ef_clear_subslot2 symmetry for sub-slot 2.
	channel.lfo_sub_active[1] = 1
	slot.word_11e |= 0x1
