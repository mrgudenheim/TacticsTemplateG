extends RefCounted
## Byte-exact EMITTER-BLOCK writer for `E###.BIN` (ADR-0089) — GDScript port of
## `tools/write_effect_emitters.py`.
##
## The 196-byte emitter records after the particle-system header at `effect_data_ptr`.
##
## A PARTIAL PATCH AT TWO GRAINS:
##   * per DICT KEY — an absent key leaves its bytes untouched (the saver may emit sparse
##     dicts; an older `emitters.json` may lack newer keys);
##   * per BYTE — bytes the parser does not surface are NEVER written: `unknown_12`/`13`, the
##     unparsed halves at `0x4D`/`0x50-0x53`, the HIGH nibble of `0x11`, `reserved_C2/C3`;
##     reserved-but-parsed bytes (`byte_00`, `byte_05`) round-trip through their own keys.
##
## The particle header itself (count/gravity) stays display-only and is never written.
##
## All 16-bit fields are written UNSIGNED-masked: signedness is interpretation, not bytes, so
## both encodings of the same halfword round-trip (e.g. a lifetime of `0xFFFF` reads as 65535
## from the current u16 reader but as the -1 animation-driven sentinel in older JSON).
##
## THE CONVERTED VIEWS ARE NOT AN EDIT SURFACE. `EffectReadEmitters` publishes nine fields
## twice: once as PSX integers under `raw`, once as Godot-unit floats beside it
## (`position`, `spread`, `velocity_base_angle`, `velocity_direction_spread`, `acceleration`,
## `drag`, `target_offset`, `radial_velocity`, `homing_strength`). ONLY `raw` is serialized,
## so
##
##     em["position"]["start"] = [0.0, 2.0, 0.0]      # saves NOTHING
##     em["raw"]["position_start"] = [0, -56, 0]      # saves
##
## and the first is silent in the worst possible way: the byte round-trip stays perfect,
## because a no-op patch returns the base bytes unchanged.
##
## `converted_drift()` asks the inverse question instead: every converted view is mapped back
## to PSX integers through `PsxMagnitude` and compared to the `raw` it claims to describe, and
## `patch_into` REFUSES a block where the two DISAGREE, with the field named. One dict cannot
## tell "the view was edited" apart from "the raw was edited" — a block whose view and raw
## disagree is ambiguous about what the author meant, and the fix is one line at the call
## site: update the view, or drop it (an absent view is never drift — sparse blocks are
## supported, and the studio's own `EffectEmitterSaver` emits `raw` with no views at all, so
## this never fires on the production save path).
##
## Comparison happens in INTEGER space on purpose: after a JSON round-trip the two floats
## differ by parse noise alone, and an epsilon that absorbed it would swallow a one-unit
## acceleration edit, which is 1/114688. Integer comparison has neither problem — noise rounds
## to the same integer, a real edit does not.

const Layout = preload("res://addons/exmateria_effects/file_model/EffectBinLayout.gd")
const PsxMagnitude = ExMateriaPlatform.PsxMagnitude

## Top-level u8 keys (offsets within one 196-byte record; mirror `parse_emitter`).
const U8_FIELDS: Dictionary = {
	"byte_00": 0x00, "anim_index": 0x01, "motion_type_flag": 0x02,
	"animation_target_flag": 0x03, "anim_param": 0x04, "byte_05": 0x05,
	"emitter_flags_lo": 0x06, "emitter_flags_hi": 0x07,
	"child_emitter_on_death": 0xC0, "child_emitter_mid_life": 0xC1,
}

## `raw` sub-dict: s16 vec3 triplets — key -> [x, y, z] offsets. Contiguous for the
## position family; min/max INTERLEAVED per component for accel/drag.
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

## `raw` sub-dict: s16 scalars.
const RAW_S16: Dictionary = {
	"radial_min_start": 0x5C, "radial_max_start": 0x5E,
	"radial_min_end": 0x60, "radial_max_end": 0x62,
	"homing_min_start": 0xB8, "homing_max_start": 0xBA,
	"homing_min_end": 0xBC, "homing_max_end": 0xBE,
}

## Named sub-dicts whose values ARE the raw bytes: dict key -> {value key: [offset, width]}.
## Width 1 is a u8; width 2 is a halfword (always written unsigned-masked — see the note above).
const DICT_FIELDS: Dictionary = {
	"inertia": {"min_start": [0x44, 2], "max_start": [0x46, 2],
		"min_end": [0x48, 2], "max_end": [0x4A, 2]},
	"weight": {"min_start": [0x54, 2], "max_start": [0x56, 2],
		"min_end": [0x58, 2], "max_end": [0x5A, 2]},
	"lifetime": {"min_start": [0x94, 2], "max_start": [0x96, 2],
		"min_end": [0x98, 2], "max_end": [0x9A, 2]},
	"spawn": {"particle_count_start": [0xB0, 2], "particle_count_end": [0xB2, 2],
		"interval_start": [0xB4, 2], "interval_end": [0xB6, 2]},
	"callback_params": {"param_4C": [0x4C, 1], "param_4E": [0x4E, 1],
		"param_A8": [0xA8, 2], "param_AA": [0xAA, 2],
		"param_AC": [0xAC, 2], "param_AE": [0xAE, 2]},
}


## The converted VIEWS this writer does not serialize: view key -> {slot key -> raw key}, plus
## the `scale` that maps the view back to PSX integers. Mirrors `EffectReadEmitters`' forward
## direction exactly, including which conversions flip Y (chirality belongs to positions and
## accelerations, not to angles).
##
##   tile   `raw / 28`            position, spread, target_offset          Y flipped
##   accel  `raw / 114688`        acceleration, drag (vec3), homing (s16)  Y flipped (vec3 only)
##   angle  `raw * TAU / 4096`    velocity_base_angle, velocity_dir_spread
##   radial `raw / 14336`         radial_velocity (s16)
const CONVERTED_VIEWS: Dictionary = {
	"position": {"scale": "tile", "vec3": true,
		"slots": {"start": "position_start", "end": "position_end"}},
	"spread": {"scale": "tile", "vec3": true,
		"slots": {"start": "spread_start", "end": "spread_end"}},
	"target_offset": {"scale": "tile", "vec3": true,
		"slots": {"start": "target_start", "end": "target_end"}},
	"velocity_base_angle": {"scale": "angle", "vec3": true,
		"slots": {"start": "angle_start", "end": "angle_end"}},
	"velocity_direction_spread": {"scale": "angle", "vec3": true,
		"slots": {"start": "vel_spread_start", "end": "vel_spread_end"}},
	"acceleration": {"scale": "accel", "vec3": true,
		"slots": {"min_start": "accel_min_start", "max_start": "accel_max_start",
			"min_end": "accel_min_end", "max_end": "accel_max_end"}},
	"drag": {"scale": "accel", "vec3": true,
		"slots": {"min_start": "drag_min_start", "max_start": "drag_max_start",
			"min_end": "drag_min_end", "max_end": "drag_max_end"}},
	"radial_velocity": {"scale": "radial", "vec3": false,
		"slots": {"min_start": "radial_min_start", "max_start": "radial_max_start",
			"min_end": "radial_min_end", "max_end": "radial_max_end"}},
	"homing_strength": {"scale": "accel", "vec3": false,
		"slots": {"min_start": "homing_min_start", "max_start": "homing_max_start",
			"min_end": "homing_min_end", "max_end": "homing_max_end"}},
}


## One converted scalar, mapped back to the PSX integer it was read from. `flip_y` is the
## chirality the reader applied on the Y component of a position/acceleration triple.
static func _to_raw(value: float, scale: String, flip_y: bool) -> int:
	var v: float = -value if flip_y else value
	match scale:
		"tile": return int(round(PsxMagnitude.game_to_tile(v)))
		"accel": return int(round(PsxMagnitude.game_to_accel(v)))
		"angle": return int(round(PsxMagnitude.rad_to_angle(v)))
		"radial": return int(round(PsxMagnitude.game_to_radial_velocity(v)))
	return 0


## Every converted view of `em` that DISAGREES with the `raw` it is derived from — i.e. every
## edit this writer would silently drop; field paths like `position.start[1]`, empty when the
## dict is consistent. An absent view, slot or `raw` counterpart is NOT drift (sparse dicts
## are explicitly supported); only a view that is present and disagrees is reported.
static func converted_drift(em: Dictionary) -> Array:
	var raw = em.get("raw")
	if not (raw is Dictionary):
		return []
	var drift: Array = []
	for view_key in CONVERTED_VIEWS:
		var view = em.get(view_key)
		if not (view is Dictionary):
			continue
		var spec: Dictionary = CONVERTED_VIEWS[view_key]
		var scale: String = str(spec["scale"])
		var is_vec3: bool = bool(spec["vec3"])
		var slots: Dictionary = spec["slots"]
		for slot_key in slots:
			if not view.has(slot_key):
				continue
			var raw_key: String = str(slots[slot_key])
			if not raw.has(raw_key):
				continue
			var got = view[slot_key]
			var want = raw[raw_key]
			if is_vec3:
				if not (got is Array and want is Array and got.size() >= 3 and want.size() >= 3):
					continue
				for i in range(3):
					# Only positions and accelerations flip Y; angles do not.
					var flip: bool = i == 1 and scale != "angle"
					if _to_raw(float(got[i]), scale, flip) != int(want[i]):
						drift.append("%s.%s[%d] = %s, but raw.%s[%d] = %d"
							% [view_key, slot_key, i, str(got[i]), raw_key, i, int(want[i])])
			elif _to_raw(float(got), scale, false) != int(want):
				drift.append("%s.%s = %s, but raw.%s = %d"
					% [view_key, slot_key, str(got), raw_key, int(want)])
	return drift


## The record base of emitter `index` (mirror `parse_all_emitters`).
static func emitter_offset(effect_data_ptr: int, index: int) -> int:
	return effect_data_ptr + Layout.PARTICLE_HEADER_SIZE + index * Layout.EMITTER_SIZE


static func _put(buf: PackedByteArray, offset: int, width: int, value) -> void:
	if width == 1:
		buf[offset] = int(value) & 0xFF
	else:
		buf.encode_u16(offset, int(value) & 0xFFFF)


## Partial-patch ONE emitter record at `base` from the keys present in `em`.
static func serialize_emitter(buf: PackedByteArray, base: int, em: Dictionary) -> void:
	for key in U8_FIELDS:
		if em.has(key):
			_put(buf, base + int(U8_FIELDS[key]), 1, em[key])

	var ci = em.get("curve_indices_raw")
	if ci is Array:
		for i in range(mini(8, ci.size())):
			_put(buf, base + 0x08 + i, 1, ci[i])

	var cc = em.get("color_curves")
	if cc is Dictionary:
		# Nibble-patch: r/g pack byte 0x10; b is the LOW nibble of 0x11 — the HIGH nibble
		# there is unparsed and is preserved from the base.
		if cc.has("r") or cc.has("g"):
			var cur: int = buf[base + 0x10]
			var r: int = int(cc.get("r", cur & 0x0F)) & 0x0F
			var g: int = int(cc.get("g", (cur >> 4) & 0x0F)) & 0x0F
			buf[base + 0x10] = r | (g << 4)
		if cc.has("b"):
			buf[base + 0x11] = (buf[base + 0x11] & 0xF0) | (int(cc["b"]) & 0x0F)

	var raw = em.get("raw", {})
	if raw is Dictionary:
		for key in RAW_VEC3:
			if not raw.has(key):
				continue
			var vec: Array = raw[key]
			var offs: Array = RAW_VEC3[key]
			for comp in range(3):
				_put(buf, base + int(offs[comp]), 2, vec[comp])
		for key in RAW_S16:
			if raw.has(key):
				_put(buf, base + int(RAW_S16[key]), 2, raw[key])

	for dict_key in DICT_FIELDS:
		var sub = em.get(dict_key)
		if not (sub is Dictionary):
			continue
		var spec: Dictionary = DICT_FIELDS[dict_key]
		for value_key in spec:
			if not sub.has(value_key):
				continue
			var where: Array = spec[value_key]
			_put(buf, base + int(where[0]), int(where[1]), sub[value_key])


## Partial-patch every emitter record IN PLACE, addressed by each dict's own `index` (the same
## stride math as `parse_all_emitters`), so a sparse edit set may name any subset. REFUSES
## before writing ANY emitter if any carries a converted view that disagrees with its `raw` —
## see `converted_drift`; its own pass first, so a refusal leaves the buffer untouched.
static func patch_into(buf: PackedByteArray, header: Dictionary, block) -> String:
	if not (block is Array):
		return ""
	var effect_data_ptr: int = int(header["effect_data_ptr"])
	for em in block:
		if not (em is Dictionary):
			continue
		var drift: Array = converted_drift(em)
		if not drift.is_empty():
			return ("emitters: emitter %s carries a CONVERTED view that disagrees with its "
				% str(em.get("index", "?"))
				+ "`raw` — only `raw` is serialized, so writing this block would drop one of "
				+ "the two silently (the bytes would still round-trip). Update the view or "
				+ "drop it. %d disagreement(s), first: %s" % [drift.size(), str(drift[0])])
	for em in block:
		if not (em is Dictionary) or not em.has("index"):
			continue
		serialize_emitter(buf, emitter_offset(effect_data_ptr, int(em["index"])), em)
	return ""
