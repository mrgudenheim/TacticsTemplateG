class_name SharedOpInstrumentReload
## FFT analog: FUN_8001613C @ 0x8001613C
##                (opcode 0xC0)

const _CH = preload("res://addons/exmateria_sound/runtime/shared/channel_state.gd")
const _SS = preload("res://addons/exmateria_sound/runtime/shared/slot_state.gd")
const _Trace = preload("res://addons/exmateria_sound/runtime/effect_sound/trace_writer.gd")
const _ProbeCounters = preload("res://addons/exmateria_sound/runtime/effect_sound/probes/probe_counters.gd")
const _LfoStepCalc = preload("res://addons/exmateria_sound/runtime/shared/helpers/lfo_step_calc.gd")
const _LfoPrng = preload("res://addons/exmateria_sound/runtime/shared/helpers/lfo_prng.gd")


static func apply(dispatcher, channel: _CH, slot: _SS, op: SMDOpcodes.OpcodeEvent, voice_writes: bool) -> void:
	## Opcode 0xC0 — instrument data reload at FUN_8001613C (jumptable
	## 0x80028C0C). FFT disasm calls Hyp_instrument_data_loader with
	## a0 = chan+0x2C (stored instrument index), reissuing the same loader
	## path 0xAC uses but with no payload byte consumed. Effect: re-arm
	## the per-instrument SPU registers (ADSR1/ADSR2/sample addrs) by
	## re-running the loader for the channel's current instrument.
	## Hyp_instrument_data_loader at PC 0x80017064-88 sets walker_flag_word
	## |= 0x1FF and chan_word_1 |= 0x300 when chan_word_0 & 0xC is set,
	## forcing the next walker pass to re-commit every SPU register.
	_ProbeCounters.opcode_c0_instrument_reload += 1
	_Trace.emit("opcode_c0_instrument_reload", {
		"call_index": _ProbeCounters.opcode_c0_instrument_reload,
		"instrument_idx": channel.instrument_idx,
	})
	if channel.instrument_idx < 0:
		return
	var idx: int = channel.instrument_idx
	if dispatcher.get_waveset() != null and idx < dispatcher.get_waveset().instruments.size():
		var inst: WavesetParser.Instrument = dispatcher.get_waveset().instruments[idx]
		if not inst.is_null:
			channel.fine_tune = inst.fine_tune
			channel.adsr1 = inst.adsr1
			channel.adsr2 = inst.adsr2
			channel.sample_start_addr = Spu.RAM_INSTRUMENT_BASE \
					+ inst.sample_offset + inst.start_offset_bytes
			channel.sample_loop_addr = inst.sample_offset + inst.sample_size
	if voice_writes and channel.instrument_idx >= 0:
		slot.instrument_idx = channel.instrument_idx
		slot.fine_tune = channel.fine_tune
		slot.adsr1 = channel.adsr1
		slot.adsr2 = channel.adsr2
		slot.prev_adsr2 = slot.adsr2
		slot.adsr_opcode_modified = false
		slot.sample_start_addr = channel.sample_start_addr
		slot.sample_loop_addr = channel.sample_loop_addr
		# Hyp_instrument_data_loader PC 0x80017064-88: re-arm full walker
		# pass when chan_word_0 & 0xC is set (HAS_TONES + bit 0x4).
		if (channel.channel_word_0 & 0xC) != 0:
			channel.channel_word_1 |= 0x300
			slot.walker_flag_word |= 0x1FF
