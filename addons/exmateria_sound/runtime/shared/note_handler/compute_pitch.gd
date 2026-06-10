class_name SharedComputePitch
## FFT analog: Note handler pitch baseline @ PC 0x8001545C +
##              SPU pitch formula @ FUN_80017424 / PC 0x80017340..0x80017364
##
## Called from Note dispatch (note_handler.apply) to:
##   - compute pre_pitch_baseline = (bmidi_byte << 8) + fine_tune + word_86
##   - stage the upper halfword of pre_pitch_acc_u32 (= FFT chan+0x82)
##   - evaluate the formula via PitchTable.note_to_pitch
##
## The evaluation half is also called separately by the drainer in
## play_sound.gd via dispatcher's _evaluate_pitch_formula. Expose both
## as standalone static functions; dispatcher.gd has thin wrappers for
## back-compat.

const _CH = preload("res://addons/exmateria_sound/runtime/shared/channel_state.gd")
const _SS = preload("res://addons/exmateria_sound/runtime/shared/slot_state.gd")
const _Trace = preload("res://addons/exmateria_sound/runtime/effect_sound/trace_writer.gd")
const _ProbeCounters = preload("res://addons/exmateria_sound/runtime/effect_sound/probes/probe_counters.gd")


static func apply(channel: _CH, slot: _SS, note: SMDOpcodes.NoteEvent) -> int:
	## Pitch formula (probe-validated 100% on cure voice 21 in
	## pitch_formula_001).
	##
	## At Note dispatch, FFT's Note handler at LAB_80015458 (PC 0x8001545C)
	## writes a 32-bit `sw v0, 0x7e(s0)` to chan+0x82..0x85, with v0 =
	## (note key data << 8) + chan+0x88 + a0 (octave-related), then SLL by
	## 16 so the new value lands in the upper halfword of the 32-bit word
	## and the lower halfword is zeroed.
	##
	## We model this by setting the upper 16 bits of pre_pitch_acc_u32 to
	## (midi_note*256 + fine_tune) per `PitchTable.note_to_pitch`
	## semantics, with lower halfword = 0. The per-tick accumulator (per
	## chan+0x9C) then increments the full 32-bit value, evolving the
	## upper halfword ~14 units per tick for cure (rate_q24 / 65536 ≈
	## 14.22).
	##
	## At the flush, the formula reads the UPPER halfword of
	## pre_pitch_acc_u32 (= chan+0x82 in FFT layout, lh signed) and
	## combines:
	##   sum = pre_pitch_high_s16 + pitch_bend_u16 + s2+0xA2_s16
	## then PitchTable.note_to_pitch is called on (sum >> 8, sum & 0xFF) —
	## equivalent to FFT's FUN_80017424 because note_to_pitch internally
	## computes adjusted = midi*256 + fine_tune.
	##
	## FFT computes:
	##   a1 = (slot+0x7E low byte + lookup_e70[key]) & 0xFF
	##   slot+0x80 = (a1 << 8) + slot+0x84 + slot+0x86
	## Open issue: slot+0x84 (channel.word_84 ≡ slot.fine_tune) has
	## dynamic FFT behavior driven by slot+0x6 → pool walker refresh.
	var key: int = note.relative_key & 0xFF
	# The e70 table is the precomputed `byte / 19` lookup
	# (note_lookup.gd:6-22: e70[0..18]=0, e70[19..37]=1, ..., e70[202..220]=10).
	# Per smd_opcodes.gd the SMD parser already computes `relative_key =
	# data_byte / 19`, so `e70(relative_key)` was a double-divide-by-19.
	var a1: int = (channel.bmidi_baseline_byte + key) & 0xFF
	var ft: int = slot.fine_tune  # ≡ channel.word_84 ≡ slot+0x84
	var pre_pitch_baseline: int = (a1 << 8) + ft + channel.word_86
	_ProbeCounters.note_pitch_baseline += 1
	_Trace.emit("note_pitch_baseline", {
		"call_index": _ProbeCounters.note_pitch_baseline,
		"chan_84_finetune": ft,
		"chan_86_pitch_bend": channel.word_86,
		"a1_bmidi_byte": a1,
		"sum": pre_pitch_baseline & 0xFFFF,
	})
	var _prior_acc: int = channel.pre_pitch_acc_u32
	# Note handler stores into upper halfword of 32-bit acc; lower zeroed.
	channel.pre_pitch_acc_u32 = (pre_pitch_baseline & 0xFFFF) << 16
	channel.pitch_state = pre_pitch_baseline  # retained for compatibility
	var _result: int = evaluate(channel, slot)
	_ProbeCounters.diag_pitch_formula_inputs += 1
	_Trace.emit("diag_pitch_formula_inputs", {
		"call_index": _ProbeCounters.diag_pitch_formula_inputs,
		"slot_idx": slot.slot_idx,
		"voice": channel.target_voice_idx,
		"note_relative_key": key,
		"bmidi_baseline_byte": channel.bmidi_baseline_byte,
		"slot_fine_tune": slot.fine_tune,
		"channel_word_86": channel.word_86,
		"pre_pitch_baseline": pre_pitch_baseline & 0xFFFF,
		"pre_pitch_acc_u32_pre": _prior_acc,
		"result_raw_pitch": _result,
	})
	return _result


static func evaluate(channel: _CH, _slot: _SS) -> int:
	## Compose chan+0x82 (high half of acc, s16) + chan+0x86 (u16) +
	## s2+0xA2 (s16, =0 for cure), then PitchTable.note_to_pitch.
	## Result mask & 0x3FFF per L80017364 disasm.
	## Per Write BP at v21 chan+0x86 + chan+0x88, FFT mode-0 LFO writes
	## chan+0x88 NOT chan+0x86. Same offset miscount affects formula at
	## L80017344: `lhu v0, 0x86(s0)` with s0=chan+0x2 (set at L80014BBC
	## area) reads chan+0x88. Reading channel.pitch_bend (= chan+0x88)
	## restores the correct field.
	var acc_high: int = (channel.pre_pitch_acc_u32 >> 16) & 0xFFFF
	var pp_s16: int = acc_high - 0x10000 if acc_high >= 0x8000 else acc_high
	var bend_u16: int = channel.pitch_bend & 0xFFFF
	var s2_a2_s16: int = 0  # cure has no global LFO bias
	var sum: int = pp_s16 + bend_u16 + s2_a2_s16
	var sum_u16: int = sum & 0xFFFF
	var sum_s16: int = sum_u16 - 0x10000 if sum_u16 >= 0x8000 else sum_u16
	# PitchTable.note_to_pitch(midi, ft) computes adjusted = midi*256 +
	# ft. We feed the pre-summed adjusted value via (sum >> 8, sum & 0xFF)
	# split, which reconstructs to the same adjusted value (sign-
	# preserving on >>).
	var midi_arg: int = sum_s16 >> 8
	var ft_arg: int = sum_s16 & 0xFF
	var result: int = PitchTable.note_to_pitch(midi_arg, ft_arg) & 0x3FFF
	return result


static func evaluate_with_music_probe(channel: _CH, slot: _SS) -> int:
	## Music-only wrapper around evaluate(). Emits the 5-stage
	## probe_pitch_formula_stages bisection rows. Used by music callers
	## (runtime.gd, sequencer.gd, sequencer/note_handler/note_handler.gd);
	## SFX calls evaluate() directly because play_sound.gd has its own
	## inline emit at lines 1680-1684 — calling this from SFX would
	## DOUBLE the pitch_formula_stage row count.
	## See docs/MUSIC_ITER19_PITCH_FORMULA_STAGES_MUSIC.md.
	var acc_high: int = (channel.pre_pitch_acc_u32 >> 16) & 0xFFFF
	var pp_s16: int = acc_high - 0x10000 if acc_high >= 0x8000 else acc_high
	var bend_u16: int = channel.pitch_bend & 0xFFFF
	var s2_a2_s16: int = 0
	var sum: int = pp_s16 + bend_u16 + s2_a2_s16
	# Emit the four pre-result stages BEFORE the final pitch lookup so
	# the cadence-trace shows the same dependency order PCSX captures
	# at PCs 0x80017344-0x80017354.
	_ProbeCounters.pitch_formula_stages_music += 1
	_Trace.emit("pitch_formula_stage", {
		"call_index": _ProbeCounters.pitch_formula_stages_music,
		"stage": "pitch_base",
		"value": pp_s16,
		"channel_idx": channel.channel_idx,
	})
	_ProbeCounters.pitch_formula_stages_music += 1
	_Trace.emit("pitch_formula_stage", {
		"call_index": _ProbeCounters.pitch_formula_stages_music,
		"stage": "pitch_bend",
		"value": bend_u16,
		"channel_idx": channel.channel_idx,
	})
	_ProbeCounters.pitch_formula_stages_music += 1
	_Trace.emit("pitch_formula_stage", {
		"call_index": _ProbeCounters.pitch_formula_stages_music,
		"stage": "pool_a2",
		"value": s2_a2_s16,
		"channel_idx": channel.channel_idx,
	})
	_ProbeCounters.pitch_formula_stages_music += 1
	_Trace.emit("pitch_formula_stage", {
		"call_index": _ProbeCounters.pitch_formula_stages_music,
		"stage": "midi_sum",
		"value": sum,
		"channel_idx": channel.channel_idx,
	})
	var result: int = evaluate(channel, slot)
	_ProbeCounters.pitch_formula_stages_music += 1
	_Trace.emit("pitch_formula_stage", {
		"call_index": _ProbeCounters.pitch_formula_stages_music,
		"stage": "pitch_result",
		"value": result,
		"channel_idx": channel.channel_idx,
	})
	return result
