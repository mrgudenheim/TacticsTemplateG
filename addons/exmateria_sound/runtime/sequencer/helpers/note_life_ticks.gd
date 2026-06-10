class_name SequencerNoteLifeTicks
## Converts a raw note tick count + gate mode into the sustain tick
## count used for note_ticks_remaining. Gate mode 0x10 means "hold for
## full duration"; 0x0F (default) is "hold for duration - 1"; other
## modes scale by gate_mode/16.

const DEFAULT_NOTE_GATE := 0x0F


static func compute(raw_ticks: int, gate_mode: int = DEFAULT_NOTE_GATE) -> int:
	if raw_ticks <= 0:
		return 0
	var sustain_ticks := raw_ticks
	if gate_mode == 0x0F:
		sustain_ticks = raw_ticks - 1
	elif gate_mode != 0x10:
		sustain_ticks = (raw_ticks * gate_mode) >> 4
	if sustain_ticks <= 0:
		return 1
	return sustain_ticks
