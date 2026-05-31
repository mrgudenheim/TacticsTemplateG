class_name SharedOpFlagClearDb
## FFT analog: smd_op_db_clear_chFE_bit0 @ 0x800165FC
##                (opcode 0xDB)

const _CH = preload("res://addons/exmateria_sound/runtime/shared/channel_state.gd")
const _SS = preload("res://addons/exmateria_sound/runtime/shared/slot_state.gd")
const _Trace = preload("res://addons/exmateria_sound/runtime/effect_sound/trace_writer.gd")
const _ProbeCounters = preload("res://addons/exmateria_sound/runtime/effect_sound/probes/probe_counters.gd")
const _LfoStepCalc = preload("res://addons/exmateria_sound/runtime/shared/helpers/lfo_step_calc.gd")
const _LfoPrng = preload("res://addons/exmateria_sound/runtime/shared/helpers/lfo_prng.gd")


static func apply(_dispatcher, channel: _CH, slot: _SS, op: SMDOpcodes.OpcodeEvent, _voice_writes: bool) -> void:
	## 0xDB FlagClear_0xFE — LAB_800165FC (jumptable @0x80028C78).
	## Disasm:
	##   lhu v0, 0xfe(a2); andi v0,v0,0xfffe; sh v0, 0xfe(a2)
	## Clears bit 0x1 of chan+0xFE. Counterpart to 0xDA FlagSet
	## which sets it. D9 init seeds chan+0xFE = 3 (bit 0x1 set);
	## DB clears bit 0x1 → 2. The cleared bit gates downstream
	## behaviour but isn't routed through Godot's LFO model today,
	## so this handler is structural-only — keeping
	## channel.lfo_mode_flags in sync with chan+0xFE means future
	## reads can rely on it.
	# Iter-35: sub-slot 0 unified — bit 0x1 of chan+0xFE is
	# lfo_sub_active[0]. mode_pre emits the FFT chan+0xFE shape
	# (dir_flags | active) for probe parity.
	var _mode_pre_db: int = (channel.lfo_sub_dir_flags[0] | channel.lfo_sub_active[0])
	_ProbeCounters.opcode_db_flag_clear += 1
	_Trace.emit("opcode_db_flag_clear", {
		"call_index": _ProbeCounters.opcode_db_flag_clear,
		"mode_pre": _mode_pre_db & 0xFFFF,
	})
	channel.lfo_sub_active[0] = 0
