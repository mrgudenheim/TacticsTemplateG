extends RefCounted

## The addon's ONE injection point for host content it can never ship — ADR-0202 dec. 5's
## "settable search root with a default". The content (per-effect E### dirs,
## callback_data.json, the four TRAP tables, the TRAP1 texture/palette) is ROM-derived
## and gitignored (ADR-0142). INJECT, not the read ADR-0203 dec. 2 forbids (dec. 1
## blesses Class B); transcribed from BattlefieldContent.gd.
## 🔴 Default EMPTY on purpose: a res://assets/ default silently resolves nonexistent
## paths in a bare project — dec. 5's "legible failure instead of a silent empty load".
## vault: .vaults/comments/exmateria_effects/effects-content-root.md

## The ProjectSettings key; a directory path — a trailing slash is supplied by resolve().
const ROOT_SETTING: String = "exmateria_effects/content_root"

## Subpaths below the root — the tree shape, named once here (never res:// literals).
const EFFECTS_SUBPATH: String = "effects/"
const TRAP_SUBPATH: String = "effects/trap/"
const TRAP_TEX_SUBPATH: String = "sprites/textures/TRAP1.tga"
const TRAP_PALETTE_SUBPATH: String = "sprites/textures/TRAP1.palette.tga"

static var _unset_reported: bool = false


## The content root normalised to a trailing slash; "" when the host has not declared one.
static func root() -> String:
	var raw: String = str(ProjectSettings.get_setting(ROOT_SETTING, ""))
	if raw.is_empty():
		return ""
	return raw if raw.ends_with("/") else raw + "/"


static func has_root() -> bool:
	return not root().is_empty()


## "" (not a half-formed path) when unset, so caller existence checks fail like a missing file.
## Reported ONCE per run — a cast spawns per action; push_error per spawn would bury it.
static func resolve(subpath: String) -> String:
	var base: String = root()
	if base.is_empty():
		if not _unset_reported:
			_unset_reported = true
			push_error(
				"ExMateria Effects: no content root. This addon needs ROM-derived "
				+ "content it cannot ship (the per-effect `E###` directories, the TRAP "
				+ "config tables, the TRAP1 texture/palette pair), so a host must declare `"
				+ ROOT_SETTING + "` in project.godot, pointing at the directory holding "
				+ "its `" + EFFECTS_SUBPATH + "` and `sprites/textures/` trees. Until then "
				+ "no effect will load. See the addon README, \"Content the host must "
				+ "supply\"."
			)
		return ""
	return base + subpath


## effects/E###; the caller formats E%03d. "" when unset.
static func effect_dir(effect_name: String) -> String:
	var base: String = resolve(EFFECTS_SUBPATH)
	if base.is_empty():
		return ""
	return base + effect_name


## effects/E###/callbacks/CB##/callback_data.json. "" when unset.
static func callback_data_path(effect_name: String, callback_id: int) -> String:
	var dir: String = effect_dir(effect_name)
	if dir.is_empty():
		return ""
	return "%s/callbacks/CB%02d/callback_data.json" % [dir, callback_id]


## One of the four TRAP config tables by file name. "" when unset.
static func trap_table_path(file_name: String) -> String:
	var base: String = resolve(TRAP_SUBPATH)
	if base.is_empty():
		return ""
	return base + file_name


## The ROM-ripped TRAP indexed texture. "" when unset.
static func trap_tex_path() -> String:
	return resolve(TRAP_TEX_SUBPATH)


## Its palette LUT. "" when unset.
static func trap_palette_path() -> String:
	return resolve(TRAP_PALETTE_SUBPATH)
