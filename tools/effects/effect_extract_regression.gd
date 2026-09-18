extends Node
## Does TacticsG's own parse of `E###.BIN` reproduce `content/effects/E###/`? Diffs every
## leaf against the copy on disk, which was produced by separate tooling, and reads through
## the ROM so the header-offset arithmetic is exercised as well.
## THE COPY IT COMPARES AGAINST MUST NOT BE THIS EXPORTER'S OWN OUTPUT: run
## `generate_effects_content()` against the default `res://content/effects` and this becomes
## a build checked against itself, green for anything. Point `--oracle=` elsewhere first.
##
## Run: <GODOT> --path . res://tools/effects/effect_extract_regression.tscn -- auto [export] [--oracle=DIR]

const EffectExtractScript := preload("res://src/file_formats/vfx/effect_extract.gd")
const BinHeader := preload("res://addons/exmateria_effects/file_model/EffectBinHeader.gd")

## What it compares against unless told otherwise: the extract already committed here.
const CONTENT_EFFECTS := "res://content/effects"

## Floats get a relative tolerance because the committed numbers were written by Python's
## JSON and read back by Godot's; below this, numbers compare EXACTLY.
const FLOAT_REL_TOLERANCE := 1e-9

## Where the worst float disagreement sits. Asserted rather than printed, because a
## systematic error can otherwise sit unnoticed under the tolerance above.
const FLOAT_NOISE_CEILING := 1e-12

## The directory actually compared against — `--oracle=DIR` overrides `CONTENT_EFFECTS`.
var _oracle := CONTENT_EFFECTS

var _passed := 0
var _failed := 0
var _float_rel_max := 0.0
var _auto := false


func _ready() -> void:
	_auto = "auto" in OS.get_cmdline_user_args()
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--oracle="):
			_oracle = arg.trim_prefix("--oracle=").rstrip("/")
	if not _auto:
		print("effect_extract_regression: pass `-- auto` to run.")
		return
	_run.call_deferred()


func _run() -> void:
	var rom_path: String = str(GameData.external_data_paths.get("ROM_PATH", ""))
	if rom_path.is_empty() or not FileAccess.file_exists(rom_path):
		print("[FAIL] no ROM_PATH in external_data_paths.cfg — nothing to score")
		_quit(1)
		return
	print("oracle: %s" % _oracle)
	print("loading ROM: %s" % rom_path)
	# NOT a coroutine: it emits `rom_loaded` before returning, so awaiting the signal
	# afterwards waits forever. `is_ready` is the repo's guard for this.
	if not RomReader.is_ready:
		RomReader.on_load_rom_dialog_file_selected(rom_path)
	if not RomReader.is_ready:
		await RomReader.rom_loaded
	print("ROM loaded (%d effect files)" % RomReader.vfx.size())

	var battle_bin: PackedByteArray = RomReader.get_file_data("BATTLE.BIN")
	_test_header_offsets_agree(battle_bin)
	await _test_the_extract_matches_the_committed_content(battle_bin)
	_test_a_corrupt_buffer_refuses()
	if "export" in OS.get_cmdline_user_args():
		await _test_the_exporter_writes_a_matching_tree()

	print("--- %d passed, %d failed (worst float rel %s) ---"
		% [_passed, _failed, String.num_scientific(_float_rel_max)])
	_quit(0 if _failed == 0 else 1)


## ARM 1 — TacticsG's own BATTLE.BIN table read and the addon's must agree for every id.
func _test_header_offsets_agree(battle_bin: PackedByteArray) -> void:
	var table: PackedInt32Array = RomReader.battle_bin_data.ability_vfx_header_offsets
	var checked := 0
	var disagreed: Array[String] = []
	for vfx_id in table.size():
		var mine: int = table[vfx_id]
		var theirs: int = BinHeader.vfx_header_offset(battle_bin, vfx_id)
		# A negative on TacticsG's side is the same below-load-base refusal spelled
		# differently, not a mismatch.
		if theirs == BinHeader.NO_OFFSET:
			if mine >= 0:
				disagreed.append("id %d: TacticsG %d, vendored refused" % [vfx_id, mine])
			continue
		checked += 1
		if mine != theirs:
			disagreed.append("id %d: TacticsG %d, vendored %d" % [vfx_id, mine, theirs])
	for d in disagreed.slice(0, 5):
		print("  [offset] %s" % d)
	_assert_true(checked > 400, "BATTLE.BIN answered for the whole table — %d ids" % checked)
	_assert_eq(disagreed.size(), 0, "header offsets agree across both readings")


## ARM 2 + ARM 3 — the extract against the committed content, and its JSON round trip.
func _test_the_extract_matches_the_committed_content(battle_bin: PackedByteArray) -> void:
	var names: Array = _effect_dir_names(_oracle)
	_assert_true(names.size() > 390, "found the committed extract — %d directories"
		% names.size())
	if names.is_empty():
		return

	var compared := 0
	var refused: Array[String] = []
	var leaf_hits: Dictionary = {}
	var field_diffs: Array[String] = []
	var json_diffs: Array[String] = []
	var missing_leaves: Array[String] = []
	var extra_leaves: Array[String] = []
	var frame_budget := Time.get_ticks_msec()

	for eff: String in names:
		if Time.get_ticks_msec() - frame_budget > 100:
			await get_tree().process_frame
			frame_budget = Time.get_ticks_msec()

		var vfx_id: int = BinHeader.vfx_id_from_filename(eff)
		var file_name: String = "%s.BIN" % eff
		if not RomReader.file_records.has(file_name):
			refused.append("%s: no such file in the ROM" % eff)
			continue
		var buf: PackedByteArray = RomReader.get_file_data(file_name)
		var built: Dictionary = EffectExtractScript.build(buf, battle_bin, vfx_id, eff)
		if not built["ok"]:
			for e in (built["errors"] as Array).slice(0, 2):
				refused.append(str(e))
			continue
		compared += 1

		var leaves: Dictionary = built["leaves"]
		var dir: String = "%s/%s" % [_oracle, eff]
		for leaf: String in leaves:
			var path: String = "%s/%s" % [dir, leaf]
			if not FileAccess.file_exists(path):
				if missing_leaves.size() < 10:
					missing_leaves.append("%s: built %s, not in the committed extract"
						% [eff, leaf])
				continue
			leaf_hits[leaf] = int(leaf_hits.get(leaf, 0)) + 1
			var value = leaves[leaf]
			if value is PackedByteArray:
				# As BYTES: the addon loads them as bytes.
				var want_bytes: PackedByteArray = FileAccess.get_file_as_bytes(path)
				if value != want_bytes:
					if field_diffs.size() < 10:
						field_diffs.append("%s %s: %d bytes built, %d committed"
							% [eff, leaf, (value as PackedByteArray).size(), want_bytes.size()])
				continue
			var want = JSON.parse_string(FileAccess.get_file_as_string(path))
			var d: Array = _deep_diff(value, want, leaf)
			for x in d.slice(0, 2):
				if field_diffs.size() < 10:
					field_diffs.append("%s %s" % [eff, x])
			# ARM 3 — what would actually be WRITTEN, reparsed.
			var round_tripped = JSON.parse_string(EffectExtractScript.to_json(value))
			var rd: Array = _deep_diff(round_tripped, value, leaf)
			for x in rd.slice(0, 2):
				if json_diffs.size() < 10:
					json_diffs.append("%s %s" % [eff, x])

		# The other direction: a leaf the committed extract has and this build does not.
		for leaf: String in _committed_leaves(dir):
			if not leaves.has(leaf) and extra_leaves.size() < 10:
				extra_leaves.append("%s: committed %s, not built" % [eff, leaf])

	for d in refused.slice(0, 5):
		print("  [refused] %s" % d)
	for d in field_diffs:
		print("  [field] %s" % d)
	for d in json_diffs:
		print("  [json] %s" % d)
	for d in missing_leaves:
		print("  [extra] %s" % d)
	for d in extra_leaves:
		print("  [absent] %s" % d)

	var hits: Array = []
	for leaf in leaf_hits:
		hits.append("%s=%d" % [leaf, leaf_hits[leaf]])
	hits.sort()
	print("  scored: %s" % ", ".join(hits))

	_assert_eq(refused.size(), 0, "every committed effect extracted without an error")
	_assert_eq(compared, names.size(), "extracted all %d effects" % names.size())
	_assert_eq(field_diffs.size(), 0, "every leaf matches the committed extract")
	_assert_eq(json_diffs.size(), 0, "every leaf survives its own JSON round trip")
	_assert_eq(missing_leaves.size(), 0, "no leaf built that the extract does not carry")
	_assert_eq(extra_leaves.size(), 0, "no committed leaf left unbuilt")
	_assert_true(_float_rel_max <= FLOAT_NOISE_CEILING,
		"float disagreement stayed at parser noise — worst %s, ceiling %s"
			% [String.num_scientific(_float_rel_max),
				String.num_scientific(FLOAT_NOISE_CEILING)])


## ARM 4 — the negative control. Without this, "ok" for everything scores green above.
func _test_a_corrupt_buffer_refuses() -> void:
	var junk := PackedByteArray()
	junk.resize(4096)
	junk.fill(0xAB)
	var built: Dictionary = EffectExtractScript.build(junk, PackedByteArray(), 1, "JUNK")
	_assert_true(not built["ok"], "a buffer of junk refuses to extract")
	var tiny := PackedByteArray()
	tiny.resize(8)
	var built_tiny: Dictionary = EffectExtractScript.build(tiny, PackedByteArray(), 1, "TINY")
	_assert_true(not built_tiny["ok"], "a buffer too short for a header refuses to extract")


## ARM 5 — `-- auto export`. Scores `write()` rather than `build()`: directory layout, the
## nested `callbacks/CB##/` path, binary-vs-JSON dispatch and encoding. Off by default,
## ~224 MB. Writes to a SCRATCH directory, never `res://content/effects/` — that tree is
## gitignored, and a wrong build written over it destroys the only thing that would have
## caught the wrong build.
func _test_the_exporter_writes_a_matching_tree() -> void:
	var out_dir: String = ProjectSettings.globalize_path("user://effect_extract_check")
	print("exporting to %s" % out_dir)
	var summary: Dictionary = await RomReader.generate_effects_content(out_dir)

	_assert_eq(int(summary["written"]), 401, "the exporter wrote 401 effect directories")
	_assert_eq(int(summary["skipped_empty"]), 111, "it skipped the 111 empty EFFECT slots")
	_assert_eq((summary["failures"] as Array).size(), 0, "no effect failed to export")

	var mismatches: Array[String] = []
	var files_compared := 0
	var files_expected := 0
	for eff: String in _effect_dir_names(_oracle):
		var want_dir: String = "%s/%s" % [_oracle, eff]
		var got_dir: String = "%s/%s" % [out_dir, eff]
		for leaf: String in _committed_leaves_recursive(want_dir, ""):
			files_expected += 1
			var want_path: String = "%s/%s" % [want_dir, leaf]
			var got_path: String = "%s/%s" % [got_dir, leaf]
			if not FileAccess.file_exists(got_path):
				if mismatches.size() < 10:
					mismatches.append("%s/%s: not written" % [eff, leaf])
				continue
			files_compared += 1
			if leaf.ends_with(".json"):
				# As VALUES, not bytes: the two serializers differ in whitespace and float
				# spelling, and `EffectData` reads these through `JSON.parse_string`.
				var d: Array = _deep_diff(
					JSON.parse_string(FileAccess.get_file_as_string(got_path)),
					JSON.parse_string(FileAccess.get_file_as_string(want_path)), leaf)
				for x in d.slice(0, 2):
					if mismatches.size() < 10:
						mismatches.append("%s %s" % [eff, x])
			elif FileAccess.get_file_as_bytes(got_path) \
					!= FileAccess.get_file_as_bytes(want_path):
				if mismatches.size() < 10:
					mismatches.append("%s/%s: bytes differ" % [eff, leaf])
	for m in mismatches:
		print("  [export] %s" % m)
	# Counted from the committed tree, not hardcoded: a fixed floor stops meaning "nothing
	# was skipped" the moment the extract gains or loses a leaf.
	_assert_eq(files_compared, files_expected,
		"compared every file the committed extract carries — %d" % files_expected)
	_assert_eq(mismatches.size(), 0, "every written file matches the committed extract")


# --- helpers ----------------------------------------------------------------

## Every leaf under `dir`, RECURSIVELY, as paths relative to it — `callbacks/CB##/…` included.
func _committed_leaves_recursive(dir: String, prefix: String) -> Array:
	var out: Array = []
	var da := DirAccess.open(dir)
	if da == null:
		return out
	da.list_dir_begin()
	var entry := da.get_next()
	while entry != "":
		var rel: String = entry if prefix.is_empty() else "%s/%s" % [prefix, entry]
		if da.current_is_dir():
			out.append_array(_committed_leaves_recursive("%s/%s" % [dir, entry], rel))
		elif not entry.ends_with(".import") and entry != "feds.json":
			out.append(rel)
		entry = da.get_next()
	da.list_dir_end()
	return out



func _committed_leaves(dir: String) -> Array:
	## Only the leaves this extractor produces: `.import` belongs to Godot's importer,
	## `feds.json` is not part of the extract, and `callbacks/` is a directory.
	var out: Array = []
	var da := DirAccess.open(dir)
	if da == null:
		return out
	da.list_dir_begin()
	var leaf := da.get_next()
	while leaf != "":
		if not da.current_is_dir() and not leaf.ends_with(".import") and leaf != "feds.json":
			out.append(leaf)
		leaf = da.get_next()
	da.list_dir_end()
	return out


func _effect_dir_names(root: String) -> Array:
	var out: Array = []
	var da := DirAccess.open(root)
	if da == null:
		return out
	da.list_dir_begin()
	var entry := da.get_next()
	while entry != "":
		if da.current_is_dir() and BinHeader.vfx_id_from_filename(entry) >= 0:
			out.append(entry)
		entry = da.get_next()
	da.list_dir_end()
	out.sort()
	return out


## Every way `got` differs from `want`, as sentences. Numbers compare through float so a
## JSON-parsed `3.0` matches a native `3`, bools compare as bools, and only a non-integral
## value may claim the tolerance — an off-by-one in a count must never look like rounding.
func _deep_diff(got, want, path: String) -> Array:
	var diffs: Array = []
	if want == null:
		if got != null:
			diffs.append("%s: got %s, want null" % [path, str(got)])
		return diffs
	if want is Dictionary:
		if not (got is Dictionary):
			return ["%s: got %s, want a Dictionary" % [path, type_string(typeof(got))]]
		for k in want:
			if not got.has(k):
				diffs.append("%s.%s: missing" % [path, k])
			else:
				diffs.append_array(_deep_diff(got[k], want[k], "%s.%s" % [path, k]))
		for k in got:
			if not want.has(k):
				diffs.append("%s.%s: unexpected key" % [path, k])
		return diffs
	if want is Array:
		if not (got is Array):
			return ["%s: got %s, want an Array" % [path, type_string(typeof(got))]]
		if got.size() != want.size():
			return ["%s: size got %d, want %d" % [path, got.size(), want.size()]]
		for i in range(want.size()):
			diffs.append_array(_deep_diff(got[i], want[i], "%s[%d]" % [path, i]))
		return diffs
	if want is bool or got is bool:
		if bool(got) != bool(want) or (got is bool) != (want is bool):
			diffs.append("%s: got %s, want %s" % [path, got, want])
		return diffs
	if (want is int or want is float) and (got is int or got is float):
		var a := float(got)
		var b := float(want)
		if a == b:
			return diffs
		if a == floorf(a) and b == floorf(b):
			diffs.append("%s: got %s, want %s" % [path, got, want])
			return diffs
		var scale := maxf(absf(a), absf(b))
		var rel := absf(a - b) / scale if scale > 0.0 else absf(a - b)
		_float_rel_max = maxf(_float_rel_max, rel)
		if rel > FLOAT_REL_TOLERANCE:
			diffs.append("%s: got %s, want %s (relative %s)" % [path, String.num(a, 17),
				String.num(b, 17), String.num_scientific(rel)])
		return diffs
	if str(got) != str(want):
		diffs.append("%s: got %s, want %s" % [path, got, want])
	return diffs


func _assert_eq(got, want, msg: String) -> void:
	if got == want:
		_passed += 1
		print("  [ok] %s" % msg)
	else:
		_failed += 1
		print("  [FAIL] %s — got %s, want %s" % [msg, str(got), str(want)])


func _assert_true(cond: bool, msg: String) -> void:
	if cond:
		_passed += 1
		print("  [ok] %s" % msg)
	else:
		_failed += 1
		print("  [FAIL] %s" % msg)


func _quit(code: int) -> void:
	if _auto:
		get_tree().quit(code)
