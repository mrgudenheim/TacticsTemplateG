@tool
extends RefCounted
## The EVENT-SOUND router's PORT SIGNATURE — the seven verbs an addon may name
## instead of the `SfxRouter` autoload identifier.
##
## `SfxRouter="*res://src/audio/SfxRouter.gd"` is registered by the HOST's
## `project.godot [autoload]` block, so naming it from inside an addon is the
## standalone-parse break `TunePort`, `DisplayPort`, `EventPort` and `SfxPort`
## exist to end (ADR-0308 dec. 1: a member may reach NO autoload identifier at
## all). It was seven of `addons/exmateria_cutscene`'s eighteen remaining arm-2
## lines and the largest single block of them.
##
## 🔴 **THIS IS NOT `SfxPort`, AND THE TWO FRONT DIFFERENT ENGINES.** `SfxPort`
## fronts `ExMateriaEffectSfx` — the BATTLE EFFECT-SFX engine, the FEDS
## pair dispatcher a spell cast drives. This one fronts `SfxRouter`: system cues,
## `{6B}` BG ambients and the `{7C}` 8-voice teardown, which is the EVENT SCRIPT's
## sound surface. The name is the autoload's own for that reason — `SfxPort` was
## taken by the other engine and a second port called anything vaguer than the
## singleton it resolves would have made the ambiguity permanent. Note the layering
## while reading the absent column below: `SfxRouter` itself calls
## `ExMateriaEffectSfx` to reach voices, so this port sits ABOVE `SfxPort`'s engine
## and never beside it.
##
## 🔴 **THE NODE-PATH REMEDY WAS CLOSED HERE, WHICH IS WHY THIS IS A PORT.**
## `check_addon_portability.py` arm 2b frees an addon that binds its OWN singleton by
## node path, because it ships the script the `[autoload]` line points at.
## `src/audio/SfxRouter.gd` is a HOST path that no addon ships, so arm 2b's own remedy
## note applies verbatim: *"A SYSTEM naming a script it does not ship has swapped a
## parse error for a silent null, which is a worse report of the same dependency. Its
## answer is a PORT."* Same finding, same route, as `SfxPort` (ADR-0139 dec. 9/12 for
## what a portable addon may name; ADR-0175 dec. 2 for the soft-bind).
##
## | verb | with the router | without it |
## |---|---|---|
## | `play_cue` | plays a registered cue, returns its token | **`0`** |
## | `play_system_by_id` | plays a system-bank slot, returns its handle | **`0`** |
## | `play_bg` | starts an env ambient, returns its handle | **`0`** |
## | `set_bg_volume` | drives a bg cast's ramp volume | **no-op** |
## | `stop_bg_handle` | key-off ring-out for one bg cast | **no-op** |
## | `stop_all_event_sound` | the `{7C}` 8-voice teardown | **no-op** |
## | `emit_bg_sound_changed` | re-ramp notification to listeners | **no-op** |
##
## 🔴 **EVERY ABSENT ANSWER IS THE ROUTER'S OWN MISS BEHAVIOUR, QUOTED FROM ITS OWN
## BODY — none is a degradation this port invented.** `play_cue` answers `0` on an
## unknown cue, `play_system_by_id` answers `0` on a non-positive slot, `play_bg`
## answers `0` on a non-positive sound id; `set_bg_volume` and `stop_bg_handle` both
## open with `if handle == 0: return`; and `stop_all_event_sound` documents itself
## *"Idempotent: no tracked voices → nothing to do"*. So a consumer who installed
## `exmateria_cutscene` without the host's audio reaches the state the shipped game
## already reaches on an SPU miss.
##
## 🔴 **AND THE HANDLE CHAIN CLOSES ON ITSELF, WHICH IS STRONGER THAN SEVEN
## INDEPENDENT ANSWERS.** Without the router `play_bg` returns `0`, and `0` is exactly
## the handle both `set_bg_volume` and `stop_bg_handle` already early-return on. The
## call sites need no new branch because the absent path feeds them a value their
## live path already produces: `ScenarioWorld.play_bg_sound`'s own docstring reads
## *"returns the backend handle (0 = SPU miss / bad id)"* and the `{6B}` ramp registry
## is keyed on it. Nothing downstream had to learn a new state.
##
## 🔴 **`emit_bg_sound_changed` IS A SIGNAL EMISSION AND NOT A METHOD CALL, AND THAT
## IS WHY IT IS SPELLED DIFFERENTLY FROM THE OTHER SIX.** `ScenarioWorld:817` does
## `SfxRouter.bg_sound_changed.emit(…)` — the `{6A}` Edit BG Sound opcode telling
## listeners a live ambient was re-ramped in place. A port cannot publish a signal
## OBJECT without handing back the autoload's own member and putting the identifier
## right back in the consumer's hands, so it publishes the emission as a verb. The
## parameter names are the SIGNAL's (`action`, not the call site's `kind`), because
## the signature this mirrors is `signal bg_sound_changed(action: String,
## sound_id: int, stacking: int, handle: int)`.
##
## 🔴 **SEVEN VERBS IS THE WHOLE REACH AND NOT THE WHOLE ROUTER, STATED AS AN
## ASYMMETRY.** `SfxRouter` also publishes `play_env`, `stop_bg_sound`,
## `set_listener`, its `cue_requested` signal and more; none is reached from inside
## any addon today, so none is here. `DisplayPort`'s docstring records what leaving
## that unsaid costs — #590 shipped `set_camera_angle` without its read, and the
## missing half *"reads as complete for exactly as long as nobody outside the host
## wants the value back"* (ADR-0234). The first addon that wants one of those adds it
## HERE rather than going back to the identifier.
##
## Signatures mirror the router's exactly, including the three `int` returns the
## current call sites discard, so a re-point changes the receiver name and nothing
## else. Nothing here is instantiated; the class is a namespace of statics.
## `tests/TunePortTest.gd` drives both the bound and the absent path.

## Resolved singleton, or `null`. Same cache discipline as this addon's sibling ports:
## never caches a NEGATIVE result, because the router's autoload can appear after this
## class is first touched and a test can rename it and put it back.
static var _port: Node = null


## The live event-sound router, or `null` where the consumer registered no autoload.
static func _resolve() -> Node:
	if _port != null and is_instance_valid(_port):
		return _port
	var loop := Engine.get_main_loop()
	if loop == null or not (loop is SceneTree):
		return null
	var root: Window = (loop as SceneTree).root
	if root == null:
		return null
	var n := root.get_node_or_null(^"SfxRouter")
	if n == null or not n.has_method(&"play_bg"):
		return null
	_port = n
	return n


## Test seam — see `TunePort._forget_port` for why `is_instance_valid` is not the same
## question as "does the lookup still succeed".
static func _forget_port() -> void:
	_port = null


## Play a registered cue by name; returns its audition token, or `0` with no router.
##
## `0` is the router's own answer for an unknown cue, so the absent path is a miss the
## call sites already survive.
static func play_cue(name: String) -> int:
	var p := _resolve()
	if p == null:
		return 0
	return p.play_cue(name)


## `{21}` Sound Effect — play a system-bank sound by raw FFT sound id.
##
## `0` is the router's own answer for a non-positive slot.
static func play_system_by_id(slot: int) -> int:
	var p := _resolve()
	if p == null:
		return 0
	return p.play_system_by_id(slot)


## `{6B}` BG Sound — start an env-bank ambient (`stacking != 0` = an overlay voice).
## Returns the backend handle, or `0` with no router.
##
## `0` is the router's own miss handle AND the value `set_bg_volume` /
## `stop_bg_handle` below already early-return on — see the handle-chain note in the
## header. This is the one verb whose absent answer the rest of the port depends on.
static func play_bg(sound_id: int, stacking: int) -> int:
	var p := _resolve()
	if p == null:
		return 0
	return p.play_bg(sound_id, stacking)


## Push a bg ambient's current ramp volume (0..127) to its SPU voices.
static func set_bg_volume(handle: int, vol: int) -> void:
	var p := _resolve()
	if p == null:
		return
	p.set_bg_volume(handle, vol)


## Stop one bg ambient's voices by handle (key-off ring-out).
static func stop_bg_handle(handle: int) -> void:
	var p := _resolve()
	if p == null:
		return
	p.stop_bg_handle(handle)


## `{7C}` End Sound — stop every currently-playing event SFX/BGM voice (the PSX
## SUB_800440cc 8-voice teardown).
static func stop_all_event_sound() -> void:
	var p := _resolve()
	if p == null:
		return
	p.stop_all_event_sound()


## `{6A}` Edit BG Sound — notify listeners a live ambient was re-ramped in place.
##
## The emission, not the signal object — see the red note in the header for why a port
## cannot publish the latter. Parameter names are the signal's own.
static func emit_bg_sound_changed(action: String, sound_id: int, stacking: int,
		handle: int) -> void:
	var p := _resolve()
	if p == null:
		return
	p.bg_sound_changed.emit(action, sound_id, stacking, handle)


## The bank-slot LABEL for `slot` in `bank` ("" if unknown), or `""` with no router.
##
## 🔴 A CATALOGUE LOOKUP AND NOT A PLAYBACK VERB, AND IT IS HERE BECAUSE THE CATALOGUE
## ITSELF CANNOT BE PORTED. `SfxCatalog` is a path-preloaded STATIC class, not an
## autoload, so `_resolve`'s node path has nothing to bind — an addon that wanted these
## two answers had to `preload("res://src/audio/SfxCatalog.gd")`, which is a reach into
## another system's SOURCE (arm 6) rather than a parse break (arm 2). The router already
## preloads the catalogue for four of its own lookups, so it is the RESOLVABLE thing
## that has it, and it re-publishes these two as `catalog_name_for` / `catalog_is_loop`
## (gl-ADR-0330).
##
## `""` is the catalogue's own answer for an unknown slot, so the absent path is a miss
## its one caller already survives — `ScenarioVM` uses it in a log string.
static func catalog_name_for(bank: String, slot: int) -> String:
	var p := _resolve()
	if p == null:
		return ""
	return p.catalog_name_for(bank, slot)


## Whether `slot` in `bank` is a looping/continuous sound; `false` with no router.
##
## `false` is the catalogue's own answer for an unknown slot AND the safe one: a bg
## ambient that is not marked looping is triggered as a ONE-SHOT, so a portless consumer
## gets a sound that ends rather than a voice that never releases.
static func catalog_is_loop(bank: String, slot: int) -> bool:
	var p := _resolve()
	if p == null:
		return false
	return p.catalog_is_loop(bank, slot)
