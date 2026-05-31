class_name SharedOpPan
## FFT analog: smd_pan @ LAB_8001689C
##                (opcode 0xE8)

const _CH = preload("res://addons/exmateria_sound/runtime/shared/channel_state.gd")
const _SS = preload("res://addons/exmateria_sound/runtime/shared/slot_state.gd")
const _Trace = preload("res://addons/exmateria_sound/runtime/effect_sound/trace_writer.gd")
const _ProbeCounters = preload("res://addons/exmateria_sound/runtime/effect_sound/probes/probe_counters.gd")
const _LfoStepCalc = preload("res://addons/exmateria_sound/runtime/shared/helpers/lfo_step_calc.gd")
const _LfoPrng = preload("res://addons/exmateria_sound/runtime/shared/helpers/lfo_prng.gd")


static func apply(_dispatcher, channel: _CH, slot: _SS, op: SMDOpcodes.OpcodeEvent, voice_writes: bool) -> void:
	## Pan — opcode 0xE8.
	if voice_writes and op.params.size() > 0:
		# Store raw pan input. FFT 0xE8 stores raw pan at
		# chan+0xae; FUN_80017118 vol formula adds it via
		# `lh a0,0xae(s2)` (L80017218). Drainer applies pan
		# as part of its single computation.
		channel.pan_offset_ae = op.params[0]
		channel.channel_word_1 |= _SS.CHAN1_VOL_PRESTAGE


# Back-compat: play_sound.gd:1345-1352 calls these statically on
# SharedDispatcher. Refactor Pass 1 moved the bodies to
# probes/probe_emit.gd; thin pass-throughs preserve the call sites.
