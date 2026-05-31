extends RefCounted
## Probe trace writer for the effect-sound parity loop.
##
## The orchestrator at smd-player/workspace/orchestrator/ runs PCSX-side
## probes that write JSONL rows for each of the 8 GOLD probe sites. This
## class emits the matching Godot-side rows to a single combined JSONL file;
## smd-player/workspace/orchestrator/validate_probe_pair.py filters by
## the row's `kind` field to compare per-probe.
##
## Activated by render_feds_pair.gd's `--trace-effect-sound=<dir>` flag. When
## disabled, every emit() is a fast no-op so the dispatcher can leave its
## emit calls in place without conditional gating at every site.
##
## NOTE: deliberately uses `extends RefCounted` without `class_name`. The
## emit sites preload this script (`const _Trace = preload(...)`); the
## script Resource itself is the type the callers see. Avoiding `class_name`
## means the singleton works even when the project's class cache is stale or
## absent (which is the common state under `godot --script ... --headless`
## or just-cloned worktrees), and there's no self-reference parse cycle.

static var _INST = null  # of this script's class -- avoid forward self-typing

# Clock 1 anchor: cadence pulse index. Incremented by play_sound.gd at the
# start of each tick_all_dispatchers call (= one RCnt2 IRQ fire on the FFT
# side). emit() auto-injects this into every row so Clock 2 events
# (opcode dispatches, note handler, etc.) carry the cadence pulse they
# fired in. PCSX-side global CADENCE_INDEX in _probe_common.lua mirrors
# this exactly; matching values prove Clock 1 ↔ Clock 2 phase alignment.
static var _cadence_index: int = 0

# Flips true on the first event_dispatch fire (set by SharedDispatcher).
# Layer-5 probes that fire pre-anchor (spu_irq_walker passes, LFO state
# init, etc.) gate their emits on this so PCSX's post-anchor-only row
# count is matched exactly. The SPU register writes / state updates
# themselves are NOT gated — only the trace emits.
static var _first_dispatch_fired: bool = false

# Flips true one tick AFTER _first_dispatch_fired — set by play_sound.gd's
# end-of-tick anchor latch. Use this (not _first_dispatch_fired) to gate
# probes that fire from walker passes INSIDE the anchor tick: by the time
# `_post_anchor` is true, the cadence has truly transitioned to post-
# anchor numbering (cad=1 on the next tick). Symmetric with PCSX gating
# on `FIRST_OPCODE_FIRED && CADENCE_INDEX > 0`.
static var _post_anchor: bool = false


var _file: FileAccess = null
var _path: String = ""
var _row_count: int = 0


static func is_enabled() -> bool:
	return _INST != null and _INST._file != null


static func get_instance():
	return _INST


static func enable(jsonl_path: String):
	## Open a fresh JSONL file at `jsonl_path` and install the instance as
	## the global trace sink. If a sink is already open, it is flushed +
	## closed first.
	if _INST != null:
		_INST.disable_inst()
	# `_INST` is typed Variant deliberately; `(load(SELF_PATH) as Script).new()`
	# would self-reference. The cheapest path is `(get_script() as Script)` but
	# `get_script()` is instance-only. Use the fact that we ARE in the script
	# context and call `new` via the script Resource preloaded by callers.
	# For callers, `_Trace.enable(...)` works because GDScript resolves
	# `_Trace.new()` if `_Trace` is a preload const. So we delegate
	# instantiation to a tiny helper that's also reachable as the static
	# entry point.
	var inst = _build_instance()
	inst._open(jsonl_path)
	_INST = inst
	print("[EffectSoundTraceWriter] enabled -> %s" % jsonl_path)
	return inst


static func _build_instance():
	# `load("res://...")` returns the script Resource even before class
	# cache is built; calling `.new()` on it produces an instance without
	# triggering a class_name lookup. Local path avoids preload self-cycle.
	var s := load("res://addons/exmateria_sound/runtime/effect_sound/trace_writer.gd")
	return s.new()


static func disable() -> void:
	if _INST != null:
		_INST.disable_inst()
		_INST = null


static func emit(kind: String, payload: Dictionary) -> void:
	## Class-level pass-through. Cheap when disabled (one nil-check + return).
	if _INST == null or _INST._file == null:
		return
	_INST._emit(kind, payload)


# --- instance ---


func _open(path: String) -> void:
	# Ensure the directory exists.
	var dir := path.get_base_dir()
	if dir != "" and not DirAccess.dir_exists_absolute(dir):
		DirAccess.make_dir_recursive_absolute(dir)
	_file = FileAccess.open(path, FileAccess.WRITE)
	if _file == null:
		push_error("EffectSoundTraceWriter: cannot open %s (err=%d)" %
				[path, FileAccess.get_open_error()])
		return
	_path = path
	_row_count = 0


func disable_inst() -> void:
	if _file != null:
		_file.flush()
		_file.close()
		_file = null
	print("[EffectSoundTraceWriter] disabled (%d rows -> %s)" %
			[_row_count, _path])


func _emit(kind: String, payload: Dictionary) -> void:
	# call_index lives in payload; the probe sites maintain their own counters.
	# Auto-inject cadence_index (= Clock 1 pulse index at the moment of the
	# emit) so every Clock 2 event row carries the cadence pulse it fired
	# in. Callers may pre-set cadence_index in their payload; we respect
	# that and only inject if absent.
	# Wrap into a single-line JSON object: {"kind": <kind>, ...payload}.
	var row: Dictionary = { "kind": kind }
	for k in payload.keys():
		row[k] = payload[k]
	if not row.has("cadence_index"):
		row["cadence_index"] = _cadence_index
	_file.store_line(JSON.stringify(row))
	_row_count += 1
