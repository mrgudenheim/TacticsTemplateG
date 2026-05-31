class_name SharedSlotState
## One pool slot's runtime state — corresponds to one FFT effect-pool entry.
##
## In FFT, slot_base and channel_base point at the same struct, offset by 2
## (slot_base = channel_base + 2). We collapse both into a single GDScript
## object whose fields cover the union.
##
## The dispatcher populates flag bits by walking a feds opcode stream;
## the per-tick flush consumes them and stages SPU writes.

# --- Slot flag word (FFT slot_base + 0x2 — read as `s1` in FUN_80017118) ---
const FLAG_PRIMARY_KON   := 0x001  # triggers s4 accumulator (fresh start)
const FLAG_SECONDARY_KON := 0x002  # triggers s5 accumulator (re-key)
const FLAG_KOFF_PENDING  := 0x004  # flush issues SPU key_off this tick (TTL boundary OR stream end)
const FLAG_STREAM_END    := 0x008  # set together with FLAG_KOFF_PENDING when opcode stream is truly exhausted; flush deactivates the slot only when this is set. TTL-fired KOFFs leave the slot active so opcode walker can continue to the next Note.
# FFT disasm L80015460-0x5464: Note handler atomically sets bit 0x200 on
# slot+0x2 (= flag_word). Per FUN_80017118 L80017370 this is the PITCH
# recompute trigger. flush_tick.gd does NOT consume this bit today (no
# Spu mid-tone vol setter; see flush_tick.gd:8 GAP). Set in
# dispatcher._handle_note matching FFT's atomic order; observable to
# probe_note_post_state only — no per-tick behavior change because
# clear_per_tick_flags() zeroes flag_word each tick.
const FLAG_VOL_UPDATE    := 0x200
# In FFT, the kon-suppress gate is at slot+0x0 bit 0x20 (channel-state/
# active_word), not slot+0x2. Per FUN_80017118 line 78:
# `(*param_2 & 0x20) == 0` reads chan+0xb8 (= slot+0x0 = active_word in
# Godot terms). Currently no setter wires this in Godot — readers stay
# vacuous until a session needs the gate.
const ACTIVE_WORD_KON_SUPPRESS := 0x020
# ADSR2 register-update flags. Per disasm L80014714-0x4730, FFT per-tick
# handler dispatches:
#   bit 0x40 → FUN_8001b9d4(slot+0x64, slot+0x58)  — write ADSR2 sustain bits
#   bit 0x80 → FUN_8001bab8(slot+0x66, slot+0x5c)  — write ADSR2 release bits
# Set by opcodes 0xC9 / 0xCA (or by 0xC2/0xC3/0xC4/0xC5/0xC7 in their
# halfword-stage variants). ADSR2 modifier opcodes now stage
# WALKER_FLAG_ADSR2_HIGH (0x040) or WALKER_FLAG_ADSR2_LOW (0x080)
# directly; walker fires the helpers via _fan_adsr2_high/_fan_adsr2_low.

# --- Walker flag word (FFT sub_slot+0x2 — read by FUN_80014590 at SPU IRQ) ---
# Distinct from flag_word above (the per-tick flag at FFT slot+0x4 read by
# FUN_80017118). The walker fires asynchronously at the SPU sample-buffer
# IRQ rate (~88 Hz) and fans out per-bit to register-writer helpers, then
# clears the word. Per-tick handler / opcode handlers stage bits here for
# the walker to drain at the next IRQ — a deferred-commit pipeline.
# See spu_irq_walker.gd. Bit layout matches FFT FUN_80014590 fan-out bits.
const WALKER_FLAG_VOL_LR_RAW     := 0x001  # FUN_8001B428 — vol_L (SPU+0) + vol_R (SPU+2), no sweep
const WALKER_FLAG_VOL_LR_SWEEP   := 0x002  # FUN_8001B4B0 — vol_L+vol_R with sweep mode (STUB)
const WALKER_FLAG_PITCH          := 0x004  # FUN_8001B628 — pitch (SPU+4)
const WALKER_FLAG_SAMPLE_ADDR    := 0x008  # FUN_8001B6A4 + B720 — start_addr SPU+6 + repeat_addr SPU+E (STUB)
const WALKER_FLAG_ADSR1_HIGH     := 0x010  # FUN_8001B938 — ADSR1 high byte (attack rate + lin/exp) (STUB)
const WALKER_FLAG_ADSR1_MID      := 0x020  # FUN_8001B79C — ADSR1 mid-nibble bits 4-7 (decay/sustain rate) (STUB)
const WALKER_FLAG_ADSR2_HIGH     := 0x040  # FUN_8001B9D4 — ADSR2 high bits 6-15
const WALKER_FLAG_ADSR2_LOW      := 0x080  # FUN_8001BAB8 — ADSR2 low bits 0-5 + mode (STUB)
const WALKER_FLAG_ADSR1_LOW      := 0x100  # FUN_8001B8B0 — ADSR1 low nibble (sustain level)

# --- Channel-state word 0 (FFT channel_base + 0x0 = slot+0x0) ---
# Bit 0x008 is the play_sound effect-load HAS_TONES marker (per
# L80013CB0-CD0 init writes 0x409 = 0x400 + 0x008 + 0x001), NOT the
# SlurOn opcode flag. Bit 0x800 is SLUR_PENDING — set by opcode 0xB0
# (SlurOn) at L80015EB0/EB4 and cleared by opcode 0xB1 (SlurOff) at
# L80015EC0/EC8. The two are distinct in FFT and both checked in
# different code paths.
const CHAN0_HAS_TONES   := 0x008   # play_sound init marker (L80013CD0); L800153B8 gates chan_92_value storage on this bit
const CHAN0_NOTE_FIRED  := 0x080
const CHAN0_PITCH_REQ   := 0x100   # Note handler sets 0x180 (this | NOTE_FIRED)
const CHAN0_VOL_PENDING := 0x200   # L80015524-30: SLUR_PENDING propagates to this; gates duration-tick decrement
const CHAN0_KON_ARM     := 0x400   # Rest, duration-tick, effect-load set this
const CHAN0_SLUR_PENDING := 0x800  # L80015EB0: SlurOn opcode (0xB0) sets; SlurOff (0xB1) at L80015EC8 clears via andi 0xf7ff
# Post-walker look-ahead at PC 0x80015534-94 sets this when the byte at the
# walker pointer (peeked, not dispatched) is a Note (< 0x80), and clears it
# when the byte is any non-Note terminator (0x80/0x81/0x90-no-loop/0xB0/0xB1
# or a generic 0x80+ opcode reached at the end of the look-ahead chain).
# Preserved across snapshot+clear (chan_word_0 &= 0xf8ff). No currently-
# modeled gate reads it, but captured by probe_slur_propagation.
const CHAN0_LAST_NOTE_FLAG := 0x1000

# --- Raw-input fields (single-source-of-truth refactor) ---
# FFT's opcode handlers store RAW inputs at primitive struct fields
# (chan+0x98, chan+0xae, etc.) and set channel_word_1 prestage bits;
# FUN_80017118 reads ALL inputs per-tick and computes scaled vol/pitch
# ONCE. Opcode handlers store these raw fields; the drainer (in
# play_sound.gd) is the sole writer of vol_staging_l/r and pitch_staging.
var note_velocity_raw: int = 0x7F  # Last Note's velocity (0..127). Default 0x7F.

# (Removed empirical envelope model. The FFT-faithful expression
# accumulator lives on SharedChannelState as expression_acc_s32 /
# expression_delta_s32; the drainer in play_sound.gd reads
# `(channel.expression_acc_s32 >> 16) & 0xFFFF` to mirror FFT's
# `lh 0x98(s0)` with s0=chan_base+0x2. Confirmed bit-exact against PCSX
# via probe_expression_ramp + probe_vol_inputs PAIRs on cure_no_music.)

# --- Channel-state word 1 (FFT channel_base + 0x2 = slot_base + 0x0) ---
# Per FUN_80017118 disasm L800171b8/L80017334:
#   bit 0x100 → drains to walker_flag_word bit 0x1 (vol_lr_raw) at L80017330
#   bit 0x200 → drains to walker_flag_word bit 0x4 (pitch)       at L80017370
# So bit 0x100 is the VOL prestage, bit 0x200 is the PITCH prestage.
const CHAN1_NOTE_FIRED       := 0x080   # Note handler sets 0x80 in word 1
const CHAN1_VOL_PRESTAGE     := 0x100   # FFT FUN_80017118 L800171b8: drains to walker bit 0x1 (vol_lr_raw)
const CHAN1_PITCH_PRESTAGE   := 0x200   # FFT FUN_80017118 L80017334: drains to walker bit 0x4 (pitch)


# Slot identity
var slot_idx: int = 0                    # 0..7 within the pool
var voice_mask: int = 0                  # FFT slot+0x34 — 1 << (slot_idx + 16)

# Monotonic bind-time counter — LRU proxy for FFT entity+0x10 (preempt
# priority/lifetime). Set by EffectSoundPool.allocate_pair at bind time
# from the pool's monotonic counter; the slot with the smallest bind_tick
# among busy slots is the preempt candidate (FFT picks the slot with the
# smallest entity+0x10; since every slot starts at the same init value
# and decrements per tick, smallest = oldest = smallest bind_tick).
# See DISILLUSIONMENT_PAIR_SLOT_PREEMPT_DEFICIT.md Phase 1.
# -1 = slot has never been bound (treated as not-a-preempt-candidate).
var bind_tick: int = -1

# Dispatcher-vs-flush cadence split. dispatcher.tick() is called once per
# sub_tick (= 120 Hz, FLUSH rate) but FFT's FUN_80015324 dispatcher fires
# at the timeline rate (= 30 Hz, every 4th sub_tick). Logic that is
# dispatcher-rate (e.g. per-tick portamento accumulator) gates on
# `tick_phase % FLUSH_PER_DISPATCH == 0`; flush-rate logic (duration
# counter, LFO countdown) keeps running every call. Increment per
# dispatcher.tick().
var tick_phase: int = 0

# Active marker (FFT slot_base + 0x0): non-zero = slot is in use; flush walks it
var active_word: int = 0

# Effect controller TTL — sub-ticks remaining until forced KOFF.
# Per probe koff_trigger_001 + koff_controller_001, FFT sets pool_B+0x10
# bit 0x8000 at +567ms after cure start (= 17 outer ticks at 30Hz = 68
# sub-ticks at 120Hz). Source mechanism still unknown — likely an
# effect-load setting in cure's metadata, not in the opcode stream. For
# now hardcoded to 68 sub-ticks at pair-allocate time in play_sound.gd.
# -1 = no TTL (slot lives until stream-end).
var ttl_sub_ticks: int = -1

# Slot flag word (FFT slot_base + 0x2)
var flag_word: int = 0

# Walker flag word (FFT sub_slot+0x2 — distinct from flag_word above).
# Read + cleared by spu_irq_walker.gd at SPU IRQ cadence. Set by per-tick
# handler / opcode handlers staging deferred register writes. WALKER_FLAG_*
# constants above. DO NOT confuse with flag_word (per-tick flag).
var walker_flag_word: int = 0

# Per-slot one-shot deferred prestage arm. Set by play_sound.
# _prestage_first_instrument when the bound bytecode dispatches 0xAC
# before its first Note (= PCSX's Hyp_instrument_data_loader will arm
# walker_flag_word=0x1FF at cad=0). flush_tick._process_slot reads +
# clears this on the first FLAG_PRIMARY_KON post-anchor, staging the
# full 0x1FF arm so the next walker pass emits the cluster row at
# cad>=1 (probe-visible). Reset to false in reset() so slot reuse
# re-evaluates the arm on the next bind.
var walker_seed_pending: bool = false

# Narrow walker seed — see VOICE_18_ADSR1_HIGH_PREARM_PATCH.md. When set,
# the next first-FLAG_PRIMARY_KON flush ORs only WALKER_FLAG_ADSR1_HIGH
# (0x010) into walker_flag_word, instead of the full 0x1FF set by
# `walker_seed_pending`. Used for Note-before-AC channels where PCSX's
# FFT instrument-loader residue pre-arms ADSR1_HIGH but not the rest.
var walker_seed_pending_narrow: bool = false

# Channel-state words (collapsed into the same struct)
var channel_word_0: int = 0              # FFT channel_base + 0x0
var channel_word_1: int = 0              # FFT channel_base + 0x2 = slot_base

# Opcode stream — each slot has its own feds file_channel byte stream
var opcode_bytes: PackedByteArray = PackedByteArray()
var opcode_pos: int = 0

# Per-channel runtime state used by the dispatcher
var note_duration: int = 0               # FFT channel + 0x72 — ticks until next Note

# Model FFT slot+0x78 (idle_timeout) separately from note_duration.
# Per probe slot78_writes: slot+0x78 init = note.delta_time after Note
# dispatch (L80015714 + later overwrite). PCSX decrements at ~0.8
# dec/sub_tick (= 4 decs per 5 sub_ticks, alternating 1.0/1.5 sub_tick
# intervals — the dispatcher cadence at 96 Hz on a 120 Hz SPU clock).
# When idle_timeout drains 1→0, FFT L800152F0-F8 sets KON_ARM (bit
# 0x400) + FLAG_SECONDARY_KON. -1 = idle_timeout disabled.
var idle_timeout: int = -1

# Opcode 0xB4 (LAB_80015F44 at jumptable 0x80028BDC) writes operand to
# slot+0x1E and calls FUN_80019D88 which puts the value into SPUCNT bits
# 8-13 = noise_clock (per L80019DB4-CC: andi 0x3F, sll 0x8). Setting
# noise_pending in the opcode handler; flush_tick consumes (calls
# mixer.set_voice_noise + clock).
# -1 = no noise pending; 0..0x3F = pending clock value.
var noise_pending: int = -1

# Persisted slot-level noise_clock storage (FFT slot+0x1E). Set by 0xB4
# (absolute write: operand & 0x3F) and adjusted by 0xB5 (additive:
# `slot+0x1E = (slot+0x1E + operand) & 0x3F` per FUN_80015FB4 PC
# 0x80015FD0-FE4). Tracked here so 0xB5's relative-add semantic has a
# stable base. flush_tick republishes to the SPU via set_noise_clock
# when noise_pending != -1.
var noise_clock_value: int = 0

# Opcode 0xB7 (LAB_80016060 at jumptable 0x80028BE8) clears the voice's
# noise bit on the entity's per-IRQ noise mask:
#   entity[+0x6c] &= ~chan[+0x34]
# FFT's Hyp_spu_updater_callee_2 (FUN_80014FF8) aggregates entity[+0x6c]
# across the entity list each IRQ and writes the result to SPU NoiseOn
# (0x1F801D94/D96) via FUN_80019B5C. Setting this flag in the 0xB7
# handler; flush_tick consumes it by calling mixer.set_voice_noise(false).
var noise_disable_pending: bool = false

# Opcode 0xB2 (Hyp_smd_op_test_ch2d_bit0 at handler 0x80015ED8,
# jumptable 0x80028BD4) / 0xB3 (handler 0x80015F18, jumptable
# 0x80028BD8). When the channel's bytecode dispatches these:
#   0xB2: entity[+0x68] |= chan[+0x34]   (enable Chan::FMod=1 on voice)
#   0xB3: entity[+0x68] &= ~chan[+0x34]  (disable Chan::FMod=1 on voice)
# chan[+0x34] is the precomputed (1 << voice_idx) mask. The walker
# FUN_8001_4F58 OR-accumulates entity[+0x68] per IRQ and writes the
# result to the SPU FMon register, which PCSX FModOn() interprets as
# "set Chan::FMod=1 on voice N (and Chan::FMod=2 on voice N-1 as the
# freq source)". See V21_FMOD_PITCH_MODULATION_FIX.md +
# FMOD_GENERALIZATION_PLAN.md for the full chain.
#
# Dispatcher sets this on opcode 0xB2/0xB3; flush_tick consumes it and
# calls mixer.set_voice_fmod. Per-IRQ assertion matches FFT's behavior
# (the walker re-asserts every IRQ).
# -1 = no change pending; 1 = enable (B2); 0 = disable (B3).
var fmod_pending: int = -1

# slot+0x76 byte field. Per probe slot78_init_exec: the L800156B4
# `move v1, a0` in `bgtz` delay slot overwrites v1 with
# `a0 = sign_extend(slot+0x76) + note_duration`, which then gets stored
# to slot+0x78 in case 2 (slot+0x7A==16) via `move a0, v1` at L800156E8.
# So idle_timeout init = note.delta_time + slot.byte_76.
#
# byte_76 is modified by opcode 0xAD (LAB_80015E68 / L80015E80):
#   * operand != 0: byte_76 = sign_extend(byte_76 + signed_byte)
#   * operand == 0: byte_76 = 0
# Stored at L80015E88 / L80015E8C as `sb` (single byte). Sign-extended on
# read at L800156A0-A4 (sll/sra by 0x18).
var byte_76: int = 0

# slot+0x7A — the formula CASE SELECTOR at L800156D0-DC. Per FFT disasm:
#   * slot+0x7A == 15 → case 15 path: a0 = v1 - 1 (idle_timeout = sum-1)
#   * slot+0x7A == 16 → case 16 path: a0 = v1     (idle_timeout = sum)
#   * else            → case other:    a0 = (delta_time * slot+0x7A) >> 4
# Set by opcode 0xA9 (LAB_80015dd0: `sh v0, 0x7a(a2)`).
var byte_7A: int = 15
var pitch_state: int = 0                 # FFT channel + 0x82 — current pitch reference
var stored_AC_param: int = 0             # FFT channel + 0x2c — instrument/AC

# Stored param (FFT slot + 0x2c/0x2e). Set during effect-load / pair allocation
# from the feds header — drives instrument selection.
var stored_param_lo: int = 0
var stored_param_hi: int = 0

# Staging — written by dispatcher, consumed by flush when corresponding bit set
var pitch_staging: int = 0               # FFT slot + 0x3a/0x3c
var vol_staging_l: int = 0               # FFT slot + 0x46
var vol_staging_r: int = 0

# SPU sample binding (resolved at Instrument opcode dispatch from WAVESET)
var instrument_idx: int = 0
var sample_start_addr: int = 0
var sample_loop_addr: int = 0
var adsr1: int = 0
var adsr2: int = 0
# FFT slot+0x60: byte stored by opcode 0xCA at PC 0x800162B0
# (`sw v1, 0x60(a2)`). FUN_8001BAB8 reads this as the mode selector
# (`a2`) when committing ADSR2 low 6 bits — 7 → mode_bits=0x20
# (release_mode_exp), else 0. Walker fan-out _fan_adsr2_low reads this
# to compute the ADSR2 low-6-bit write value.
var adsr2_mode_byte: int = 0
# FFT slot+0x6A: byte stored by opcode 0xC5 at PC 0x80016218
# (`sh v1, 0x6a(a2)`) and by the instrument-load fan-out. Holds the raw
# release_rate (0-31), no mode bit. Distinct from `slot.adsr2 & 0x1F`
# (which is the standing SPU-register low 5 bits) — FFT's walker
# reads this dedicated field at PC 0x80014738 (`lhu a1, 0x66(s0)` =
# slot+0x6A in true coords per s0 = slot+4) to feed FUN_8001BAB8's a1,
# then OR's mode_bits inside the function. See
# docs/MUSIC_ITER32_ADSR2_LOW_RELEASE_BYTE_FIELD_SOURCE.md.
var release_rate_byte: int = 0
# Tracks whether 0xC4/0xC5/0xC7 ADSR-modifier opcodes have mutated
# adsr1/adsr2 since the last Instrument-opcode load. When true,
# flush_tick.gd's KEYON ADSR override is SKIPPED so the opcode-modified
# value reaches the SPU register at re-KEYON. Reset on Instrument opcode
# (= new instrument default load).
var adsr_opcode_modified: bool = false
# Tracks ADSR2 across dispatcher ticks so flush_tick can stage walker
# re-emit ONLY when the value actually changes. A change-driven stage
# pattern matches FFT semantics (FFT's per-tick handler stages bit 0x40
# on the SAME conditions Godot detects via slot.adsr_opcode_modified
# PLUS LFO mode 1 value-change).
var prev_adsr2: int = -1  # -1 = uninitialized; first compare always stages
var fine_tune: int = 0

# Octave (FFT chan + 0x94 implied; default 4 per Sequencer.TrackState).
# Set by Octave (0x94), RaiseOctave (0x95), LowerOctave (0x96) opcodes.
var octave: int = 4

# Parity-shadow fields for opcodes 0x90 / 0xE2 / 0xE5 whose FFT-side
# writes have no current downstream readers in our model (slot+0x118/
# 0x11a/0x11e are dead state, slot+0x2b is read by per-tick handler at
# PC 0x8001719c which Godot doesn't replicate). Modeled as fields anyway
# so the dispatcher mirrors FFT faithfully and future readers don't
# silently ignore them.
var byte_2b: int = 0      # 0x90 EndBar copies byte_7e here (FFT slot+0x2b)
var byte_5c: int = 0      # 0xC9 ADSR-mode store (FFT slot+0x5c, sw at PC 0x80016294 — read by FUN_8001B9D4 mode selector path; parity-shadow for the walker fan-out)
var byte_7e: int = 0      # also written by Repeat-related code (FFT slot+0x7e)
var word_118: int = 0     # 0xE2 vol-scale division output
var word_11a: int = 0     # 0xE2 vol-scale division output (duplicate)
var word_11e: int = 0     # 0xE5/0xE6 set/clear bit 0x1
# FFT chan+0x6 bit 0x4 — set by 0xD6 (LAB_800163EC) when param != 0,
# cleared when param == 0. Tracked here as a parity-shadow flag; the
# downstream readers of bit 0x4 in FFT are not currently modeled by
# Godot's pan formula (which uses channel.chan_90_value directly).
var chan_6_detune_active: bool = false

# Snapshot of channel.pre_pitch_acc_u32 / pre_pitch_delta_u32 / pitch_bend
# at the moment FLAG_PITCH_UPDATE was set by the dispatcher. Used to
# capture the inputs that produced a pitch_written value.
var debug_pitch_acc_at_update: int = 0
var debug_pitch_delta_at_update: int = 0
var debug_pitch_bend_at_update: int = 0

# PitchLFO state.
# Mirrors FFT chan+0xE0..0xFE LFO state struct populated by opcode 0xD9
# handler at FUN_80016420.
#   chan+0xEC (state+0xC, 32-bit): step_base = (rate^2 << 14) / step_param
#                                              [per FUN_80016BF8 with a2=3]
#   chan+0xF0 (state+0x10, u16): countdown — decremented per tick; on wrap
#                                triggers direction swap.
#   chan+0xF2 (state+0x12, u16): period reload value (= step_param from
#                                D9 handler L8001647C).
#   chan+0xFE (state+0x1E, u16): mode flags; bit 0x8 = direction (negate or
#                                not). Toggled per swap.
#   chan+0xE4 (state+0x4, 32-bit): current LFO output. Returned by advance
#                                  fn at LAB_80017690. Per LAB_80017568
#                                  this output is shifted >> 16 (sign-
#                                  preserving) then ADDED to chan+0x88.
var lfo_active: bool = false
var lfo_step_base: int = 0     # state+0xC (32-bit)
var lfo_current_output: int = 0  # state+0x4 (32-bit, sign-flipped each period)
var lfo_countdown: int = 1     # state+0x10 (init 1 so first tick triggers swap)
var lfo_period_reload: int = 0  # state+0x12
var lfo_dir_negate: bool = false  # state+0x1E bit 0x8

# Repeat/Coda loop stack.
# Mirrors FFT's chan+0xB0..0xAC (depth at chan+0xAC, entries 12 bytes
# each at chan+0xB0 + depth*12).
# Each entry: {count: int, back_pos: int, octave: int}
#   count = N - 1 (off-by-one; body runs N times for opcode 0x98 N)
#   back_pos = opcode_pos of first event AFTER Repeat (loop-body start)
#   octave = chan+0x7E snapshot at Repeat-time (restored on each
#            Coda jump-back, critical for cure's `96 LowerOctave`
#            inside the loop body).
var loop_stack: Array = []

# Tracks whether the dispatcher has staged the envelope-force write that
# makes this voice audible. Voices that never get this stay silent (the
# D4-sink mechanism). The flush consults this at primary-KON time.
var force_envelope_open: bool = false

# Per-slot tracking for natural-release KOFF.
# driving_channels counts channels routing through this slot (audible +
# silent overlays); kept for back-compat / debug. last_kon_channel = the
# channel that fired the most-recent primary KON for this slot. When that
# channel's bytecode hits stream_end, fire KOFF. Earlier silent drivers
# ending do NOT fire KOFF — only the latest KON-firer's stream_end
# triggers it.
var driving_channels: int = 1
var last_kon_channel = null  # SharedChannelState ref

# --- Pitch formula state ---
#
# The SPU pitch staging at chan+0x48 = FUN_80017424((sum) & 0xFFFF, sign-ext)
# & 0x3FFF, where:
#   sum = (s16) chan+0x82  +  (u16) chan+0x88  +  (s16) s2+0xA2
#
# In-memory layout (cited disassembly + probe):
#   chan+0x80..0x83 = pre_pitch_acc_u32  (32-bit per-tick accumulator)
#       Updated at L9359..9362 (PC 0x80015244): chan+0x80 += chan+0x9C
#       Note handler sets via L9514..9523 (PC 0x8001545C): sw at chan+0x82
#       The formula reads the UPPER halfword (chan+0x82..0x83) as signed.
#   chan+0x88     = pitch_bend  (signed 16, treated as u16 by formula)
#       0xD0 SetPitchBend: pitch_bend = (s8 param) << 5    [L10675..10683]
#       0xD1 AddPitchBend: pitch_bend += (s8 param) << 5   [L10689..10699]
#       LFO add path at PC 0x800175B0
#   chan+0x9C..0x9F = pre_pitch_delta_u32  (32-bit per-tick delta)
#       0xD4 init handler L10742 (PC 0x800163A0): sw v1, 0x9c(a2) where
#       v1 = (s8(rate) << 24) / target.
#   chan+0x6 bit 0x1 = portamento_active (set by 0xD4)
#       Gates the per-tick acc add (FUN_80015138 L9344..L9362).
var pre_pitch_acc_u32: int = 0
var pre_pitch_delta_u32: int = 0
var pitch_bend: int = 0           # signed -32768..32767, formula reads as u16
var portamento_active: bool = false
# Pass 7.E.F — per-slot reverb-enable for the KON path. SFX defaults
## true to preserve the prior `reverb_enabled = is_primary` short-
## circuit semantic (primary KON enables reverb). Music's note_handler
## writes ts.ctx.channel.reverb_send_enabled here at KON time so the
## flush_tick._key_on_voice picks up per-track 0xBA/0xBB toggles.
var reverb_send_enabled: bool = true


func _init(idx: int = 0) -> void:
	slot_idx = idx


func reset() -> void:
	## Clear runtime state. Voice mask is set by the pool at allocate_pair time.
	active_word = 0
	flag_word = 0
	walker_flag_word = 0
	walker_seed_pending = false
	walker_seed_pending_narrow = false
	channel_word_0 = 0
	channel_word_1 = 0
	note_velocity_raw = 0x7F
	opcode_bytes = PackedByteArray()
	opcode_pos = 0
	note_duration = 0
	pitch_state = 0
	stored_AC_param = 0
	stored_param_lo = 0
	stored_param_hi = 0
	pitch_staging = 0
	vol_staging_l = 0
	vol_staging_r = 0
	instrument_idx = 0
	sample_start_addr = 0
	sample_loop_addr = 0
	adsr1 = 0
	adsr2 = 0
	adsr2_mode_byte = 0
	release_rate_byte = 0
	adsr_opcode_modified = false
	prev_adsr2 = -1
	fine_tune = 0
	octave = 4
	loop_stack = []
	tick_phase = 0
	lfo_active = false
	lfo_step_base = 0
	lfo_current_output = 0
	lfo_countdown = 1
	lfo_period_reload = 0
	lfo_dir_negate = false
	force_envelope_open = false
	driving_channels = 1
	pre_pitch_acc_u32 = 0
	pre_pitch_delta_u32 = 0
	pitch_bend = 0
	portamento_active = false
	voice_mask = 0
	idle_timeout = -1
	byte_76 = 0
	noise_pending = -1
	noise_disable_pending = false
	noise_clock_value = 0
	fmod_pending = -1
	byte_2b = 0
	byte_5c = 0
	byte_7e = 0
	word_118 = 0
	word_11a = 0
	word_11e = 0
	chan_6_detune_active = false
	bind_tick = -1
	reverb_send_enabled = true


func clear_per_tick_flags() -> void:
	## FUN_80017118 does `sh zero, 0x0(s0)` after each slot is processed
	## (L12002) — clears the slot flag word so it must be re-set by the
	## dispatcher every tick to retrigger.
	flag_word = 0


func clear_walker_flags() -> void:
	## FUN_80014590 clears sub_slot+0x2 to 0 after fan-out IFF any bit was
	## set (`if (uVar4 != 0) *(ushort *)piVar3 = 0`). Walker handles the
	## conditional; this helper just zeros the field.
	walker_flag_word = 0
