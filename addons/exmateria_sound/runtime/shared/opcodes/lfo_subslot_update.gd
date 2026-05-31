class_name SharedOpLfoSubslotUpdate
## FFT analog: smd_op_f1_lfo_subslot_update @ FUN_80016B80
##                (opcode 0xF1)

const _CH = preload("res://addons/exmateria_sound/runtime/shared/channel_state.gd")
const _SS = preload("res://addons/exmateria_sound/runtime/shared/slot_state.gd")
const _Trace = preload("res://addons/exmateria_sound/runtime/effect_sound/trace_writer.gd")
const _ProbeCounters = preload("res://addons/exmateria_sound/runtime/effect_sound/probes/probe_counters.gd")
const _LfoStepCalc = preload("res://addons/exmateria_sound/runtime/shared/helpers/lfo_step_calc.gd")
const _LfoPrng = preload("res://addons/exmateria_sound/runtime/shared/helpers/lfo_prng.gd")


static func apply(_dispatcher, channel: _CH, slot: _SS, op: SMDOpcodes.OpcodeEvent, _voice_writes: bool) -> void:
	## Opcode 0xF1 — FUN_80016B80 at jumptable 0x80028CD0 = base
	## 0x80028B0C + (0xF1-0x80)*4. 3 params. Updates the currently-
	## selected sub-slot's LFO depth + 16-bit signed rate. Reads
	## chan+0xae (set by 0xF0) to find which sub-slot to update.
	##
	## FFT disasm (FUN_80016B80 prologue + body):
	##   subslot = chan + 0xe0 + chan[0xae] * 0x20
	##   a0_input = ((char)param[1] << 24) | (param[2] << 16)   ; 16-bit signed rate
	##   step = pitch_lfo_step_calc(a0_input, param[0], subslot[0x1d])
	##   sw   step,       0xc(subslot)           ; step_source
	##   sh   param[0],   0x12(subslot)          ; inner_reload (depth)
	##   return param + 3
	##
	## Pairs with 0xF0; the F0→F1 sequence is the dynamic-subslot
	## equivalent of 0xD8's fixed-subslot-0 init.
	_ProbeCounters.opcode_f1_lfo_subslot_update += 1
	_Trace.emit("opcode_f1_lfo_subslot_update", {
		"call_index": _ProbeCounters.opcode_f1_lfo_subslot_update,
		"arg0_depth": (op.params[0] if op.params.size() > 0 else 0) & 0xFF,
		"arg1_rate_hi": (op.params[1] if op.params.size() > 1 else 0) & 0xFF,
		"arg2_rate_lo": (op.params[2] if op.params.size() > 2 else 0) & 0xFF,
	})
	if op.params.size() < 3:
		return
	var subslot_idx: int = channel.pan_offset_ae
	if subslot_idx < 0 or subslot_idx >= 4:
		return
	var depth: int = op.params[0] & 0xFF
	var rate_hi_raw: int = op.params[1] & 0xFF
	var rate_lo: int = op.params[2] & 0xFF
	var rate_hi_signed: int = rate_hi_raw if rate_hi_raw < 0x80 else rate_hi_raw - 0x100
	# Compose 16-bit signed rate into bits 16-31 of a0 input (mirroring
	# FFT's `(char)param[1] << 24 | param[2] << 16`).
	var a0_input: int = (rate_hi_signed * 0x01000000) | (rate_lo * 0x00010000)
	var wf_idx: int = channel.lfo_sub_callback_idx[subslot_idx]
	var step_source: int = _LfoStepCalc.step_calc(a0_input, depth, wf_idx)
	channel.lfo_sub_step_source[subslot_idx] = step_source
	channel.lfo_sub_inner_reload[subslot_idx] = depth
