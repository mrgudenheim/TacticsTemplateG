class_name SharedIrqWalker
## Async-commit walker — port of FFT FUN_80014590 (PC 0x80014590).
##
## FFT's walker is called from FUN_800149DC (the 240 Hz BIOS callback).
## On each call, it walks the pool channel list, then for each channel
## walks its 8 sub-slots, reads the flag word at sub_slot+0x2, and fans
## out per bit to register-writer helpers (FUN_8001B428..BAB8). After
## fan-out, the flag word is cleared IFF any bit was set.
##
## This is a deferred-commit pipeline — opcode handlers and the
## per-tick handler (FUN_80017118 / flush_tick.gd) stage register
## writes by setting walker_flag_word bits; the walker drains them at
## the next BIOS callback.
##
## Sibling: flush_tick.gd ports FUN_80017118 (the per-tick handler).
##
## Cadence: walker.tick() runs `_RCNT2_PER_SUBTICK` times per dispatcher
## sub_tick from test_effect_pipeline.gd, modeling the 240 Hz BIOS
## callback rate.
##
## Pool model: Godot's _pool.active_slots() is 8 entries flat (one per
## SPU voice 16..23). FFT's (channel × 8 sub-slots) hierarchy is
## collapsed — the walker iterates active pool slots directly.
##
## Per-bit fan-out — labels and routing derived from the FFT helper
## decomps directly.
##   0x001 VOL_LR_RAW    → STUB (FUN_8001B428 writes vol_L+vol_R; no
##                         set_voice_volume_lr API yet)
##   0x002 VOL_LR_SWEEP  → STUB (FUN_8001B4B0; vol_L+vol_R+sweep mode)
##   0x004 PITCH         → set_voice_pitch(voice, slot.pitch_staging)
##                         (FUN_8001B628 writes SPU+4 pitch)
##   0x008 SAMPLE_ADDR   → STUB (FUN_8001B6A4 + B720; no setter)
##   0x010 ADSR1_HIGH    → STUB (FUN_8001B938; attack rate + lin/exp)
##   0x020 ADSR1_MID     → STUB (FUN_8001B79C; ADSR1 mid-nibble)
##   0x040 ADSR2_HIGH    → set_voice_adsr2(voice, slot.adsr2)
##                         (FUN_8001B9D4 writes ADSR2 bits 6-15;
##                         set_voice_adsr2 rewrites full register but
##                         slot.adsr2 carries post-modification value)
##   0x080 ADSR2_LOW     → STUB (FUN_8001BAB8; ADSR2 bits 0-5 + mode)
##   0x100 ADSR1_LOW     → set_voice_adsr1_low(voice, slot.adsr1 & 0xF)
##                         (FUN_8001B8B0 writes ADSR1 sustain level)

const _SS = preload("res://addons/exmateria_sound/runtime/shared/slot_state.gd")
const _Trace = preload("res://addons/exmateria_sound/runtime/effect_sound/trace_writer.gd")

# probe_adsr2_register (Layer 5 synthesis) counter. Bumped at every
# _fan_adsr2_high call to mirror the FFT FUN_8001B9D4 commit cadence.
static var _probe_adsr2_register_count: int = 0
# probe_pitch_register (Layer 5 synthesis) counter. Symmetric to adsr2;
# bumped at every _fan_pitch call to mirror FFT FUN_8001B628 entry cadence.
static var _probe_pitch_register_count: int = 0
# probe_vol_register (Layer 5 synthesis) counter. Bumped at every
# _fan_vol_lr_raw call to mirror FFT FUN_8001B428 entry cadence.
static var _probe_vol_register_count: int = 0
static var _probe_vol_register_sweep_count: int = 0
# probe_walker_flag_word_entry (Layer 5 diagnostic) counter. Bumped at
# every per-slot fan-out where walker_flag_word != 0 — mirrors FFT
# FUN_80014590 PC 0x80014660 with filter s1 != 0.
static var _probe_walker_flag_word_entry_count: int = 0
# probe_adsr2_low_register (Layer 5 synthesis) counter. Bumped at every
# _fan_adsr2_low call to mirror FFT FUN_8001BAB8 commit cadence.
static var _probe_adsr2_low_register_count: int = 0
# ADSR1 family counters. Each bumped at the matching _fan_adsr1_*
# call. Cure_no_music fires these only at play_sound init (~2 each).
static var _probe_adsr1_high_register_count: int = 0
static var _probe_adsr1_mid_register_count: int = 0
static var _probe_adsr1_low_register_count: int = 0
# Sample address SPU register writers — fires at play_sound init seed
# (walker bit 0x008). Both fire from one _fan_sample_addr call.
static var _probe_sample_start_addr_register_count: int = 0
static var _probe_sample_repeat_addr_register_count: int = 0


# _pool is duck-typed (untyped) to accept both EffectSoundPool and
## MusicSlotPool. Both expose active_slots() + voice_for_slot(slot_idx).
## Pass 7.E.A — untyped so music can reuse the same per-IRQ walker.
var _pool = null
var _mixer: Spu


func _init(pool, mixer: Spu) -> void:
	_pool = pool
	_mixer = mixer


func tick(pass_idx: int = 0) -> void:
	## One walker pass. Walks active pool slots, reads walker_flag_word,
	## fans out per bit, then clears the word per FUN_80014590's
	## `if (uVar4 != 0) *(ushort *)piVar3 = 0` semantic.
	for slot in _pool.active_slots():
		# FFT FUN_80014590 per-slot loop gate at ram:80014638
		# (`andi v0, v0, 0x1; beq v0, zero, LAB_800147c4`) — skip
		# slots whose slot+0x0 bit 0x1 is clear. Godot's analog is
		# `slot.active_word & 0x1`. Note: this gate is currently a
		# no-op because slot.active_word is set once at allocation
		# and never cleared during the spell.
		if (slot.active_word & 0x1) == 0:
			continue
		var w: int = slot.walker_flag_word
		var voice: int = _pool.voice_for_slot(slot.slot_idx)
		if w == 0:
			continue

		# probe_walker_flag_word_entry (Layer 5 diagnostic). Mirror of
		# FFT BP @ 0x80014660 with s1 != 0 filter. Same anchor gating
		# as _fan_pitch / _fan_adsr2_high.
		if _Trace._post_anchor and _Trace._cadence_index > 0:
			_probe_walker_flag_word_entry_count += 1
			_Trace.emit("walker_flag_word_entry", {
				"call_index": _probe_walker_flag_word_entry_count,
				"voice": voice,
				"walker_flag_word": w & 0xFFFF,
			})

		# FFT mutex: bit 0x002 (vol_lr_sweep) clears bit 0x001
		# (vol_lr_raw) before vol_lr_raw is checked, mirroring FUN_80014590
		# decomp:
		#   if ((uVar4 & 2) != 0) { uVar4 = uVar4 & 0xfffe; FUN_8001b4b0(); }
		#   if ((uVar4 & 1) != 0) { FUN_8001b428(); }
		# This way, when both bits are set (e.g. play_sound's 0x1ff
		# full-arm seed), only vol_lr_sweep fires — vol_lr_raw is
		# suppressed.
		if (w & _SS.WALKER_FLAG_VOL_LR_SWEEP) != 0:
			w &= ~_SS.WALKER_FLAG_VOL_LR_RAW
			_fan_vol_lr_sweep(voice, slot, pass_idx)
		if (w & _SS.WALKER_FLAG_VOL_LR_RAW) != 0:
			_fan_vol_lr_raw(voice, slot, pass_idx)
		if (w & _SS.WALKER_FLAG_PITCH) != 0:
			_fan_pitch(voice, slot, pass_idx)
		if (w & _SS.WALKER_FLAG_SAMPLE_ADDR) != 0:
			_fan_sample_addr(voice, slot, pass_idx)
		if (w & _SS.WALKER_FLAG_ADSR1_HIGH) != 0:
			_fan_adsr1_high(voice, slot, pass_idx)
		if (w & _SS.WALKER_FLAG_ADSR1_MID) != 0:
			_fan_adsr1_mid(voice, slot, pass_idx)
		if (w & _SS.WALKER_FLAG_ADSR2_HIGH) != 0:
			_fan_adsr2_high(voice, slot, pass_idx)
		if (w & _SS.WALKER_FLAG_ADSR2_LOW) != 0:
			_fan_adsr2_low(voice, slot, pass_idx)
		if (w & _SS.WALKER_FLAG_ADSR1_LOW) != 0:
			_fan_adsr1_low(voice, slot, pass_idx)

		slot.clear_walker_flags()


# --- Implemented fan-outs ---

func _fan_pitch(voice: int, slot: _SS, pass_idx: int) -> void:
	# FUN_8001B628: writes SPU+4 (pitch). Sourced from slot.pitch_staging.
	var v: int = slot.pitch_staging & 0xFFFF
	# probe_pitch_register (Layer 5 synthesis). Mirror of FFT BP
	# @ 0x8001B628 — the entry of spu_write_voice_pitch where a0 holds
	# the voice index and a1 holds the 16-bit pitch value about to be
	# committed to SPU+4. Same anchor gating as probe_adsr2_register:
	# skip pre-anchor and the anchor cadence itself, since walker passes
	# fire in both sides before _post_anchor flips and would emit
	# spurious zero rows.
	if _Trace._post_anchor and _Trace._cadence_index > 0:
		_probe_pitch_register_count += 1
		_Trace.emit("pitch_register", {
			"call_index": _probe_pitch_register_count,
			"voice": voice,
			"pitch": v,
		})
	_mixer.set_voice_pitch(voice, v)


func _fan_adsr2_high(voice: int, slot: _SS, pass_idx: int) -> void:
	# FUN_8001B9D4: writes ADSR2 bits 6-15 (sustain rate + sustain mode +
	# release mode + release rate-bits). Godot's set_voice_adsr2 rewrites
	# the whole 16-bit register; slot.adsr2 already carries the
	# post-modification value.
	#
	# Mode dispatch from slot.byte_5c (set by opcode 0xC9 / smd_op_c9_
	# adsr_mode at PC 0x8001627C). FUN_8001B9D4 PC 0x8001b9d0-0x8001ba28:
	#   a2 (= slot+0x5c) == 1 → a3 = 0x000
	#   a2 == 5            → a3 = 0x200
	#   a2 == 7            → a3 = 0x300
	#   else (incl. 0)     → a3 = 0x100 (default sustain_decrease)
	# Then SPU adsr2 high = (sustain_rate | a3) << 6.
	# When byte_5c == 0 (default), mode = 0x100 — matches 0xC4 ADSR2_
	# SustainRate's default, so behavior is unchanged for bytecodes
	# that don't fire 0xC9.
	var sustain_rate: int = (slot.adsr2 >> 6) & 0x7F
	var mode_bits: int
	match slot.byte_5c:
		1: mode_bits = 0x000
		5: mode_bits = 0x200
		7: mode_bits = 0x300
		_: mode_bits = 0x100
	var new_high: int = ((sustain_rate | mode_bits) << 6) & 0xFFC0
	# Recompose: new high bits OR'd with existing low bits (preserves
	# 0xC5 release_rate + 0xCA mode_byte handled separately by
	# _fan_adsr2_low).
	var v: int = (new_high | (slot.adsr2 & 0x3F)) & 0xFFFF
	# probe_adsr2_register (Layer 5 synthesis). Mirror of FFT BP
	# @ 0x8001BA54 — the sh that commits ADSR2 to SPU register 0xA.
	# Pre-anchor emits (before first event_dispatch) are spurious-zero
	# fires through walker passes that PCSX doesn't have. Gate the
	# emit (NOT the SPU write — the write itself is faithful even
	# pre-anchor).
	# Symmetric gate with PCSX's `FIRST_OPCODE_FIRED && CADENCE_INDEX > 0`.
	# _post_anchor flips at the end of the anchor sub-tick; but walker
	# runs BEFORE play.tick_all_dispatchers in the next sub-tick, so the
	# next walker pass still sees _Trace._cadence_index == 0 (the reset
	# value). Additionally guard on cadence_index > 0 to skip those
	# in-between sub-tick walker emits.
	if _Trace._post_anchor and _Trace._cadence_index > 0:
		_probe_adsr2_register_count += 1
		_Trace.emit("adsr2_register", {
			"call_index": _probe_adsr2_register_count,
			"adsr2_register": v,
			# iter-23: voice added for pair_by precision. PCSX probe
			# lua doesn't yet capture voice (would need to derive from
			# v1 register: voice = (v1 - 0x1F801C00) / 0x10).
			"voice": voice,
		})
	_mixer.set_voice_adsr2(voice, v)


func _fan_adsr1_low(voice: int, slot: _SS, pass_idx: int) -> void:
	# FUN_8001B8B0: writes ADSR1 sustain-level nibble (low 4 bits at SPU+0x8).
	var nibble: int = slot.adsr1 & 0xF
	# probe_adsr1_low_register (Layer 5). Mirror of FFT BP @ 0x8001B8B0
	# (function entry). FFT a0=voice, a1=low_nibble.
	if _Trace._post_anchor and _Trace._cadence_index > 0:
		_probe_adsr1_low_register_count += 1
		_Trace.emit("adsr1_low_register", {
			"call_index": _probe_adsr1_low_register_count,
			"voice": voice,
			"low_nibble": nibble,
		})
	_mixer.set_voice_adsr1_low(voice, nibble)


# --- Stub fan-outs ---
# These need C++ API additions before they can be implemented faithfully.

func _fan_vol_lr_raw(voice: int, slot: _SS, pass_idx: int) -> void:
	# FUN_8001B428: writes vol_L (SPU+0) + vol_R (SPU+2), no sweep.
	# Sourced from slot.vol_staging_l / vol_staging_r (FFT slot+0x46/0x48).
	var vol_l: int = slot.vol_staging_l & 0x7FFF
	var vol_r: int = slot.vol_staging_r & 0x7FFF
	# probe_vol_register (Layer 5 synthesis). Mirror of FFT BP
	# @ 0x8001B428 — entry of spu_write_voice_volume_no_sweep where
	# a0=voice, a1=vol_L, a2=vol_R (both masked to 15-bit before the
	# SPU sh). Same anchor gating as _fan_pitch / _fan_adsr2_high.
	if _Trace._post_anchor and _Trace._cadence_index > 0:
		_probe_vol_register_count += 1
		_Trace.emit("vol_register", {
			"call_index": _probe_vol_register_count,
			"voice": voice,
			"vol_l": vol_l,
			"vol_r": vol_r,
		})
	_mixer.set_voice_volume_lr(voice, vol_l, vol_r)


func _fan_vol_lr_sweep(voice: int, slot: _SS, pass_idx: int) -> void:
	# FUN_8001B4B0: vol_L + vol_R with optional sweep mode (mode 1..7
	# maps to high-nibble bits 0x8000..0xE000). Modes aren't surfaced
	# on slot today (FFT reads piVar3+0xf / +0x3e); pass mode 0 to
	# get the no-sweep equivalent — set_voice_volume_lr_with_mode
	# falls through to plain vol_l/vol_r when mode == 0.
	var vol_l: int = slot.vol_staging_l & 0x7FFF
	var vol_r: int = slot.vol_staging_r & 0x7FFF
	# probe_vol_register_sweep (Layer 5). Mirror of FFT BP @ 0x8001B4B0
	# (function entry). FFT a0=voice, a1=vol_L, a2=vol_R, a3=mode.
	# Godot doesn't yet surface sweep mode bits on slot (FFT reads them
	# from slot+0x3C); always emits mode=0. If a session uses sweep
	# modes, expect mode divergence here.
	if _Trace._post_anchor and _Trace._cadence_index > 0:
		_probe_vol_register_sweep_count += 1
		_Trace.emit("vol_register_sweep", {
			"call_index": _probe_vol_register_sweep_count,
			"voice": voice,
			"vol_l": vol_l,
			"vol_r": vol_r,
			"mode": 0,
		})
	_mixer.set_voice_volume_lr_with_mode(voice, vol_l, vol_r, 0, 0)


func _fan_sample_addr(voice: int, slot: _SS, pass_idx: int) -> void:
	# FUN_8001B6A4 + FUN_8001B720 — sample start_addr (SPU+0x6) +
	# repeat_addr (SPU+0xE) re-emit. Bit 0x008 fans out as TWO helper
	# calls. slot.sample_start_addr / sample_loop_addr are populated
	# by dispatcher.gd at every KON-arm.
	var start_addr: int = slot.sample_start_addr
	var repeat_addr: int = slot.sample_loop_addr
	# probe_sample_start_addr_register / _repeat_ — mirror of FFT
	# BP @ PC 0x8001B6A4 and PC 0x8001B720 (function entries).
	if _Trace._post_anchor and _Trace._cadence_index > 0:
		_probe_sample_start_addr_register_count += 1
		_Trace.emit("sample_start_addr_register", {
			"call_index": _probe_sample_start_addr_register_count,
			"voice": voice,
			"addr": start_addr,
		})
	_mixer.set_voice_start_addr(voice, start_addr)
	if _Trace._post_anchor and _Trace._cadence_index > 0:
		_probe_sample_repeat_addr_register_count += 1
		_Trace.emit("sample_repeat_addr_register", {
			"call_index": _probe_sample_repeat_addr_register_count,
			"voice": voice,
			"addr": repeat_addr,
		})
	_mixer.set_voice_repeat_addr(voice, repeat_addr)


func _fan_adsr1_high(voice: int, slot: _SS, pass_idx: int) -> void:
	# FUN_8001B938: RMW ADSR1 high byte (bits 8-15) = attack rate (bits 8-14)
	# + lin/exp flag (bit 15). Source from slot.adsr1's standing high byte:
	#   attack_rate = (slot.adsr1 >> 8) & 0x7F
	#   lin_or_exp  = (slot.adsr1 >> 15) ? 5 : 0   (FFT mode==5 → bit 15 set)
	var attack_rate: int = (slot.adsr1 >> 8) & 0x7F
	var lin_or_exp_mode: int = 5 if (slot.adsr1 & 0x8000) != 0 else 0
	# probe_adsr1_high_register (Layer 5). Mirror of FFT BP @ 0x8001B938
	# (function entry). FFT a0=voice, a1=attack_rate, a2=mode (5 or 0).
	if _Trace._post_anchor and _Trace._cadence_index > 0:
		_probe_adsr1_high_register_count += 1
		# Capture the effective lin/exp mode bit (1 iff lin_or_exp_mode == 5)
		# so the value pairs against FFT's (a2 == 5) check at PC 0x8001B940.
		var mode_bit: int = 1 if lin_or_exp_mode == 5 else 0
		_Trace.emit("adsr1_high_register", {
			"call_index": _probe_adsr1_high_register_count,
			"voice": voice,
			"attack_rate": attack_rate,
			"mode_bit": mode_bit,
		})
	_mixer.set_voice_adsr1_high(voice, attack_rate, lin_or_exp_mode)


func _fan_adsr1_mid(voice: int, slot: _SS, pass_idx: int) -> void:
	# FUN_8001B79C: RMW ADSR1 mid-nibble (bits 4-7) = decay/sustain rate.
	# Source from slot.adsr1's bits 4-7.
	var mid_nibble: int = (slot.adsr1 >> 4) & 0xF
	# probe_adsr1_mid_register (Layer 5). Mirror of FFT BP @ 0x8001B79C
	# (function entry). FFT a0=voice, a1=mid_nibble.
	if _Trace._post_anchor and _Trace._cadence_index > 0:
		_probe_adsr1_mid_register_count += 1
		_Trace.emit("adsr1_mid_register", {
			"call_index": _probe_adsr1_mid_register_count,
			"voice": voice,
			"mid_nibble": mid_nibble,
		})
	_mixer.set_voice_adsr1_mid(voice, mid_nibble)


func _fan_adsr2_low(voice: int, slot: _SS, pass_idx: int) -> void:
	# FUN_8001BAB8: RMW ADSR2 low 6 bits. FFT computes:
	#   mode_bits = (a2 == 7) ? 0x20 : 0   (where a2 = slot+0x60 = mode_byte)
	#   new_low   = (a1 | mode_bits) & 0x3F (where a1 = slot+0x6A = release_byte)
	#   ADSR2     = (current & 0xFFC0) | new_low
	#
	# Disasm verified PC 0x8001bab8-0x8001bad4:
	#   ori   v0, zero, 0x3          ; v0 = 3
	#   beq   a2, v0, LAB_8001bad4   ; if mode==3 skip ahead (a3 = 0)
	#   _clear a3                    ; delay slot: a3 = 0
	#   xori  v0, a2, 0x7            ; v0 = mode XOR 7
	#   sltiu v0, v0, 0x1            ; v0 = (mode == 7) ? 1 : 0
	#   sll   a3, v0, 0x5            ; a3 = (mode == 7) ? 0x20 : 0
	# The `mode == 3 → skip` branch is a MIPS micro-optimization to
	# bypass the xori sequence; semantically `a3 = 0` either way for
	# non-7 modes. So the complete FFT mode-byte dispatch is:
	#   mode == 7 → 0x20    (release_mode_exp)
	#   else      → 0
	# No other mode values (1, 3, 5, ...) contribute additional bits to
	# the low-6 helper. Sibling `_fan_adsr2_high` (FUN_8001B9D4) has
	# more cases (1/5/7) because it touches different bit fields.
	# Iter-32: rate input source. FFT walker reads slot+0x6A (a dedicated
	# 5-bit rate field) via `lhu a1, 0x66(s0)` at PC 0x80014738 (s0 =
	# slot+4 per reference_fft_walker_s0_offset, so 0x66(s0) = slot+0x6A
	# in true coords). slot+0x6A is set by opcode 0xC5 and by inst-load;
	# both write the raw 5-bit rate (no mode bit). Mask `& 0x1F` matches
	# FFT's invariant that bit 5 belongs to the mode-byte path, not the
	# rate field. Previously this read `slot.adsr2 & 0x3F`, which
	# preserved stale mode-bit residue and produced systematic Δ=-32
	# divergence at probe_adsr2_low_inputs (MUSIC_25/28 — 93/160 rows).
	# See docs/MUSIC_ITER32_ADSR2_LOW_RELEASE_BYTE_FIELD_SOURCE.md.
	# slot.adsr2_mode_byte is the standing mode selector (set by 0xCA =
	# _op_ca_adsr2_mode and by inst-load via channel.mode_byte_60).
	var release_low: int = slot.release_rate_byte & 0x1F
	# iter-25 fix: FFT walker uses s0 = slot+4 (set at PC 0x80014628
	# `addiu s0, s7, 0x4`, where s7 = music_entity+0xb8 = slot base).
	# So `lw a2, 0x5c(s0)` at PC 0x8001473c reads effective slot+0x60,
	# NOT slot+0x5c. The Ghidra label is faithful to the assembly but
	# off-by-4 semantically. The LOW writer's mode source is
	# slot+0x60 = inst byte 0xf = Godot's `slot.adsr2_mode_byte` (set
	# by 0xCA opcode AND by instrument-load via channel.mode_byte_60).
	# Iter-23 mis-identified slot+0x5c as the source; that field is
	# read by the HIGH writer (PC 0x80014720 `lw a2, 0x58(s0)` = slot+0x5c).
	# See docs/MUSIC_ITER25_VOICE_16_17_RELEASE_TAIL.md.
	var mode_bits: int = 0x20 if slot.adsr2_mode_byte == 7 else 0
	var low_bits: int = (release_low | mode_bits) & 0x3F
	# iter-25 bisecting probe — mirror of FFT BP @ 0x8001BAB8 (entry of
	# FUN_8001BAB8). Pairs against PCSX probe_adsr2_low_inputs by voice.
	if _Trace._post_anchor and _Trace._cadence_index > 0:
		_Trace.emit("adsr2_low_inputs", {
			"voice": voice,
			"release_byte": release_low,
			"mode": slot.adsr2_mode_byte,
		})
	# probe_adsr2_low_register (Layer 5 synthesis). Mirror of FFT BP
	# @ 0x8001BAF8 — the sh inside FUN_8001BAB8 that commits the ADSR2
	# LOW-bits RMW to the SPU register. FFT computes:
	#   spu_value = (current_adsr2 & 0xFFC0) | low_bits
	# slot.adsr2 already carries the current value (kept in sync by
	# _op_adsr_release / end-of-note prep), so the same combination
	# yields the bit-exact value FFT writes.
	if _Trace._post_anchor and _Trace._cadence_index > 0:
		var spu_value: int = (slot.adsr2 & 0xFFC0) | low_bits
		_probe_adsr2_low_register_count += 1
		_Trace.emit("adsr2_low_register", {
			"call_index": _probe_adsr2_low_register_count,
			"voice": voice,
			"adsr2": spu_value,
		})
	_mixer.set_voice_adsr2_low(voice, low_bits, 0)
