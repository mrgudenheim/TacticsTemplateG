extends RefCounted
## EMITTER-BLOCK reader for `E###.BIN` (#1329) — GDScript port of
## `parse_effect.parse_emitter` / `parse_all_emitters` / `parse_particle_header`, the read
## mirror of `writers/EffectWriteEmitters.gd`.
## Vault: [[Particle Emitter Format]]
##
## The 20-byte particle-system header at `effect_data_ptr`, then `emitter_count` records of
## 196 bytes each. Biggest single section in the file and by far the widest leaf: one emitter
## carries 9 scalars, a 15-entry curve table, a 10-entry flag decode, 18 s16 vec3 triplets and
## five sub-dicts.
##
## 🔴 MOST OF THIS LEAF IS DERIVED, AND THAT IS WHERE REFEREE A EARNS ITS KEEP. Only the `raw`
## sub-dict and the u8 scalars are bytes as stored. `position`, `spread`, `velocity_base_angle`,
## `velocity_direction_spread`, `acceleration`, `drag`, `target_offset`, `radial_velocity`,
## `homing_strength` and the whole `curves` and `flags` dicts are COMPUTED — unit conversions,
## a Y-flip, nibble unpacking, and two DIFFERENT anchor-mode tables that map the same numeric
## range to different names. `EffectWriteEmitters` writes none of them (it writes `raw` and the
## sub-dicts whose values ARE the bytes), so referee B is blind to every one, and the only
## thing that can score them is `emitters.json`.
##
## 🔴 THE EXTRACT CANNOT BE COMPARED TO EXACTLY, AND THE READER IS THE ACCURATE SIDE. Every
## conversion here is one IEEE-754 double divide or multiply, so `raw / 114688.0` in GDScript
## is the same bit pattern Python computed. The LEAF is where the precision goes: Godot's
## decimal parser is not correctly rounded, and `JSON.parse_string` turns Python's
## `0.00017438616071428572` into a double 211 ulps away (relative 2.3e-14). So referee A
## compares floats with a tolerance — and then pins that tolerance with a measured ceiling, at
## 1e-12 against a corpus worst of 6.14e-14. Seeding a 1e-11 relative drift into the accel
## divisor (now `PsxMagnitude.ACCEL_DIVISOR`)
## produces ZERO field mismatches and reds the ceiling alone, which is the proof that the
## ceiling, not the tolerance, is the guard. See `EffectBinReadWriteCorpusTest`'s
## `FLOAT_NOISE_CEILING`.
##
## ⚠️ `lifetime`'s 65535 -> -1 IS NOT IN `parse_emitter`. `extract_effect` rewrites it after the
## fact ("animation-driven lifetime"), so a straight port of `parse_emitter` alone disagrees
## with `emitters.json` on every emitter that has one. The writer masks to 0xFFFF, so -1 and
## 65535 both round-trip — which is exactly why referee B cannot see this and referee A can.
##
## ABSENT IS `null`. `effect_data_ptr` out of bounds, or an `emitter_count` whose records would
## run past EOF. The Python guards neither (it would raise); measured over the corpus,
## `emitter_count` is 2..16 and no effect's records overrun, so the guard is defensive only.
##
## 🔴 ONE CLAIM HERE IS UNGUARDED. `ANCHOR_MODES` has seven names for a THREE-bit field, so
## index 7 falls through to "UNKNOWN" — and renaming that fallback is green across all 400
## effects, so no corpus emitter reaches it. `TARGET_ANCHOR_MODES` is the opposite: all eight
## of its inputs occur, which is why the Python's `UNKNOWN_%02X` fallback is not ported at all
## rather than ported and left unexercised.
##
## No `class_name` (ADR-0004) — file_model members stay path-preloaded.

const Layout = preload("res://addons/exmateria_effects/file_model/EffectBinLayout.gd")
const PsxMagnitude = ExMateriaPlatform.PsxMagnitude

# --- unit conversions --------------------------------------------------------
#
# 🔴 ROUTED THROUGH `PsxMagnitude`, NOT RE-DERIVED. ADR-0091 puts every raw-PSX magnitude
# conversion behind one seam, and it already carries all four of these by name —
# `tile_to_game` (/28), `radial_velocity_to_game` (/14336), `accel_to_game` (/114688) and
# `angle_to_rad` (TAU/4096) — with the effects divisors documented against
# `parse_effect.py`'s own constants. Writing them out here again passed the corpus and was
# caught by `check_no_raw_psx_units.py`, which is what that guard is for: the numbers were
# right and the SEAM was the point. Nine other files in this addon already reach it, and
# `exmateria_platform` is already in `plugin.cfg`'s `deps=`.
#
# The arithmetic is bit-identical either way — `raw * TAU / 4096` and `raw * (TAU / 4096)`
# agree because dividing by a power of two is exact — so referee A stays at 0 field
# mismatches across the corpus's ~13,000 emitters.

## `emitter_count` above this is taken as a mis-read rather than a real count. Measured max on
## the corpus is 16; the bound exists so a garbage header cannot make this loop for minutes.
const MAX_EMITTERS: int = 64

## `(anim_target >> 1) & 0x07` -> the emitter's anchor. Index 7 has no name, and that fallback
## is LIVE — unlike `TARGET_ANCHOR_MODES`, which covers all eight of its inputs.
const ANCHOR_MODES: Array = ["WORLD", "CURSOR", "ORIGIN", "TARGET", "PARENT", "CAMERA",
	"TRACKED"]

## 🔴 `motion_type & 0xE0` -> the TARGET anchor, and this table is NOT `ANCHOR_MODES`. The same
## ordinal means different things in the two: 0x40 is CAMERA here and ORIGIN there, 0x80 is
## TARGET here and PARENT there. Verified in the disassembly at 0x801a7ae8+. Indexed by
## `motion_type >> 5`, so all eight entries exist and the Python's `UNKNOWN_%02X` fallback is
## unreachable — which is why it is not ported.
const TARGET_ANCHOR_MODES: Array = ["WORLD", "WORLD", "CAMERA", "ORIGIN", "TARGET", "PARENT",
	"UNKNOWN_C0", "UNKNOWN_E0"]

## Which curve each nibble of the 8 `curve_indices_raw` bytes selects: name -> [byte, shift,
## mask]. Mirrors `parse_emitter`'s fifteen hand-written lines, INCLUDING that byte 2's high
## nibble and byte 6's low nibble are read by nothing, and that byte 7's top four bits are two
## TWO-bit fields rather than one nibble.
const CURVE_NIBBLES: Dictionary = {
	"position": [0, 0, 0x0F], "spread": [0, 4, 0x0F],
	"velocity_base_angle": [1, 0, 0x0F], "velocity_dir_spread": [1, 4, 0x0F],
	"inertia": [2, 0, 0x0F],
	"weight": [3, 0, 0x0F], "radial_velocity": [3, 4, 0x0F],
	"acceleration": [4, 0, 0x0F], "drag": [4, 4, 0x0F],
	"lifetime": [5, 0, 0x0F], "target_offset": [5, 4, 0x0F],
	"particle_count": [6, 4, 0x0F],
	"spawn_interval": [7, 0, 0x0F], "homing_strength": [7, 4, 0x03],
	"homing_blend": [7, 6, 0x03],
}

## The s16 vec3 triplets of the `raw` sub-dict: key -> the three byte offsets. The position
## family is contiguous; accel and drag INTERLEAVE min and max per component, which is why
## these are offset LISTS and not a base plus a stride.
const RAW_VEC3: Dictionary = {
	"position_start": [0x14, 0x16, 0x18], "position_end": [0x1A, 0x1C, 0x1E],
	"spread_start": [0x20, 0x22, 0x24], "spread_end": [0x26, 0x28, 0x2A],
	"angle_start": [0x2C, 0x2E, 0x30], "angle_end": [0x32, 0x34, 0x36],
	"vel_spread_start": [0x38, 0x3A, 0x3C], "vel_spread_end": [0x3E, 0x40, 0x42],
	"accel_min_start": [0x64, 0x68, 0x6C], "accel_max_start": [0x66, 0x6A, 0x6E],
	"accel_min_end": [0x70, 0x74, 0x78], "accel_max_end": [0x72, 0x76, 0x7A],
	"drag_min_start": [0x7C, 0x80, 0x84], "drag_max_start": [0x7E, 0x82, 0x86],
	"drag_min_end": [0x88, 0x8C, 0x90], "drag_max_end": [0x8A, 0x8E, 0x92],
	"target_start": [0x9C, 0x9E, 0xA0], "target_end": [0xA2, 0xA4, 0xA6],
}

## The s16 scalars of the `raw` sub-dict.
const RAW_S16: Dictionary = {
	"radial_min_start": 0x5C, "radial_max_start": 0x5E,
	"radial_min_end": 0x60, "radial_max_end": 0x62,
	"homing_min_start": 0xB8, "homing_max_start": 0xBA,
	"homing_min_end": 0xBC, "homing_max_end": 0xBE,
}

## Top-level u8 scalars: key -> offset.
const U8_FIELDS: Dictionary = {
	"byte_00": 0x00, "anim_index": 0x01, "motion_type_flag": 0x02,
	"animation_target_flag": 0x03, "anim_param": 0x04, "byte_05": 0x05,
	"emitter_flags_lo": 0x06, "emitter_flags_hi": 0x07,
	"child_emitter_on_death": 0xC0, "child_emitter_mid_life": 0xC1,
}

## `lifetime` values at or above this read as -1 — "die when the animation completes".
const LIFETIME_ANIMATION_DRIVEN: int = 65535


# --- conversions -------------------------------------------------------------

## FFT position -> Godot units, Y NEGATED (FFT is -Y up). The seam converts a MAGNITUDE; the
## flip is chirality and stays the caller's, exactly as `PsxMagnitude.tile_to_game` says.
static func convert_position(xyz: Array) -> Array:
	return [PsxMagnitude.tile_to_game(xyz[0]), PsxMagnitude.tile_to_game(-int(xyz[1])),
		PsxMagnitude.tile_to_game(xyz[2])]


## FFT acceleration / drag / gravity -> Godot units, Y NEGATED. Same shape as
## `convert_position` on a different divisor; `parse_effect` keeps `convert_gravity` as a
## separate name for the same body.
static func convert_accel(xyz: Array) -> Array:
	return [PsxMagnitude.accel_to_game(xyz[0]), PsxMagnitude.accel_to_game(-int(xyz[1])),
		PsxMagnitude.accel_to_game(xyz[2])]


## FFT angle triplet (0..4096 is a full turn) -> radians. No Y flip — these are angles.
static func convert_angles(xyz: Array) -> Array:
	return [PsxMagnitude.angle_to_rad(xyz[0]), PsxMagnitude.angle_to_rad(xyz[1]),
		PsxMagnitude.angle_to_rad(xyz[2])]


# --- derived view: the 20-byte particle-system header -------------------------

## `particle_header.json`'s shape, or `null` when out of bounds.
##
## A DERIVED VIEW, NOT A REGISTRY SECTION — `EffectWriteEmitters` calls it "display-only" and
## never writes it, so registering it would make `EffectBinWriter.patch_all` refuse the
## section. It is read here rather than anywhere else because `emitter_count` lives in it and
## nothing else can say how many records follow.
static func particle_header(buf: PackedByteArray, header: Dictionary):
	var base: int = int(header.get("effect_data_ptr", 0))
	if base <= 0 or base + Layout.PARTICLE_HEADER_SIZE > buf.size():
		return null
	var raw: Array = [buf.decode_s32(base + 0x04), buf.decode_s32(base + 0x08),
		buf.decode_s32(base + 0x0C)]
	return {
		"constant": buf.decode_u16(base + 0x00),
		"emitter_count": buf.decode_u16(base + 0x02),
		"gravity": convert_accel(raw),
		"gravity_raw": raw,
		"inertia_threshold": buf.decode_u32(base + 0x10),
	}


# --- the section --------------------------------------------------------------

## The record base of emitter `index` (mirror `parse_all_emitters`).
static func emitter_offset(effect_data_ptr: int, index: int) -> int:
	return effect_data_ptr + Layout.PARTICLE_HEADER_SIZE + index * Layout.EMITTER_SIZE


## Every emitter record — `emitters.json`'s shape — or `null` when the particle header is
## absent, its `emitter_count` is implausible, or the records would run past EOF.
static func parse(buf: PackedByteArray, header: Dictionary):
	var ph = particle_header(buf, header)
	if ph == null:
		return null
	var count: int = int(ph["emitter_count"])
	if count < 0 or count > MAX_EMITTERS:
		return null
	var base: int = int(header["effect_data_ptr"])
	if emitter_offset(base, count) > buf.size():
		return null
	var out: Array = []
	for i in range(count):
		out.append(parse_emitter(buf, emitter_offset(base, i), i))
	return out


## One 196-byte emitter record at `offset`.
static func parse_emitter(buf: PackedByteArray, offset: int, index: int) -> Dictionary:
	var curve_bytes: Array = []
	for i in range(8):
		curve_bytes.append(buf[offset + 0x08 + i])

	var raw: Dictionary = {}
	for key in RAW_VEC3:
		var offs: Array = RAW_VEC3[key]
		raw[key] = [buf.decode_s16(offset + int(offs[0])),
			buf.decode_s16(offset + int(offs[1])), buf.decode_s16(offset + int(offs[2]))]
	for key in RAW_S16:
		raw[key] = buf.decode_s16(offset + int(RAW_S16[key]))

	var em: Dictionary = {
		"index": index,
		"file_offset": offset,
		"curve_indices_raw": curve_bytes,
		"curves": _curves(curve_bytes),
		"color_curves": {
			"r": buf[offset + 0x10] & 0x0F,
			"g": (buf[offset + 0x10] >> 4) & 0x0F,
			"b": buf[offset + 0x11] & 0x0F,
		},
		"position": {"start": convert_position(raw["position_start"]),
			"end": convert_position(raw["position_end"])},
		"spread": {"start": convert_position(raw["spread_start"]),
			"end": convert_position(raw["spread_end"])},
		"velocity_base_angle": {"start": convert_angles(raw["angle_start"]),
			"end": convert_angles(raw["angle_end"])},
		"velocity_direction_spread": {"start": convert_angles(raw["vel_spread_start"]),
			"end": convert_angles(raw["vel_spread_end"])},
		# Inertia and weight stay RAW: both are used directly in a fixed-point formula
		# (`new_vel = ((inertia - threshold) * old_vel + accel * 4096) / inertia`), so a
		# converted value would have to be converted back before it meant anything.
		"inertia": {
			"min_start": buf.decode_s16(offset + 0x44), "max_start": buf.decode_s16(offset + 0x46),
			"min_end": buf.decode_s16(offset + 0x48), "max_end": buf.decode_s16(offset + 0x4A),
		},
		"weight": {
			"min_start": buf.decode_s16(offset + 0x54), "max_start": buf.decode_s16(offset + 0x56),
			"min_end": buf.decode_s16(offset + 0x58), "max_end": buf.decode_s16(offset + 0x5A),
		},
		"radial_velocity": {
			"min_start": PsxMagnitude.radial_velocity_to_game(raw["radial_min_start"]),
			"max_start": PsxMagnitude.radial_velocity_to_game(raw["radial_max_start"]),
			"min_end": PsxMagnitude.radial_velocity_to_game(raw["radial_min_end"]),
			"max_end": PsxMagnitude.radial_velocity_to_game(raw["radial_max_end"]),
		},
		"acceleration": {
			"min_start": convert_accel(raw["accel_min_start"]),
			"max_start": convert_accel(raw["accel_max_start"]),
			"min_end": convert_accel(raw["accel_min_end"]),
			"max_end": convert_accel(raw["accel_max_end"]),
		},
		"drag": {
			"min_start": convert_accel(raw["drag_min_start"]),
			"max_start": convert_accel(raw["drag_max_start"]),
			"min_end": convert_accel(raw["drag_min_end"]),
			"max_end": convert_accel(raw["drag_max_end"]),
		},
		"lifetime": _lifetime(buf, offset),
		"target_offset": {"start": convert_position(raw["target_start"]),
			"end": convert_position(raw["target_end"])},
		"spawn": {
			"particle_count_start": buf.decode_u16(offset + 0xB0),
			"particle_count_end": buf.decode_u16(offset + 0xB2),
			"interval_start": buf.decode_u16(offset + 0xB4),
			"interval_end": buf.decode_u16(offset + 0xB6),
		},
		"homing_strength": {
			"min_start": PsxMagnitude.accel_to_game(raw["homing_min_start"]),
			"max_start": PsxMagnitude.accel_to_game(raw["homing_max_start"]),
			"min_end": PsxMagnitude.accel_to_game(raw["homing_min_end"]),
			"max_end": PsxMagnitude.accel_to_game(raw["homing_max_end"]),
		},
		"callback_params": {
			"param_4C": buf[offset + 0x4C],
			"param_4E": buf[offset + 0x4E],
			"param_A8": buf.decode_s16(offset + 0xA8),
			"param_AA": buf.decode_s16(offset + 0xAA),
			"param_AC": buf.decode_s16(offset + 0xAC),
			"param_AE": buf.decode_s16(offset + 0xAE),
		},
		"raw": raw,
	}
	for key in U8_FIELDS:
		em[key] = buf[offset + int(U8_FIELDS[key])]
	em["flags"] = _flags(em)
	return em


## `0` means NO CURVE and reads as -1; `N` means curve `N - 1`. Mirrors `decode_curve_index`.
static func decode_curve_index(raw: int) -> int:
	return raw - 1 if raw > 0 else -1


static func _curves(curve_bytes: Array) -> Dictionary:
	var out: Dictionary = {}
	for name in CURVE_NIBBLES:
		var spec: Array = CURVE_NIBBLES[name]
		out[name] = decode_curve_index((int(curve_bytes[int(spec[0])]) >> int(spec[1]))
			& int(spec[2]))
	return out


## The four lifetime halfwords, with 65535 folded to -1 the way `extract_effect` does AFTER
## `parse_emitter` returns. Not part of the Python's parser, but part of `emitters.json`.
static func _lifetime(buf: PackedByteArray, offset: int) -> Dictionary:
	var out: Dictionary = {}
	var offsets: Dictionary = {"min_start": 0x94, "max_start": 0x96,
		"min_end": 0x98, "max_end": 0x9A}
	for key in offsets:
		var v: int = buf.decode_u16(offset + int(offsets[key]))
		out[key] = -1 if v >= LIFETIME_ANIMATION_DRIVEN else v
	return out


static func _flags(em: Dictionary) -> Dictionary:
	var motion_type: int = int(em["motion_type_flag"])
	var anim_target: int = int(em["animation_target_flag"])
	var flags_lo: int = int(em["emitter_flags_lo"])
	var flags_hi: int = int(em["emitter_flags_hi"])
	var anchor: int = (anim_target >> 1) & 0x07
	return {
		"align_to_velocity": (motion_type & 0x02) != 0,
		"target_anchor_mode": TARGET_ANCHOR_MODES[(motion_type & 0xE0) >> 5],
		"spread_mode": "BOX" if (anim_target & 0x01) else "SPHERICAL",
		"emitter_anchor_mode": ANCHOR_MODES[anchor] if anchor < ANCHOR_MODES.size() else "UNKNOWN",
		"color_curve_enabled": (flags_lo & 0x40) != 0,
		"velocity_inward": (flags_lo & 0x10) != 0,
		"child_death_enabled": (flags_lo & 0x03) != 0,
		"child_midlife_enabled": (flags_lo & 0x0C) != 0,
		"align_to_facing": (flags_hi & 0x04) != 0,
		"homing_arrival_threshold": flags_hi & 0x03,
	}
