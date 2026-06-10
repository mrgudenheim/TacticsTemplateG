class_name SharedOpNoiseEnableNoArm
## FFT analog: smd_noise_enable_no_arm @ LAB_80016034
##                (opcode 0xB6)

const _CH = preload("res://addons/exmateria_sound/runtime/shared/channel_state.gd")
const _SS = preload("res://addons/exmateria_sound/runtime/shared/slot_state.gd")
const _Trace = preload("res://addons/exmateria_sound/runtime/effect_sound/trace_writer.gd")
const _ProbeCounters = preload("res://addons/exmateria_sound/runtime/effect_sound/probes/probe_counters.gd")
const _LfoStepCalc = preload("res://addons/exmateria_sound/runtime/shared/helpers/lfo_step_calc.gd")
const _LfoPrng = preload("res://addons/exmateria_sound/runtime/shared/helpers/lfo_prng.gd")


static func apply(_dispatcher, channel: _CH, slot: _SS, op: SMDOpcodes.OpcodeEvent, voice_writes: bool) -> void:
	## Opcode 0xB6 — Noise_EnableNoArm at FFT LAB_80016034 (jumptable
	## 0x80028BE4). 0 params. Variant of 0xB4 (Noise_EnableAndClock) that
	## enables noise mode for this voice WITHOUT writing a new clock value.
	## FFT MIPS:
	##   lw   v0, 0x6c(a1)      ; entity+0x6C |= chan+0x34 (set voice's noise bit)
	##   or   v0, v0, chan_34
	##   sw   v0, 0x6c(a1)
	##   lhu  v0, 0x4(a2)       ; chan+0x4 |= 0x10 (walker ADSR1_HIGH flag)
	##   ori  v0, v0, 0x10
	##   sh   v0, 0x4(a2)
	## Affects 1 effect (DarkHoly). See SMD_OPCODE_COVERAGE_STATUS.md §4.7.
	_ProbeCounters.opcode_b6_noise_enable_no_arm += 1
	_Trace.emit("opcode_b6_noise_enable_no_arm", {
		"call_index": _ProbeCounters.opcode_b6_noise_enable_no_arm,
		"channel_idx": channel.channel_idx,
	})
	if voice_writes:
		# Re-publish the existing clock so flush_tick reasserts noise mode
		# for this voice without changing the rate. Mirrors B5's pattern of
		# setting noise_pending = noise_clock_value to re-enable noise on
		# the voice. Silent driver doesn't enable noise on the audible voice.
		slot.noise_pending = slot.noise_clock_value
		slot.walker_flag_word |= _SS.WALKER_FLAG_ADSR1_HIGH
