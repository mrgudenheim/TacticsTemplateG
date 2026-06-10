class_name Spu
extends RefCounted

## Thin GDScript binding to the native PSX SPU (FFTSpuMixerNative in libfftspu).
## This class holds NO DSP — it programs voice registers and forwards every
## call to the native core, which does the ADPCM decode, ADSR, pitch/vol LFOs,
## reverb, and the 24-voice → interleaved-stereo mix. It is the GDScript-facing
## handle to the SPU; the FFT sound driver (sequencer / effect VM) drives it the
## same way FFT's CPU code drove the real PSX SPU's registers.

const SAMPLE_RATE := 44100
const NUM_VOICES := 24
const RAM_INSTRUMENT_BASE := 0x1000

var _native := FFTSpuMixerNative.new()
var _reverb_enabled_state := true


func load_instruments(source) -> bool:
	var instruments: Array
	var adpcm_bank := PackedByteArray()
	if source is WavesetParser:
		instruments = source.instruments
		adpcm_bank = source.adpcm_data
	else:
		instruments = source
	var payload: Array = []
	payload.resize(instruments.size())
	for i in range(instruments.size()):
		var inst = instruments[i]
		var dict := {
			"is_null": inst.is_null,
			"fine_tune": inst.fine_tune,
			"adsr1": inst.adsr1,
			"adsr2": inst.adsr2,
			"sample_offset": inst.sample_offset,
			"sample_size": inst.sample_size,
			"loop_start": inst.loop_start,
			"loop_offset_bytes": inst.loop_offset_bytes,
			"has_explicit_loop_start": inst.has_explicit_loop_start,
			"has_loop_repeat": inst.has_loop_repeat,
			"start_offset_bytes": inst.start_offset_bytes,
			"start_sample_skip": inst.start_sample_skip,
		}
		payload[i] = dict
	return _native.load_instruments(payload, adpcm_bank)


func reset() -> void:
	_native.reset()


func key_on(voice_idx: int, instrument_idx: int, pitch: int, vol_l: int, vol_r: int,
		adsr1: int, adsr2: int, p_reverb: bool = false) -> void:
	_native.key_on(voice_idx, instrument_idx, pitch, vol_l, vol_r, adsr1, adsr2, p_reverb)


func key_on_with_addresses(voice_idx: int, instrument_idx: int, pitch: int, vol_l: int, vol_r: int,
		adsr1: int, adsr2: int, start_addr: int, loop_addr: int, p_reverb: bool = false) -> void:
	_native.key_on_with_addresses(
		voice_idx,
		instrument_idx,
		pitch,
		vol_l,
		vol_r,
		adsr1,
		adsr2,
		start_addr,
		loop_addr,
		p_reverb
	)


func key_off(voice_idx: int) -> void:
	_native.key_off(voice_idx)


func release_all() -> void:
	## Key-off every voice so currently-sounding notes enter their ADSR release
	## and fade out naturally (reverb tail too), instead of being hard-cut like
	## reset(). Used at song-switch for a seamless transition — the previous
	## song's notes ring out as the new one starts — while still guaranteeing
	## they terminate (release → 0), so no voice can stick on forever.
	for v in range(NUM_VOICES):
		_native.key_off(v)


func seed_voice_residue(voice_idx: int, start_addr: int, loop_addr: int, curr_addr: int,
		adsr1: int, adsr2: int, env_state: int, env_vol: int,
		vol_l: int, vol_r: int, raw_pitch: int, reverb: bool) -> void:
	# State-preserving residue seed for voices that were keyed-on in the
	# savestate (e.g. haste voice 20 / 21 — the FM modulator+carrier pair
	# captured mid-note). Restores SPU register state verbatim WITHOUT
	# resetting the ADSR to ATTACK or rewinding curr_addr to start_addr —
	# the voice continues playing from where the savestate caught it.
	# See HASTE_VOICE_21_FMOD_LFO_RESIDUE_FIX.md §5.
	_native.seed_voice_residue(voice_idx, start_addr, loop_addr, curr_addr,
			adsr1, adsr2, env_state, env_vol, vol_l, vol_r, raw_pitch, reverb)


func set_voice_pitch(voice_idx: int, raw_pitch: int) -> void:
	_native.set_voice_pitch(voice_idx, raw_pitch)


func set_voice_fmod(voice_idx: int, mode: int) -> void:
	# FMod mode: 0=off, 1=this voice modulated by previous voice's
	# emitted sample, 2=this voice provides FM to next voice. Used
	# for FFT effect-pool silent-driver pairs (e.g. ice v18=2 → v19=1).
	_native.set_voice_fmod(voice_idx, mode)


func set_voice_noise(voice_idx: int, on: bool) -> void:
	# SPU noise mode (Chan::Noise per PCSX-Redux spu.cc:296-345). When on,
	# this voice's source sample is replaced by the global LFSR noise output;
	# ADSR/volume still apply normally.
	_native.set_voice_noise(voice_idx, on)


func set_noise_clock(noise_clock: int) -> void:
	# SPU global noise clock (spuCtrl bits 8-13, range 0..63). 0 = broadband.
	# Hardcoded default works for ice's "white noise" character; FFT may
	# write a different value (probe pending).
	_native.set_noise_clock(noise_clock)


func set_noise_state(noise_val: int, noise_clock: int, noise_count: int) -> void:
	# Seed noise LFSR state from a PCSX-Redux savestate's m_noiseVal so
	# Godot's noise generator matches PCSX bit-for-bit from the seed point
	# forward. Used to align noise-using sessions where LFSR phase matters.
	_native.set_noise_state(noise_val, noise_clock, noise_count)


func set_voice_pre_pitch(voice_idx: int, pre_pitch: int) -> void:
	_native.set_voice_pre_pitch(voice_idx, pre_pitch)


func set_voice_adsr1_low(voice_idx: int, nibble: int) -> void:
	_native.set_voice_adsr1_low(voice_idx, nibble)


func set_voice_adsr2(voice_idx: int, adsr2: int) -> void:
	_native.set_voice_adsr2(voice_idx, adsr2)


# Bit-window setters mirroring FFT helpers FUN_8001B428/B4B0/B79C/B938/BAB8.
# These match the actual FFT helper write granularity so the SPU register-
# walker can fan out to the right SPU register on the right bits with RMW
# semantics on each voice's cached adsr1/adsr2/vol_L/vol_R.
func set_voice_volume_lr(voice_idx: int, vol_l: int, vol_r: int) -> void:
	_native.set_voice_volume_lr(voice_idx, vol_l, vol_r)


func set_voice_volume_lr_with_mode(voice_idx: int, vol_l: int, vol_r: int, mode_l: int, mode_r: int) -> void:
	_native.set_voice_volume_lr_with_mode(voice_idx, vol_l, vol_r, mode_l, mode_r)


func set_voice_adsr1_high(voice_idx: int, attack_rate: int, lin_or_exp_mode: int) -> void:
	_native.set_voice_adsr1_high(voice_idx, attack_rate, lin_or_exp_mode)


func set_voice_adsr1_mid(voice_idx: int, mid_nibble: int) -> void:
	_native.set_voice_adsr1_mid(voice_idx, mid_nibble)


func set_voice_adsr2_low(voice_idx: int, low_bits: int, mode: int) -> void:
	_native.set_voice_adsr2_low(voice_idx, low_bits, mode)


# Walker bit 0x008 SAMPLE_ADDR fan-out (FUN_8001B6A4 writes SPU+0x6,
# FUN_8001B720 writes SPU+0xE). Pure register writes; no KEYON re-arm.
func set_voice_start_addr(voice_idx: int, start_addr: int) -> void:
	_native.set_voice_start_addr(voice_idx, start_addr)


func set_voice_repeat_addr(voice_idx: int, repeat_addr: int) -> void:
	_native.set_voice_repeat_addr(voice_idx, repeat_addr)


func init_voice_pitch_lfo(voice_idx: int, count: int, signed_step: int, rate_reload: int) -> void:
	_native.init_voice_pitch_lfo(voice_idx, count, signed_step, rate_reload)


func clear_voice_pitch_lfo(voice_idx: int) -> void:
	_native.clear_voice_pitch_lfo(voice_idx)


func set_voice_pitch_lfo_depth(voice_idx: int, depth: int, depth_delta: int) -> void:
	_native.set_voice_pitch_lfo_depth(voice_idx, depth, depth_delta)


func init_voice_volume_lfo(voice_idx: int, count: int, signed_step: int, rate_reload: int) -> void:
	_native.init_voice_volume_lfo(voice_idx, count, signed_step, rate_reload)


func clear_voice_volume_lfo(voice_idx: int) -> void:
	_native.clear_voice_volume_lfo(voice_idx)


func set_voice_volume_lfo_depth(voice_idx: int, depth: int, depth_delta: int) -> void:
	_native.set_voice_volume_lfo_depth(voice_idx, depth, depth_delta)


func set_voice_lfo_subslot(voice_idx: int, subslot_idx: int,
		accum: int, step_current: int, step_source: int,
		countdown: int, inner_reload: int,
		depth: int, depth_reload: int,
		mode: int, active_dir_flags: int) -> void:
	# Seed a chan-side LFO subslot from a PCSX savestate's chan_lfo_residue
	# snapshot. For sessions whose savestate caught a voice mid-LFO (haste
	# voice 20 subslot 2 with accum=-9.4e8), Godot would otherwise start
	# every subslot zeroed and the modulator's per-sample sval would
	# diverge — FM then amplifies that into voice 21 cos_dist 0.43. See
	# HASTE_VOICE_21_FAITHFUL_LFO_RESIDUE_REPLAY.md §6.4/§6.5.
	_native.set_voice_lfo_subslot(voice_idx, subslot_idx,
			accum, step_current, step_source,
			countdown, inner_reload,
			depth, depth_reload,
			mode, active_dir_flags)


func set_lfo_pitch_bias_enabled(enabled: bool) -> void:
	_native.set_lfo_pitch_bias_enabled(enabled)


func set_lfo_tick_samples(samples: int) -> void:
	_native.set_lfo_tick_samples(samples)


func render_interleaved_pcm16(num_frames: int) -> PackedInt32Array:
	return _native.render_interleaved_pcm16(num_frames)


func render(num_frames: int) -> PackedVector2Array:
	return _native.render_frames(num_frames)


func render_voice_pcm16(num_frames: int, voice_idx: int) -> PackedInt32Array:
	return _native.render_voice_pcm16(num_frames, voice_idx)


func render_replay_mix_frames(num_frames: int, per_voice_samples: Array, per_voice_events: Array,
		ground_truth_rvb_input: PackedInt32Array = PackedInt32Array()) -> PackedInt32Array:
	return _native.render_replay_mix_frames(num_frames, per_voice_samples, per_voice_events, ground_truth_rvb_input)


func set_reverb_debug(enabled: bool, path: String = "") -> void:
	if path != "":
		_native.set_reverb_debug_path(path)
	_native.set_reverb_debug_enabled(enabled)


func get_active_voice_count() -> int:
	return _native.get_active_voice_count()


func get_debug_stats() -> Dictionary:
	return _native.get_debug_stats()


func get_voice_debug_info(voice_idx: int) -> Dictionary:
	return _native.get_voice_debug_info(voice_idx)


func set_sampled_voice_trace_enabled(enabled: bool) -> void:
	_native.set_sampled_voice_trace_enabled(enabled)


func set_sampled_voice_trace_dense(enabled: bool) -> void:
	_native.set_sampled_voice_trace_dense(enabled)


func set_sampled_voice_trace_voices(voice_indices: PackedInt32Array) -> void:
	_native.set_sampled_voice_trace_voices(voice_indices)


func clear_sampled_voice_trace() -> void:
	_native.clear_sampled_voice_trace()


func get_sampled_voice_trace() -> Array:
	return _native.get_sampled_voice_trace()


func set_reverb_enabled(enabled: bool) -> void:
	_reverb_enabled_state = enabled
	_native.set_reverb_enabled(enabled)


func set_reverb_algorithm(algorithm: String) -> void:
	_native.set_reverb_algorithm(algorithm.to_lower())


func get_reverb_algorithm() -> String:
	return _native.get_reverb_algorithm()


func set_reverb_buffer_start(addr: int) -> void:
	_native.set_reverb_buffer_start(addr)


func get_reverb_buffer_start() -> int:
	return _native.get_reverb_buffer_start()


func set_reverb_curr_addr(addr: int) -> void:
	_native.set_reverb_curr_addr(addr)


func get_reverb_curr_addr() -> int:
	return _native.get_reverb_curr_addr()


# Async-commit walker IRQ cadence (FUN_80014590 analog).
func set_irq_period_samples(n: int) -> void:
	_native.set_irq_period_samples(n)


func drain_irq_passes() -> int:
	return _native.drain_irq_passes()


func get_irq_pass_counter() -> int:
	return _native.get_irq_pass_counter()
