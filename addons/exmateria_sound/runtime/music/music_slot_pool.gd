class_name MusicSlotPool
## Thin pool wrapper over Sequencer.tracks — adapts the music
## TrackState array to the SharedFlushTick / SharedIrqWalker pool
## interface. Mirrors EffectSoundPool's surface but iterates music
## tracks instead of the SFX 8-slot allocator.
##
## Music maps voices directly: track i (i >= 1) drives SPU voice
## (i - 1), so voice_for_slot is identity. SFX's pool offsets
## slot_idx by SPU_VOICE_BASE (= 16); music's base is 0.
##
## Pass 7.E.A — instantiated by Sequencer; SharedFlushTick and
## SharedIrqWalker are constructed but inert (no tick() calls).

const SPU_VOICE_BASE := 0
const POOL_SLOT_COUNT := Spu.NUM_VOICES


var _sequencer


func _init(sequencer) -> void:
	_sequencer = sequencer


static func voice_for_slot(slot_idx: int) -> int:
	return slot_idx


func active_slots() -> Array:
	var out: Array = []
	if _sequencer == null:
		return out
	for ts in _sequencer.tracks:
		if ts.ctx == null:
			continue
		if ts.done:
			continue
		if ts.voice_idx < 0:
			continue
		out.append(ts.ctx.slot)
	return out
