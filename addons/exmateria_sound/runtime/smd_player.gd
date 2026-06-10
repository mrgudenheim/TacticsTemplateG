class_name SMDPlayer
extends Node

signal playback_finished
signal debug_stats_updated(summary: String)

var waveset := WavesetParser.new()
var mixer := Spu.new()
var seq: Sequencer
var smd_file: SMDParser.SMDFile
var _engine_attached := false

var _audio_player: AudioStreamPlayer
var _generator: AudioStreamGenerator
var _playback: AudioStreamGeneratorPlayback
var _playing := false
var _total_ticks: int = 0
var _last_report_time: float = 0.0
var _buffer_capacity_frames: int = 0
var _source_exhausted := false
var _last_skip_count := 0
var _max_refill_ms := 0.0
var _last_refill_ms := 0.0
var _last_push_frames := 0
var _last_active_voices := 0
var _queue_underruns := 0
var _debug_enabled := true

var _producer_thread: Thread
var _queue_mutex := Mutex.new()
var _chunk_queue: Array = []
var _queued_frames := 0
var _producer_exit := false

const GENERATOR_BUFFER_SECONDS := 1.5
const PRODUCER_TARGET_SECONDS := 1.0
const INITIAL_PREFILL_FRAMES := 4096
const REFILL_CHUNK_FRAMES := 2048
const PRODUCER_IDLE_MS := 2


func _init() -> void:
	seq = Sequencer.new(mixer, waveset)
	# Use the GDScript sequencer (the documented game-side FFT music driver),
	# not the native C++ core. The C++ sequencer (src/shared/fft_smd_sequencer_
	# core.cpp) is the DAW's port and never received the FFT end-of-note ADSR2
	# release-rate force (PC 0x800152A8 — Sequencer.tick:569-573), so retriggers
	# step the envelope from sustain straight to 0 on key-on and click/pop. The
	# GDScript path forces ADSR2 release=0x06 on a note's last tick, releasing
	# the SPU envelope to ~0 before the next key-on. Keep music on GDScript.
	seq.set_use_native_core(false)


func _ready() -> void:
	_generator = AudioStreamGenerator.new()
	_generator.mix_rate = Spu.SAMPLE_RATE
	_generator.buffer_length = GENERATOR_BUFFER_SECONDS
	_audio_player = AudioStreamPlayer.new()
	_audio_player.stream = _generator
	_audio_player.bus = "Master"
	add_child(_audio_player)
	_buffer_capacity_frames = int(_generator.mix_rate * _generator.buffer_length)


func _exit_tree() -> void:
	_stop_producer_thread()


func attach_shared_engine(shared_spu: Spu, shared_waveset: WavesetParser) -> void:
	## Replace this player's self-owned SPU + waveset with shared, already-loaded
	## instances (see godot-learning's AudioEngine autoload). Lets several players
	## share one static SPU + instrument set instead of each constructing an SPU
	## and re-uploading the instrument bank. Call once before load_smd/play_music.
	mixer = shared_spu
	waveset = shared_waveset
	seq = Sequencer.new(mixer, waveset)
	seq.set_use_native_core(false)  # keep music on the GDScript driver (see _init)
	_engine_attached = true


func load_waveset(path: String) -> bool:
	if _engine_attached:
		return true  # shared engine already has the instrument bank loaded
	var ok := waveset.load_from_file(path)
	if ok:
		ok = mixer.load_instruments(waveset)
	return ok


func load_smd(path: String) -> bool:
	# Join the producer thread BEFORE touching seq. Otherwise the previous song's
	# render thread is still calling seq.tick()/render_tick() while we reload the
	# sequencer here — a data race that can orphan a key_on (voice never keyed
	# off → note stuck on forever). See song-switch race notes.
	stop_music()
	smd_file = SMDParser.load_from_file(path)
	if smd_file == null:
		return false
	seq.load_smd(smd_file)
	return true


func load_feds_pair(path: String, pair_idx: int) -> bool:
	## Load an effect-sound pair from a feds blob (raw ENV.SED, or feds.bin
	## produced by godot-learning's parser). The pair's two channels map to
	## voices 0 and 1 via a synthetic SMDFile; music and effects use the
	## same Sequencer/SPU pipeline.
	stop_music()  # join the producer thread before mutating seq (see load_smd)
	var fb := FedsBank.load_from_file(path)
	if fb == null:
		push_error("SMDPlayer: failed to load feds from %s" % path)
		return false
	if pair_idx < 0 or pair_idx >= fb.num_pairs:
		push_error("SMDPlayer: pair %d out of range (num_pairs=%d)" % [pair_idx, fb.num_pairs])
		return false
	smd_file = fb.make_synthetic_smd(pair_idx)
	seq.load_smd(smd_file)
	return true


func play_music() -> void:
	if smd_file == null:
		return

	stop_music()

	# Let the previous song's lingering notes fade out naturally (ADSR release)
	# as this song starts — a seamless transition — instead of hard-cutting them.
	# release_all() still guarantees they terminate, so no voice sticks on (the
	# stuck-note failure mode the song-switch race used to trigger).
	mixer.release_all()

	_total_ticks = 0
	_source_exhausted = false
	_last_skip_count = 0
	_last_report_time = 0.0
	_max_refill_ms = 0.0
	_last_refill_ms = 0.0
	_last_push_frames = 0
	_last_active_voices = 0
	_queue_underruns = 0
	_queue_mutex.lock()
	_chunk_queue.clear()
	_queued_frames = 0
	_producer_exit = false
	_queue_mutex.unlock()

	# Small synchronous prefill to avoid starting completely dry.
	_enqueue_rendered_chunk(_render_chunk(INITIAL_PREFILL_FRAMES))

	_audio_player.play()
	_playback = _audio_player.get_stream_playback()
	_playing = true
	_push_ready_audio()

	_producer_thread = Thread.new()
	_producer_thread.start(Callable(self, "_producer_main"))


func stop_music() -> void:
	_playing = false
	_audio_player.stop()
	_playback = null
	_stop_producer_thread()


func is_playing() -> bool:
	return _playing


func _process(delta: float) -> void:
	if not _playing or _playback == null:
		return

	_push_ready_audio()

	var buffered := _estimate_buffered_frames()
	if _source_exhausted and buffered <= 0 and _queued_frames <= 0:
		_playing = false
		playback_finished.emit()
		return

	_last_report_time += delta
	if _last_report_time >= 1.0:
		var skips := _playback.get_skips()
		var skip_delta := skips - _last_skip_count
		_last_skip_count = skips
		var engine_ms := float(buffered) / Spu.SAMPLE_RATE * 1000.0
		var queued_ms := float(_queued_frames) / Spu.SAMPLE_RATE * 1000.0
		var summary := "eng=%sms queue=%sms push=%d gen=%sms max=%sms skips=%d(+%d) q_under=%d active=%d fps=%d" % [
			snapped(engine_ms, 0.1),
			snapped(queued_ms, 0.1),
			_last_push_frames,
			snapped(_last_refill_ms, 0.01),
			snapped(_max_refill_ms, 0.01),
			skips,
			skip_delta,
			_queue_underruns,
			_last_active_voices,
			Engine.get_frames_per_second(),
		]
		if _debug_enabled:
			print(summary)
		debug_stats_updated.emit(summary)
		_last_report_time = 0.0


func _estimate_buffered_frames() -> int:
	if _playback == null:
		return 0
	return maxi(0, _buffer_capacity_frames - _playback.get_frames_available())


func _push_ready_audio() -> void:
	if _playback == null:
		return

	var frames_available := _playback.get_frames_available()
	var pushed_total := 0

	while frames_available > 0:
		var chunk_to_push := PackedVector2Array()

		_queue_mutex.lock()
		if _chunk_queue.is_empty():
			_queue_mutex.unlock()
			if not _source_exhausted and frames_available > 0:
				_queue_underruns += 1
			break

		var queued_chunk: PackedVector2Array = _chunk_queue[0]
		if queued_chunk.size() <= frames_available:
			chunk_to_push = queued_chunk
			_chunk_queue.remove_at(0)
			_queued_frames -= chunk_to_push.size()
		else:
			chunk_to_push = queued_chunk.slice(0, frames_available)
			_chunk_queue[0] = queued_chunk.slice(frames_available)
			_queued_frames -= chunk_to_push.size()
		_queue_mutex.unlock()

		_playback.push_buffer(chunk_to_push)
		pushed_total += chunk_to_push.size()
		frames_available = _playback.get_frames_available()

	_last_push_frames = pushed_total


func _enqueue_rendered_chunk(chunk: PackedVector2Array) -> void:
	if chunk.is_empty():
		_source_exhausted = true
		return

	_queue_mutex.lock()
	_chunk_queue.append(chunk)
	_queued_frames += chunk.size()
	_queue_mutex.unlock()


func _producer_main() -> void:
	var target_frames := int(Spu.SAMPLE_RATE * PRODUCER_TARGET_SECONDS)

	while true:
		_queue_mutex.lock()
		var should_exit: bool = _producer_exit
		var queue_frames: int = _queued_frames
		_queue_mutex.unlock()

		if should_exit:
			return

		if _source_exhausted or queue_frames >= target_frames:
			OS.delay_msec(PRODUCER_IDLE_MS)
			continue

		var started_us := Time.get_ticks_usec()
		var chunk := _render_chunk(REFILL_CHUNK_FRAMES)
		var elapsed_ms := float(Time.get_ticks_usec() - started_us) / 1000.0
		_last_refill_ms = elapsed_ms
		if elapsed_ms > _max_refill_ms:
			_max_refill_ms = elapsed_ms

		if chunk.is_empty():
			_source_exhausted = true
			OS.delay_msec(PRODUCER_IDLE_MS)
			continue

		_queue_mutex.lock()
		_chunk_queue.append(chunk)
		_queued_frames += chunk.size()
		_queue_mutex.unlock()


func _stop_producer_thread() -> void:
	if _producer_thread == null:
		return

	_queue_mutex.lock()
	_producer_exit = true
	_queue_mutex.unlock()
	_producer_thread.wait_to_finish()
	_producer_thread = null


func _render_chunk(target_frames: int) -> PackedVector2Array:
	var chunk := PackedVector2Array()
	while chunk.size() < target_frames:
		if seq.tick():
			chunk.append_array(seq.render_tick())
			_total_ticks += 1
			continue
		if seq.has_active_audio():
			var remaining := target_frames - chunk.size()
			chunk.append_array(seq.render_frames_only(remaining))
			break
		break
	_last_active_voices = seq.get_active_voice_count()
	return chunk
