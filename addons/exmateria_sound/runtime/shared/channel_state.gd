class_name SharedChannelState
## Per-channel bytecode-runner state — corresponds to one FFT feds channel
## struct (each ~0x160 bytes per stride observation).
##
## Mirrors the FFT architecture where a CHANNEL holds bytecode position +
## per-channel runtime state, and writes its flag bits to a separate per-
## voice slot via a `target_voice_idx` route. Multiple channels CAN share
## a target voice — the audible pair's slot_a channel and a silent driver
## pair's slot_a channel may both contribute flag bits to the same SPU
## voice. The flush layer (flush_tick.gd) then issues one set of SPU
## writes per voice, regardless of how many channels contributed.

# --- Routing identity ---
var channel_idx: int = 0          # 0..7 (4 pairs × 2 channels)
var target_voice_idx: int = -1    # 16..23 SPU voice this channel drives
# Silent-driver channels (FFT mode `00`) overlay onto an audible voice's
# slot. They contribute FLAG_PRIMARY_KON / SECONDARY_KON arm bits via OR
# (mirroring FFT kon_accum), but their stream-end behavior MUST NOT
# key_off the shared SPU voice — only the audible pair's stream-end
# KOFF should affect SPU output. The dispatcher's end-of-stream path
# gates FLAG_KOFF_PENDING + STREAM_END on this flag.
var is_silent_driver: bool = false
# FFT chan+0x92 — env-multiplier slot read by the vol formula at
# FUN_80017118 PC 0x800171f4-L80017208. Written at PC 0x80013D2C
# (`sh t1, 0x60(s0)`) inside FUN_80013B20's per-channel init loop;
# the value is `clamp((a2 * instr_byte) >> 7, 0, 0x7FFF)` where a2 =
# 0x6000 (constant from all 3 FUN_80013B20 callers at 0x80012548,
# 0x80012590, 0x800125F0) and instr_byte is a byte from the sound-
# engine table at `*DAT_80032A00 + halfword(s5+0xc) + sound_id`.
# For cure_4_no_music (sound_id 4), instr_byte = 0x60, giving
# chan_92 = (0x6000 * 0x60) >> 7 = 0x4800 = 18432 across all 4 voices.
# The Note pre-pass (PC 0x800153C4) and 2-byte opcode handlers
# (0x800168AC / 0x800168D8) can also write chan+0x92, but
# diag_chan_92_writers.lua on cure_4 confirmed only the engine-init
# writer fires for this effect — see VOL_FORMULA_INPUTS_PARITY_PLAN.md
# Step 1 results / research/effect_sound/working_documents/
# VOICE_18_CHAN_92_SILENCE.md.
# Default 18432 is the cure_4-specific value (instr_byte 0x60). The plan
# (CHAN_92_STATIC_PORT_PLAN.md §7.4) called for switching to 0 once the
# FEDS lookup is the primary seed, but a default-0 introduces audible
# residue divergence on protect_no_music (full_mix cos_dist jitter
# ~0.05) — likely via the dispatcher.gd:1520 "first Note before tones"
# writer reading whatever the default is during the pre-Note window. Left
# at 18432 until that interaction is understood; the FEDS lookup still
# overwrites this value at bind time when a sound_id is provided.
var chan_92_value: int = 18432
# FFT chan+0x88 — vol-LFO accumulator output. Read by the vol formula at
# FUN_80017118 PC 0x800171C8 (`lh v0, 0x88(s0)`) and added to chan+0x98
# inside the env_sample clamp. Written per-tick by lfo_handler_tick's
# mode-1 path at PC 0x800175C8 (`sh v0, 0x88(s0)`). Pre-cleared every
# cadence by per_channel_tick PC 0x800151BC so the net value per tick
# is the LFO callback's contribution for that tick.
var chan_88_value: int = 0
# FFT chan+0x8a — pan-LFO accumulator output. Read by the vol formula
# at PC 0x80017214 (`lh v1, 0x8a(s0)`) and added to chan+0x90 + pool+0xAE
# inside the pan_arg clamp. Written per-tick by lfo_handler_tick's
# mode-2 path at PC 0x800175DC. Same per-tick pre-clear semantics as
# chan_88_value.
var chan_8a_value: int = 0
# Tracks the value FFT opcode 0xD6 (LAB_800163EC) writes to chan_base+0x90
# via `sh v0, 0x90(a2)` (a2 = chan_base in the dispatcher). Default 0x4000
# matches the cure_no_music init observation.
#
# IMPORTANT NAMING NOTE: this field is NOT the same as the "chan_90" field
# the probe_vol_inputs Lua reads (`s0+0x90` where s0=slot_base=chan_base+2
# in FUN_80017118, per PC 0x80017188 `addiu s0,s3,0x2`). The probe's
# "chan_90" reads chan_base+0x92 (FFT-naming "slot+0x90" = the env-multiplier
# / pan-baseline). D6's write target (chan_base+0x90 = "slot+0x8E") has
# NO known downstream reader in our current Godot pan formula — so this
# field is a parity-shadow at the state-tracking level. Integrating D6's
# audible effect requires finding the FFT consumer of chan_base+0x90;
# out of scope for the initial Haste / E032 opcode coverage patch.
var chan_90_value: int = 0x4000
# One-shot flag so stream-end KOFF fires exactly once per audible-primary
# channel. Without this, after opcode_pos >= events.size the dispatcher
# would re-fire FLAG_KOFF_PENDING + FLAG_STREAM_END every tick, spamming
# SPU key_off on the shared voice and gating out any subsequent primary
# KONs from silent-driver overlays.
var stream_end_fired: bool = false
# Persistent end-of-spell flag for pitch-flush re-emission at kill chain.
# Mirrors FFT's PC 0x800159ac (`ori v0, v0, 0x54; sh v0, 0x4(a2);
# sh zero, 0x0(a2)`) which sets chan+0x04 bit 0x4 (= FLAG_PITCH_UPDATE)
# THEN deactivates chan+0x00=0. The bit persists through the silent
# period (FFT skips deactivated channels in FUN_80014590) until the
# kill chain reactivates, at which point FUN_80014590 fires the SPU
# pitch register write. In Godot, slot.flag_word is cleared every tick
# by clear_per_tick_flags(), so we cannot use it for this persistent
# purpose. This channel-side field survives per-tick clearing and gets
# translated back to slot.flag_word |= FLAG_PITCH_UPDATE at the kill-
# chain reactivation event.
var pending_kill_pitch_flush: bool = false
# When this audible-primary channel's bytecode ends but a silent-driver
# overlay still drives the same SPU voice, the stream-end KOFF must NOT
# fire — otherwise the voice releases prematurely. Set by
# play_silent_driver_pair on the audible primary it overlays.
# In FFT, KOFF for these voices is timeline-driven (effect-end), not
# per-channel-stream-end; this flag approximates that.
var has_silent_overlay: bool = false

# --- Bytecode runner state ---
var opcode_pos: int = 0
var loop_stack: Array = []        # Repeat/Coda stack: {count, back_pos, octave}

# Godot analog of FFT slot+0x1c (saved-Repeat-target pointer).
# Mirrors the value set by opcode 0x91 (L800159DC `sw v0, 0x1c(a2)`).
# Used by the 0x90 EndBar handler's clear-vs-skip predicate (L80015900
# `beq v0, zero, LAB_80015924`). 0 = no active loop target → fall
# through to clear path (L800159CC clearer). Non-zero = loop target
# saved → skip clearer.
# This CANNOT be substituted with `loop_stack.is_empty()` — Godot's
# loop_stack tracks 0x98 Repeat (different opcode, different lifecycle).
# Cleared at play_sound init (mirroring PC 0x80013CF8 `sw zero, -0x18(s0)`).
var saved_loop_target_pos: int = 0

# --- Channel flag words (FFT channel+0x0 / channel+0x2) ---
var channel_word_0: int = 0
var channel_word_1: int = 0

# --- Per-Note timing state ---
var note_duration: int = 0        # FFT channel+0x72/0x74
var idle_timeout: int = -1        # FFT channel+0x78

# FFT entity+0x74 / entity+0x78 sub-tick-budget mirror.
# Algorithm per RCnt2 fire (240 Hz on PCSX):
#     sub_tick_acc -= sub_tick_budget         # signed s32
#     while sub_tick_acc < 0:                 # underflow loop
#         <fire dispatcher chain>             # mirrors FFT cadence_fired body
#         sub_tick_acc += 0x10000
# Effect-entity sub_tick_budget = 0x6600 (= 26112) static.
var sub_tick_acc: int = 0          # FFT entity+0x74 (s32 rolling acc)
var sub_tick_budget: int = 0x6600  # FFT entity+0x78 (effect = 0x6600 static)

# --- byte_76 / byte_7A formula state ---
var byte_76: int = 0              # FFT channel+0x76, modified by 0xAD
var byte_7A: int = 15             # FFT channel+0x7A, set by 0xA9 (default 15)

# --- Pitch state (per-channel formula inputs) ---
var pitch_bend: int = 0           # signed -32768..32767
var pre_pitch_acc_u32: int = 0
var pre_pitch_delta_u32: int = 0
var portamento_active: bool = false
# FFT slot+0x84. Read as the third addend in the Note handler's
# acc-baseline computation at L80015450 (`addu v0, v0, a0` where
# a0=lh slot+0x84 via `lh a0, 0x82(s0)` with s0=slot+0x2). This field =
# inst.fine_tune (already modeled in slot.fine_tune via the 0xAC handler
# reading inst.fine_tune from waveset).
var word_84: int = 0
# FFT slot+0x7C low byte. Read at L800153dc as `lbu v0, 0x7c(s0)` where
# s0=slot+0x2 (BP frame), so abs offset slot+0x7E. Used in Note-handler
# natural-MIDI byte computation:
#   a1 = (slot+0x7E_low + lookup_e70[key]) & 0xFF
# Godot's existing `midi_note = octave*12 + relative_key` produces the
# same a1 value when the bytecode key + lookup_e70 entries + slot+0x7E
# init are all coherent. FFT writers live at 0x80013880
# (sw 0x00660000), 0x800139dc (sh 0xFFFF), 0x80015170 (per-tick
# handler, sw with low halfword zeroed), 0x80015cc4 (opcode 0xA0,
# sw mult << 16), 0x80015cf0 (opcode 0xA1, sw add preserving low
# halfword). Default = 0.
var bmidi_baseline_byte: int = 0
# FFT slot+0x86. Read as the second addend in the Note baseline
# (L80015444 `lh v1, 0x84(s0)`). channel.pitch_bend ≡ slot+0x88 (LFO),
# NOT slot+0x86. slot+0x86 is a separate slow-modulation accumulator
# that ramps.
var word_86: int = 0
# FFT slot+0xa6 — per-tick decrementing target counter that
# auto-clears portamento_active when it reaches 0. Mirrors the FFT
# per-tick handler at PC 0x80015214 (decrement) / PC 0x80015230 (clear
# bit 0x1 of slot+0x6). Initialized to D4's `target` param byte on the
# D4 init at dispatcher.gd. Skipped when bit 0x2 of channel_word_0 is
# set (FFT gate at PC L8001520c bypasses the counter logic). -1 = inactive.
var portamento_target_counter: int = -1
# FFT chan+0x6 bit 0x2 — porta-counter "no auto-terminate" gate. Toggled
# by opcode 0xD5 (LAB_800163BC: xori chan+0x6, 0x2). Read by per-channel
# tick at PC 0x80015208 (`_andi v0, a3, 0x2; bne v0, zero, LAB_80015234`):
# when set, skip the porta target-counter decrement/clear path so
# portamento runs indefinitely until terminated by 0xDC (clears bit 0x1)
# or a fresh 0xD4. Default false matches FFT init (chan+0x6 = 0 at engine
# setup).
var chan_6_bit_2: bool = false
# FFT chan+0x6 bit 0x8 — vol-burst gate. Set by opcode 0xE2
# (smd_expression at PC 0x80016680; the bit-0x8 OR is at PC 0x800166B4
# `ori v0, v0, 0x8; sh v0, 0x6(a2)`). Cleared by the per-tick handler
# at PC 0x800151E8 when the burst counter wraps to 0. See
# research/effect_alignment/PER_CHANNEL_TICK_BIT100_ISSUE.md. (The doc
# names this opcode 0xE1 following an off-by-one Ghidra annotation;
# the FFT dispatcher arithmetic at PC 0x800154e4 routes byte 0xE2 to
# smd_expression — 0xE1 → LAB_80016640 which CLEARS bit 0x8.)
var vol_burst_active: bool = false
# FFT chan+0xa8 — vol-burst countdown seed. Set by 0xE2 to param[0]
# (PC 0x800166B0 `sh a3, 0xa8(a2)`). Decrements each tick while
# vol_burst_active is true (PC 0x800151D4-D8); when the post-decrement
# value reaches 0 the gate is cleared. FFT stores it as a halfword
# (sh), but we always clear the gate at hit-zero so the 0xFFFF
# underflow path is never reached in practice.
var vol_burst_counter: int = 0
# FFT chan+0x98 — 32-bit expression accumulator (signed). Set
# instantaneously by 0xE0 smd_dynamics (PC 0x80016620 `sw byte<<24,
# 0x98(a2)`) and by 0xE2 smd_expression's per-tick ramp at PC
# 0x800151F8 (`addu chan+0x98, chan+0x98, chan+0xa0` — runs every
# tick the bit-0x8 gate was set on entry, before the wrap clear).
# Read by the vol drainer FUN_80017118 at PC 0x800171c4
# (`lh v1, 0x98(s0)` — LOW halfword, signed; populates only as
# the expression burst ramps, since 0xE0 leaves the low bytes 0).
# FFT initializes chan+0x98 to 0x7F000000 (= 127 << 24, the
# default max-volume seed) at engine setup via FUN_80012F08 from
# spu_updater_tick (PCs 0x8001223C / 0x800122CC). Channels that
# receive an 0xE0 dispatch then have this overwritten by
# byte<<24; channels without an E0 (e.g., cure_4 slot 4 in PCSX
# 0x80037718) keep the 0x7F000000 default — and the next 0xE2 on
# that channel reads it as the source, computes delta != 0, and
# arms vol_burst. Earlier this defaulted to 0, which caused E2
# on E0-less channels to early-return at the delta == 0 check —
# costing ~115 expression_ramp fires and ~115 vol_inputs fires
# on cure_4. See VOL_FORMULA_GATE_DEFICIT.md.
var expression_acc_s32: int = 0x7F000000
# FFT chan+0xa0 — 32-bit per-tick expression ramp delta (signed).
# Set by 0xE2 smd_expression (PC 0x800166BC `sw v1, 0xa0(a2)` where
# v1 = ((sb_param[1] << 24) - chan+0x98) / param[0]). Consumed by the
# per-tick ramp at PC 0x800151F0 (`lw v1, 0x9a(a0)` with a0=a1+0x6).
# Holds the (target - current) / duration step that drives the burst.
var expression_delta_s32: int = 0
var pitch_state: int = 0          # FFT channel+0x82 — current pitch reference

# SFX-only pan field. Comment was historically wrong: FFT 0xE8 Pan
# writes chan+0x92 (see iter-54), and chan+0xae is the lfo subslot
# index (0xF0 LAB_80016B08). The SFX vol formula in play_sound.gd:1579
# adds 0x4000 baseline explicitly, so this field stores the byte-scale
# offset and defaults to 0. Music's pan baseline lives in the separate
# `chan_92_pan_baseline` field below — they were conflated pre-iter-54.
var pan_offset_ae: int = 0
# FFT chan+0x92 — the pan baseline read by the FFT vol formula
# (FUN_80017118 @ PC 0x80017210, `lh v0, 0x90(s0)` with s0=chan+0x2).
# Music's 0xE8 smd_pan handler writes `byte << 8` here (0x4000 = center).
# PCSX inherits this value from the savestate; render_music_wav.gd's
# savestate seed propagates it. Default 0x4000 = CENTER pan so primary
# music channels (which don't carry per-channel savestate seed) get a
# sane baseline instead of hard-left. See MUSIC_ITER54_STEREO_PAN_BASELINE.md.
var chan_92_pan_baseline: int = 0x4000

# Pass 7.B.reverb — per-voice reverb-send enable. Models the bit FFT's
# 0xBA `smd_reverb_on @ 0x800160E4` sets in chan+0x70 (per-pool voice
# mask). The SFX side's `flush_tick.gd::reverb_enabled` is currently
# hardcoded to `is_primary` because the chan+0x70 mask wasn't modeled
# at all — adding this field carves out space for the proper model
# when SFX-side reverb parity work lands. Music dual-writes from
# its 0xBA/0xBB opcodes and reads here for the note_handler's
# voice_reverb routing decision.
var reverb_send_enabled: bool = false

# --- LFO state (per-channel) ---
# Iter-35: previously held flat lfo_* fields for sub-slot 0 (the pitch-
# LFO callback driven by 0xD8 / 0xD9 SFX). Unified onto the per-sub-slot
# arrays below (lfo_sub_*[0]) so all 4 FFT sub-slots share the same
# chan+0xE0..0x15F layout. See
# docs/MUSIC_ITER35_PITCH_LFO_SUBSLOT0_UNIFICATION.md.

# Per-channel LFO sub-slots (FUN_8001749C call-stack alignment).
# FFT's FUN_8001749C iterates 4 sub-slots per channel/slot, each with its
# own countdown / depth / depth_delta / mode_byte / active_flag state at
# chan+0xF4 / +0xF8 / +0xFA / +0xFC / +0xFE for slot 0; subsequent slots
# stride by 0x20 (per disasm 0x800174e0..0x80017584). Each sub-slot can
# be in mode 0 (pitch LFO → chan+0x86), mode 1 (vol-L → chan+0x88), or
# mode 2 (vol-R → chan+0x8a). No fire when active==0 OR mode ∉ {0,1,2}.
#
# Godot stores 4 sub-slots as parallel arrays. Initial state matches FFT
# savestate (all zero / inactive unless seeded by session-specific path).
# Iter-35: sub-slot 0 (driven by 0xD8 / 0xD9 SFX) now also uses
# lfo_sub_*[0] — previously held in flat lfo_* fields.
const LFO_SUB_SLOT_COUNT: int = 4
var lfo_sub_countdown: PackedInt32Array      # 4 entries, per-tick decrement
var lfo_sub_depth: PackedInt32Array          # 4 entries, scales step output
var lfo_sub_depth_delta: PackedInt32Array    # 4 entries, depth += this each fire
var lfo_sub_mode: PackedByteArray            # 4 entries: 0=vol, 1=pitch, 2=vol_alt
var lfo_sub_active: PackedByteArray          # 4 entries, bit 0x1

# pitch_accum_callback state machine mirror (FFT PC 0x80017744).
# Stored s32 because the source value is param[1]<<24 (potentially
# negated), divided by param[0], which exceeds s16 range. Per-tick
# the LFO advances `accumulator += step_current`; on inner-countdown
# wrap the swap path reloads countdown (optionally doubled) and
# optionally negates the step. The lfo_handler_tick mode dispatch
# then writes (accumulator >> 16) into chan+0x88 / chan+0x8a.
var lfo_sub_step_source: PackedInt32Array    # 4 entries, signed s32; arm-time `pitch_lfo_step_calc` result
var lfo_sub_step_current: PackedInt32Array   # 4 entries, signed s32; per-tick step, may be negated
var lfo_sub_accumulator: PackedInt32Array    # 4 entries, signed s32; running accumulator (a0+0x4)
var lfo_sub_inner_reload: PackedInt32Array   # 4 entries, period reload (a0+0x12 = param[0])
var lfo_sub_dir_flags: PackedByteArray       # 4 entries, chan+0x1e mirror (bits 0x4 / 0x8 → double / negate)
# Per-sub-slot delay-reload value (FFT subslot+0x16). Set by 0xD9 init
# (PC 0x800164B0 `sh v1, 0xf6(s0)`), 0xF0 (= 0), 0xE4 (= param[2]),
# and 0xF2 (= param[0]). Source for delay_counter reload on period_reset
# (PC 0x80016DE0 `sh v1, 0x14(a0)`). Iter-35 renamed from
# `lfo_sub_outer_delay` for FFT-faithful naming.
var lfo_sub_delay_reload: PackedInt32Array   # 4 entries
# Per-sub-slot delay countdown (FFT subslot+0x14). Reloaded from
# delay_reload by pitch_lfo_period_reset (PC 0x80016DE0). Gates the
# per-tick callback at PC 0x800174F8-518 — when non-zero, decrement
# and skip the callback this tick (= no accumulator advance, no
# countdown decrement). Iter-35 added (was missing on sub-slot 0).
var lfo_sub_delay_counter: PackedInt32Array  # 4 entries
# Per-sub-slot LFO callback variant (FFT jumptable PTR_LAB_80028f54
# index = p2 & 0xf at 0xE5/0xED arm time). Default 3 = pitch_accum_
# callback (triangle with doubling — the most common). cure_4's voice
# 19/18 re-arms use index 4 (sawtooth) which has different cd-zero
# semantics: resets accumulator to 0 instead of swap+accumulate.
var lfo_sub_callback_idx: PackedByteArray    # 4 entries, 0..15

# --- Octave / instrument-staging ---
var octave: int = 4
var stored_AC_param: int = 0      # FFT channel+0x2c
var stored_param_lo: int = 0      # FFT channel+0x2c/0x2e (effect-load)
var stored_param_hi: int = 0

# Per-channel instrument state. Set by 0xAC; mid-effect ADSR modifiers
# (0xC4, 0xC5, 0xC7) must also write channel.adsr1/adsr2 so the per-
# channel state stays in sync with slot.* (which the modifiers also
# touch). At Note dispatch, _handle_note copies channel.* → slot.* so
# each channel's KON loads its own instrument.
var instrument_idx: int = -1
var sample_start_addr: int = 0
var sample_loop_addr: int = 0
var fine_tune: int = 0
var adsr1: int = 0
var adsr2: int = 0
# FFT slot+0x58 / slot+0x5c / slot+0x60 — ADSR2 mode bytes from
# instrument data (loaded at 0xAC dispatch). Walker reads slot+0x5c
# for ADSR2 LOW writer mode mapping (FUN_8001BAB8 with a2 = slot+0x5c).
# iter-24 fix: prior to this iter, the WAVESET parser dropped these
# bytes during parse. See docs/MUSIC_ITER24_WAVESET_MODE_BYTES_DROPPED.md.
var mode_byte_58: int = 0
var mode_byte_5c: int = 0
var mode_byte_60: int = 0
# FFT slot+0x60: byte stored by opcode 0xCA (`sw v1, 0x60(a2)` at
# PC 0x800162B0). FUN_8001BAB8 reads this as the `a2` mode selector
# when rewriting ADSR2 low 6 bits — 3 → mode_bits=0, 7 → mode_bits=0x20,
# else → 0. Default 0 = linear release.
var adsr2_mode_byte: int = 0
# FFT slot+0x6A mirror (channel-side). Set by 0xC5 (raw operand) and
# by instrument-load (waveset byte 3 low 5 bits). Music's note_handler
# copies this to slot.release_rate_byte at Note dispatch; SFX's
# shared/opcodes/instrument.gd does the channel→slot copy inline.
# See docs/MUSIC_ITER32_ADSR2_LOW_RELEASE_BYTE_FIELD_SOURCE.md.
var release_rate_byte: int = 0

# --- Cadence/phase tracking (dispatcher-rate vs flush-rate) ---
var tick_phase: int = 0

# FFT slot+0x16 dispatch gate (per disasm L80014d24:
# `lbu s1, 0x16(s0); beq s1, zero, LAB_80014d70` — when zero, skips
# all per-tick channel jals including the bytecode walker
# FUN_80015324). Defaults to true (current Godot behavior: walk
# unconditionally).
var dispatch_enabled: bool = true

# --- Deprecated/compat (slot still has these) ---
var ttl_sub_ticks: int = -1


func _init(idx: int = 0, target_voice: int = -1) -> void:
	channel_idx = idx
	target_voice_idx = target_voice
	# Iter-28: corrected the iter-26 framing. FUN_8001749C uses
	# `s0 = chan_base + 2` (PC 0x800174B4 `addiu s0,s4,0x2`), so the
	# `sh v0, 0x86(s0)` mode-0 store at PC 0x800175B0 writes effective
	# chan+0x88 (= channel.pitch_bend) — Godot's outer-LFO routing is
	# CORRECT, not "writes word_86" as iter-26 framed.
	#
	# Iter-33: sub-slot 1 + 2 depth defaults → 0 (was 256). FFT
	# FUN_800138AC's LFO sub-slot init loop at PC 0x80013A70-84 only
	# zeroes offset 0x1E (active_dir) of each sub-slot; depth (offset
	# 0x18) and depth_reload (offset 0x1A) inherit allocation BSS-zero
	# = 0. probe_lfo_subslot{1,2}_state showed 26,300 Δ=+256 paired-row
	# divergences each on MUSIC_10 (Godot 256 vs PCSX 0). Sub-slot 0
	# stays at 256 — advance_lfo.gd:203's `if depth < 0x100` branch
	# selects the no-scale path at 256; iter-28's "no-scale branch"
	# justification applies to slot 0 only (slot 0's probe hardcodes
	# depth=0 emit, hiding RAM divergence; out of scope here).
	# See docs/MUSIC_ITER33_LFO_SUBSLOT_DEPTH_DEFAULT.md.
	# The previous `mode = [0,1,2,0]` default was a Godot-only
	# invention with no FFT basis (FUN_8001749C doesn't seed mode
	# bytes; only the arm opcodes 0xC9/0xCA/0xE5 / instrument-load
	# write them). PCSX probe_lfo_subslot{1,2}_state shows mode=0 in
	# 100% of rows on MUSIC_34. Switching the default mode to
	# [0,0,0,0] closes the 9704-row "mode" half of the subslot 1/2
	# divergence without changing audio: the sub-slot iterator at
	# advance_lfo.gd:222 already gates `if mode != 1 and mode != 2:
	# continue`, so default mode=0 → continue, the math doesn't run.
	# Same audio as default mode=1/2 with active=0 (which also skips
	# earlier at the active gate). See iter-28 doc for that arm.
	lfo_sub_countdown = PackedInt32Array([0, 0, 0, 0])
	# Iter-37 Bug B: sub-slot 0 depth/depth_delta defaults → 0 (was 256).
	# FFT FUN_800138AC PC 0x80013A70-84 only zeroes chan+0xFE (active_dir);
	# chan+0xF8 (depth) and chan+0xFA (depth_reload) inherit BSS-zero = 0.
	# The previous default=256 worked-around the advance_lfo.gd:219 `depth
	# < 0x100` no-scale gate but caused 52,600 paired-row divergences on
	# MUSIC_10 (no D8/D9 dispatch). Tightly coupled with Bug C — D8/D9 init
	# now writes 0x100 explicitly. See MUSIC_ITER36_PITCH_LFO_DEPTH_EXPOSED_BUGS.md §2.
	lfo_sub_depth = PackedInt32Array([0, 0, 0, 0])
	lfo_sub_depth_delta = PackedInt32Array([0, 0, 0, 0])
	lfo_sub_mode = PackedByteArray([0, 0, 0, 0])
	lfo_sub_active = PackedByteArray([0, 0, 0, 0])
	lfo_sub_step_source = PackedInt32Array([0, 0, 0, 0])
	lfo_sub_step_current = PackedInt32Array([0, 0, 0, 0])
	lfo_sub_accumulator = PackedInt32Array([0, 0, 0, 0])
	lfo_sub_inner_reload = PackedInt32Array([0, 0, 0, 0])
	lfo_sub_dir_flags = PackedByteArray([0, 0, 0, 0])
	lfo_sub_delay_reload = PackedInt32Array([0, 0, 0, 0])
	lfo_sub_delay_counter = PackedInt32Array([0, 0, 0, 0])
	# Default to idx 3 = pitch_accum_callback (triangle with doubling).
	# 0xE5/0xED overwrite this from p2 & 0xf at arm time.
	lfo_sub_callback_idx = PackedByteArray([3, 3, 3, 3])


func reset() -> void:
	opcode_pos = 0
	loop_stack = []
	saved_loop_target_pos = 0
	channel_word_0 = 0
	channel_word_1 = 0
	note_duration = 0
	idle_timeout = -1
	byte_76 = 0
	byte_7A = 15
	pitch_bend = 0
	pre_pitch_acc_u32 = 0
	pre_pitch_delta_u32 = 0
	portamento_active = false
	portamento_target_counter = -1
	chan_6_bit_2 = false
	vol_burst_active = false
	vol_burst_counter = 0
	expression_acc_s32 = 0x7F000000
	expression_delta_s32 = 0
	word_84 = 0
	word_86 = 0
	pitch_state = 0
	pan_offset_ae = 0
	chan_92_pan_baseline = 0x4000
	chan_88_value = 0
	chan_8a_value = 0
	chan_90_value = 0x4000
	# Iter-35: flat lfo_* fields removed; sub-slot 0 is now lfo_sub_*[0].
	# Iter-28: mode default → [0,0,0,0] (closes mode-byte half of the
	# MUSIC_34 subslot 1/2 probe divergence — see _init comment).
	# Iter-33: sub-slot 1 + 2 depth → 0 (was 256) to match FFT
	# FUN_800138AC's BSS-zero default — see _init comment + docs/
	# MUSIC_ITER33_LFO_SUBSLOT_DEPTH_DEFAULT.md.
	var _default_mode: PackedByteArray = PackedByteArray([0, 0, 0, 0])
	var _default_depth: PackedInt32Array = PackedInt32Array([256, 0, 0, 0])
	for _i in range(LFO_SUB_SLOT_COUNT):
		lfo_sub_countdown[_i] = 0
		lfo_sub_depth[_i] = _default_depth[_i]
		lfo_sub_depth_delta[_i] = _default_depth[_i]
		lfo_sub_mode[_i] = _default_mode[_i]
		lfo_sub_active[_i] = 0
		lfo_sub_step_source[_i] = 0
		lfo_sub_step_current[_i] = 0
		lfo_sub_accumulator[_i] = 0
		lfo_sub_inner_reload[_i] = 0
		lfo_sub_dir_flags[_i] = 0
		lfo_sub_delay_reload[_i] = 0
		lfo_sub_delay_counter[_i] = 0
		lfo_sub_callback_idx[_i] = 3
	octave = 4
	stored_AC_param = 0
	stored_param_lo = 0
	stored_param_hi = 0
	instrument_idx = -1
	sample_start_addr = 0
	sample_loop_addr = 0
	fine_tune = 0
	adsr1 = 0
	adsr2 = 0
	adsr2_mode_byte = 0
	release_rate_byte = 0
	tick_phase = 0
	ttl_sub_ticks = -1
	stream_end_fired = false
	pending_kill_pitch_flush = false
	has_silent_overlay = false
	dispatch_enabled = true
