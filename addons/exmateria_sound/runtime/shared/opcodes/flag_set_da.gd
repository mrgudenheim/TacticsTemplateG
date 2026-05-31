class_name SharedOpFlagSetDa
## FFT analog: smd_op_da_set_chFE_bit0 @ 0x800165E4
##                (opcode 0xDA)

const _CH = preload("res://addons/exmateria_sound/runtime/shared/channel_state.gd")
const _SS = preload("res://addons/exmateria_sound/runtime/shared/slot_state.gd")
const _Trace = preload("res://addons/exmateria_sound/runtime/effect_sound/trace_writer.gd")
const _ProbeCounters = preload("res://addons/exmateria_sound/runtime/effect_sound/probes/probe_counters.gd")
const _LfoStepCalc = preload("res://addons/exmateria_sound/runtime/shared/helpers/lfo_step_calc.gd")
const _LfoPrng = preload("res://addons/exmateria_sound/runtime/shared/helpers/lfo_prng.gd")


static func apply(_dispatcher, channel: _CH, slot: _SS, op: SMDOpcodes.OpcodeEvent, _voice_writes: bool) -> void:
	## 0xDA FlagSet_0xFE — smd_op_da_set_chFE_bit0 @ 0x800165E4 (jumptable
	## entry @ 0x80028C74). Disasm:
	##   lhu v0, 0xfe(a2); ori v0,v0,0x1; sh v0, 0xfe(a2)
	## Sets bit 0x1 of chan+0xFE. Mirror of 0xDB FlagClear with `|=` instead
	## of `&= ~`. Structural-only in Godot's LFO model (same justification
	## as _op_db_flag_clear); kept for parity so probe_event_dispatch row
	## counts and downstream walker fan-out match cad-for-cad on bytecodes
	## that use 0xDA.
	# Iter-35: sub-slot 0 unified — bit 0x1 of chan+0xFE is
	# lfo_sub_active[0]. mode_pre emits the FFT chan+0xFE shape
	# (dir_flags | active) for probe parity.
	var _mode_pre_da: int = (channel.lfo_sub_dir_flags[0] | channel.lfo_sub_active[0])
	_ProbeCounters.opcode_da_flag_set += 1
	_Trace.emit("opcode_da_flag_set", {
		"call_index": _ProbeCounters.opcode_da_flag_set,
		"mode_pre": _mode_pre_da & 0xFFFF,
	})
	channel.lfo_sub_active[0] = 1
