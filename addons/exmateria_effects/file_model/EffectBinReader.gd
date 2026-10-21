extends RefCounted
## The per-section PARSER registry for E###.BIN — the read direction, mirroring
## EffectBinWriter.gd (#1329). No class_name (ADR-0004) — path-preloaded.
## Vault: [[Effect File Format]]
## Contract: reader returns = JSON.parse_string() of the committed extract — no JSON
## serialized, float/key ordering out of the problem. ABSENT is null, never an empty dict
## ("no section" vs "all zeroes"; 269 of 400 have no time_scale). Two referees pin every
## reader, neither alone sufficient: extract-compare + round-trip
## (EffectBinReadWriteCorpusTest).
## vault: .vaults/comments/exmateria_effects/bin-reader-referees.md

const ReadFlags = preload("res://addons/exmateria_effects/file_model/readers/EffectReadFlags.gd")
const ReadContainers = preload("res://addons/exmateria_effects/file_model/readers/EffectReadContainers.gd")
const ReadTimeScale = preload("res://addons/exmateria_effects/file_model/readers/EffectReadTimeScale.gd")
const ReadSound = preload("res://addons/exmateria_effects/file_model/readers/EffectReadSound.gd")
const ReadTexture = preload("res://addons/exmateria_effects/file_model/readers/EffectReadTexture.gd")
const ReadFrames = preload("res://addons/exmateria_effects/file_model/readers/EffectReadFrames.gd")
const ReadEmitters = preload("res://addons/exmateria_effects/file_model/readers/EffectReadEmitters.gd")
const ReadAnimation = preload("res://addons/exmateria_effects/file_model/readers/EffectReadAnimation.gd")
const ReadCamera = preload("res://addons/exmateria_effects/file_model/readers/EffectReadCamera.gd")
const ReadScreen = preload("res://addons/exmateria_effects/file_model/readers/EffectReadScreen.gd")
const ReadPalette = preload("res://addons/exmateria_effects/file_model/readers/EffectReadPalette.gd")
const ReadParticleTimeline = preload("res://addons/exmateria_effects/file_model/readers/EffectReadParticleTimeline.gd")
const ReadSoundDef = preload("res://addons/exmateria_effects/file_model/readers/EffectReadSoundDef.gd")
const ReadCurves = preload("res://addons/exmateria_effects/file_model/readers/EffectReadCurves.gd")
const ReadScript = preload("res://addons/exmateria_effects/file_model/readers/EffectReadScript.gd")

## section -> parser. The 14 `patch_all` sections, plus two VIEWS:
##   `script` — written in both languages since #1416 (`EffectWriteScript.gd` +
##     `EffectBinWriter.serialize_script`; `write_effect_script.py`, #273/ADR-0094), but out
##     of this registry because the writer never consumes a parsed block: a swap RESIZES, and
##     the writer regenerates the whole canonical section — child body included — from a
##     table, where this walk stops at the root's first `end`. `script.json` is the studio's
##     oracle, not the writer's input.
##   `curves` — no writer in any language: the write-reach probe flips all 2,400 curve bytes
##     on E019 and every one comes back unwritten (#448 / #274). Unwritable is not unused —
##     heavily read.
## `timeline_header` shares `ReadParticleTimeline.parse`: one `timeline.json`, two
## serializers over disjoint bytes of the section (#271).
## A section is a patchable unit: `texture` = the plane alone (ADR-0199 holds the CLUT);
## `meta()`/`swatches()`/`decode` + `group_sizes()` + `particle_header()` are views, not
## sections — `patch_all` refuses no-serializer.
static var _registry: Dictionary = {}


static func _ensure_builtins() -> void:
	if not _registry.is_empty():
		return
	_registry["effect_flags"] = ReadFlags.parse
	_registry["sound_containers"] = ReadContainers.parse
	_registry["time_scale"] = ReadTimeScale.parse
	_registry["sound"] = ReadSound.parse
	_registry["texture"] = ReadTexture.parse
	_registry["frames"] = ReadFrames.parse
	_registry["emitters"] = ReadEmitters.parse
	_registry["animation"] = ReadAnimation.parse
	_registry["camera"] = ReadCamera.parse
	_registry["screen"] = ReadScreen.parse
	_registry["palette"] = ReadPalette.parse
	_registry["particle_timeline"] = ReadParticleTimeline.parse
	_registry["timeline_header"] = ReadParticleTimeline.parse
	_registry["sound_def"] = ReadSoundDef.parse


static func parsed_sections() -> Array:
	_ensure_builtins()
	return _registry.keys()


## The registered parser for section, or an INVALID Callable — check .is_valid().
static func parser_for(section: String) -> Callable:
	_ensure_builtins()
	if not _registry.has(section):
		return Callable()
	return _registry[section]


## Every registered section; ABSENT omitted (not null) so the result hands to patch_all; only = subset, empty = all.
static func parse_all(buf: PackedByteArray, header: Dictionary, only: Array = []) -> Dictionary:
	_ensure_builtins()
	var out: Dictionary = {}
	for name in _registry:
		if not only.is_empty() and not only.has(name):
			continue
		var block = _registry[name].call(buf, header)
		if block != null:
			out[name] = block
	return out
