class_name EffectSoundProbeCounters
## Per-render-session probe call_index counters extracted from
## dispatcher.gd (refactor Pass 1).
##
## Static vars — shared across all dispatcher instances per session so
## the cadence matches FFT's per-session BP hit count. Each counter
## tracks one PCSX BP's hit-count on the Godot side; the
## `Trace.emit(..., {"call_index": X})` calls feed validate_probe_pair.py's
## paired-row alignment.
##
## Naming convention: `<probe_name>` (no `_probe_` prefix, no `_count`
## suffix). `_diag_X` counters keep the `diag_` prefix because the probe
## name itself starts with `diag_`.
##
## Counters that fire from inside helper modules (e.g.
## `_diag_lfo_prng_step_count` is bumped by the PRNG step function)
## live next to the function that bumps them — see
## helpers/lfo_prng.gd (Pass 2).
##
## Counter for probe_adsr2_register lives in spu_irq_walker.gd since
## the emit happens inside _fan_adsr2_high — not here.

# GOLD probes (Layer 0-4: paired with PCSX BPs at known PCs)
static var event_dispatch: int = 0
static var note_handler: int = 0
static var note_post_state: int = 0

# Music-side vol-formula probes — fire from SharedComputeVolLr.apply,
# pair with PCSX BP 0x80017328 (FUN_80017118 vol-formula end). The
# SFX side uses _probe_vol_inputs_count / _probe_vol_lr_staging_count
# on play_sound.gd; music keeps a separate counter so call_index
# numbering doesn't collide between paths. See
# docs/MUSIC_ITER12_PAN_SCALE_FIX.md for the pan-direction context
# this surfaces.
static var vol_inputs_music: int = 0
static var vol_lr_staging_music: int = 0

# Music-side pitch-formula bisection probe — fires 5 rows per pitch
# evaluate (one per stage). Pairs with PCSX probe_pitch_formula_stages
# at PCs 0x80017344-0x8001736C. Counter is shared across stages (each
# emit increments) so PCSX and Godot call_indices align by emit-order.
# See docs/MUSIC_ITER19_PITCH_FORMULA_STAGES_MUSIC.md.
static var pitch_formula_stages_music: int = 0

# Note dispatch / pitch baseline
# probe_note_pitch_baseline — mirrors FFT BP @ PC 0x80015454 inside
# smd_note_state_setup. Captures the unshifted pitch baseline sum + 3
# addends (finetune chan+0x84, pitch_bend chan+0x86, bmidi byte a1)
# right before `sw v0, 0x7e(s0)` commits.
static var note_pitch_baseline: int = 0

# Opcode handlers — bytecode-flow
static var opcode_rest: int = 0
static var opcode_fermata: int = 0
static var opcode_endbar: int = 0
static var opcode_9a_repeat_break: int = 0
static var opcode_octave: int = 0
static var opcode_raise_octave: int = 0
static var opcode_lower_octave: int = 0
static var opcode_repeat: int = 0
static var opcode_coda: int = 0

# Opcode handlers — channel-state / SPU-mode
static var opcode_instrument: int = 0
static var opcode_slur_on: int = 0
static var opcode_reverb_on: int = 0
static var opcode_reverb_off: int = 0
# 0xB6: SETS noise/audio bit on entity+0x6C WITHOUT arming ADSR1_HIGH
# (the no_arm distinguishes it from 0xB4). See dispatcher._op_b6.
static var opcode_b6_noise_enable_no_arm: int = 0

# Opcode handlers — ADSR cluster
static var opcode_c0_instrument_reload: int = 0
static var opcode_c7_adsr: int = 0
static var opcode_c9_adsr: int = 0
static var opcode_adsr2_sustain: int = 0

# Opcode handlers — pitch / portamento cluster
static var opcode_d0_pitch_bend: int = 0
static var opcode_d1_pitch_bend: int = 0
static var opcode_d2_rel_pitch_bend: int = 0
static var opcode_d3_pitch_bend_add_16bit: int = 0
static var opcode_d4_portamento: int = 0
static var opcode_d5_chan6_bit2_toggle: int = 0
static var opcode_d6_detune: int = 0
static var opcode_d7_pitch_lfo_depth: int = 0
static var opcode_d9_lfo: int = 0
static var opcode_da_flag_set: int = 0
static var opcode_db_flag_clear: int = 0
static var opcode_dc_porta_stop: int = 0

# Opcode handlers — dynamics / pan / LFO sub-slot cluster
static var opcode_dynamics: int = 0
static var opcode_e1_dynamics_add: int = 0
static var opcode_e2_vol_scale: int = 0
static var opcode_e3_vol_lfo_depth: int = 0
# 0xE4: hardcoded-callback sibling of 0xE5. Arms LFO sub-slot 1 with
# mode=1, callback_idx=2 (fixed), dir_flags=3 (fixed). Rate negated.
static var opcode_e4_arm_subslot1_pitch_lfo: int = 0
static var opcode_e5: int = 0
static var opcode_eb_pan_lfo_depth: int = 0
static var opcode_ec_lfo_arm_subslot2: int = 0
static var opcode_ef_clear_subslot2: int = 0
# 0xF0/0xF1: dynamic-subslot pair (companion to 0xEC/0xED which target
# a fixed sub-slot). 0xF0 SELECTS the active sub-slot via chan+0xae and
# arms its waveform/mode; 0xF1 UPDATES the currently-selected sub-slot's
# depth + 16-bit rate.
static var opcode_f0_lfo_subslot_select: int = 0
static var opcode_f1_lfo_subslot_update: int = 0
static var opcode_f2_lfo_subslot_dynamic_depth: int = 0
# 0xF6: ACTIVATES the sub-slot specified by param[0] (companion to F0+F1
# which leave the subslot inactive). Sets bit 0x1 of subslot+0x1e and
# calls pitch_lfo_period_reset.
static var opcode_f6_lfo_subslot_activate: int = 0
static var opcode_f7_lfo_subslot_dynamic_disable: int = 0

# Per-tick / structural probes
static var vol_prestage_lfo: int = 0
static var lfo_swap: int = 0
# probe_lfo_handler_entry — DIAG for VOICE_19_LFO_REARM_CADENCE_SHIFT
# §6 Step 1. Mirrors PCSX BP @ 0x800174C8 (lfo_handler_tick per-channel
# inner loop top, BEFORE the chan_word_0 != 0 gate at 0x800174D0).
static var lfo_handler_entry: int = 0
# probe_lfo_subslot0_state — sibling of subslot1/2 covering the D9
# pitch-LFO sub-slot 0 (chan+0xE0..0xFF). Godot tracks this in flat
# `lfo_*` fields, not the lfo_sub_*[0] arrays; emit maps onto schema.
static var lfo_subslot0_state: int = 0
# probe_lfo_subslot1_state — companion DIAG. Snapshots sub-slot 1 state
# (countdown, dir_flags, accumulator, step_*, delay) at the per-channel
# inner loop top.
static var lfo_subslot1_state: int = 0
# probe_lfo_subslot2_state — pan-LFO sibling of subslot1. Same schema.
# Promoted after CHAN_8A_PAN_LFO_SIGN_FLIP_INVESTIGATION.md showed the
# period_reset bug was hard to localize without sub-slot 2 state diffing.
static var lfo_subslot2_state: int = 0
# probe_lfo_subslot3_state — gap filler for sub-slot 3 (chan+0x140..0x15F).
# Existing 0/1/2 probes left subslot 3 invisible despite non-trivial
# residue activity on multiple sessions.
static var lfo_subslot3_state: int = 0
# probe_chan_pitch_state — chan-side pitch input trajectory
# (chan+0x80 pitch_base + chan+0x86 pitch_bend) per IRQ per channel.
# Pairs upstream of probe_pitch_formula_stages.
static var chan_pitch_state: int = 0
# probe_expression_ramp mirrors PCSX BP @ PC 0x800151FC (the
# `sw v0, 0x92(a0)` chan+0x98 += chan+0xa0 commit).
static var expression_ramp: int = 0
# probe_per_channel_tick_note_active — bisection probe between
# per_channel_tick_entry (PC 0x80015198) and expression_ramp (PC 0x800151FC).
# Fires at chan+0x88 clear inside note_duration!=0 block (PC 0x800151BC).
static var per_channel_tick_note_active: int = 0
# probe_per_channel_tick_word0_pass — finer bisection. Fires post
# chan_word_0 gate, pre note_duration gate. Mirrors FFT PC 0x800151B4.
static var per_channel_tick_word0_pass: int = 0
# probe_smd_interpreter_post_gates — bisection between per_channel_tick_entry
# and event_dispatch. Mirrors FFT BP at PC 0x80015398.
static var smd_interpreter_post_gates: int = 0
# probe_smd_interpreter_tick_entry — sister to post_gates. Fires at the
# per-channel iteration entry BEFORE either selectivity gate (PC 0x8001536C).
static var smd_interpreter_tick_entry: int = 0
# probe_smd_interpreter_gate_skip — sister to tick_entry/post_gates.
# Fires in the `else` branch of `if channel.note_duration == 0`.
static var smd_interpreter_gate_skip: int = 0
# probe_slur_propagation mirrors PCSX BP @ PC 0x80015530 (SLUR→VOL_PENDING
# commit inside smd_dispatcher's exit path).
static var slur_propagation: int = 0
# probe_slur_propagation_pre mirrors PCSX BP @ PC 0x80015524 (the
# `andi v0, v1, 0x800` SLUR test) — fires for every walker exit.
static var slur_propagation_pre: int = 0

# Diagnostic (Godot-only) counters
# diag_vol_burst_transition — Godot-only diagnostic for the 115-row
# expression_ramp deficit on cure_4. Fires on every vol_burst_active
# transition (arm/disarm).
static var diag_vol_burst_transition: int = 0
# diag_walker_flag_adsr1_high_set — Godot-only diagnostic for the
# adsr1_high cluster. Fires on every site that sets
# WALKER_FLAG_ADSR1_HIGH (bit 0x10 of slot+0x4) with a source tag.
static var diag_walker_flag_adsr1_high_set: int = 0
# diag_adsr2_low_gate — Godot-only bisection probe for the
# probe_adsr2_low_register 66/60 deficit.
static var diag_adsr2_low_gate: int = 0
# diag_pitch_formula_inputs — captures the inputs to _compute_pitch at
# every Note dispatch. Pairs with PCSX diag_spu_pitch_writer.lua.
static var diag_pitch_formula_inputs: int = 0
