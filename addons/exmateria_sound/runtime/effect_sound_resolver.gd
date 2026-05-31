class_name EffectSoundResolver
## Port of lookup_sound_effect (0x801A32E8) from research/decompiled_functions/
## lookup_sound_effect.c. Resolves a timeline sound_id through one of 4
## effect-flags channels (each with mode + id_a + id_b + id_c) into a
## concrete sound_id that the feds pair selector consumes.
##
## A per-channel sound_index counter ticks every time that channel fires; the
## 5 modes use the counter for parity/cycle variants. Modes:
##   0 DIRECT_A      → id_a
##   1 PARITY_A      → id_a + (count & 1)            (alternates id_a/id_b)
##   2 DIRECT_B      → id_b if count > 0 else id_a
##   3 PARITY_B      → id_b + (count & 1) if count > 0 else id_a   (alternates id_b/id_c)
##   4 TRIPLE_CYCLE  → id_a + (count % 3)            (cycles id_a/id_b/id_c)
##   5+ DEFAULT      → pass timeline sound_id through unchanged


# sound_config.json channel entries, indexed 0..3.
# Each entry is a Dictionary: { mode, id_a, id_b, id_c, index }.
var channels: Array = []

# Per-channel counters (DAT_801b9250 in the C source).
var counters: PackedInt32Array = PackedInt32Array([0, 0, 0, 0])


static func from_sound_config(config: Dictionary):
	## Build a resolver from godot-learning's sound_config.json shape.
	## Untyped return so this script compiles in --script mode (no class
	## registry); callers get an EffectSoundResolver instance.
	var r = load("res://addons/exmateria_sound/runtime/effect_sound_resolver.gd").new()
	var raw_channels: Array = config.get("channels", [])
	r.channels = raw_channels
	return r


func reset_counters() -> void:
	counters = PackedInt32Array([0, 0, 0, 0])


func resolve(channel_index: int, timeline_sound_id: int) -> int:
	## Returns the resolved sound_id (config_channel argument to the feds
	## selector). Skips (returns -1) when timeline_sound_id == 0 or 1 per
	## sound_section.txt §7.3 ("Sound ID 0/1 = Skip").
	if timeline_sound_id < 2:
		return -1
	if channel_index < 0 or channel_index >= channels.size():
		return -1

	var chan: Dictionary = channels[channel_index]
	var mode: int = int(chan.get("mode", 0))
	var id_a: int = int(chan.get("id_a", 0))
	var id_b: int = int(chan.get("id_b", 0))
	var id_c: int = int(chan.get("id_c", 0))

	# Load-then-increment (post-increment like the C source).
	var count: int = counters[channel_index]
	counters[channel_index] = (count + 1) & 0xFF

	match mode:
		0:
			return id_a
		1:
			# PARITY_A: id_a when count even, id_b when count odd. In the C
			# source this reads (effect_flags_ptr + channel*4 + (count & 1) + 9)
			# — index 9 is id_a, index 10 is id_b.
			return id_a if (count & 1) == 0 else id_b
		2:
			return id_b if count > 0 else id_a
		3:
			if count > 0:
				# PARITY_B: id_b when (count & 1) == 0, id_c when == 1.
				return id_b if (count & 1) == 0 else id_c
			return id_a
		4:
			var slot := count % 3
			if slot == 0:
				return id_a
			elif slot == 1:
				return id_b
			return id_c
		_:
			# Mode 5+ DEFAULT: pass timeline_sound_id through.
			return timeline_sound_id
