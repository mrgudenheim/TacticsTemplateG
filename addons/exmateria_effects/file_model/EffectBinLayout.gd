extends RefCounted
## The `E###.BIN` ROM layout: every offset a section writer needs, in ONE place (#1326).
## Vault: [[Effect File Format]]
##
## Every table mirrors the identically-named constant in `tools/parse_effect.py` (the single
## shared ROM layout reader and writer import, so they cannot disagree about geometry).
## The GDScript writers import from here for the same reason; `EffectBinHeader.gd` holds the
## header half. The one representation change: Python's `None` absent-value sentinel becomes
## `NO_MAX_KF` (-1) — 0 is a real offset.
##
## No `class_name` (ADR-0004) — file_model members stay path-preloaded.

## `SCREEN_TRACK_OFFSETS["phase1"]["max_keyframe"]` when the watermark has no offset of its own
## and lives at the channel's own tail instead. Not 0 — 0 is a real channel-relative offset;
## confusing the two writes a watermark over the keyframe's bytes.
const NO_MAX_KF: int = -1

# --- record sizes (parse_effect: HEADER_SIZE … FRAMESET_HEADER_SIZE) ---------

const HEADER_SIZE: int = 0x28            ## 40 bytes
const PARTICLE_HEADER_SIZE: int = 0x14   ## 20 bytes, ahead of emitter 0
const EMITTER_SIZE: int = 0xC4           ## 196 bytes per emitter record
const FRAME_SIZE: int = 24
const FRAMESET_HEADER_SIZE: int = 4

# --- screen (parse_effect.SCREEN_TRACK_OFFSETS / MAX_SCREEN_KEYFRAMES) -------

## `phase1`/`phase2` watermarks sit at the channel's own tail (+298), not a table offset.
const SCREEN_TRACK_OFFSETS: Dictionary = {
	"for_each": {"data": 0x057E, "max_keyframe": 0x06A8},
	"phase1": {"data": 0x1036, "max_keyframe": NO_MAX_KF},
	"phase2": {"data": 0x13BA, "max_keyframe": NO_MAX_KF},
}
const MAX_SCREEN_KEYFRAMES: int = 33

## Field offsets within one screen channel (mirror `parse_screen_channel`).
const SCREEN_OFF_TIME: int = 0x00    ## + i*2, s16
const SCREEN_OFF_START: int = 0x42   ## + i*3, u8 R/G/B
const SCREEN_OFF_END: int = 0xA5     ## + i*3, u8 R/G/B
const SCREEN_OFF_CTRL: int = 0x108   ## + i,   u8
const SCREEN_OFF_MAX_KF_TAIL: int = 298  ## s16 at the channel tail (phase1/phase2)

# --- palette (parse_effect.PALETTE_TRACK_OFFSETS / _SIZE / MAX_) -------------

const PALETTE_TRACK_OFFSETS: Dictionary = {
	"for_each": {"affected_units": 0x0326, "caster": 0x03EE, "target": 0x04B6},
	"phase1": {"affected_units": 0x0DDE, "caster": 0x0EA6, "target": 0x0F6E},
	"phase2": {"affected_units": 0x1162, "caster": 0x122A, "target": 0x12F2},
}
const PALETTE_TRACK_SIZE: int = 198   ## the max_keyframe s16 sits here, channel-relative
const MAX_PALETTE_KEYFRAMES: int = 33

## Field offsets within one palette channel (mirror `parse_palette_channel`).
const PALETTE_OFF_TIME: int = 0x00   ## + i*2, s16
const PALETTE_OFF_RGB: int = 0x42    ## + i*3, u8 R/G/B
const PALETTE_OFF_CTRL: int = 0xA5   ## + i,   u8

# --- camera (parse_effect.CAMERA_TRACK_TABLES) ------------------------------

## All three camera tables base at `timeline_section_ptr` directly — NOT `+8` like the
## screen/palette `for_each` channels (see `parse_camera_keyframes`).
const CAMERA_TRACK_TABLES: Dictionary = {
	"phase1": {"end_frame": 0x14E6, "angle": 0x1510, "position": 0x158E,
		"zoom": 0x160C, "command": 0x168A, "max_keyframe": 0x16B4, "count": 21},
	"for_each": {"end_frame": 0x06B2, "angle": 0x06D4, "position": 0x073A,
		"zoom": 0x07A0, "command": 0x0806, "max_keyframe": 0x0828, "count": 17},
	"phase2": {"end_frame": 0x16B6, "angle": 0x16E0, "position": 0x175E,
		"zoom": 0x17DC, "command": 0x185A, "max_keyframe": 0x1884, "count": 21},
}

# --- timeline header (write_effect_timeline_header.OFF_*) -------------------

## The 12 bytes at `timeline_section_ptr` before the particle channels: six s16 slots, three
## authorable phase durations, three (`0x00`, `0x02`, `0x08`) read by the parser and ignored
## by the engine — non-zero across the corpus, so preserved verbatim, not written whole-struct.
const TIMELINE_HEADER_BYTES: int = 12
const TIMELINE_OFF_PHASE1_DURATION: int = 0x04
const TIMELINE_OFF_SPAWN_DELAY: int = 0x06
const TIMELINE_OFF_PHASE2_DELAY: int = 0x0A

# --- particle timeline (parse_effect.PARTICLE_*) ----------------------------

const PARTICLE_CHANNEL_SIZE: int = 128
const PARTICLE_SLOTS: int = 25

## `time[]` (25 s16 spanning 0x00..0x31) and `emitter_id[]` (from 0x31) physically share byte
## 0x31: `time[24]` is a phantom slot, `emitter_id[0]` is the semantic owner, so a byte-exact
## writer writes `time[]` BEFORE `emitter_id[]`.
const PARTICLE_OFF_TIME: int = 0x00          ## + i*2, s16
const PARTICLE_OFF_EMITTER_ID: int = 0x31    ## + i,   u8
const PARTICLE_OFF_ACTION_FLAGS: int = 0x4A  ## + i*2, u16
const PARTICLE_OFF_MAX_KEYFRAME: int = 0x7E  ## s16

const PARTICLE_FOR_EACH_OFFSETS: Array = [0x0004, 0x0084, 0x0104, 0x0184, 0x0204]
const PARTICLE_PHASE1_OFFSETS: Array = [0x082A, 0x08AA, 0x092A, 0x09AA, 0x0A2A]
const PARTICLE_PHASE2_OFFSETS: Array = [0x0AAA, 0x0B2A, 0x0BAA, 0x0C2A, 0x0CAA]
## The `for_each` bias is the whole timeline super-section's, not the particle lanes': every
## `for_each` channel — particle, screen AND palette — bases at `timeline_ptr + 8` while its
## `phase1`/`phase2` siblings base at `timeline_ptr`. The camera tables are the exception:
## none of the three is biased (`parse_camera_keyframes`). Named for the section, not the
## lane, because three subsystems read it.
const TIMELINE_FOR_EACH_BASE_BIAS: int = 8


## File offset of one particle channel from its context + lane index. Returns -1 for an
## unknown context or out-of-range lane; never 0, which is a real offset.
static func particle_channel_offset(timeline_ptr: int, context: String,
		channel_index: int) -> int:
	var table: Array
	var bias: int = 0
	match context:
		"for_each":
			table = PARTICLE_FOR_EACH_OFFSETS
			bias = TIMELINE_FOR_EACH_BASE_BIAS
		"phase1":
			table = PARTICLE_PHASE1_OFFSETS
		"phase2":
			table = PARTICLE_PHASE2_OFFSETS
		_:
			return -1
	if channel_index < 0 or channel_index >= table.size():
		return -1
	return timeline_ptr + bias + int(table[channel_index])

# --- sound timeline (parse_effect.SOUND_*) ----------------------------------

const SOUND_PHASE1_OFFSETS: Array = [0xD2A, 0xD48, 0xD66]          ## 0xD2A + i*30
const SOUND_PHASE2_OFFSETS: Array = [0xD84, 0xDA2, 0xDC0]          ## 0xD2A + 90 + i*30
const SOUND_ANIMATE_OFFSETS: Array = [0x284, 0x2BA, 0x2F0]         ## 0x284 + i*54
const SOUND_OUTER_SIZE: int = 30     ## bytes per outer channel
const SOUND_FOREACH_SIZE: int = 54   ## bytes per for-each channel
const SOUND_OUTER_KF: int = 9        ## keyframes per outer (phase1/phase2) 30-byte channel
const SOUND_FOREACH_KF: int = 17     ## keyframes per for_each 54-byte channel
const SOUND_OUTER_MAXKF_OFF: int = 28
const SOUND_FOREACH_MAXKF_OFF: int = 52

# --- time scale (write_effect_time_scale) -----------------------------------

const TIME_SCALE_REGION_FRAMES: int = 600
const TIME_SCALE_REGION_BYTES: int = 300     ## two 0..15 nibbles per byte
const TIME_SCALE_OFF_OUTER: int = 0x000
const TIME_SCALE_OFF_FOR_EACH: int = 300     ## 0x12C

# --- effect flags / sound containers (write_effect_flags / _containers) -----

const FLAGS_OFF: int = 0x00              ## the flags byte, effect_flags-relative
const CONTAINERS_OFFSET: int = 8         ## containers begin at effect_flags_ptr + 8
const CONTAINER_COUNT: int = 4
const CONTAINER_STRIDE: int = 4
const CONTAINER_FIELDS: Array = ["mode", "id_a", "id_b", "id_c"]

# --- texture (write_effect_texture.PLANE_OFFSET) ----------------------------

## Palette 1 (512 B) + palette 2 (512 B) + the 4-byte VRAM header — all of which the
## fixed-CLUT policy leaves untouched, so the writable plane starts after them.
const TEXTURE_PLANE_OFFSET: int = 0x404

## The two 512-byte CLUT blocks, section-relative. A frame selects between them with
## `uses_palette_2` (`flags_byte0 & 0x10`); each holds 256 BGR555 words, which is one 8bpp
## palette OR sixteen 4bpp sub-palettes of 16.
const TEXTURE_CLUT_1_OFFSET: int = 0x000
const TEXTURE_CLUT_2_OFFSET: int = 0x200
const TEXTURE_CLUT_BLOCK_BYTES: int = 0x200
const TEXTURE_CLUT_ENTRIES: int = 256        ## entries in one block — also the 8bpp palette size
const TEXTURE_SUB_PALETTE_ENTRIES: int = 16  ## a 4bpp sub-palette; `palette_id` selects which

## The 4-byte VRAM upload header, section-relative (`parse_effect.parse_texture_meta`):
## a u24 PIXEL DATA SIZE in bytes at +0x400, then a row-stride selector at +0x403
## (0 -> 128 bytes per row, non-0 -> 256). The size is a byte count, not a coordinate —
## measured, it equals the pixel plane's length exactly in all 401 non-empty corpus effects.
const TEXTURE_VRAM_HEADER_OFFSET: int = 0x400
const TEXTURE_STRIDE_FLAG_OFFSET: int = 0x403
const TEXTURE_ROW_BYTES_NARROW: int = 128
const TEXTURE_ROW_BYTES_WIDE: int = 256

## The upload X is fixed at 0x180; the Y is not encoded in the section at all.
const TEXTURE_VRAM_X: int = 0x180

# --- script / sound def / header relocation (effect_writer_registry) --------

## The stored-header offsets the four RESIZING sections name when they call
## `EffectBinWriter.relocate`. Same rule, four different shapes (ADR-0337):
## `SOUND_DEF_PTR_OFF` moves ONE pointer, `SCRIPT_PTR_OFF` six or seven,
## `ANIMATION_PTR_OFF` eight, and `FRAMES_PTR_OFF` — the first section in the file —
## moves all NINE of the others.
const FRAMES_PTR_OFF: int = 0x00
const ANIMATION_PTR_OFF: int = 0x04
const SCRIPT_PTR_OFF: int = 0x08
const SOUND_DEF_PTR_OFF: int = 0x20
const TEXTURE_PTR_OFF: int = 0x24

# --- the header's ten section pointers, for the RELOCATION contract ----------

## Stored offset -> the key `EffectBinHeader.parse_header` publishes it under. The order is
## the header's own and also the section order: measured over all 401 non-empty corpus
## effects, the non-zero stored pointers are non-decreasing by offset in every one. The
## relocation contract still compares VALUES rather than trusting that order.
const HEADER_POINTERS: Array = [
	[0x00, "frames_ptr"], [0x04, "animation_ptr"], [0x08, "script_data_ptr"],
	[0x0C, "effect_data_ptr"], [0x10, "anim_table_ptr"], [0x14, "time_scale_ptr"],
	[0x18, "effect_flags_ptr"], [0x1C, "timeline_section_ptr"],
	[0x20, "sound_def_ptr"], [0x24, "texture_ptr"],
]

## A stored `0` means the section is ABSENT, not "at the header base" — and it is not only
## `time_scale_ptr`: measured over the 401 non-empty corpus effects, `time_scale_ptr` is 0 in
## 270 and `effect_flags_ptr` in 2 (E509 and E510, which zero both). Anything deriving a
## section's extent must treat 0 as "not present", not an address — `calculate_sections`
## does, which is why E509's AnimCurves size comes out negative rather than plausible.
## `EffectBinWriter.relocate` needs no clause: its rule moves only stored pointers greater
## than the resized section's own, and no section begins at stored 0.
const PTR_ABSENT: int = 0
