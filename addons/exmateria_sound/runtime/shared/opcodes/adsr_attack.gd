class_name SharedOpAdsrAttack
## FFT analog: smd_op_c2_adsr_attack @ LAB_800161A8
##                (opcode 0xC2)

const _CH = preload("res://addons/exmateria_sound/runtime/shared/channel_state.gd")
const _SS = preload("res://addons/exmateria_sound/runtime/shared/slot_state.gd")
const _Trace = preload("res://addons/exmateria_sound/runtime/effect_sound/trace_writer.gd")
const _ProbeCounters = preload("res://addons/exmateria_sound/runtime/effect_sound/probes/probe_counters.gd")
const _LfoStepCalc = preload("res://addons/exmateria_sound/runtime/shared/helpers/lfo_step_calc.gd")
const _LfoPrng = preload("res://addons/exmateria_sound/runtime/shared/helpers/lfo_prng.gd")


static func apply(_dispatcher, channel: _CH, slot: _SS, op: SMDOpcodes.OpcodeEvent, voice_writes: bool) -> void:
	## Opcode 0xC2 — smd_attack at LAB_800161A8 (jumptable 0x80028C14).
	## 1 param. Disasm (PC 0x800161A8..0x800161C4):
	##   lhu  v0, 0x4(a2)      ; v0 = slot+0x4 (walker_flag_word)
	##   lbu  v1, 0x0(a0)      ; v1 = param byte = attack_rate
	##   ori  v0, v0, 0x10     ; v0 |= 0x10 (WALKER_FLAG_ADSR1_HIGH)
	##   sh   v0, 0x4(a2)      ; commit slot+0x4
	##   sh   v1, 0x64(a2)     ; chan+0x64 = attack_rate (read by walker
	##                         ;             fan-out at FUN_8001B938)
	##
	## Godot's _fan_adsr1_high (spu_irq_walker.gd:289) reads attack_rate
	## from `(slot.adsr1 >> 8) & 0x7F` — bits 8-14 of slot.adsr1. Mirror
	## by writing the param's low 7 bits into those positions; preserve
	## the lin/exp flag at bit 15 and the lower byte (mid/low nibbles
	## owned by 0xC7 / 0xCA).
	##
	## Without this, every adsr1_high probe row on Godot carried
	## attack_rate=0 instead of PCSX's actual values (50, 53, 52, 45 on
	## cure_4's initial KONs; 50 on the 14 B5-driven re-arms). Implementing
	## C2 + the existing B5 handler should bring probe_adsr1_high_register
	## from 14/26-FAIL to ~28/26 with value parity on the matching rows.
	var p_c2_raw: int = (op.params[0] if op.params.size() > 0 else 0) & 0xFF
	var new_attack: int = p_c2_raw & 0x7F
	# Preserve bit 15 (lin/exp mode flag) and lower byte; replace bits 8-14.
	channel.adsr1 = (channel.adsr1 & 0x80FF) | (new_attack << 8)
	if voice_writes:
		slot.adsr1 = channel.adsr1
		_ProbeCounters.diag_walker_flag_adsr1_high_set += 1
		_Trace.emit("walker_flag_adsr1_high_set", {
			"call_index": _ProbeCounters.diag_walker_flag_adsr1_high_set,
			"channel_idx": channel.channel_idx,
			"source": "op_c2",
			"slot_flag_word_pre": slot.walker_flag_word & 0xFFFF,
		})
		slot.walker_flag_word |= _SS.WALKER_FLAG_ADSR1_HIGH
		slot.adsr_opcode_modified = true
