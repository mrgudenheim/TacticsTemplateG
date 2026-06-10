class_name SoundTrackController
## Orchestrates FFT effect sound playback at the timeline layer: walks the
## sound tracks embedded in the effect's timeline section, resolves each
## keyframe's sound_id through the effect_flags resolver, and triggers the
## corresponding feds pair for playback.
##
## Designed to migrate into godot-learning as a sibling to
## PaletteTrackController / CameraTrackController — subscribes to an external
## 30 Hz tick instead of owning one. The smd-player integration wraps this
## with a Timer; a future godot-learning integration would replace the Timer
## with TimelineController's existing frame signal.
##
## Reference behaviour:
##   - research/wiki_articles/timeline_section.txt §3, §4, §7
##   - research/wiki_articles/effect_flags_section.txt


signal pair_triggered(pair_idx: int, from_channel: int, sound_id: int)
signal finished()

var debug_log: bool = true


class Channel:
	var keyframes: Array = []
	var channel_index: int = 0
	var max_keyframe: int = 0
	var enforce_max: bool = false
	var kf_idx: int = 0
	var frames_left: int = 0
	var done: bool = false

	func start() -> void:
		kf_idx = 0
		done = keyframes.is_empty()
		frames_left = int(keyframes[0].get("duration_frames", 0)) if not done else 0

	func advance() -> bool:
		## Advance one keyframe. Returns true if the new current keyframe
		## should fire (i.e. it's within bounds and has a real sid).
		kf_idx += 1
		if (enforce_max and kf_idx > max_keyframe) or kf_idx >= keyframes.size():
			done = true
			return false
		frames_left = int(keyframes[kf_idx].get("duration_frames", 0))
		return true

	func current_sid() -> int:
		if done or kf_idx < 0 or kf_idx >= keyframes.size():
			return 0
		return int(keyframes[kf_idx].get("sound_id", 0))


class ForEachContext:
	var channels: Array = []
	var started_at_frame: int = 0
	var done: bool = false

	func relative_frame(abs_frame: int) -> int:
		return abs_frame - started_at_frame

	func all_channels_done() -> bool:
		for c in channels:
			if not c.done:
				return false
		return true


# Typed as Variant (no annotation) so this script compiles in --script
# mode (Godot CLI) where the class_name registry isn't refreshed. Editor
# mode is unaffected — these still hold EffectSoundResolver / FedsBank.
const _EffectSoundResolver = preload("res://addons/exmateria_sound/runtime/effect_sound_resolver.gd")
const _FedsBank = preload("res://addons/exmateria_sound/runtime/feds_bank.gd")
const _EffectJSONLoader = preload("res://addons/exmateria_sound/runtime/effect_json_loader.gd")
var resolver = null
var feds_bank = null

var phase1_channels: Array = []      # Array[Channel]
var phase2_channels: Array = []
var animate_tick_template: Array = []  # Array[Dictionary] — clone per for-each spawn

var phase1_duration: int = 0
var spawn_delay: int = 0
var phase2_delay: int = 0
var target_count: int = 1
var three_phase: bool = false

var _for_each_contexts: Array = []   # Array[ForEachContext]
var _next_spawn_target: int = 0
var _started: bool = false
var _finished_emitted: bool = false
var _frame: int = 0
# Frames of FFT-side pre-anchor lead-in to skip before Godot's _frame=0.
# Resolves the "timeline-driver anchor lag": Godot's `update(0)` runs at the
# very first render-loop outer tick, but FFT's `process_timeline_frame`
# advances inside an animation-VM dispatcher that has already ticked N frames
# of savestate-restore replay before the FIRST_OPCODE_FIRED anchor. Setting
# `pre_anchor_offset = N` makes Godot's logical _frame = update_arg - N, so
# update(N) corresponds to FFT frame 0. See
# research/effect_sound/working_documents/TIMELINE_DRIVER_ANCHOR_LAG_REFACTOR_PLAN.md.
var _pre_anchor_frame_offset: int = 0
var _initial_fired: bool = false
# Sub-tick within each outer-tick at which the keyframe walker decrements +
# fires. Set by load_effect from the timeline header's `stc_fire_sub_tick`
# field (default 0 = legacy sub-tick-0 fire for un-calibrated effects).
# Mirrors FFT's animate_tick walker's per-effect sub-tick offset (ice=5,
# cure_4=6). See ICE_V16_STC_IRQ_GRANULAR_REFACTOR_PLAN.md §7.
var fire_sub_tick: int = 0


func load_effect(loaded) -> bool:
	if not loaded.has_sound():
		return false

	feds_bank = loaded.feds_bank
	resolver = _EffectSoundResolver.from_sound_config(loaded.sound_config)

	var header: Dictionary = loaded.timeline_header
	phase1_duration = int(header.get("phase1_duration", 0))
	spawn_delay = int(header.get("spawn_delay", 1))
	phase2_delay = int(header.get("phase2_delay", 0))
	fire_sub_tick = int(header.get("stc_fire_sub_tick", 0))

	three_phase = loaded.script_is_three_phase()

	phase1_channels = _build_channels(loaded.sound_tracks.get("phase1", []), true)
	phase2_channels = _build_channels(loaded.sound_tracks.get("phase2", []), true)
	animate_tick_template = loaded.sound_tracks.get("animate_tick", [])
	return true


func start(p_target_count: int = 1, pre_anchor_offset: int = 0,
		vm_snapshot: Dictionary = {}) -> void:
	target_count = maxi(1, p_target_count)
	_pre_anchor_frame_offset = maxi(0, pre_anchor_offset)
	resolver.reset_counters()
	_frame = -_pre_anchor_frame_offset
	_next_spawn_target = 0
	_started = true
	_finished_emitted = false
	_initial_fired = false
	_for_each_contexts.clear()

	for ch in phase1_channels:
		ch.start()
	for ch in phase2_channels:
		ch.start()

	# vm_snapshot replay (HASTE_VOICE_21_FAITHFUL_TIMELINE_VM_REPLAY.md §6.2).
	# Per-channel cursor seed for sessions whose savestate captured the audio
	# entity mid-cast. For haste the per-channel rows are out-of-bounds
	# residue (camera/palette state in the same offsets) so this is a
	# defensive no-op there; other sessions may carry real data.
	#
	# The entity-level sound_track_cursor (+0x34/+0x36) is NOT consumed here
	# yet — see HASTE_VOICE_21_KEYON_LAG_INVESTIGATION.md §5 Path A. The
	# Path A experiment closed the absolute KEY-ON timing gap but exposed a
	# downstream bytecode-cadence-rate mismatch (Godot pair=0 dispatcher
	# reaches v20 KEY-ON in 1.55 cad after trigger; PCSX takes 2.77 cad)
	# that regresses voice 21 cos_dist 0.094 → 0.610 on haste + 0.0007 →
	# 0.029 on reraise. Path A needs the bytecode-timing fix first.
	if not vm_snapshot.is_empty():
		_apply_vm_snapshot(vm_snapshot)

	# Initial keyframe firing + standalone-effect spawn are deferred to the
	# first update() call where _frame >= 0. With pre_anchor_offset = 0 this
	# happens on update(0) immediately after start(), matching the previous
	# behaviour; with offset > 0 the deferral aligns the first fire with FFT
	# frame 0 instead of Godot's update_arg=0.


func _apply_vm_snapshot(snapshot: Dictionary) -> void:
	## Per-channel cursor seed from PCSX's animation-VM snapshot's audio
	## entity (chcnt>=4, target_index==1). Reads sound_channels[] and
	## applies (kf_idx, frames_left) to matching phase1/phase2 channels
	## when the values pass defensive bounds (within keyframes.size(),
	## not past max_keyframe, non-negative). Out-of-bounds rows (haste's
	## kf=48/4/4 carrying camera-track residue) are skipped.
	var entities: Array = snapshot.get("entities", [])
	if entities.is_empty():
		return
	var audio_entity: Dictionary = {}
	for ent_v in entities:
		if not (ent_v is Dictionary):
			continue
		var ent: Dictionary = ent_v
		var chcnt: int = int(ent.get("chcnt", 0))
		var target_index: int = int(ent.get("target_index", 0))
		if chcnt >= 4 and target_index == 1:
			audio_entity = ent
			break
	if audio_entity.is_empty():
		if debug_log:
			print("[stc] vm_snapshot: no audio entity (chcnt>=4, target_index==1) — skipping seed")
		return
	var sound_channels: Array = audio_entity.get("sound_channels", [])
	var seeded := 0
	for entry_v in sound_channels:
		if not (entry_v is Dictionary):
			continue
		var entry: Dictionary = entry_v
		var ci: int = int(entry.get("channel_index", -1))
		var kf_idx: int = int(entry.get("kf_idx", 0))
		var frames_left: int = int(entry.get("frames_left", 0))
		if kf_idx == 0 and frames_left == 0:
			continue
		var target: Channel = _channel_for_index(phase1_channels, ci)
		if target == null:
			target = _channel_for_index(phase2_channels, ci)
		if target == null:
			continue
		if kf_idx < 0 or kf_idx >= target.keyframes.size():
			continue
		if target.enforce_max and kf_idx > target.max_keyframe:
			continue
		if frames_left < 0:
			continue
		target.kf_idx = kf_idx
		target.frames_left = frames_left
		target.done = false
		seeded += 1
	if debug_log:
		print("[stc] vm_snapshot seeded %d sound-track cursors from audio entity %s" % [
			seeded, str(audio_entity.get("entity_addr", "?"))])


static func _channel_for_index(channels: Array, channel_index: int) -> Channel:
	for ch in channels:
		if (ch as Channel).channel_index == channel_index:
			return ch
	return null


func update(frame: int, sub_tick: int = 0) -> void:
	if not _started:
		return
	# FFT-faithful gate: animate_tick decrements once per outer-tick AT the
	# per-effect sub-tick offset. Skip every sub-tick except the calibrated
	# fire moment. Default fire_sub_tick=0 preserves legacy behaviour.
	if sub_tick != fire_sub_tick:
		return
	_frame = frame - _pre_anchor_frame_offset
	if _frame < 0:
		return  # FFT-side pre-anchor — skip Godot's tick

	if not _initial_fired:
		_initial_fired = true
		# 1-phase (or 3-phase with no phase1 duration): spawn target 0 now;
		# its kf[0] fires inside _try_spawn_for_each.
		if not three_phase or phase1_duration <= 0:
			_try_spawn_for_each()
		# 3-phase: fire phase1 kf[0]. _fire_initial_keyframes is a no-op for
		# the 1-phase case so it's safe to call unconditionally.
		_fire_initial_keyframes()

	# Tick existing channels FIRST. Spawns that happen this frame start fresh
	# next frame, which matches the game's "frame N = spawn → frame N+1 =
	# first tick" semantics.
	if three_phase and _frame < phase1_duration:
		for ch in phase1_channels:
			_tick_channel(ch, 0)

	for ctx in _for_each_contexts:
		if ctx.done:
			continue
		for ch in ctx.channels:
			_tick_channel(ch, 0)
		if ctx.all_channels_done():
			ctx.done = true

	var phase2_start := _compute_phase2_start()
	if three_phase and _frame >= phase2_start:
		for ch in phase2_channels:
			_tick_channel(ch, 0)

	# Spawn new for-each instances whose scheduled frame has been reached.
	if three_phase and _frame >= phase1_duration:
		_try_spawn_for_each()

	_check_finished()


func is_finished() -> bool:
	return _started and _finished_emitted


func _compute_phase2_start() -> int:
	if not three_phase:
		return 0
	return phase1_duration + maxi(0, target_count - 1) * spawn_delay + phase2_delay


func _try_spawn_for_each() -> void:
	while _next_spawn_target < target_count:
		var spawn_at := phase1_duration + _next_spawn_target * spawn_delay
		if _frame < spawn_at:
			return
		var ctx := ForEachContext.new()
		ctx.started_at_frame = spawn_at
		ctx.channels = _build_channels(animate_tick_template, false)
		for ch in ctx.channels:
			ch.start()
		_for_each_contexts.append(ctx)
		_next_spawn_target += 1
		# Fire kf[0] for the newly spawned for-each context.
		for ch in ctx.channels:
			_maybe_fire(ch)


func _fire_initial_keyframes() -> void:
	if three_phase:
		for ch in phase1_channels:
			_maybe_fire(ch)
		# phase2 starts later; don't fire at start()
	# Standalone (1-phase) animate_tick already fired via _try_spawn_for_each.


func _tick_channel(ch: Channel, _reserved: int) -> void:
	if ch.done:
		return
	if ch.frames_left > 0:
		ch.frames_left -= 1
		if ch.frames_left <= 0:
			if ch.advance():
				_maybe_fire(ch)


func _maybe_fire(ch: Channel) -> void:
	var sid := ch.current_sid()
	if sid < 2:
		return
	if resolver == null or feds_bank == null:
		if debug_log:
			print("[stc] frame=%d ch=%d kf=%d sid=%d SKIP (no resolver/bank)" % [
				_frame, ch.channel_index, ch.kf_idx, sid])
		return
	# Note: `resolver` is typed as the class_name EffectSoundResolver. When
	# this script is loaded from --script mode (no editor cache), that
	# class isn't resolved, so untyped vars (no `:=`) keep the inference
	# pipeline happy. Editor-mode behavior is unchanged.
	#
	# Config-channel index is derived from the TIMELINE sound_id, not the
	# track's position within its phase. Per sound_section.txt §7.3:
	#   sound_id 0/1 → skip
	#   sound_id N → use config_channel (N - 2)
	# Verified against FFT MIPS advance_p1_sound_track (0x801A478C) at the
	# `lookup_sound_effect(sound_id - 2)` call site.
	#
	# This was previously passing ch.channel_index (the track index 0/1/2
	# within phase1/phase2/animate_tick). For cure_no_music the track at
	# ch_index=0 happened to point at config_ch0 — so the bug was invisible
	# until cure_4's animate_tick.track0 needed config_ch2 (PARITY_AB).
	var config_channel_index: int = sid - 2
	var config_channel: int = int(resolver.resolve(config_channel_index, sid))
	var pair_idx: int = config_channel - 1
	var bytes_size_a: int = 0
	var bytes_size_b: int = 0
	var pair_in_range: bool = pair_idx >= 0 and pair_idx < feds_bank.num_pairs
	if pair_in_range:
		bytes_size_a = feds_bank.get_channel_bytes(pair_idx * 2).size()
		bytes_size_b = feds_bank.get_channel_bytes(pair_idx * 2 + 1).size()
	if debug_log:
		print("[stc] frame=%d ch=%d kf=%d sid=%d -> config=%d pair=%d bytes=(%d,%d) %s" % [
			_frame, ch.channel_index, ch.kf_idx, sid,
			config_channel, pair_idx, bytes_size_a, bytes_size_b,
			"" if pair_in_range else "OUT_OF_RANGE"])
	if config_channel <= 0 or not pair_in_range:
		return
	# FFT's FUN_80013B20 receives sound_id = low 16 bits of a1, where a1
	# was set by lookup_sound_effect → the *resolved* id (id_a/id_b/id_c
	# per the channel's mode). The timeline sid is the keyframe value
	# BEFORE that resolution and is wrong for the FEDS chan+0x92 lookup
	# (e.g. cure_no_music timeline sid=2 with mode=1 resolves to id_a=1,
	# and feds[D+1]=0x64=19200 matches PCSX, while feds[D+2]=0xBA
	# saturates to 32767). See CHAN_92_STATIC_PORT_PLAN.md §4 Q2.
	pair_triggered.emit(pair_idx, ch.channel_index, config_channel)


func _check_finished() -> void:
	if _finished_emitted:
		return
	if three_phase:
		for ch in phase1_channels:
			if not ch.done:
				return
		for ch in phase2_channels:
			if not ch.done:
				return
	if _next_spawn_target < target_count:
		return
	for ctx in _for_each_contexts:
		if not ctx.done:
			return
	_finished_emitted = true
	finished.emit()


static func _build_channels(raw_channels: Array, enforce_max: bool) -> Array:
	var out: Array = []
	for raw in raw_channels:
		if not (raw is Dictionary):
			continue
		var ch := Channel.new()
		ch.channel_index = int(raw.get("channel_index", 0))
		ch.max_keyframe = int(raw.get("max_keyframe", 0))
		ch.enforce_max = enforce_max
		ch.keyframes = raw.get("keyframes", [])
		out.append(ch)
	return out
