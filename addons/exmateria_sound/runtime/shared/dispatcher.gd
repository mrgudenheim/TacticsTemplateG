class_name SharedDispatcher
## Per-channel feds opcode dispatcher — port of FUN_80015324.
##
## Each pool slot owns one feds file_channel. Per tick, the dispatcher:
##   1. Decrements note_duration. When it reaches 0, sets channel_word_0
##      bit 0x400 (KON_ARM) — the duration-expire path that arms the
##      next Note for a primary KON.
##   2. Snapshots channel_word_0 → s2; clears bits 0x100/0x200/0x400 from
##      the live word_0 (L9472–9477).
##   3. Walks opcode bytes until a delta-time consumes the rest of the tick.
##      Each opcode handler sets flag bits + per-channel state.
##
## After the dispatcher returns, the slot's flag_word drives the per-tick
## flush which stages SPU writes.
##
## Walker re-arm convention (DO NOT add walker_flag_word arms in opcode
## handlers below). Per FFT semantics, opcode dispatch sets the per-tick
## flag (slot+0x4 / `flag_word` here); the per-tick handler (FUN_80017118
## / flush_tick.gd) is what re-arms the walker flag (sub_slot+0x2 /
## `walker_flag_word`) at the timeline rate. Adding walker re-arms at
## opcode time would cause same-tick double-write relative to the per-tick
## path.


const _SS = preload("res://addons/exmateria_sound/runtime/shared/slot_state.gd")
const _CH = preload("res://addons/exmateria_sound/runtime/shared/channel_state.gd")
const _NoteLookup = preload("res://addons/exmateria_sound/runtime/shared/note_lookup.gd")
const _Trace = preload("res://addons/exmateria_sound/runtime/effect_sound/trace_writer.gd")
# Refactor Pass 1: probe counters + emit helpers moved out to probes/.
const _ProbeCounters = preload("res://addons/exmateria_sound/runtime/effect_sound/probes/probe_counters.gd")
const _ProbeEmit = preload("res://addons/exmateria_sound/runtime/effect_sound/probes/probe_emit.gd")
# Refactor Pass 2: LFO math + PRNG moved out to helpers/.
const _LfoStepCalc = preload("res://addons/exmateria_sound/runtime/shared/helpers/lfo_step_calc.gd")
const _LfoPrng = preload("res://addons/exmateria_sound/runtime/shared/helpers/lfo_prng.gd")
# Refactor Pass 3: opcode dispatch via Dictionary[int, Callable].
const _OpcodeTable = preload("res://addons/exmateria_sound/runtime/shared/opcodes/_table.gd")
# Refactor Pass 5: per-tick handlers extracted into per_tick/.
const _PerTickAdvanceLfo = preload("res://addons/exmateria_sound/runtime/shared/per_tick/advance_lfo.gd")
const _PerTickPitchStaging = preload("res://addons/exmateria_sound/runtime/shared/per_tick/pitch_staging.gd")
const _PerTickLfoPeriodReset = preload("res://addons/exmateria_sound/runtime/shared/per_tick/lfo_period_reset.gd")
const _PerTickStreamEnd = preload("res://addons/exmateria_sound/runtime/shared/per_tick/stream_end.gd")
const _PerTickPostWalkerLookahead = preload("res://addons/exmateria_sound/runtime/shared/per_tick/post_walker_lookahead.gd")
# Refactor Pass 6: note handler + pitch helpers extracted.
const _NoteHandler = preload("res://addons/exmateria_sound/runtime/shared/note_handler/note_handler.gd")
const _ComputePitch = preload("res://addons/exmateria_sound/runtime/shared/note_handler/compute_pitch.gd")


# Per probe flush_rate_001: FUN_80017118 fires 4× per timeline tick.
# Audition harness now ticks at 4× rate. Multiply Note delta_time by
# this to preserve Note duration in wall-clock terms.
const FLUSH_PER_DISPATCH := 8


# Decoded events list from feds_bank.get_channel_events()
# (Array of SMDOpcodes.NoteEvent / OpcodeEvent).
var _events: Array = []
var _waveset: WavesetParser = null

# Constant from FFT disasm at PC 0x80014cc8 (`lui a0, 0x1` immediately
# before LAB_80014ccc inner-loop entry). Each sub-tick body iteration
# adds this to entity+0x74. This is the granularity of the sub-tick
# budget integer part.
const _SUBTICK_INCREMENT := 0x10000

# How many PSX RCnt2 fires (240 Hz) one Godot sub_tick represents.
# When the pipeline runs at FLUSH_PER_DISPATCH=8 (= 240 Hz beat, the
# FFT-faithful rate), this is 1 so the e74/e78 algorithm fires per-
# sub_tick at the same rate FFT does per-RCnt2.
static var _RCNT2_PER_SUBTICK: int = 1

# Back-compat: render_effect_sound.gd:805 calls this statically on
# SharedDispatcher to seed the LFO PRNG from the savestate.
# Refactor Pass 2 moved the body to helpers/lfo_prng.gd; thin
# pass-through preserves the call site.
static func set_lfo_prng_state(state: int) -> void:
	_LfoPrng.set_state(state)


func bind(channel_events: Array, waveset: WavesetParser = null) -> void:
	## Bind a feds channel's decoded opcode stream to this dispatcher.
	## Waveset is consulted on Instrument (0xAC) opcodes to resolve
	## fine_tune, ADSR, and SPU-VRAM sample addresses (mirrors
	## Sequencer's path at sequencer.gd:678..696).
	_events = channel_events
	_waveset = waveset


# Accessors used by opcode handler modules (opcodes/*.gd) to reach
# into instance state without taking a typed `SharedDispatcher`
# parameter — that would create a preload cycle since opcode files
# preload state classes that dispatcher.gd also preloads.
func get_waveset() -> WavesetParser:
	return _waveset


func get_events() -> Array:
	return _events


# Back-compat: play_sound.gd:1687 calls disp._evaluate_pitch_formula(...)
# on the dispatcher instance. Pass 6 moved the body to
# note_handler/compute_pitch.gd as a static method; thin pass-through
# preserves the call site.
func _evaluate_pitch_formula(channel: _CH, slot: _SS) -> int:
	return _ComputePitch.evaluate(channel, slot)


func tick(channel: _CH, slot: _SS, cadence_fired: bool = false) -> void:
	## Advance the dispatcher one effect-tick (30 Hz, per timeline cadence).
	## Mutates `slot` flag_word + channel_word + per-channel state.
	##
	## `cadence_fired` is passed in by play_sound.gd:tick_all_dispatchers,
	## computed from the entity-level catch-up state
	## (EffectEntityCatchupState). It's true if the entity catch-up loop
	## fired ≥ 1 time this IRQ. The per-channel sub_tick_acc /
	## sub_tick_budget catch-up loop has been lifted out of this function
	## into the entity-level loop.
	##
	## `channel` is the per-bytecode ChannelState; `slot` is the per-
	## voice SlotState. Currently bound 1:1 (channel.target_voice_idx ==
	## voice_for_slot(slot.slot_idx)) and the dispatcher still
	## reads/writes via slot.

	# Once the channel has fired its stream-end, skip the rest of tick —
	# no more bytecode means no more arms or pitch updates.
	if channel.stream_end_fired:
		return

	# Capture porta-active state BEFORE the cadence_fired block
	# decrement+deactivation runs. FFT disasm L80015214-L80015244 shows
	# the per-tick acc-add at LAB_80015234 ALWAYS runs after the porta-
	# block (when entry porta_active was true) — even on the deactivation
	# tick. Using porta_was_active in both the acc-add gate and the
	# pitch-update gate makes Godot fire the deactivation-tick acc-add
	# matching FFT's behavior.
	var porta_was_active: bool = channel.portamento_active
	# Pre-drain snapshot for FFT PC 0x800151B4 gate. The drain runs
	# BEFORE the acc_gate check, so checking `channel.note_duration > 0`
	# there evaluates the POST-drain value. FFT's gate at PC 0x800151B4
	# (`lh v0, 0x6e(a0); beq v0, zero, LAB_800152fc`) reads PRE-drain
	# (drain happens later at PC 0x80015290). Snapshot here so the gate
	# mirrors FFT's pre-drain check.
	var _pre_drain_note_dur: int = channel.note_duration

	# Silent-driver dispatchers must NOT write voice-side state
	# (pitch_staging, vol_staging_l/r, instrument_idx, sample_*_addr,
	# adsr1/2, fine_tune, force_envelope_open, lfo_active, noise_pending),
	# nor FLAG_PITCH_UPDATE / FLAG_VOL_UPDATE. Their bytecode runs purely
	# to contribute KON arm bits (FLAG_PRIMARY_KON / FLAG_SECONDARY_KON)
	# into the SHARED slot's flag_word, mirroring FFT's kon_accum which
	# OR's voice_mask from every targeting channel without disturbing the
	# audible voice's SPU state. Without this gate the audible pair's
	# staging gets clobbered.
	var voice_writes: bool = not channel.is_silent_driver

	var _lfo_swap_fired: bool = _PerTickAdvanceLfo.apply(channel, slot, voice_writes, cadence_fired)
	_PerTickPitchStaging.apply(channel, slot, voice_writes, cadence_fired, porta_was_active)
	# (_apply_slur_propagation moved into cadence_body — gated on walker
	# actually entering, matching FFT's dispatcher-exit-only behavior.)
	_PerTickStreamEnd.apply(self, channel, slot)


func cadence_body(channel: _CH, slot: _SS) -> void:
	## Renamed from _cadence_body_tickbase + made public. Entity-level
	## catch-up loop in play_sound.gd:tick_all_dispatchers calls this for
	## ALL channels per sub-loop fire, mirroring FFT's per_channel_tick × 8
	## invocation from inside the sub-loop body
	## (PC 0x80014d34..0x80014d68).

	# Selectivity gates. Sit AFTER any pre-test recorder so the
	# BP-equivalent fires regardless of the FFT L800151A0 selectivity
	# test (matches PCSX behavior at PC 0x80015198).
	# probe_per_channel_tick_entry lives in play_sound.gd's outer slot
	# loop — emitted 8 times per spu_slot_loop iteration (once per FFT
	# channel position in the chan struct array), not once per
	# cadence_body call. cadence_body only fires for the bound channel
	# subset (2 of 8 in cure_no_music's audible pair), which would miss
	# 6 of FFT's 8 per_channel_tick entries.
	#
	# probe_smd_interpreter_tick_entry — emit at function top BEFORE the
	# early-returns so the row count matches PCSX BP @ PC 0x8001536C
	# (per-channel loop entry, BEFORE either selectivity gate AND before
	# the Godot-only stream_end_fired gate). See §4.1 problem A of
	# SMD_INTERPRETER_GATE_SKIP_EARLY_RETURN_DEFICIT.md.
	_ProbeCounters.smd_interpreter_tick_entry += 1
	_Trace.emit("smd_interpreter_tick_entry", {
		"call_index": _ProbeCounters.smd_interpreter_tick_entry,
		"chan_word_0": channel.channel_word_0 & 0xFFFF,
		"note_duration": channel.note_duration & 0xFFFF,
		"slot_idx": slot.slot_idx,
	})
	# (probe_lfo_handler_* emit relocated to cadence_body BOTTOM — see
	# PROBE_LFO_HANDLER_RELOCATION_PLAN.md. The emit at cadence_body
	# top captured PRE-dispatch chan+0x82 / chan+0x88 values; PCSX's
	# BP at PC 0x800174C8 fires AFTER smd_interpreter_tick +
	# per_channel_tick, so the emit must follow cadence_body's
	# state-mutation work, not precede it. The early-return branches
	# below each get their own _ProbeEmit.emit_lfo_handler_probes call to keep
	# row count paired with PCSX's pre-gate BP.)
	if channel.stream_end_fired:
		# stream_end_fired channels have no PCSX equivalent — PCSX keeps
		# iterating the channel with leftover state. Classify the
		# gate_skip emit by what PCSX would see at BP time
		# (cw0==0 → gate-1, else gate-2). See §6 of
		# SMD_INTERPRETER_GATE_SKIP_EARLY_RETURN_DEFICIT.md.
		_ProbeEmit.emit_smd_interpreter_gate_skip_for_state(channel, slot)
		# lfo_handler probes must still fire (PCSX BP @ 0x800174C8
		# fires for all 8 channels regardless of state). State is
		# unmutated here, matching what PCSX captures for these chans.
		_ProbeEmit.emit_lfo_handler_probes(channel)
		return
	if channel.channel_word_0 == 0:
		# Mirrors PCSX gate-1 fail at PC 0x80015374
		# (beq v0=cw0, zero, LAB_80015814). Emit which_gate=1 before
		# the return so the gate_skip row count matches PCSX.
		_ProbeCounters.smd_interpreter_gate_skip += 1
		_Trace.emit("smd_interpreter_gate_skip", {
			"call_index": _ProbeCounters.smd_interpreter_gate_skip,
			"chan_word_0": 0,
			"note_duration": channel.note_duration & 0xFFFF,
			"which_gate": 1,
			"slot_idx": slot.slot_idx,
		})
		# lfo_handler probes must still fire (PCSX BP fires pre-gate).
		# State unmutated; matches PCSX BP capture for cw0==0 chans.
		_ProbeEmit.emit_lfo_handler_probes(channel)
		return
	# Capture porta-active state at the TOP of cadence_body (before the
	# porta decrement below can clear it, and crucially before the opcode
	# walker can mutate pre_pitch_delta_u32 via 0xD4). FFT per_channel_tick
	# reads bit 0x1 of chan+0x6 at PC 0x80015200 — pre-decrement, pre-
	# opcode-dispatch. The pre_pitch_acc advance at PC 0x80015234 uses
	# THIS value. Capturing here lets cadence_body run the advance before
	# the opcode walker dispatches Note (which resets pre_pitch_acc to
	# its Note baseline). Without this ordering, Note's reset is followed
	# by the advance, leaving pitch_base +1 step ahead of PCSX.
	var _cb_porta_was_active: bool = channel.portamento_active
	# probe_per_channel_tick_word0_pass — bisection probe at this point.
	# Mirrors FFT BP @ 0x800151B4 (post chan_word_0 gate, pre
	# note_duration gate). Fires for every channel × tick where
	# chan_word_0 != 0, regardless of note_duration.
	# Gated on `_Trace._post_anchor` (not `_first_dispatch_fired`) because
	# PCSX's `per_channel_tick` is NOT entered during the engine-init
	# dispatch — only the post-init main loop reaches PC 0x800151B4. The
	# init dispatch in Godot routes through this same `cadence_body`, so
	# we need a gate that stays false for the entire init tick (both slot
	# 4 + slot 5 init iterations). `_post_anchor` flips one tick after
	# init (post-loop in `tick_all_dispatchers`), matching PCSX's
	# structural separation. See
	# PROTECT_2_6_WORD0_PASS_PREANCHOR_OVERCOUNT.md §2.6.
	if _Trace._post_anchor:
		_ProbeCounters.per_channel_tick_word0_pass += 1
		_Trace.emit("per_channel_tick_word0_pass", {
			"call_index": _ProbeCounters.per_channel_tick_word0_pass,
			"chan_word_0": channel.channel_word_0 & 0xFFFF,
			"note_duration": channel.note_duration & 0xFFFF,
			"slot_idx": slot.slot_idx,
		})
	# Gate is signed-zero (lh @ PC 0x800151ac
	# `beq v0, zero, LAB_800152fc`), not `> 0`. Post-truncation the field
	# is unsigned 0..0xFFFF so `!= 0` matches FFT semantics.
	if channel.note_duration != 0:
		# 16-bit halfword truncation per FFT PC 0x80015294 `sh v0, 0x6e(a0)`.
		# Without the mask Godot's int32 underflows past 0 instead of
		# wrapping at 0xFFFF.
		channel.note_duration = (channel.note_duration - 1) & 0xFFFF
		# (Deleted: an early-KOFF lookahead block that fired
		# FLAG_KOFF_PENDING when note_duration post-decremented to 1
		# AND a peek-ahead at the next audible opcode said it was a
		# Rest. This was a Godot-only approximation of FFT's slot+0x10
		# bit 0x2 mechanism. After Phase A landed (idle-drain owns the
		# byte_7A=16 case), the actual idle_timeout drain at line ~1113
		# fires FLAG_KOFF_PENDING on its FFT-faithful gate — the
		# lookahead is no longer needed. Removed along with the
		# `_next_audible_event_is_rest` helper. See
		# FFT_GODOT_DATA_FLOW_ALIGNMENT.md §4.3 + §5.1.2.)
		# FFT per_channel_tick PC 0x800152A8-C0 — KOFF-prep ADSR2 release
		# rate force. When note_duration just decremented to 1 AND
		# chan_word_0 has CHAN0_LAST_NOTE_FLAG (bit 0x1000) set (last
		# dispatched byte was a Note, set by the post-walker look-ahead),
		# FFT overrides the release_byte to a fixed value of 6 and
		# schedules WALKER_FLAG_ADSR2_LOW so the next walker pass commits
		# it to the SPU:
		#   PC 0x800152A0  bne  v0, v1=1, skip      ; gate on note_duration == 1
		#   PC 0x800152A8  andi v0, t1, 0x1000      ; t1 = chan_word_0
		#   PC 0x800152AC  beq  v0, zero, skip
		#   PC 0x800152B0  ori  v0, zero, 0x6       ; release_byte = 6 (constant)
		#   PC 0x800152B4  lhu  v1, -0x2(a0)        ; v1 = walker_flag_word
		#   PC 0x800152B8  sh   v0, 0x64(a0)        ; chan+0x6A = 6
		#   PC 0x800152BC  ori  v1, v1, 0x80
		#   PC 0x800152C0  sh   v1, -0x2(a0)        ; commit walker_flag_word
		# Source of 74 walker-entry bit-0x80 sets per cure_no_music run
		# (verified via diag_walker_flag_word_writers — equal contribution
		# to the Note handler at PC 0x80015438). Without this, Godot
		# never re-commits the release rate at end-of-note, so SPU ADSR2
		# stays at whatever value it had after the last 0xC5 dispatch
		# (or 0 if no 0xC5 fired).
		# diag_adsr2_low_gate (Godot-only) — bisection probe for the
		# probe_adsr2_low_register 66/60 deficit on cure_4. Emits the
		# pre-decrement note_duration + chan_word_0 bit mask just
		# before the FFT release-prep gate at PC 0x800152A0..C0. Diff
		# against PCSX's diag_walker_flag_word_writers' bit-0x80 set
		# events to find cadences where FFT enters the gate and Godot
		# doesn't (or vice versa). Always fires on the note_active path
		# so we capture EVERY gate-eligible cadence regardless of
		# whether it actually fires; the gate_passed field tells us.
		var _adsr2_gate_passed: int = 0
		if channel.note_duration == 1 \
				and (channel.channel_word_0 & _SS.CHAN0_LAST_NOTE_FLAG) != 0:
			_adsr2_gate_passed = 1
		_ProbeCounters.diag_adsr2_low_gate += 1
		_Trace.emit("adsr2_low_gate", {
			"call_index": _ProbeCounters.diag_adsr2_low_gate,
			"channel_idx": channel.channel_idx,
			"note_duration_pre": channel.note_duration & 0xFFFF,
			"chan_word_0": channel.channel_word_0 & 0xFFFF,
			"gate_passed": _adsr2_gate_passed,
		})
		if _adsr2_gate_passed == 1:
			# iter-39: FFT PC 0x800152B8 writes the value 6 directly to
			# chan+0x6A — the same byte slot.release_rate_byte mirrors
			# after iter-32. The walker reader at spu_irq_walker.gd:383
			# pulls its rate input from release_rate_byte, NOT slot.adsr2,
			# so the rate-field write is the load-bearing one. The adsr2
			# update keeps Godot's SPU-mirror in sync defensively;
			# FUN_8001BAB8 re-commits the same low 6 on the next walker
			# IRQ. See docs/MUSIC_ITER39_ADSR2_END_OF_NOTE_FORCE_RATE_FIELD.md.
			slot.release_rate_byte = 0x06
			slot.adsr2 = (slot.adsr2 & 0xFFC0) | 0x06
			slot.walker_flag_word |= _SS.WALKER_FLAG_ADSR2_LOW
		# Deleted: a Godot-only periodic re-KEY workaround that lived
		# here, blocking the idle_timeout drain at line ~1113 from
		# firing FLAG_KOFF_PENDING (the workaround set chan_word_0
		# bit 0x400, which fails the drain's `chan_word_0 & 0x600 == 0`
		# gate). Removed once probe_kon_koff_mask bisection on
		# reraise_no_music pinned voice_18's 55 missing KOFFs to this
		# block. The idle drain now owns the byte_7A=16 case; KON
		# vs KOFF SPU-window race that the workaround was originally
		# papering over is handled by flush_kon_commit's deferred-
		# rotation (one-IRQ KON deferral via _deferred_kon_*) +
		# flush_koff_post_loop's same-IRQ KOFF commit — KOFF fires
		# at IRQ N, KON commits at IRQ N+1. See
		# FFT_GODOT_DATA_FLOW_ALIGNMENT.md §5.1.1.
		# FFT per_channel_tick PC 0x800151BC clears chan+0x88 every tick
		# (gated on note_duration != 0 by the outer beq at PC 0x800151B4).
		# This is the per-tick reset that lets FFT's mode-0 LFO dispatch
		# (LAB_8001759C..B0) effectively SET chan+0x88 via accumulate-from-
		# zero pattern: chan+0x88 = (chan+0x88_cleared = 0) + step. With
		# the clear here AND the every-tick LFO write in _advance_lfo,
		# Godot's pitch_bend tracks the current LFO step value across all
		# cadences (probe_per_channel_tick_exit confirmed chan+0x88 = 0
		# at every tick on PCSX, then chan+0x88 = step at FUN_80017118
		# iter — the LFO writes between exit and iter).
		#
		# probe_per_channel_tick_note_active — bisection probe at this PC.
		# Mirrors FFT BP @ 0x800151BC. Fires for every channel × tick
		# that passes BOTH gates (chan_word_0 != 0 + note_duration != 0).
		# Gated on _cadence_anchored to mirror PCSX's FIRST_OPCODE_FIRED.
		_ProbeCounters.per_channel_tick_note_active += 1
		_Trace.emit("per_channel_tick_note_active", {
			"call_index": _ProbeCounters.per_channel_tick_note_active,
			"chan_word_0": channel.channel_word_0 & 0xFFFF,
			"note_duration": channel.note_duration & 0xFFFF,
			"chan_88": channel.pitch_bend & 0xFFFF,
			"slot_idx": slot.slot_idx,
		})
		channel.pitch_bend = 0
		# Per-tick vol-burst handler — mirrors FFT per_channel_tick PC
		# 0x800151B8..0x800151E8. Gated on pre-decrement note_duration != 0
		# (the FFT outer gate at PC 0x800151B4 `beq v0, zero, LAB_800152fc`
		# where v0 = lh chan+0x74), so it lives inside this block. When
		# chan+0x6 bit 0x8 is set, decrement chan+0xa8 AND set chan_word_1
		# bit 0x100 unconditionally — the ori at PC 0x800151E4 is in the
		# bne delay slot, so it fires every iter regardless of the wrap
		# branch. When chan+0xa8 wraps to 0, clear the gate (PC 0x800151E8
		# andi chan+0x6, 0xfff7). Source of the 48-fire vol_lr_staging gap
		# (PCSX 126 vs Godot 78). Armed by opcode 0xE2 (smd_expression at
		# PC 0x80016680). See research/effect_alignment/
		# PER_CHANNEL_TICK_BIT100_ISSUE.md.
		if channel.vol_burst_active:
			channel.vol_burst_counter = (channel.vol_burst_counter - 1) & 0xFFFF
			channel.channel_word_1 |= _SS.CHAN1_VOL_PRESTAGE
			if channel.vol_burst_counter == 0:
				channel.vol_burst_active = false
				_ProbeCounters.diag_vol_burst_transition += 1
				_Trace.emit("vol_burst_transition", {
					"call_index": _ProbeCounters.diag_vol_burst_transition,
					"channel_idx": channel.channel_idx,
					"transition": "disarm",
					"cause": "counter_wrap",
					"counter": 0,
				})
			# Expression-acc ramp — mirrors FFT PC 0x800151EC..0x800151FC
			# (`lw v0, 0x92(a0); lw v1, 0x9a(a0); addu v0,v0,v1;
			# sw v0, 0x92(a0)` with a0=a1+0x6, so 0x92(a0)=chan+0x98 and
			# 0x9a(a0)=chan+0xa0). LAB_800151EC is the merge point of the
			# bne wrap branch, so the ramp ALWAYS runs when the bit-0x8
			# gate was set on entry — including the wrap tick where the
			# gate also clears. We piggyback on the same vol_burst_active
			# check because the FFT gate test (`andi v0, a3, 0x8`) at PC
			# 0x800151B8 reads chan+0x6 bit 0x8 BEFORE the andi clear at
			# PC 0x800151E8, so the ramp sees the pre-clear state.
			# FFT stores chan+0x98 as a signed 32-bit accumulator (s32).
			# We track it as a Python-style int and rewrap to s32 here so
			# the value matches FFT's overflow behavior.
			var new_acc: int = channel.expression_acc_s32 + channel.expression_delta_s32
			new_acc = new_acc & 0xFFFFFFFF
			if new_acc >= 0x80000000:
				new_acc -= 0x100000000
			var _ramp_pre: int = channel.expression_acc_s32
			channel.expression_acc_s32 = new_acc
			# probe_expression_ramp — paired with PCSX BP @ 0x800151FC
			# (`sw v0, 0x92(a0)` chan+0x98 commit). Emits the same three
			# s32 fields the PCSX probe back-computes from v0/v1
			# registers: pre-add, post-add, and the per-tick delta.
			# channel_idx is diagnostic-only (not in schema_keys) — lets
			# us group Godot rows by channel to compare against PCSX's
			# per-channel breakdown (120/96/115/115 on cure_4) and
			# pinpoint which channel's vol_burst disarms early.
			_ProbeCounters.expression_ramp += 1
			_Trace.emit("expression_ramp", {
				"call_index": _ProbeCounters.expression_ramp,
				"chan_98_pre": _ramp_pre,
				"chan_98_post": new_acc,
				"chan_a0_delta": channel.expression_delta_s32,
				"channel_idx": channel.channel_idx,
			})
	# Portamento target counter — mirrors FFT per-tick handler at PC
	# 0x80015214-0x80015230. When porta_active and bit 0x2 of chan+0x6
	# is clear, decrement slot+0xa6 (= portamento_target_counter); when
	# it reaches 0, clear portamento_active. FFT disasm at PC 0x80015208
	# `_andi v0,a3,0x2; bne v0,zero,LAB_80015234` (a3 = chan+0x6) skips
	# the decrement path when bit 0x2 is set, leaving porta active until
	# 0xDC terminates it. chan_6_bit_2 is toggled by 0xD5.
	if channel.portamento_active and (channel.channel_word_0 & 0x2) == 0 \
			and not channel.chan_6_bit_2 \
			and channel.portamento_target_counter > 0:
		channel.portamento_target_counter -= 1
		if channel.portamento_target_counter == 0:
			channel.portamento_active = false
	if channel.idle_timeout > 0 and (channel.channel_word_0 & 0x600) == 0:
		channel.idle_timeout -= 1
		if channel.idle_timeout == 0:
			# FFT per_channel_tick PC 0x800152C8-F8 idle_timeout drain:
			#   chan_word_1 |= 0x2     ; KOFF request this tick (FFT
			#                          ; PC 0x800173A0 reads this bit
			#                          ; in FUN_80017118 and OR-s chan+
			#                          ; 0x34 into the s5 KOFF mask)
			#   chan_word_0 |= 0x400   ; KON_ARM for NEXT tick (snapshot
			#                          ; captures this; next walker entry
			#                          ; sets FLAG_PRIMARY_KON via
			#                          ; _note_arm_kon's s2_snapshot)
			channel.channel_word_0 |= _SS.CHAN0_KON_ARM
			channel.channel_word_1 |= 0x2
			# Per probe_kon_koff_mask + probe_kon_koff_accumulator
			# investigation (KON_KOFF_STRUCTURAL_ISSUE.md): Godot
			# previously set FLAG_SECONDARY_KON here, which fired KON
			# this tick via flush_tick._commit_kon's s5 path. FFT does
			# the OPPOSITE — KOFF this tick (via chan_word_1 bit 0x2,
			# which flush_tick now treats as a KOFF trigger via
			# FLAG_KOFF_PENDING) and KON next tick (via chan_word_0
			# bit 0x400 propagating through s2_snapshot to
			# FLAG_PRIMARY_KON in _note_arm_kon).
			slot.flag_word |= _SS.FLAG_KOFF_PENDING

	# FFT per_channel_tick PC 0x80015234..0x80015244:
	#   lw   v0, 0x7a(a0)       ; v0 = chan+0x80 (pre_pitch_acc)
	#   lw   v1, 0x96(a0)       ; v1 = chan+0x9c (pre_pitch_delta)
	#   addu v0, v0, v1
	#   sw   v0, 0x7a(a0)
	# LAB_80015234 is reached whenever bit 0x1 of chan+0x6 was set at
	# entry (porta_was_active), regardless of porta_target_counter wrap
	# behavior. Must run BEFORE the opcode walker so that Note's
	# `pre_pitch_acc_u32 = baseline` reset at _handle_note overrides any
	# advance from a stale prior-tick state — matching FFT's order where
	# per_channel_tick fires entirely before smd_interpreter_tick.
	if _cb_porta_was_active and channel.pre_pitch_delta_u32 != 0:
		channel.pre_pitch_acc_u32 = (channel.pre_pitch_acc_u32 + channel.pre_pitch_delta_u32) & 0xFFFFFFFF

	# Pitch prestage — set BEFORE the porta deactivation can take effect for
	# this tick's recompute. FFT PC 0x80015210 (`_ori t0, t0, 0x200`) sets
	# bit 0x200 of chan_word_1 in the per_channel_tick handler's delay slot
	# AFTER confirming porta_active was true at entry, BEFORE the
	# target_counter decrement/clear. Setting it here (using _cb_porta_was_active,
	# captured at line 510 pre-decrement) matches FFT's pre-decrement gate.
	# Previously this lived in _recompute_pitch_staging gated on tick()'s
	# late-captured porta_was_active, which is false on the deactivation
	# tick — Godot then missed the pitch_staging recompute that FFT does on
	# that same tick (PCSX captures porta_active==true at per_channel_tick
	# entry → sets bit, then clears active after; flush_tick recomputes).
	# Manifests as voice 20's missing probe_walker_flag_word_entry row at
	# cad=241 on cure_4_no_music. See
	# PROBE_WALKER_FLAG_WORD_ENTRY_924_923.md.
	if _cb_porta_was_active:
		channel.channel_word_1 |= _SS.CHAN1_PITCH_PRESTAGE
		slot.walker_flag_word |= _SS.WALKER_FLAG_PITCH

	# Snapshot+clear (FFT FUN_80015324 L80015394-98). Gated on
	# note_duration == 0 because that's when bytecode dispatch runs.
	# Snapshot/clear + bytecode walker live here (per-fire order:
	# per_channel_tick → smd_interpreter_tick inside the sub-loop body,
	# PC 0x80014d38..0x80014d4c).
	# (probe_smd_interpreter_tick_entry is emitted at the function top
	# above, before the early-returns — see §4.1 problem A of
	# SMD_INTERPRETER_GATE_SKIP_EARLY_RETURN_DEFICIT.md.)

	var s2_snapshot: int = 0
	var walker_entered: bool = false
	if channel.note_duration == 0:
		s2_snapshot = channel.channel_word_0
		# probe_smd_interpreter_post_gates — bisection probe at this PC
		# equivalent of FFT 0x80015398 (post-gates, pre-byte-fetch).
		# Gated on `_Trace._first_dispatch_fired` to mirror PCSX's
		# FIRST_OPCODE_FIRED suppression: PCSX's BP at PC 0x80015398 fires
		# BEFORE the byte-fetch BP within the same first-tick call, so the
		# very first init dispatch is suppressed (flag still false). The
		# byte-fetch then flips the flag, and the SECOND init channel's
		# `post_gates` BP emits cleanly. Godot mirrors this exactly because
		# `_first_dispatch_fired` flips inside `_dispatch` (post-emit). See
		# PROTECT_2_6_WORD0_PASS_PREANCHOR_OVERCOUNT.md §2.7.
		if _Trace._first_dispatch_fired:
			_ProbeCounters.smd_interpreter_post_gates += 1
			_Trace.emit("smd_interpreter_post_gates", {
				"call_index": _ProbeCounters.smd_interpreter_post_gates,
				"chan_word_0_pre": channel.channel_word_0 & 0xFFFF,
				"chan_word_0_post": (channel.channel_word_0 & 0xf8ff) & 0xFFFF,
				"slot_idx": slot.slot_idx,
				"opcode_pos": channel.opcode_pos,
			})
		channel.channel_word_0 &= 0xf8ff  # clear bits 0x100, 0x200, 0x400
		walker_entered = true
		# Do NOT eagerly re-OR VOL_PENDING here. FFT's L80015524-30
		# SLUR→VOL propagation fires AFTER the bytecode walk in the
		# dispatcher's exit path. The propagation is now applied below
		# in the walker_entered post-block — gated correctly to match
		# FFT (was firing every tick in tick()'s _apply_slur_propagation,
		# leaking VOL_PENDING into chan_word_0 on non-dispatch ticks and
		# blocking the idle_timeout decrement at PC 0x800152C8 via the
		# `chan_word_0 & 0x600 == 0` gate).
	else:
		# probe_smd_interpreter_gate_skip — gate-2 fail mirror
		# (FFT entry to LAB_80015814 from PC 0x80015384 with
		# note_duration != 0). Helper classifies by current cw0/nd:
		# cw0 != 0 (always true here — cw0==0 early-returned above)
		# AND nd != 0 → which_gate=2.
		_ProbeEmit.emit_smd_interpreter_gate_skip_for_state(channel, slot)

	# Walk opcodes until delta-time exhausts the fire. Multiple control
	# opcodes (Tempo, Instrument, Dynamics, PitchBend) can run in the
	# same fire before the next Note. Note's delta_time becomes
	# note_duration for subsequent fires.
	var note_dispatched: bool = false
	while channel.opcode_pos < _events.size() and channel.note_duration == 0:
		var evt = _events[channel.opcode_pos]
		channel.opcode_pos += 1
		if evt is SMDOpcodes.NoteEvent:
			note_dispatched = true
		_dispatch(channel, slot, evt, s2_snapshot)

	# probe_smd_interpreter_gate_skip — post-walker fall-through mirror
	# (FFT XREF[2] from PC 0x80015718 `beq s4, zero, LAB_80015814`). The
	# walker has dispatched at least one opcode (Note advances
	# note_duration); the helper classifies by post-walker state — typically
	# cw0 != 0 AND nd != 0 → which_gate=2, matching the PCSX probe's BP-
	# time heuristic. See §6 of
	# SMD_INTERPRETER_GATE_SKIP_EARLY_RETURN_DEFICIT.md.
	if walker_entered:
		_ProbeEmit.emit_smd_interpreter_gate_skip_for_state(channel, slot)

	# Post-dispatch: FFT smd_interpreter_tick PC 0x80015478-90 sits INSIDE
	# the byte-<0x80 Note inline state setup (smd_note_state_setup @
	# PC 0x80015428..0x80015494). The byte-fetch dispatcher at PC
	# 0x800153A4-A8 (`sltiu v0, a1, 0x80; beq v0, zero, ...control...`)
	# branches byte>=0x80 (Rest 0x80, control ops 0xA0+) to the
	# smd_dispatcher_control_opcode path — those handlers return to
	# post_handler_check at PC 0x80015504 and never touch this OR site.
	#   andi v0, s2, 0x400               ; check s2_snapshot bit 0x400 (KON_ARM)
	#   beq  v0, zero, smd_note_kon_check
	#   lhu  v0, 0x0(s0)                 ; load chan_word_1
	#   ori  s4, zero, 0x1               ; (kon_active local flag — unused here)
	#   ori  v0, v0, 0x1                 ; chan_word_1 |= 0x1
	#   sh   v0, 0x0(s0)                 ; commit
	# Gate: a NoteEvent (FFT byte < 0x80, including rest-as-note and tie
	# variants which all share smd_note_state_setup) dispatched this tick
	# AND s2_snapshot (pre-clear chan_word_0) had bit 0x400.
	if note_dispatched and (s2_snapshot & _SS.CHAN0_KON_ARM) != 0:
		channel.channel_word_1 |= 0x1
		# FFT PC 0x80015488 sets s4 = 1 at the same gate; s4 is then
		# checked at PC 0x80015718 (later in per_channel_tick) to fire
		# the LFO sub-slot **period_reset** at PC 0x800157AC..0x80015804.
		# For each sub-slot with (dir & 0x3) == 0x3 (active + first-
		# segment), the reset clears acc, resets countdown to 1, clears
		# dir bits 0x4/0x8, and OR's chan_word_0 |= 0x100. Without this
		# reset the swap-path's `(dir | 0x4) ^ 0x8` toggle keeps drifting
		# direction (chan_8a sign-flip on protect_no_music). See
		# research/effect_sound/working_documents/
		# CHAN_8A_PAN_LFO_SIGN_FLIP_INVESTIGATION.md.
		_PerTickLfoPeriodReset.apply(channel)

	# FFT smd_dispatcher PC 0x80015524-30 — SLUR→VOL_PENDING propagation:
	#   lhu  v1, 0x0(s1)               ; chan_word_0
	#   andi v0, v1, 0x800              ; check SLUR_PENDING
	#   beq  v0, zero, LAB_80015534
	#   ori  v0, v1, 0x200              ; v0 |= VOL_PENDING
	#   sh   v0, 0x0(s1)                ; commit
	# This is INSIDE the dispatcher's exit path (after the byte-fetch
	# loop completes), so it only fires on cadences where the walker
	# actually entered — i.e. when note_duration was 0 at snapshot time.
	# Previously called unconditionally from tick() which leaked
	# VOL_PENDING (0x200) into chan_word_0 on every cadence; that bit
	# fails the `chan_word_0 & 0x600 == 0` gate at the idle_timeout
	# block (PC 0x800152C8), blocking bit-0x2 set events FFT fires.
	# probe_slur_propagation_pre. Mirrors FFT PC 0x80015524, which only
	# executes when the walker exited via the `while ((chan_word_0 &
	# 0x500) == 0)` loop condition (i.e., bit 0x100 or 0x400 of
	# chan_word_0 was set by a Note/Rest dispatched this tick). We mirror
	# that gate exactly so row counts pair.
	if walker_entered and (channel.channel_word_0 & 0x500) != 0:
		_ProbeCounters.slur_propagation_pre += 1
		_Trace.emit("slur_propagation_pre", {
			"call_index": _ProbeCounters.slur_propagation_pre,
			"chan_word_0": channel.channel_word_0,
			"channel_idx": channel.channel_idx,
			"note_duration": channel.note_duration & 0xFFFF,
		})

	if walker_entered \
			and (channel.channel_word_0 & _SS.CHAN0_SLUR_PENDING) != 0:
		var _cw0_pre: int = channel.channel_word_0
		channel.channel_word_0 |= _SS.CHAN0_VOL_PENDING
		_ProbeCounters.slur_propagation += 1
		_Trace.emit("slur_propagation", {
			"call_index": _ProbeCounters.slur_propagation,
			"chan_word_0_pre": _cw0_pre,
			"chan_word_0_post": channel.channel_word_0,
		})

	# FFT smd_dispatcher post-walker look-ahead (PC 0x80015534-0x80015694).
	# Peeks events forward from channel.opcode_pos without dispatching them,
	# follows coda/loop redirects, and decides chan_word_0 bits 0x200 and
	# 0x1000 from what kind of byte terminates the chain. See
	# research/effect_sound/working_documents/POST_WALKER_LOOKAHEAD.md.
	if walker_entered:
		_PerTickPostWalkerLookahead.apply(self, channel)

	# probe_lfo_handler_* — emit at cadence_body BOTTOM, AFTER opcode
	# dispatch + _apply_lfo_period_reset + _post_walker_lookahead.
	# Matches PCSX BP @ PC 0x800174C8 (lfo_handler_tick per-channel loop
	# top), which fires AFTER smd_interpreter_tick + per_channel_tick
	# inside the LAB_80014CCC entity-catchup sub-loop. cadence_body is
	# Godot's analog of (smd_interpreter_tick + per_channel_tick) and
	# runs at the same cadence (per catchup-iter × 8 slots) — emitting
	# here preserves PCSX's cardinality AND captures post-dispatch
	# chan+0x82 / chan+0x88 state. (Earlier placement at cadence_body
	# top captured PRE-dispatch state, producing 1-IRQ-stale reads.
	# Move to tick() was considered but rejected — tick() fires per
	# sub-tick × bound, NOT per catchup-iter × bound, so cardinality
	# would diverge by ~4.5×.) See PROBE_LFO_HANDLER_RELOCATION_PLAN.md.
	_ProbeEmit.emit_lfo_handler_probes(channel)


func _dispatch(channel: _CH, slot: _SS, evt, s2_snapshot: int) -> void:
	# probe_event_dispatch (GOLD #2). Mirror of FFT BP @ 0x800153A4 (per-event
	# byte-fetch site inside smd_interpreter_tick). FFT a1 = the byte; here
	# byte = velocity for NoteEvent (which encodes the note byte 0x00..0x7F)
	# or opcode for OpcodeEvent.
	# First event_dispatch fire is the cadence anchor (mirroring
	# probe_event_dispatch.lua on PCSX side). Reset cadence counters
	# BEFORE the trace emit so this probe's first row reads cadence_index=0.
	# The flag lives on _Trace so spu_irq_walker / other layer-5 probes
	# can read it without a cross-file static import.
	if not _Trace._first_dispatch_fired:
		_Trace._first_dispatch_fired = true
		_Trace._cadence_index = 0
	_ProbeCounters.event_dispatch += 1
	if evt is SMDOpcodes.NoteEvent:
		var nev := evt as SMDOpcodes.NoteEvent
		_Trace.emit("event_dispatch", {
			"call_index": _ProbeCounters.event_dispatch,
			"event_type": "note",
			"byte": nev.velocity & 0xFF,
			"slot_idx": slot.slot_idx,
			"is_silent": channel.is_silent_driver,
		})
		_NoteHandler.apply(self, channel, slot, nev, s2_snapshot)
	elif evt is SMDOpcodes.OpcodeEvent:
		var oev := evt as SMDOpcodes.OpcodeEvent
		_Trace.emit("event_dispatch", {
			"call_index": _ProbeCounters.event_dispatch,
			"event_type": "opcode",
			"byte": oev.opcode & 0xFF,
			"slot_idx": slot.slot_idx,
			"is_silent": channel.is_silent_driver,
		})
		_handle_opcode(channel, slot, oev)


func _handle_opcode(channel: _CH, slot: _SS, op: SMDOpcodes.OpcodeEvent) -> void:
	# Silent driver gates voice-side state writes. Channel-side state
	# (octave, byte_76, byte_7A, loop_stack, channel_word_*, lfo_*) still
	# updates so the dispatcher can walk bytecode correctly.
	#
	# Refactor Pass 3: dispatch goes through Dictionary[int, Callable]
	# in opcodes/_table.gd — the literal analog of FFT's
	# smd_opcode_jumptable @ 0x80028B0C. Handler bodies still live on
	# this class for now; Pass 4 migrates them into opcodes/*.gd one
	# cluster at a time.
	var voice_writes: bool = not channel.is_silent_driver
	_OpcodeTable.dispatch(op.opcode, self, channel, slot, op, voice_writes)


static func emit_smd_interpreter_inactive(slot_idx: int) -> void:
	_ProbeEmit.emit_smd_interpreter_inactive(slot_idx)


static func emit_lfo_handler_inactive(slot_idx: int, residue: Dictionary = {}) -> void:
	_ProbeEmit.emit_lfo_handler_inactive(slot_idx, residue)


