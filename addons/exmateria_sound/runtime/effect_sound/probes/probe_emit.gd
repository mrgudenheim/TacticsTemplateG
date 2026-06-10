class_name EffectSoundProbeEmit
## Probe-emit helpers extracted from dispatcher.gd (refactor Pass 1).
##
## Each emit function bumps a counter in `EffectSoundProbeCounters` and
## then calls `EffectSoundTraceWriter.emit(...)`. Counters are still
## static — the cardinality contract with PCSX is preserved.
##
## dispatcher.gd keeps thin static wrappers for the two functions
## play_sound.gd calls statically (emit_smd_interpreter_inactive,
## emit_lfo_handler_inactive) so external callers don't change.

const _CH = preload("res://addons/exmateria_sound/runtime/shared/channel_state.gd")
const _SS = preload("res://addons/exmateria_sound/runtime/shared/slot_state.gd")
const _Trace = preload("res://addons/exmateria_sound/runtime/effect_sound/trace_writer.gd")
const _ProbeCounters = preload("res://addons/exmateria_sound/runtime/effect_sound/probes/probe_counters.gd")


static func emit_smd_interpreter_gate_skip_for_state(channel: _CH, slot: _SS) -> void:
	## Emit a probe_smd_interpreter_gate_skip row classifying which_gate by
	## the channel's current (cw0, nd) state. Used at the three non-null
	## exit paths from cadence_body: stream_end_fired early-return, the
	## else-branch (nd != 0), and post-walker fall-through. Mirrors the
	## PCSX Lua probe's BP-time heuristic at LAB_80015814: cw0==0 → gate-1,
	## else gate-2. See §6 of
	## SMD_INTERPRETER_GATE_SKIP_EARLY_RETURN_DEFICIT.md.
	var cw0: int = channel.channel_word_0 & 0xFFFF
	var nd: int = channel.note_duration & 0xFFFF
	var which_gate: int = 1 if cw0 == 0 else 2
	_ProbeCounters.smd_interpreter_gate_skip += 1
	_Trace.emit("smd_interpreter_gate_skip", {
		"call_index": _ProbeCounters.smd_interpreter_gate_skip,
		"chan_word_0": cw0,
		"note_duration": nd,
		"which_gate": which_gate,
		"slot_idx": slot.slot_idx,
	})


static func emit_smd_interpreter_inactive(slot_idx: int) -> void:
	## Emit structural smd_interpreter probes for an inactive (null
	## dispatcher) channel slot. PCSX's smd_interpreter_tick walks all
	## 8 chan_base struct positions per outer-tick regardless of activity;
	## entries with chan_word_0 == 0 hit the gate-1 skip path at FFT PC
	## 0x80015380. Godot's `_channels` is sparse (null = unallocated), so
	## the active-channel cadence_body() only emits tick_entry/gate_skip
	## for non-null slots. This helper closes the structural row-count
	## gap on protect_no_music (PCSX 1635 vs Godot 403 pre-fix). The
	## the FFT struct positions exist but their fields are zero/idle.
	## Companion to play_sound.gd's per_channel_tick_entry zero-emit
	## for null slots — same pattern, different probe.
	_ProbeCounters.smd_interpreter_tick_entry += 1
	_Trace.emit("smd_interpreter_tick_entry", {
		"call_index": _ProbeCounters.smd_interpreter_tick_entry,
		"chan_word_0": 0,
		"note_duration": 0,
		"slot_idx": slot_idx,
	})
	_ProbeCounters.smd_interpreter_gate_skip += 1
	_Trace.emit("smd_interpreter_gate_skip", {
		"call_index": _ProbeCounters.smd_interpreter_gate_skip,
		"chan_word_0": 0,
		"note_duration": 0,
		"which_gate": 1,
		"slot_idx": slot_idx,
	})


static func emit_lfo_handler_probes(channel: _CH) -> void:
	## Emit the four lfo_handler probes for a non-null active channel,
	## mirroring PCSX BP @ 0x800174C8 (lfo_handler_tick per-channel loop
	## top, BEFORE the chan_word_0 != 0 gate at PC 0x800174D0). Called
	## from cadence_body's top to fire once per channel per entity-iter,
	## matching PCSX's per-entity-iter invocation of lfo_handler_tick.
	## State mutation in _advance_lfo (per-IRQ) is untouched. See
	## LFO_HANDLER_PER_IRQ_GATE_DEFICIT.md §7 for context.
	_ProbeCounters.lfo_handler_entry += 1
	_Trace.emit("lfo_handler_entry", {
		"call_index": _Trace._cadence_index * 16 + channel.channel_idx,
		"channel_idx": channel.channel_idx,
		"chan_word_0": channel.channel_word_0 & 0xFFFF,
		"chan_word_1": channel.channel_word_1 & 0xFFFF,
		"gate_pass": 1 if channel.channel_word_0 != 0 else 0,
	})
	_ProbeCounters.lfo_subslot0_state += 1
	# Iter-35: sub-slot 0 unified onto lfo_sub_*[0]; emit structure
	# matches sub-slots 1-3. See
	# MUSIC_ITER35_PITCH_LFO_SUBSLOT0_UNIFICATION.md.
	var _ssa0: int = (1 if channel.lfo_sub_active[0] != 0 else 0)
	var _ssd0: int = channel.lfo_sub_dir_flags[0] & 0xFF
	_Trace.emit("lfo_subslot0_state", {
		"call_index": _Trace._cadence_index * 16 + channel.channel_idx,
		"channel_idx": channel.channel_idx,
		"accumulator": channel.lfo_sub_accumulator[0],
		"step_current": channel.lfo_sub_step_current[0],
		"step_source": channel.lfo_sub_step_source[0],
		"countdown": channel.lfo_sub_countdown[0] & 0xFFFF,
		"inner_reload": channel.lfo_sub_inner_reload[0] & 0xFFFF,
		"delay_counter": channel.lfo_sub_delay_counter[0] & 0xFFFF,
		"delay_reload": channel.lfo_sub_delay_reload[0] & 0xFFFF,
		"depth": channel.lfo_sub_depth[0] & 0xFFFF,
		"depth_reload": channel.lfo_sub_depth_delta[0] & 0xFFFF,
		"mode": channel.lfo_sub_mode[0] & 0xFF,
		"active_dir": (_ssd0 << 0) | _ssa0,
	})
	_ProbeCounters.lfo_subslot1_state += 1
	var _ssa1: int = (1 if channel.lfo_sub_active[1] != 0 else 0)
	var _ssd1: int = channel.lfo_sub_dir_flags[1] & 0xFF
	_Trace.emit("lfo_subslot1_state", {
		"call_index": _Trace._cadence_index * 16 + channel.channel_idx,
		"channel_idx": channel.channel_idx,
		"accumulator": channel.lfo_sub_accumulator[1],
		"step_current": channel.lfo_sub_step_current[1],
		"step_source": channel.lfo_sub_step_source[1],
		"countdown": channel.lfo_sub_countdown[1] & 0xFFFF,
		"inner_reload": channel.lfo_sub_inner_reload[1] & 0xFFFF,
		"delay_counter": 0,
		"delay_reload": 0,
		"depth": channel.lfo_sub_depth[1] & 0xFFFF,
		"depth_reload": 0,
		"mode": channel.lfo_sub_mode[1] & 0xFF,
		"active_dir": (_ssd1 << 0) | _ssa1,
	})
	_ProbeCounters.lfo_subslot2_state += 1
	var _ssa2: int = (1 if channel.lfo_sub_active[2] != 0 else 0)
	var _ssd2: int = channel.lfo_sub_dir_flags[2] & 0xFF
	_Trace.emit("lfo_subslot2_state", {
		"call_index": _Trace._cadence_index * 16 + channel.channel_idx,
		"channel_idx": channel.channel_idx,
		"accumulator": channel.lfo_sub_accumulator[2],
		"step_current": channel.lfo_sub_step_current[2],
		"step_source": channel.lfo_sub_step_source[2],
		"countdown": channel.lfo_sub_countdown[2] & 0xFFFF,
		"inner_reload": channel.lfo_sub_inner_reload[2] & 0xFFFF,
		"delay_counter": 0,
		"delay_reload": 0,
		"depth": channel.lfo_sub_depth[2] & 0xFFFF,
		"depth_reload": 0,
		"mode": channel.lfo_sub_mode[2] & 0xFF,
		"active_dir": (_ssd2 << 0) | _ssa2,
	})
	_ProbeCounters.lfo_subslot3_state += 1
	var _ssa3: int = (1 if channel.lfo_sub_active[3] != 0 else 0)
	var _ssd3: int = channel.lfo_sub_dir_flags[3] & 0xFF
	_Trace.emit("lfo_subslot3_state", {
		"call_index": _Trace._cadence_index * 16 + channel.channel_idx,
		"channel_idx": channel.channel_idx,
		"accumulator": channel.lfo_sub_accumulator[3],
		"step_current": channel.lfo_sub_step_current[3],
		"step_source": channel.lfo_sub_step_source[3],
		"countdown": channel.lfo_sub_countdown[3] & 0xFFFF,
		"inner_reload": channel.lfo_sub_inner_reload[3] & 0xFFFF,
		"delay_counter": 0,
		"delay_reload": 0,
		"depth": channel.lfo_sub_depth[3] & 0xFFFF,
		"depth_reload": 0,
		"mode": channel.lfo_sub_mode[3] & 0xFF,
		"active_dir": (_ssd3 << 0) | _ssa3,
	})
	_ProbeCounters.chan_pitch_state += 1
	# Per chan-side layout (raw chan_base offsets) — see
	# PROBE_CHAN_PITCH_STATE_OFFSET_FIX.md for why the field naming
	# matters here.
	#   chan+0x80 (raw) = pre_pitch_acc_u32 low 16  (probe_read16 LE)
	#   chan+0x82 (raw) = pre_pitch_acc_u32 high 16 = the "pitch_base"
	#                     the FFT formula reads via `lh a0, 0x80(s0)`
	#                     with s0 = chan_base + 0x2.
	#   chan+0x86 (raw) = channel.word_86 — D0/D1/D2/D3 slow-modulation
	#                     accumulator; NOT the formula's pitch_bend.
	#   chan+0x88 (raw) = channel.pitch_bend — LFO mode-0 commit target
	#                     AND the formula's pitch_bend input.
	_Trace.emit("chan_pitch_state", {
		"call_index": _Trace._cadence_index * 16 + channel.channel_idx,
		"channel_idx": channel.channel_idx,
		"pre_pitch_lo": channel.pre_pitch_acc_u32 & 0xFFFF,
		"pre_pitch_hi": (channel.pre_pitch_acc_u32 >> 16) & 0xFFFF,
		"word_86": channel.word_86 & 0xFFFF,
		"pitch_bend": channel.pitch_bend & 0xFFFF,
	})


static func emit_lfo_handler_inactive(slot_idx: int, residue: Dictionary = {}) -> void:
	## Sibling of emit_smd_interpreter_inactive for the lfo_handler probes.
	## PCSX's lfo_handler_tick walks all 8 chan_base positions per outer-
	## tick — BP @ 0x800174C8 fires BEFORE the chan_word_0 != 0 gate at
	## 0x800174D0, so inactive positions also emit a row. Godot's
	## _advance_lfo only runs for non-null channels via cadence_body, so
	## without this helper the structural row counts diverge (PCSX 1640
	## vs Godot 403 on protect_no_music). Closes residual §2.3 in
	## PROTECT_POST_EC_LIFT_RESIDUALS.md.
	##
	## `residue` is the optional per-slot music-engine residue snapshot
	## (chan_word_0, pre_pitch_lo/hi, word_86, pitch_bend, plus subslot_*
	## state) captured from PCSX savestate by diag_chan_lfo_residue_
	## snapshot.lua. For dormant slots (0/1/6/7 on haste_no_music), these
	## hold the frozen music-track values; emitting them here matches
	## PCSX's chan-side reads at those slots. Empty dict → emit zeros.
	## See DORMANT_SLOT_PROBE_RESIDUE_SEED.md.
	var sub0: Dictionary = residue.get("subslot_0", {}) if residue is Dictionary else {}
	var sub1: Dictionary = residue.get("subslot_1", {}) if residue is Dictionary else {}
	var sub2: Dictionary = residue.get("subslot_2", {}) if residue is Dictionary else {}
	var sub3: Dictionary = residue.get("subslot_3", {}) if residue is Dictionary else {}
	_ProbeCounters.lfo_handler_entry += 1
	_Trace.emit("lfo_handler_entry", {
		"call_index": _Trace._cadence_index * 16 + slot_idx,
		"channel_idx": slot_idx,
		"chan_word_0": int(residue.get("chan_word_0", 0)),
		"chan_word_1": 0,
		"gate_pass": 0,
	})
	_ProbeCounters.lfo_subslot0_state += 1
	_Trace.emit("lfo_subslot0_state", make_subslot_row(slot_idx, sub0))
	_ProbeCounters.lfo_subslot1_state += 1
	_Trace.emit("lfo_subslot1_state", make_subslot_row(slot_idx, sub1))
	_ProbeCounters.lfo_subslot2_state += 1
	_Trace.emit("lfo_subslot2_state", make_subslot_row(slot_idx, sub2))
	_ProbeCounters.lfo_subslot3_state += 1
	_Trace.emit("lfo_subslot3_state", make_subslot_row(slot_idx, sub3))
	_ProbeCounters.chan_pitch_state += 1
	_Trace.emit("chan_pitch_state", {
		"call_index": _Trace._cadence_index * 16 + slot_idx,
		"channel_idx": slot_idx,
		"pre_pitch_lo": int(residue.get("pre_pitch_lo", 0)),
		"pre_pitch_hi": int(residue.get("pre_pitch_hi", 0)),
		"word_86":      int(residue.get("word_86", 0)),
		"pitch_bend":   int(residue.get("pitch_bend", 0)),
	})


static func make_subslot_row(slot_idx: int, sub: Dictionary) -> Dictionary:
	## Helper for emit_lfo_handler_inactive — builds a subslot trace row
	## from the residue subslot_N dictionary. Empty dict → zero row.
	return {
		"call_index": _Trace._cadence_index * 16 + slot_idx,
		"channel_idx": slot_idx,
		"accumulator":  int(sub.get("accumulator", 0)),
		"step_current": int(sub.get("step_current", 0)),
		"step_source":  int(sub.get("step_source", 0)),
		"countdown":    int(sub.get("countdown", 0)),
		"inner_reload": int(sub.get("inner_reload", 0)),
		"delay_counter":int(sub.get("delay_counter", 0)),
		"delay_reload": int(sub.get("delay_reload", 0)),
		"depth":        int(sub.get("depth", 0)),
		"depth_reload": int(sub.get("depth_reload", 0)),
		"mode":         int(sub.get("mode", 0)),
		"active_dir":   int(sub.get("active_dir", 0)),
	}
