class_name SharedOpClearSubslot1Active
## FFT analog: smd_op_e7 @ LAB_80016884
##                (opcode 0xE7)

const _CH = preload("res://addons/exmateria_sound/runtime/shared/channel_state.gd")
const _SS = preload("res://addons/exmateria_sound/runtime/shared/slot_state.gd")
const _Trace = preload("res://addons/exmateria_sound/runtime/effect_sound/trace_writer.gd")
const _ProbeCounters = preload("res://addons/exmateria_sound/runtime/effect_sound/probes/probe_counters.gd")
const _LfoStepCalc = preload("res://addons/exmateria_sound/runtime/shared/helpers/lfo_step_calc.gd")
const _LfoPrng = preload("res://addons/exmateria_sound/runtime/shared/helpers/lfo_prng.gd")


static func apply(_dispatcher, channel: _CH, slot: _SS, op: SMDOpcodes.OpcodeEvent, _voice_writes: bool) -> void:
	## Opcode 0xE7 — FFT LAB_80016884 at jumptable 0x80028CA8. 0 params.
	## Read-modify-write:
	##   lhu  v0, 0x11e(a2)
	##   andi v0, v0, 0xfffe
	##   sh   v0, 0x11e(a2)
	## = clear chan+0x11e bit 0 (sub-slot 1 active). Disarms the vol-LFO
	## sub-slot 1 that 0xE5 (FUN_8001676c) or 0xE6 armed. Without this,
	## the per-tick LFO dispatch keeps firing CHAN1_VOL_PRESTAGE every
	## cad until end-of-spell, draining to WALKER_FLAG_VOL_LR_RAW.
	## See research/effect_sound/working_documents/
	## RERAISE_VOICE_21_LFO_E7_DISARM_MISSING.md for the investigation.
	channel.lfo_sub_active[1] = 0
	slot.word_11e &= ~0x1
