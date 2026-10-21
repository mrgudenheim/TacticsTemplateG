@tool
extends RefCounted
## The music sequencer's PORT SIGNATURE — the two verbs an addon may name instead of
## the `MusicPlayer` autoload identifier.
##
## `MusicPlayer="*res://src/audio/MusicPlayer.gd"` is registered by the HOST's
## `project.godot [autoload]` block, so naming it from inside an addon is the
## standalone-parse break this addon's sibling ports exist to end (ADR-0308 dec. 1: a
## member may reach NO autoload identifier at all). It was two of
## `addons/exmateria_cutscene`'s eighteen remaining arm-2 lines, and they sit in the
## same thin-wrapper block as `SfxRouterPort`'s seven — `ScenarioWorld.gd:785` names
## both singletons in one comment (*"Thin wrappers over the audio autoloads
## (SfxRouter / MusicPlayer)"*), which is why the two ports landed together as one
## reach family and not as two units.
##
## 🔴 **ONE PORT PER AUTOLOAD, EVEN THOUGH THESE TWO ARE ONE SYSTEM.** The obvious
## alternative was a single `AudioPort` fronting both singletons. It is rejected
## because every shipped port in this addon resolves exactly one node
## (`TunePort`→`Tune`, `DisplayPort`→`PSXDisplay`, `EventPort`→`EventBus`,
## `SfxPort`→`ExMateriaEffectSfx`), and that 1:1 is what makes `_resolve`'s cache and
## its `has_method` sentinel mean something: a two-node port has no single answer to
## *"is it bound?"* and would report a consumer who registered one of the two as
## either wholly present or wholly absent. Half-bound is a real state here — a project
## can take the event-sound router without the sequencer — so it needs two resolves.
##
## 🔴 **NOT `MusicPlayerPort`, AND NOT `WorldMapMusicPort`.** The short name matches
## the sibling ports' own convention (`DisplayPort` fronts `PSXDisplay`, not
## `PSXDisplayPort`); the collision that forced `SfxRouterPort` to take its
## autoload's full name does not exist here. ⚠️ `src/world_map/WorldMapMusicPort.gd`
## is a DIFFERENT thing despite the name — a host-tier, constructor-injected
## (`_init(player: Node)`) one-method port for the world-map theme, not a soft-bound
## static namespace an addon may name. It stays where it is; this file does not
## replace it and neither reaches the other.
##
## | verb | with the sequencer | without it |
## |---|---|---|
## | `fade_out` | fades the live track to silence, returns whether it fired | **`false`** |
## | `switch_track` | cross-fades to a slot, returns whether it fired | **`false`** |
##
## 🔴 **BOTH ABSENT ANSWERS ARE THE SEQUENCER'S OWN, QUOTED FROM ITS OWN BODY.**
## `fade_out` documents itself *"No-op (returns false) if nothing is playing —
## matching FFT's `forcePlayedMUS == 0` gate"*, and `switch_track` *"Returns false if
## the song assets are missing"*. So `false` here is not an invented degradation: it
## is the answer the shipped game already produces whenever no music is up, which for
## `{60}` Fade Sound is the common case rather than an edge one. Both call sites
## (`ScenarioWorld.fade_music`, `ScenarioWorld.switch_music_track`) are `void` and
## already discard the bool, so the absent path changes nothing downstream.
##
## 🔴 **TWO VERBS IS THE WHOLE REACH AND NOT THE WHOLE SEQUENCER, STATED AS AN
## ASYMMETRY.** `MusicPlayer` also publishes `play_slot`, `stop`, `is_playing`,
## `set_volume` and more; none is reached from inside any addon today, so none is
## here. The first addon that wants one adds it HERE rather than going back to the
## identifier (ADR-0234, and `DisplayPort`'s header for what the missing half of
## #590's `set_camera_angle` cost).
##
## Signatures mirror the sequencer's exactly, including the two `bool` returns the
## current call sites discard, so a re-point changes the receiver name and nothing
## else. Nothing here is instantiated; the class is a namespace of statics.
## `tests/TunePortTest.gd` drives both the bound and the absent path.

## Resolved singleton, or `null`. Same cache discipline as this addon's sibling ports:
## never caches a NEGATIVE result, because the sequencer's autoload can appear after
## this class is first touched and a test can rename it and put it back.
static var _port: Node = null


## The live music sequencer, or `null` where the consumer registered no autoload.
static func _resolve() -> Node:
	if _port != null and is_instance_valid(_port):
		return _port
	var loop := Engine.get_main_loop()
	if loop == null or not (loop is SceneTree):
		return null
	var root: Window = (loop as SceneTree).root
	if root == null:
		return null
	var n := root.get_node_or_null(^"MusicPlayer")
	if n == null or not n.has_method(&"switch_track"):
		return null
	_port = n
	return n


## Test seam — see `TunePort._forget_port` for why `is_instance_valid` is not the same
## question as "does the lookup still succeed".
static func _forget_port() -> void:
	_port = null


## `{60}` Fade Sound — fade the live music to silence over `ticks` sequencer ticks
## (`ticks <= 0` cuts immediately). Returns whether a fade actually started.
##
## `false` is the sequencer's own answer when nothing is playing.
static func fade_out(ticks: int) -> bool:
	var p := _resolve()
	if p == null:
		return false
	return p.fade_out(ticks)


## `{22}` Switch Track — stop the current song, start `MUSIC_<slot>` from the top,
## then ramp master volume to `target_vol` (0..127) over `ticks` sequencer ticks.
## Returns whether the switch actually fired.
##
## `false` is the sequencer's own answer when the song assets are missing.
static func switch_track(slot: int, target_vol: int, ticks: int) -> bool:
	var p := _resolve()
	if p == null:
		return false
	return p.switch_track(slot, target_vol, ticks)
