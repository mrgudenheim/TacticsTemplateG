extends RefCounted
## Adapter letting [EffectTimeline] pump the exmateria-sound addon's
## `EffectSoundController` uniformly (ADR-0012); the addon stays untouched.
## `advance(frame, phase)` → `controller.update(frame, controller.fire_sub_tick)`:
## the controller's own fire_sub_tick (not the sub_tick = 0 default) keeps
## calibrated sub-tick effects firing, as in the gold a-la-carte driver
## `effect_audition_player.gd`. `phase` is ignored - sound derives its phase from
## its own channels. No `class_name` - instantiated by path (ADR-0004 cache pattern).
## Vault: [[Effect Sound Timing]]

var _controller = null


func _init(controller) -> void:
	_controller = controller


func advance(frame: int, _phase = null) -> void:
	# Studio Solo/Mute is applied per-CHANNEL downstream: the controller fires all its
	# channels, and EffectInstance drops the triggers whose from_channel is muted (the
	# addon's sound_event carries the channel).
	if _controller:
		_controller.update(frame, _controller.fire_sub_tick)


func reset() -> void:
	# The sound controller is created and start()'d per cast by EffectInstance;
	# there is no per-frame state for the adapter to reset.
	pass
