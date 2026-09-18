extends RefCounted
## Turns one `E###.BIN` into the `E###/` directory `addons/exmateria_effects` loads.
##
## The `VisualEffectData` path is separate and still feeds `ProjectileEffectInstance`.
## Parsing the file is the addon's job; the job here is deciding which parsed section goes
## in which file. `build()` touches no disk, `write()` does.
## A missing mandatory section is an ERROR, not a default: an effect whose `emitters.json`
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

## Where the addon reads its ROM-derived content from. NOT `EXPORT_PATH` and it cannot be:
## the sheet loads through `ResourceLoader`, which only answers for a path under `res://`
## that Godot has IMPORTED, and an unimported `.tga` is skipped silently.
const CONTENT_ROOT: String = "res://content/"
const EFFECTS_DIR: String = CONTENT_ROOT + "effects/"

## Registered section -> the leaf carrying it. Every one of these must parse; see the header.
const SECTION_LEAVES: Dictionary = {
	"emitters": "emitters.json",
	"frames": "frames.json",
	# PLURAL file, singular section — the addon's reader names it `animation`.
	"animation": "animations.json",
	# The section is `particle_timeline`; the leaf is `timeline.json`.
	"particle_timeline": "timeline.json",
	"screen": "screen.json",
	"palette": "palette.json",
	"camera": "camera.json",
	"effect_flags": "effect_flags.json",
}

## Written only when present: `time_scale` is absent for 269 of 401 effects, and an absent
## section is not a section of zeroes.
const OPTIONAL_SECTION_LEAVES: Dictionary = {
	"time_scale": "time_scale.json",
}

## The two sound leaves ride with `feds.bin`'s presence: a soundless effect gets neither,
## rather than a resolver config for sounds it cannot play.
const SOUND_SECTION_LEAVES: Dictionary = {
	"sound_containers": "sound_containers.json",
	"sound": "sound.json",
}


## Every leaf of one effect, as `{"ok", "leaves", "errors"}`. `leaves` holds
## Dictionaries/Arrays for `.json` and `PackedByteArray` for `feds.bin` / `texture.tga`, and
## `write()` dispatches on type. Pass `battle_bin`: empty falls back to the prologue scan,
## which misses E259/E338/E464.
static func build(buf: PackedByteArray, battle_bin: PackedByteArray, vfx_id: int,
		effect_name: String) -> Dictionary:
	var errors: Array[String] = []
	var leaves: Dictionary = {}
	if buf.size() < BinHeader.HEADER_SIZE:
		errors.append("%s: %d bytes, too short to hold a header" % [effect_name, buf.size()])
		return {"ok": false, "leaves": leaves, "errors": errors}

	var base: int = BinHeader.header_offset(buf, battle_bin, vfx_id)
	var header: Dictionary = BinHeader.parse_header(buf, base)
	var blocks: Dictionary = BinReader.parse_all(buf, header)

	leaves["header.json"] = BinHeader.header_document("%s.BIN" % effect_name, buf, base)

	for section: String in SECTION_LEAVES:
		if not blocks.has(section):
			errors.append("%s: mandatory section '%s' did not parse" % [effect_name, section])
			continue
		leaves[SECTION_LEAVES[section]] = blocks[section]

	for section: String in OPTIONAL_SECTION_LEAVES:
		if blocks.has(section):
			leaves[OPTIONAL_SECTION_LEAVES[section]] = blocks[section]

	# FEDS: the raw blob is the addon's playback source, and the two sound leaves follow it.
	if blocks.has("sound_def"):
		leaves["feds.bin"] = blocks["sound_def"]
		for section: String in SOUND_SECTION_LEAVES:
			if blocks.has(section):
				leaves[SOUND_SECTION_LEAVES[section]] = blocks[section]

	# --- the derived VIEWS: leaves the section registry does not return ---
	_add_view(leaves, errors, effect_name, "particle_header.json",
		ReadEmitters.particle_header(buf, header))
	_add_view(leaves, errors, effect_name, "curves.json", ReadCurves.parse(buf, header))
	_add_view(leaves, errors, effect_name, "script.json", ReadScript.parse(buf, header))
	_add_view(leaves, errors, effect_name, "texture_meta.json", ReadTexture.meta(buf, header))
	_add_view(leaves, errors, effect_name, "texture_palette.json",
		ReadTexture.swatches(buf, header))

	# Conditional in `save_effect` — written only when non-empty.
	var groups = ReadFrames.group_sizes(buf, header)
	if groups is Array and not (groups as Array).is_empty():
		leaves["frameset_groups.json"] = groups

	var tga: PackedByteArray = build_texture_tga(buf, header)
	if tga.is_empty():
		errors.append("%s: texture.tga could not be decoded" % effect_name)
	else:
		leaves["texture.tga"] = tga

	# The bespoke MIPS callback tables — eight effects, nothing for the other 393. Keyed by the
	# NESTED path the addon looks for (`callbacks/CB##/callback_data.json`).
	var emitters: Array = leaves.get("emitters.json", []) as Array
	var callbacks: Dictionary = EffectCallbacksScript.build(effect_name, buf, emitters)
	for leaf: String in callbacks:
		leaves[leaf] = callbacks[leaf]

	return {"ok": errors.is_empty(), "leaves": leaves, "errors": errors}


## The RGBA sheet as TGA bytes, or empty when the section cannot be sized.
##
## The CLUT line is depth-dependent: 8bpp reads all 256 entries of line 1, 4bpp the first 16
## of line TWO. Line 1 throughout disagrees with the shipped content on exactly the 60 4bpp
## effects, and reads as a palette bug at runtime. `EXPAND_TRUNCATE` is the same story.
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


## Write one effect's leaves into `dir_path`, creating it. Nothing is REMOVED, so regenerating
## leaves any file this build did not produce in place — which `feds.json` (never emitted) and
## `texture.tga.import` (Godot's importer owns it) both depend on.
static func write(leaves: Dictionary, dir_path: String) -> Dictionary:
	var errors: Array[String] = []
	var err: Error = DirAccess.make_dir_recursive_absolute(dir_path)
	if err != OK and not DirAccess.dir_exists_absolute(dir_path):
		return {"ok": false, "errors": ["%s: %s" % [dir_path, error_string(err)]]}

	for leaf: String in leaves:
		var path: String = dir_path.path_join(leaf)
		# `callbacks/CB##/callback_data.json` is a nested leaf, so the parent may not exist.
		if leaf.contains("/"):
			DirAccess.make_dir_recursive_absolute(path.get_base_dir())
		var value = leaves[leaf]
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


## One leaf's JSON text. `full_precision` is not optional: `JSON.stringify` defaults it FALSE,
## rounding this format's converted doubles to ~6 significant digits, silently and
## survivably. `sort_keys` is off so the leaves keep the readers' field order.
static func to_json(value) -> String:
	return JSON.stringify(value, "  ", false, true)


static func _add_view(leaves: Dictionary, errors: Array[String], effect_name: String,
		leaf: String, value) -> void:
	if value == null:
		errors.append("%s: view '%s' did not parse" % [effect_name, leaf])
		return
	leaves[leaf] = value
