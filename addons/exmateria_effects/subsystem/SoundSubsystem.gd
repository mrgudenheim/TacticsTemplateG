extends RefCounted
## Subsystem adapter (renamed from SoundTrack, #31) that lets the
## [EffectTimeline] pump the exmateria-sound addon's `EffectSoundController`
## uniformly (ADR-0012). The addon stays untouched — the `Subsystem` contract
## is godot-learning's orchestration vocabulary, not the sound package's
## domain. (The addon-side class name `EffectSoundController` is a exmateria-sound
## concern; from godot-learning's perspective this adapter IS the sound
## subsystem.)
##
## `advance(frame, phase)` → `controller.update(frame, controller.fire_sub_tick)`:
## sound self-handles its one fire sub-tick internally (matching the gold
## a-la-carte driver `effect_audition_player.gd`). Passing the controller's own
## `fire_sub_tick` — not the `sub_tick = 0` default the old godot path used —
## **closes the `fire_sub_tick != 0` gap** so calibrated sub-tick effects fire.
## `phase` is ignored: sound derives its phase from its own channels.
##
## No `class_name` — instantiated by path, per the ADR-0004 cache pattern.
## Vault: [[Effect Sound Timing]]

var _controller = null


func _init(controller) -> void:
	_controller = controller


func advance(frame: int, _phase = null) -> void:
	# Studio Solo/Mute is applied per-CHANNEL downstream: the controller fires all its
	# channels (its keyframe walk stays whole), and EffectInstance drops the triggers whose
	# from_channel is muted (the addon's sound_event carries the channel). Suppressing at
	# the trigger keeps the addon untouched (CLAUDE.md).
	if _controller:
		_controller.update(frame, _controller.fire_sub_tick)


func reset() -> void:
	# The sound controller is created and start()'d per cast by EffectInstance;
	# there is no per-frame state for the adapter to reset.
	pass
