## Port of lookup_sound_effect (0x801A32E8) from research/decompiled_functions/
## lookup_sound_effect.c. Resolves a timeline sound_id through one of 4
## [SoundContainer]s (each with mode + id_a + id_b + id_c) into a concrete
## sound_id that the FEDS pair selector consumes. See CONTEXT.md "Audio".
##
## A per-container counter ticks every time that container fires; the 5 modes
## use the counter for parity/cycle variants. Modes:
##   0 DIRECT_A      → id_a
##   1 PARITY_A      → id_a + (count & 1)            (alternates id_a/id_b)
##   2 DIRECT_B      → id_b if count > 0 else id_a
##   3 PARITY_B      → id_b + (count & 1) if count > 0 else id_a   (alternates id_b/id_c)
##   4 TRIPLE_CYCLE  → id_a + (count % 3)            (cycles id_a/id_b/id_c)
##   5+ DEFAULT      → pass timeline sound_id through unchanged
##
## 🔴 **NOTHING IN THIS FILE KNOWS WHAT A SOUND IS**, which is why it moved out of the
## audio package with the walker (ADR-0318 dec. 3). Eighty-odd lines of five integer
## modes over `sound_containers.json` — a file `exmateria_effects` owns and the Effect
## Studio edits. It shipped under `exmateria_sound/runtime/` for the historical reason
## that the walker was written there, not for a reason about its content.
##
## Vault: [[Cure 4 Audio Parity]]
## Vault: [[Effect Sound Timing]]


# sound_containers.json entries, indexed 0..N-1.
# Each entry is a Dictionary: { mode, id_a, id_b, id_c, index }.
var containers: Array = []

# Per-container counters (DAT_801b9250 in the C source).
var counters: PackedInt32Array = PackedInt32Array([0, 0, 0, 0])


static func from_sound_containers(containers_doc: Dictionary):
	## Build a resolver from godot-learning's sound_containers.json shape.
	## Untyped return so this script compiles in --script mode (no class
	## registry); callers get an EffectSoundResolver instance.
	var r = load("res://addons/exmateria_platform/sound_schedule/EffectSoundResolver.gd").new()
	var raw: Array = containers_doc.get("containers", [])
	r.containers = raw
	return r


func reset_counters() -> void:
	counters = PackedInt32Array([0, 0, 0, 0])


func resolve(sound_container_idx: int, timeline_sound_id: int) -> int:
	## Returns the resolved sound_id (consumed by the FEDS pair selector,
	## pair_idx = resolved - 1). Skips (returns -1) when timeline_sound_id ==
	## 0 or 1 per sound_section.txt §7.3 ("Sound ID 0/1 = Skip").
	if timeline_sound_id < 2:
		return -1
	if sound_container_idx < 0 or sound_container_idx >= containers.size():
		return -1

	var container: Dictionary = containers[sound_container_idx]
	var mode: int = int(container.get("mode", 0))
	var id_a: int = int(container.get("id_a", 0))
	var id_b: int = int(container.get("id_b", 0))
	var id_c: int = int(container.get("id_c", 0))

	# Load-then-increment (post-increment like the C source).
	var count: int = counters[sound_container_idx]
	counters[sound_container_idx] = (count + 1) & 0xFF

	match mode:
		0:
			return id_a
		1:
			# PARITY_A: id_a when count even, id_b when count odd. In the C
			# source this reads (effect_flags_ptr + container*4 + (count & 1) + 9)
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
