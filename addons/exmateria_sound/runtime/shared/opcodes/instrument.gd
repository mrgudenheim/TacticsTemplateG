class_name SharedOpInstrument
## FFT analog: FUN_80015E30 @ 0x80015E30
##                (opcode 0xAC)

const _CH = preload("res://addons/exmateria_sound/runtime/shared/channel_state.gd")
const _SS = preload("res://addons/exmateria_sound/runtime/shared/slot_state.gd")
const _Trace = preload("res://addons/exmateria_sound/runtime/effect_sound/trace_writer.gd")
const _ProbeCounters = preload("res://addons/exmateria_sound/runtime/effect_sound/probes/probe_counters.gd")
const _LfoStepCalc = preload("res://addons/exmateria_sound/runtime/shared/helpers/lfo_step_calc.gd")
const _LfoPrng = preload("res://addons/exmateria_sound/runtime/shared/helpers/lfo_prng.gd")


static func apply(dispatcher, channel: _CH, slot: _SS, op: SMDOpcodes.OpcodeEvent, voice_writes: bool) -> void:
	# probe_opcode_instrument (GOLD #7). Mirror of FFT BP @ 0x80015E30.
	# instrument_byte = read8(a0) on FFT side = op.params[0] here (raw
	# operand byte, BEFORE the +1 inst-index adjust below).
	_ProbeCounters.opcode_instrument += 1
	_Trace.emit("opcode_instrument", {
		"call_index": _ProbeCounters.opcode_instrument,
		"instrument_byte": (op.params[0] if op.params.size() > 0 else 0) & 0xFF,
	})
	## Instrument — resolve from WAVESET via FFT's +1 indexing
	## rule. FFT's effect dispatcher reads inst entries from
	## `chan+0x30 + inst*16 + 0x30`. WAVESET entries start at
	## file_offset 0x20, so runtime inst N maps to WAVESET inst
	## (N+1).
	## AC writes per-channel state ALWAYS. Audible voice also
	## updates slot.* immediately so per-tick reads work without
	## Note dispatch. Silent driver writes channel-only;
	## _handle_note copies channel.* → slot.* at Note dispatch
	## so each channel's KON loads its own instrument
	## (last-firing-wins matches FFT). C7/C4/C5 ADSR modifiers
	## must ALSO update channel.adsr1/adsr2 (synced below in
	## those handlers) — without that, subsequent Notes revert
	## slot.adsr1 to stale channel value, blocking decay.
	var idx_runtime: int = op.params[0] if op.params.size() > 0 else 0
	var idx: int = idx_runtime + 1
	channel.instrument_idx = idx
	if dispatcher.get_waveset() != null and idx < dispatcher.get_waveset().instruments.size():
		var inst: WavesetParser.Instrument = dispatcher.get_waveset().instruments[idx]
		if not inst.is_null:
			channel.fine_tune = inst.fine_tune
			channel.adsr1 = inst.adsr1
			channel.adsr2 = inst.adsr2
			# Iter-32: FFT instrument-load also populates slot+0x6A from
			# waveset byte 3 low 5 bits. Walker reads slot+0x6A for the
			# ADSR2 LOW writer's rate input. See
			# docs/MUSIC_ITER32_ADSR2_LOW_RELEASE_BYTE_FIELD_SOURCE.md.
			channel.release_rate_byte = inst.release_rate_byte
			channel.sample_start_addr = Spu.RAM_INSTRUMENT_BASE \
					+ inst.sample_offset + inst.start_offset_bytes
			# FFT PC 0x80016FE0-F0 loop_addr formula:
			#   v0 = lhu 0x4(a0)   ; inst_data[4..5] = loop_offset (u16)
			#   v1 = lw  0x0(a0)   ; inst_data[0..3] = sample_offset (u32)
			#   v0 = v0 + v1       ; loop_addr = sample_offset + loop_offset
			# In Godot's WavesetParser the bytes [4..5] are named
			# "sample_size" but FFT uses the same bytes as a u16
			# loop offset. No RAM_INSTRUMENT_BASE addition (the FFT
			# formula uses a different in-RAM addressing convention
			# than start_addr — verified empirically by probe_sample_
			# repeat_addr_register pairing post-fix).
			channel.sample_loop_addr = inst.sample_offset + inst.sample_size
	if voice_writes and channel.instrument_idx >= 0:
		slot.instrument_idx = channel.instrument_idx
		slot.fine_tune = channel.fine_tune
		slot.adsr1 = channel.adsr1
		slot.adsr2 = channel.adsr2
		slot.release_rate_byte = channel.release_rate_byte
		# Align prev_adsr2 with the new instrument default so
		# the change-detect gate doesn't fire spuriously
		# (instrument load is a fresh baseline, not a delta).
		slot.prev_adsr2 = slot.adsr2
		# Fresh instrument default loaded → reset the opcode-
		# modified flag so KEYON override re-applies.
		slot.adsr_opcode_modified = false
		slot.sample_start_addr = channel.sample_start_addr
		slot.sample_loop_addr = channel.sample_loop_addr
		# FFT Hyp_instrument_data_loader PC 0x80017064-88: after loading
		# instrument data, if chan_word_0 has bits 0xC set, re-arm
		# walker_flag_word |= 0x1FF and chan_word_1 |= 0x300 to force
		# the next walker pass to commit every SPU register (ADSR1 +
		# ADSR2 + pitch + vol + sample addr). The gate bits 0xC =
		# bit 0x4 + CHAN0_HAS_TONES (0x8). play_sound init sets bit 0x8
		# (HAS_TONES) per L80013CD0, so every cure_no_music instrument
		# dispatch passes this gate.
		#   PC 0x80017064  andi v0, v1, 0xc           ; chan_word_0 & 0xC
		#   PC 0x80017068  beq  v0, zero, skip
		#   PC 0x80017078  ori  v0, v0, 0x300         ; chan_word_1
		#   PC 0x8001707C  ori  v1, v1, 0x1ff         ; walker_flag_word
		#   PC 0x80017080  sh   v0, 0x2(a1)
		#   PC 0x80017088  _sh  v1, 0x4(a1)
		# Source of 4 PCSX walker entries with walker_flag_word == 0x1FF
		# on cure_no_music (2 from play_sound init + 2 from instrument
		# re-arm at cadence 362). Without this, Godot fires only the
		# init seed and misses the cadence-362 ADSR re-commit.
		if (channel.channel_word_0 & 0xC) != 0:
			channel.channel_word_1 |= 0x300
			slot.walker_flag_word |= 0x1FF
		else:
			# FFT Hyp_instrument_data_loader LAB_8001708C — the else
			# branch defers the walker full-arm to the next Note via
			# bit 0x8000 of chan_word_0. smd_note (the Note handler)
			# checks this bit at PC 0x80015494, clears it, and arms
			# walker_flag_word |= 0x1FF and chan_word_1 |= 0x300 in
			# its own body. Required for music (chan_word_0 lacks
			# HAS_TONES so the if-branch above never fires). See
			# docs/MUSIC_VOL_REGISTER_SWEEP_INVESTIGATION.md.
			channel.channel_word_0 |= 0x8000
