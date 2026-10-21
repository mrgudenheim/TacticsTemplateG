extends RefCounted
## Byte-exact TIMELINE-HEADER writer for `E###.BIN` (#271) — GDScript port of
## `tools/write_effect_timeline_header.py`.
##
## The three phase-duration u16s at the top of the timeline section:
##
##     phase1_duration @ timeline_section_ptr + 0x04   frames until `for_each` opens
##     spawn_delay     @ timeline_section_ptr + 0x06   between-spawn gap, multi-target
##     phase2_delay    @ timeline_section_ptr + 0x0A   `for_each` -> phase2 gap
##
## A partial patch. It shares `timeline_section_ptr` with the `particle_timeline` serializer and
## with screen/palette/camera/sound, so the writers must own DISJOINT bytes: this one writes 6,
## at 0x04/0x06/0x0A, and the channels all live at 0x0C and beyond.
##
## This does not write `0x00-0x03` or `0x08-0x09`. The parser reads them, the engine ignores
## them, and they are NOT zero across the corpus, so writing the header as one 12-byte struct
## or zeroing what the editor does not author would move bytes no author touched. They stay
## verbatim; that is what makes an unedited save byte-exact.
##
## Stored as s16 by the reader, written as the low 16 bits: every value the reader produced
## round-trips to the same two bytes, and a negative duration (which the choke point refuses
## upstream) still cannot corrupt a neighbouring field.
##
## No `class_name` (ADR-0004) — file_model members stay path-preloaded.

const Layout = preload("res://addons/exmateria_effects/file_model/EffectBinLayout.gd")

## The three authorable duration keys -> their offset from `timeline_section_ptr`. Mirrors
## `write_effect_timeline_header.OFF_*` and the writable subset of
## `EffectReadParticleTimeline.HEADER_FIELDS`, so reader and writer share one geometry.
const DURATION_FIELDS: Dictionary = {
	"phase1_duration": Layout.TIMELINE_OFF_PHASE1_DURATION,
	"spawn_delay": Layout.TIMELINE_OFF_SPAWN_DELAY,
	"phase2_delay": Layout.TIMELINE_OFF_PHASE2_DELAY,
}


## Partial-patch the three phase durations of `buf` IN PLACE from `block` — the parsed,
## possibly edited `timeline` block, whose `header` sub-dict carries the durations. Returns
## `""` on success, else the refusal (the registry's serializer contract).
##
## A key ABSENT from the header dict leaves its two bytes untouched rather than writing a
## default: an older `timeline.json`, or a saver emitting a sparse header, must not silently
## zero a duration it never knew about.
static func patch_into(buf: PackedByteArray, header: Dictionary, block) -> String:
	if not (block is Dictionary):
		return ""
	var head = block.get("header")
	if not (head is Dictionary):
		return ""
	var ptr: int = int(header["timeline_section_ptr"])
	if ptr <= 0 or ptr + Layout.TIMELINE_HEADER_BYTES > buf.size():
		return "timeline_header: timeline_section_ptr %d does not fit the buffer" % ptr
	for key in DURATION_FIELDS:
		if head.has(key):
			buf.encode_u16(ptr + int(DURATION_FIELDS[key]), int(head[key]) & 0xFFFF)
	return ""
