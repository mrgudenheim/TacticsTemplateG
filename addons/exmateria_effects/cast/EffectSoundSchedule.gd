extends RefCounted
## The sound walker's four artifacts, READ OFF EffectData — one parse, one object; the
## loader's second parse + re-points were the undo (ADR-0085). Shape-compatible with
## exmateria_sound's LoadedEffect. No class_name (ADR-0004). has_sound() = is there a
## BANK; has_schedule() = is there anything to ANNOUNCE, and ADR-0318 dec. 2 made the
## second one the walker's gate — the first was a question about an audio artifact.
## vault: .vaults/comments/exmateria_effects/sound-schedule-dedup.md

var sound_tracks: Dictionary = {}
var sound_containers: Dictionary = {}
# RAW so the walker's per-key defaults apply — parsed TimelineData's spawn_delay differs (0 vs 1).
var timeline_header: Dictionary = {}
# The sound package's FedsBank or null; UNTYPED so this addon never names that package's type.
var feds_bank = null


static func from_effect_data(data):
	## Untyped data: no load-order cycle — EffectData preloads nothing from cast/.
	var s = load("res://addons/exmateria_effects/cast/EffectSoundSchedule.gd").new()
	if data == null:
		return s
	if data.sound is Dictionary:
		s.sound_tracks = data.sound
	if data.sound_containers is Dictionary:
		s.sound_containers = data.sound_containers
	if data.timeline and data.timeline.header is Dictionary:
		s.timeline_header = data.timeline.header
	s.feds_bank = data.feds_bank
	return s


func has_sound() -> bool:
	## Is there a BANK to play — bytes, not a schedule. Still the right question for
	## anything about to make a noise; it is no longer the question that decides whether
	## the walker runs.
	return feds_bank != null and feds_bank.num_pairs > 0


func has_schedule() -> bool:
	## Is there anything to ANNOUNCE — the gate `EffectSoundController.load_effect` uses
	## since ADR-0318 dec. 2, and the reason `has_sound()` above no longer decides
	## whether the walker runs. Blind to `feds_bank` on purpose: an effect with keyframes
	## and no `feds.bin` has a schedule, publishes its events, and is silent.
	for key in ["phase1", "phase2", "for_each"]:
		var track = sound_tracks.get(key, [])
		if track is Array and not (track as Array).is_empty():
			return true
	return false


func script_is_three_phase() -> bool:
	var p1 = sound_tracks.get("phase1", [])
	return p1 is Array and not (p1 as Array).is_empty()
