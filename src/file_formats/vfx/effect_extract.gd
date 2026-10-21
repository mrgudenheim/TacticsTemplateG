extends RefCounted
## Turns one `E###.BIN` into the `E###/` directory `addons/exmateria_effects` loads.
## `build()` touches no disk; `write()` does.
##
## A missing mandatory section is an error, not a default: an effect whose `emitters.json`
## is `[]` initializes, simulates nothing and draws nothing, so `build()` names the absence.
## `feds.json` is not emitted: decoding it needs the opcode table that plays it.

const BinHeader := preload("res://addons/exmateria_effects/file_model/EffectBinHeader.gd")
const BinReader := preload("res://addons/exmateria_effects/file_model/EffectBinReader.gd")
const ReadTexture := preload("res://addons/exmateria_effects/file_model/readers/EffectReadTexture.gd")
const ReadFrames := preload("res://addons/exmateria_effects/file_model/readers/EffectReadFrames.gd")
const ReadEmitters := preload("res://addons/exmateria_effects/file_model/readers/EffectReadEmitters.gd")
const ReadCurves := preload("res://addons/exmateria_effects/file_model/readers/EffectReadCurves.gd")
const ReadScript := preload("res://addons/exmateria_effects/file_model/readers/EffectReadScript.gd")
const TextureTga := preload("res://addons/exmateria_effects/file_model/TextureTga.gd")
const EffectCallbacksScript := preload("res://src/file_formats/vfx/effect_callbacks.gd")
const EffectsContent := preload("res://addons/exmateria_effects/install/EffectsContent.gd")

## Section -> file. Every one must parse.
const SECTION_FILES: Dictionary = {
	"emitters": "emitters.json",
	"frames": "frames.json",
	"animation": "animations.json",
	"particle_timeline": "timeline.json",
	"screen": "screen.json",
	"palette": "palette.json",
	"camera": "camera.json",
	"effect_flags": "effect_flags.json",
}

## Written only when present: an absent section is not a section of zeroes.
const OPTIONAL_SECTION_FILES: Dictionary = {
	"time_scale": "time_scale.json",
}

## The two sound files ride with `feds.bin`'s presence: a soundless effect gets neither,
## rather than a resolver config for sounds it cannot play.
const SOUND_SECTION_FILES: Dictionary = {
	"sound_containers": "sound_containers.json",
	"sound": "sound.json",
}


## Where the addon reads this content: the import path, like every other exported file.
## "" when no import path is set.
static func content_root() -> String:
	return str(GameData.external_data_paths.get("IMPORT_PATH", ""))


## The `E###/` parent under `root`, or "" when `root` is.
static func effects_dir(root: String) -> String:
	if root.is_empty():
		return ""
	return root.path_join(EffectsContent.EFFECTS_SUBPATH)


## One effect's output files, keyed by relative path. `header_offset` comes from
## `BattleBinData.ability_vfx_header_offsets`; a negative one falls back to a scan that puts
## the header at the wrong offset for E259, E338 and E464.
static func build(buf: PackedByteArray, header_offset: int, effect_name: String) -> Dictionary:
	var errors: Array[String] = []
	var files: Dictionary = {}
	if buf.size() < BinHeader.HEADER_SIZE:
		errors.append("%s: %d bytes, too short to hold a header" % [effect_name, buf.size()])
		return {"ok": false, "files": files, "errors": errors}

	var base: int = header_offset if header_offset >= 0 else BinHeader.find_header_offset(buf)
	var header: Dictionary = BinHeader.parse_header(buf, base)
	var blocks: Dictionary = BinReader.parse_all(buf, header)

	files["header.json"] = BinHeader.header_document("%s.BIN" % effect_name, buf, base)

	for section: String in SECTION_FILES:
		if not blocks.has(section):
			errors.append("%s: mandatory section '%s' did not parse" % [effect_name, section])
			continue
		files[SECTION_FILES[section]] = blocks[section]

	for section: String in OPTIONAL_SECTION_FILES:
		if blocks.has(section):
			files[OPTIONAL_SECTION_FILES[section]] = blocks[section]

	# FEDS: the raw blob is the addon's playback source, and the two sound files follow it.
	if blocks.has("sound_def"):
		files["feds.bin"] = blocks["sound_def"]
		for section: String in SOUND_SECTION_FILES:
			if blocks.has(section):
				files[SOUND_SECTION_FILES[section]] = blocks[section]

	# --- the derived VIEWS: files the section registry does not return ---
	_add_view(files, errors, effect_name, "particle_header.json",
		ReadEmitters.particle_header(buf, header))
	_add_view(files, errors, effect_name, "curves.json", ReadCurves.parse(buf, header))
	_add_view(files, errors, effect_name, "script.json", ReadScript.parse(buf, header))
	_add_view(files, errors, effect_name, "texture_meta.json", ReadTexture.meta(buf, header))
	_add_view(files, errors, effect_name, "texture_palette.json",
		ReadTexture.swatches(buf, header))

	var groups = ReadFrames.group_sizes(buf, header)
	if groups is Array and not (groups as Array).is_empty():
		files["frameset_groups.json"] = groups

	var tga: PackedByteArray = build_texture_tga(buf, header)
	if tga.is_empty():
		errors.append("%s: texture.tga could not be decoded" % effect_name)
	else:
		files["texture.tga"] = tga

	# The bespoke MIPS callback tables; only eight effects have any.
	var emitters: Array = files.get("emitters.json", []) as Array
	var callbacks: Dictionary = EffectCallbacksScript.build(effect_name, buf, emitters)
	for rel_path: String in callbacks:
		files[rel_path] = callbacks[rel_path]

	return {"ok": errors.is_empty(), "files": files, "errors": errors}


## The RGBA sheet as TGA bytes, or empty when the section cannot be sized. 8bpp reads all 256
## CLUT entries of line 1, 4bpp the first 16 of line 2; line 1 for 4bpp shows as a palette bug.
static func build_texture_tga(buf: PackedByteArray, header: Dictionary) -> PackedByteArray:
	var depth = ReadTexture.sheet_depth(buf, header)
	if depth == null:
		return PackedByteArray()
	var is_8bpp: bool = bool(depth)
	var size: Vector2i = ReadTexture.dimensions(buf, header, is_8bpp)
	if size.x <= 0 or size.y <= 0:
		return PackedByteArray()
	var pixels: PackedByteArray = ReadTexture.decode_rgba(buf, header, is_8bpp, not is_8bpp, 0,
		ReadTexture.EXPAND_TRUNCATE)
	if pixels.size() != size.x * size.y * 4:
		return PackedByteArray()
	return TextureTga.encode(size.x, size.y, pixels)


## Write one effect's files into `dir_path`, creating it. Never delete stale files here:
## `feds.json` is not built here but must survive a rerun.
static func write(files: Dictionary, dir_path: String) -> Dictionary:
	var errors: Array[String] = []
	var err: Error = DirAccess.make_dir_recursive_absolute(dir_path)
	if err != OK and not DirAccess.dir_exists_absolute(dir_path):
		return {"ok": false, "errors": ["%s: %s" % [dir_path, error_string(err)]]}

	for rel_path: String in files:
		var path: String = dir_path.path_join(rel_path)
		# `callbacks/CB##/callback_data.json` is a nested file, so the parent may not exist.
		if rel_path.contains("/"):
			DirAccess.make_dir_recursive_absolute(path.get_base_dir())
		var value = files[rel_path]
		var bytes: PackedByteArray
		if value is PackedByteArray:
			bytes = value
		else:
			bytes = to_json(value).to_utf8_buffer()
		var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
		if file == null:
			errors.append("%s: %s" % [path, error_string(FileAccess.get_open_error())])
			continue
		file.store_buffer(bytes)
		file.close()
	return {"ok": errors.is_empty(), "errors": errors}


## One file's JSON text. `full_precision` on: the default rounds to ~6 significant digits.
## `sort_keys` off keeps the readers' field order.
static func to_json(value) -> String:
	return JSON.stringify(value, "  ", false, true)


static func _add_view(files: Dictionary, errors: Array[String], effect_name: String,
		rel_path: String, value) -> void:
	if value == null:
		errors.append("%s: view '%s' did not parse" % [effect_name, rel_path])
		return
	files[rel_path] = value
