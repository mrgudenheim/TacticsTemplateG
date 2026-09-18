@tool
extends RefCounted

## The battle effect-SFX engine's PORT SIGNATURE — the five verbs an addon may name
## instead of the `ExMateriaEffectSfx` autoload identifier.
##
## `ExMateriaEffectSfx="*res://addons/exmateria_sound/runtime/effect_sfx_engine.gd"`
## is registered by the HOST's `project.godot [autoload]` block, so naming it from
## inside an addon is the standalone-parse break `TunePort`, `DisplayPort` and
## `EventPort` exist to fix (ADR-0308 dec. 1: a member may reach NO autoload
## identifier at all). It was eleven of `addons/exmateria_effects`' twenty-six arm-2
## lines, all in `cast/EffectInstance.gd`, and the last of them.
##
## 🔴 **THIS IS THE ONE OF THE FOUR REACHES THAT COULD NOT BE FIXED IN PLACE, AND
## THAT IS WHY THE PORT IS HERE AND NOT IN `exmateria_effects/install/`.**
## `Effects`' other three autoload reaches — `TintedSurfaces`,
## `ScreenEffectOverlay`, `EffectMultiMeshPool` — point at scripts
## `addons/exmateria_effects/` SHIPS, so that addon binds them by node path in its own
## `install/` ports and `check_addon_portability.py` arm 2b rules it free. This one
## points into `addons/exmateria_sound/`, a package `Effects` does not ship. Arm 2b's
## own remedy note states the consequence: *"A SYSTEM naming a script it does not ship
## has swapped a parse error for a silent null, which is a worse report of the same
## dependency. Its answer is a PORT."* `Effects` is one of the eleven systems, so the
## node path was closed to it and a port in the PORT TIER is the route that was open
## (ADR-0139 dec. 9/12 — the kernel and the platform port are what a portable addon
## may name; ADR-0175 dec. 2 for the soft-bind).
##
## 🔴 **AND THIS PORT NAMES NO PATH INTO THE SOUND PACKAGE EITHER.** The bind is a
## node-path string and every call is duck-typed, so this file carries no `preload`,
## no `class_name` and no `res://addons/exmateria_sound/` literal — which is the whole
## reason it works. A port that imported the engine to call it would have moved the
## dependency one directory and left every arm measuring it exactly where it was.
## `feds_bank` stays UNTYPED for the same reason: it is the sound package's `FedsBank`
## and annotating it would name that package's type.
##
## | verb | with the engine | without it |
## |---|---|---|
## | `begin_effect` | opens a cast, returns its token | **`0`** |
## | `play_pair` | dispatches one FEDS pair | **`false`** |
## | `end_effect` | key-off, voices ring out | **no-op** |
## | `orphan_effect` | visual ended, let the sound finish | **no-op** |
## | `load_feds_bank` | parses a `feds.bin` into a bank | **`null`** |
##
## 🔴 **THE ABSENT COLUMN IS NOT INVENTED — IT IS THE ENGINE'S OWN NOT-READY
## BEHAVIOUR, VERBATIM, FOR THE FOUR CAST VERBS.** `effect_sfx_engine.gd` opens each of
## them with `if not ready_ok:` and answers `0`, `false`, and two bare `return`s. So a consumer who
## installed `exmateria_effects` without `exmateria_sound` gets the state the shipped
## game already reaches whenever the audio engine has not finished booting, and
## `cast/EffectInstance.gd` already treats `_sfx_token == 0` as "no cast" (`var
## _sfx_token: int = 0`). Nothing downstream had to learn a new state. That is the
## strongest form this table can take: an absent answer that some real run already
## produces is one the call sites are already proven to survive.
##
## ⚠️ **`load_feds_bank` IS THE ONE ROW WHERE THAT DERIVATION DOES NOT HOLD, AND IT IS
## WEAKER FOR IT.** The engine deliberately does NOT test `ready_ok` there, because it is
## a file parser rather than a device call and effects load before audio boots. So its
## `null` is this port's own answer, not a state the shipped game reaches on its own
## schedule — see that verb's note below for why `null` was nonetheless already a live
## value at every reader.
##
## 🔴 **FIVE VERBS IS THE WHOLE REACH AND NOT THE WHOLE ENGINE, STATED AS AN
## ASYMMETRY.** `effect_sfx_engine.gd` also publishes `debug_snapshot`,
## `audition_split_stats`, `unit_count`, `tunables`/`write_tunable`,
## `set_audio_monitor_enabled` and more; none is reached from inside any addon today,
## so none is here. `DisplayPort`'s docstring records what leaving that unsaid costs —
## #590 shipped `set_camera_angle` without its read, and the missing half *"reads as
## complete for exactly as long as nobody outside the host wants the value back"*
## (ADR-0234). The first addon that wants one of those verbs adds it HERE rather than
## going back to the identifier.
##
## Signatures mirror the engine's exactly, including the two `void` returns and
## `load_feds_bank`'s untyped return, so a re-point changes the receiver name and nothing else. `play_pair`'s `bool` is the
## engine's own; the two `void`s stay `void` because there is nothing to report that
## `begin_effect`'s token does not already tell the caller.
##
## Nothing here is instantiated; the class is a namespace of statics.
## `tests/TunePortTest.gd` drives both the bound and the absent path.

## Resolved singleton, or `null`. Same cache discipline as this addon's three sibling
## ports: never caches a NEGATIVE result, because the audio engine's autoload can
## appear after this class is first touched and a test can rename it and put it back.
static var _port: Node = null


## The live effect-SFX engine, or `null` where the consumer registered no autoload.
##
## Two rejections, not one (`TunePort._resolve`). `effect_sfx_engine.gd` is NOT a
## `@tool` script, so in the editor the engine instantiates the autoload as a
## PLACEHOLDER that answers to the name and carries none of the methods — which is a
## live case here rather than a hypothetical one: `cast/EffectInstance.gd:383` already
## carries the comment that the editor preview must not synthesize audio *"and
## ExMateriaEffectSfx is not a @tool"*. `has_method` is what separates the placeholder
## from the engine.
static func _resolve() -> Node:
	if _port != null and is_instance_valid(_port):
		return _port
	var loop := Engine.get_main_loop()
	if loop == null or not (loop is SceneTree):
		return null
	var root: Window = (loop as SceneTree).root
	if root == null:
		return null
	var n := root.get_node_or_null(^"ExMateriaEffectSfx")
	if n == null or not n.has_method(&"begin_effect"):
		return null
	_port = n
	return n


## Test seam — see `TunePort._forget_port` for why `is_instance_valid` is not the same
## question as "does the lookup still succeed".
static func _forget_port() -> void:
	_port = null


## Parse a `feds.bin` into the sound package's FEDS bank, or `null` where no engine is
## registered.
##
## The return is UNTYPED for the same reason `play_pair`'s `feds_bank` argument is: the
## type is `addons/exmateria_sound/runtime/feds_bank.gd` and naming it here would put the
## path this port exists to avoid back into this file. `EffectData.feds_bank` is already
## declared untyped, so the re-spelling changes no annotation downstream.
##
## 🔴 **`null` HERE MEANS TWO DIFFERENT THINGS AND BOTH WERE ALREADY REACHABLE.** No
## package installed, and no `feds.bin` on disk — `EffectData` only calls this when
## `FileAccess.file_exists` says the file is there, and every reader of `feds_bank` in
## the tree is already written against `null` because most effects ship no bank at all.
## So the absent-package column needed no new branch at any call site, which is the same
## property the four verbs above have.
##
## ⚠️ **IN THE EDITOR THIS ANSWERS `null`,** because `effect_sfx_engine.gd` is not a
## `@tool` script and `_resolve()` rejects the placeholder autoload (see its docstring).
## `cast/EffectInstance.gd` is `@tool` and DOES load effect data in-editor, so its
## in-editor casts now hold no bank — which changes nothing, because every path in that
## file that reads a bank is behind `not Engine.is_editor_hint()` or is a studio verb the
## editor never calls, and the editor preview is already forbidden to synthesize audio.
## `tests/TunePortTest.gd` drives both arms, off `EffectData.load_from_directory`
## rather than off this verb — the loaded effect is the seam every reader uses.
static func load_feds_bank(feds_path: String):
	var p := _resolve()
	if p == null or not p.has_method(&"load_feds_bank"):
		return null
	return p.load_feds_bank(feds_path)


## Open a cast and return its token, or `0` where no engine is registered.
##
## `0` is the engine's own answer when it is not `ready_ok`, and every caller already
## treats it as "no cast" — so the absent path needs no new branch at any call site.
static func begin_effect() -> int:
	var p := _resolve()
	if p == null:
		return 0
	return p.begin_effect()


## Dispatch one FEDS pair for `token`. Returns whether it was dispatched.
##
## `feds_bank` is the sound package's `FedsBank` and is deliberately UNTYPED — see the
## second red note in the header. `single_track` (0/1) is the authoring-only per-track
## energy isolation (ADR-0085 §3); `-1` is both.
static func play_pair(token: int, feds_bank, pair_idx: int, sound_id: int,
		single_track: int = -1) -> bool:
	var p := _resolve()
	if p == null:
		return false
	return p.play_pair(token, feds_bank, pair_idx, sound_id, single_track)


## End the cast: key-off its held voices so they release rather than cut.
static func end_effect(token: int) -> void:
	var p := _resolve()
	if p == null:
		return
	p.end_effect(token)


## The cast's VISUAL ended but its SOUND should finish — stop expecting new pairs and
## let the dispatched ones ring out to their natural EndBar.
static func orphan_effect(token: int) -> void:
	var p := _resolve()
	if p == null:
		return
	p.orphan_effect(token)
