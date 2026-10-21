extends RefCounted

## BakedAudio — resolve a music slot or an effect-sound pair to a PRE-RENDERED WAV.
##
## The whole corpus has been rendered offline through this same SPU
## (`exmateria-synth/tools/bake_corpus.py`): 100 songs and 1009 battle-effect pairs.
## This class is the SOURCE SWAP that lets the game play those renders
## instead of synthesising them live — `MusicPlayer.play_slot(27)` and
## `ExMateriaEffectSfx.play_pair(tok, bank, 1, 2)` keep their signatures and their
## callers, and resolve to a file here instead of to the sequencer.
##
## 🔴 **THE SEQUENCER PATH IS NOT DELETED AND MUST NOT BE.** It is the arm every parity
## number is taken against, and it is what every miss here lands on. `enabled = false`
## (the `audio.baked_enabled` tunable, F3 → AUDIO) puts every caller back on it, and so
## does a missing manifest or a missing file — the fallback is per-lookup, not per-boot,
## so one cast can sequence while the next plays a WAV.
##
## [b]Effect coverage is now TOTAL — 401 of 401 sound-bearing banks, 1009 pairs.[/b]
## It was 292 for a while: the bake sliced the feds section out of the `E###.BIN` file
## header, and that walk missed the 109 CODE-format effects (first word `0x27BDxxxx`),
## which a later locator pass added as 367 more pairs. So an UNCOVERED effect bank is
## no longer a reachable state, and the per-lookup fallback below now exists for the
## other misses, not for that one.
##
## ⚠️ [b]THE FALLBACK IS THE NATIVE C++ SPU, AND IT IS GPL.[/b] "Falls back to the
## sequencer" means the GDScript sequencer driving `ExMateriaPsxSpu` — the PCSX-derived
## native core in `addons/exmateria_spu`. It does NOT mean a GDScript synth: the
## GDScript synth lives in `exmateria-synth`, which BAKED this corpus and is not
## installed in the game at all. There is no GPL-free live renderer here, so every
## fallback below is a path back onto the GPL core.
##
## [b]The host says where the assets are[/b] — `ROOT_SETTING` below, never a path
## spelled here. That directory holds a `manifest.tsv` naming every file, its length
## and its loop points, plus the `music/` and `sfx/` trees the manifest's own paths
## are relative to. Streams are read with `AudioStreamWAV.load_from_file`, which
## bypasses Godot's import pipeline entirely — importing 1,384 WAVs would copy the
## whole 2.10 GB into the import cache for nothing, so the host is expected to keep a
## `.gdignore` beside the manifest.
##
## Vault: [[SPU Voice Engine]]
## Vault: [[WAVESET Instrument Bank]]

## The `ProjectSettings` key a HOST points at its baked corpus — a directory holding
## `manifest.tsv` plus the `music/` and `sfx/` trees the manifest's paths are relative to.
##
## 🔴 **THE ADDON MAY NOT SPELL THE HOST'S ADDRESS.** Shipping the addon ships this file;
## it does not ship a `res://assets/` laid out our way, and a stranger project need not
## have one (ADR-0202 dec. 5; `exmateria_battlefield/content_root` is the shipped
## precedent and this follows it exactly).
##
## ⚠️ **AND THE UNSET CASE IS SILENT HERE, WHICH IS WHERE IT DIVERGES FROM THAT
## PRECEDENT.** Battlefield's `resolve()` `push_error`s when no host declared a root,
## because a battlefield with no maps is a broken install. A project with no baked corpus
## is not broken — it sequences on the native core, which is the original path and still
## the only complete one. So "unset" and "declared but not linked" both mean exactly what
## `audio.baked_enabled = false` means, and neither is an error.
const ROOT_SETTING := "exmateria_sound/baked_audio_root"
const MANIFEST_NAME := "manifest.tsv"

## The flag. `false` sends every caller back to the live sequencer; the switch is
## per-LOOKUP, so it takes effect on the next `play_slot` / `play_pair` rather than
## cutting whatever is already sounding. Declared as the `audio.baked_enabled`
## tunable by `ExMateriaEffectSfx.tunables()` and bound by the host adapter.
static var enabled := true

## Loaded streams, keyed by manifest-relative path, newest use last in `_lru`.
## Bounded by BYTES, not by count: a song is ~15 MB and an effect pair ~700 KB, so
## a count-based cap would mean two very different things for the two kinds. An
## evicted stream stays alive as long as an AudioStreamPlayer still holds it —
## this dict owns a reference, not the object's lifetime.
const CACHE_BUDGET_BYTES := 256 << 20

static var _loaded := false
static var _ok := false
static var _music: Dictionary = {}    # slot int -> row
static var _sfx: Dictionary = {}      # "E117_p1" -> row
static var _cache: Dictionary = {}    # rel path -> AudioStreamWAV
static var _lru: Array[String] = []
static var _cache_bytes := 0


## Is there a usable bake? False when the manifest is absent (a checkout that never
## ran the link script) — every caller then stays on the sequencer.
static func available() -> bool:
	_ensure_loaded()
	return _ok and enabled


## Manifest row for `MUSIC_<slot>`, or `{}` when the bake does not cover it.
static func music_row(slot: int) -> Dictionary:
	_ensure_loaded()
	return _music.get(slot, {})


## Manifest row for one effect-sound pair (`E117`, pair 1), or `{}`. Carries the bake's
## MEASURED `seconds` alongside the stream fields — the Effect Studio reads it for a sound
## trigger's ghost-bar length instead of deriving one from the FEDS opcode stream.
static func sfx_row(effect_id: String, pair: int) -> Dictionary:
	_ensure_loaded()
	return _sfx.get("%s_p%d" % [effect_id, pair], {})


## The baked song for a slot, loop points already applied, or `null`.
static func music_stream(slot: int) -> AudioStreamWAV:
	if not available():
		return null
	return _stream_for(music_row(slot))


## The baked render of one sound pair, or `null`.
##
## `loop_whole` makes it a LOOPING stream over the whole file, for `{6B}` ambient beds.
## It is a PARAMETER and not a manifest column on purpose: whether an env slot loops is
## the CATALOGUE's answer (`SfxCatalog.is_loop`), which `SfxRouter` and `ScenarioBgSound`
## already consult, and duplicating it into the manifest would make two sources of truth
## that can disagree. ⚠️ And the bake's `truncated` flag is NOT that answer either — a bed
## that renders a finite pattern (Rain 1, 5.75 s) is still looped by the game, while a
## `-Blank-` slot runs past any cap and is reached by nothing.
##
## Battle effects pass `false`: a cast's render already carries its own reverb tail.
static func sfx_stream(effect_id: String, pair: int, loop_whole: bool = false) -> AudioStreamWAV:
	if not available():
		return null
	return _stream_for(sfx_row(effect_id, pair), loop_whole)


## `MUSIC_31` out of `res://assets/music/MUSIC_31.SMD`, or -1 when the path names
## no slot. `MusicPlayer.play_file` takes a path where `play_slot` takes a number,
## and both have to reach the same row.
static func music_slot_from_path(smd_path: String) -> int:
	var stem := smd_path.get_file().get_basename()
	if not stem.begins_with("MUSIC_"):
		return -1
	var digits := stem.substr(6)
	return int(digits) if digits.is_valid_int() else -1


## The bank id for a feds path, or "" when the bake does not cover it.
##
## `E117` out of `res://assets/effects/E117/feds.bin` (the game's per-effect directory)
## or out of `.../EFFECT/E117.BIN` (the raw disc file); `SYSTEM` and `ENV` out of the two
## standalone global banks. Those two are ONE KEY SPACE with the effects, not a second —
## they are assets in the same corpus with the same `<id>_p<n>` shape, which is why they
## need no branch beyond naming them.
const STANDALONE_BANKS := {
	"system.feds": "SYSTEM",
	"env.feds": "ENV",
}

static func effect_id_from_feds_path(feds_path: String) -> String:
	if feds_path.is_empty():
		return ""
	var file := feds_path.get_file()
	if STANDALONE_BANKS.has(file):
		return STANDALONE_BANKS[file]
	var stem := file.get_basename()
	if _is_effect_id(stem):
		return stem
	var parent := feds_path.get_base_dir().get_file()
	return parent if _is_effect_id(parent) else ""


static func _is_effect_id(s: String) -> bool:
	return s.length() == 4 and s[0] == "E" and s.substr(1).is_valid_int()


## Drop every cached stream. For a debug panel / a test that wants a cold read;
## playback already in flight is unaffected (its player holds its own reference).
static func clear_cache() -> void:
	_cache.clear()
	_lru.clear()
	_cache_bytes = 0


## Re-read the manifest from disk. The test seam — `_ensure_loaded` is a one-shot.
static func reload() -> void:
	_loaded = false
	clear_cache()
	_ensure_loaded()


## The configured corpus root, normalised to a trailing slash, or "" when no host
## declared one. Callers go through `_ensure_loaded` / `_stream_for`, not through here.
static func root() -> String:
	var raw := str(ProjectSettings.get_setting(ROOT_SETTING, ""))
	if raw.is_empty():
		return ""
	return raw if raw.ends_with("/") else raw + "/"


static func _ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	_music.clear()
	_sfx.clear()
	var base := root()
	if base.is_empty():
		return
	var f := FileAccess.open(base + MANIFEST_NAME, FileAccess.READ)
	if f == null:
		# Not an error: a checkout with no bake linked is a supported state, and
		# the whole game runs on the sequencer exactly as it did before.
		return
	var header := f.get_csv_line("\t")
	var col := {}
	for i in range(header.size()):
		col[header[i]] = i
	for want in ["kind", "id", "pair", "file", "frames", "loop", "loop_begin", "loop_end"]:
		if not col.has(want):
			push_error("BakedAudio: manifest is missing column '%s'" % want)
			return
	while not f.eof_reached():
		var line := f.get_csv_line("\t")
		if line.size() < header.size():
			continue
		# `rate` / `seconds` are OPTIONAL columns (not in the required set above) so an
		# older manifest still loads. `seconds` is the bake's own measured duration; when
		# it is absent it is recovered from frames/rate, and only a manifest carrying
		# neither reports 0.0 — the caller's documented "no duration known" state.
		var rate: int = int(line[col["rate"]]) if col.has("rate") and line[col["rate"]] != "" else 0
		var frames: int = int(line[col["frames"]])
		var seconds: float = 0.0
		if col.has("seconds") and line[col["seconds"]] != "":
			seconds = float(line[col["seconds"]])
		elif rate > 0:
			seconds = float(frames) / float(rate)
		var row := {
			"file": line[col["file"]],
			"frames": frames,
			"rate": rate,
			"seconds": seconds,
			"loop": line[col["loop"]] == "1",
			"loop_begin": int(line[col["loop_begin"]]) if line[col["loop_begin"]] != "" else 0,
			"loop_end": int(line[col["loop_end"]]) if line[col["loop_end"]] != "" else 0,
		}
		var id: String = line[col["id"]]
		if line[col["kind"]] == "music":
			var slot := music_slot_from_path(id)
			if slot >= 0:
				_music[slot] = row
		else:
			_sfx["%s_p%s" % [id, line[col["pair"]]]] = row
	f.close()
	_ok = not _music.is_empty() or not _sfx.is_empty()
	if _ok:
		print("[BakedAudio] manifest: %d songs, %d effect pairs — %s"
				% [_music.size(), _sfx.size(),
					"ENABLED" if enabled else "declared but DISABLED"])


static func _stream_for(row: Dictionary, loop_whole: bool = false) -> AudioStreamWAV:
	if row.is_empty():
		return null
	var rel: String = row["file"]
	# The looping variant is a SEPARATE cache entry. One slot can be played both ways —
	# `play_env` auditions an env sound one-shot while `play_bg` runs it as a bed — and
	# mutating one shared stream's loop_mode would change the other caller's playback
	# under it. `data` is copy-on-write, so the second entry costs a header, not the PCM.
	var key := rel + ("#loop" if loop_whole else "")
	var hit: AudioStreamWAV = _cache.get(key)
	if hit != null:
		_touch(key)
		return hit
	var base := root()
	if base.is_empty():
		return null
	var path := base + rel
	if not FileAccess.file_exists(path):
		# The manifest promised a file the checkout does not have (bake unlinked,
		# or linked at a different root). Fall back rather than shout per cast.
		return null
	var stream := AudioStreamWAV.load_from_file(path)
	if stream == null:
		push_warning("BakedAudio: %s would not load as WAV" % path)
		return null
	if loop_whole:
		stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
		stream.loop_begin = 0
		stream.loop_end = int(row["frames"])
	elif bool(row["loop"]):
		stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
		stream.loop_begin = int(row["loop_begin"])
		stream.loop_end = int(row["loop_end"])
	_cache[key] = stream
	_lru.append(key)
	_cache_bytes += stream.data.size()
	_evict()
	return stream


static func _touch(rel: String) -> void:
	_lru.erase(rel)
	_lru.append(rel)


static func _evict() -> void:
	while _cache_bytes > CACHE_BUDGET_BYTES and _lru.size() > 1:
		var oldest: String = _lru.pop_front()
		var s: AudioStreamWAV = _cache.get(oldest)
		if s != null:
			_cache_bytes -= s.data.size()
		_cache.erase(oldest)
