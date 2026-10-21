extends RefCounted
## The ANIMATION-CURVE compiler and writer for `E###.BIN` (#274) — the last section with no
## write path in any language, and 2,400 bytes of every effect.
## Vault: [[Particle Curve Indices]]
##
## `patch_into` writes a 15-slot table into the
## BIN, which is a count word and 15×160 raw u8 samples — the byte packing was never the hard
## part. `compile` is the hard part: ADR-0089's curve-ownership amendment EXPLODES the ROM's
## shared table at load so every use site — an `(emitter, slot)` pair — owns a private curve,
## and an effect's `curves.json` grows from 15 entries to ~22. Something has to pack that back
## into at most 15 shared slots and repoint every emitter's index nibbles. That is this.
##
## THE SECTION NEVER RESIZES, WHICH IS WHY THIS NEEDED NO EMULATOR. Measured over all 401
## corpus effects: exactly 15 curves, a 2,404-byte section, zero slack, in every one. And 15 is
## not a convention — an emitter's curve index is a NIBBLE (`0` = none, `1..15` = curve `0..14`,
## `parse_effect.decode_curve_index`), so the table structurally cannot grow.
##
## THE ORACLE IS `explode -> compile` AND IT IS AN IDENTITY. The explode already carries both
## halves the compiler needs — PROVENANCE (`EffectCurve.index`, the slot a private copy came
## from) and RESIDUE (slots nothing references) — and `CurveExplode.gd` says in its own
## docstring that nothing read them yet. Reading them makes the round-trip exact: exploding the
## ROM's own table and compiling it back reproduces **the table byte-for-byte AND every
## emitter's index nibbles, on 399 of 401 effects** (E509 and E510 have no curves at all, and
## are named rather than counted). No emulator, no golden file, no RAM channel.
##
## PROVENANCE FIRST, DEDUP SECOND — AND THE ORDER IS THE WHOLE RULE, MEASURED. Dropping
## provenance and deduping by value alone takes that 399 to **34**: 276 of the 401 shipped
## tables contain DUPLICATE curve values, so the ROM's own tool did not dedup, and a compiler
## that does would rewrite three quarters of the corpus. ADR-0089 predicted exactly this
## ("fidelity resting on a rule, not on an optimization happening to be order-stable").
##
## THE DEDUP FALLBACK IS LIVE AND THE CORPUS SCORES IT AT NOTHING. Disabling it entirely
## leaves the corpus arm green on all 399, because provenance already places every referenced
## curve at its origin slot and a second referrer of the same slot matches by value there. It
## is kept for the case the corpus cannot contain — an AUTHORED curve, whose provenance slot is
## taken by a different shape — and it is what keeps a painted effect under the 15-slot cap.
## `_test_the_dedup_fallback_shares_a_slot_between_two_painted_sites` is its only referee; do
## not read the corpus arm as covering it.
##
## No `class_name` (ADR-0004) — file_model members stay path-preloaded.

## Bytes per curve, and the count word ahead of them. Mirrors `EffectReadCurves`.
const CURVE_LENGTH: int = 160
const COUNT_BYTES: int = 4

## The most slots an emitter's index nibble can address: `0` means none, so `1..15` is the
## whole range and curve 14 is the last one anything can point at.
const MAX_SLOTS: int = 15

## Param slot -> `[byte, shift, mask]` inside the 8 index bytes at emitter `+0x08`, the exact
## inverse of `parse_effect.parse_emitter`'s read. Two nibbles in that block are read by NOTHING
## (`byte 2`'s high nibble and `byte 6`'s low nibble) and are preserved verbatim rather than
## zeroed. `homing_strength` and `homing_blend` are TWO-BIT fields sharing byte 7's high nibble,
## so they can only address curves 0..2 — a real constraint, not a transcription slip.
const PARAM_NIBBLES: Dictionary = {
	"position": [0, 0, 0x0F], "spread": [0, 4, 0x0F],
	"velocity_base_angle": [1, 0, 0x0F], "velocity_dir_spread": [1, 4, 0x0F],
	"inertia": [2, 0, 0x0F], "weight": [3, 0, 0x0F],
	"radial_velocity": [3, 4, 0x0F], "acceleration": [4, 0, 0x0F],
	"drag": [4, 4, 0x0F], "lifetime": [5, 0, 0x0F],
	"target_offset": [5, 4, 0x0F], "particle_count": [6, 4, 0x0F],
	"spawn_interval": [7, 0, 0x0F], "homing_strength": [7, 4, 0x03],
	"homing_blend": [7, 6, 0x03],
}

## The colour slots, in `CurveExplode`'s own walk order.
const COLOUR_SLOTS: Array = ["r", "g", "b"]


## Pack the exploded private curves back into `slot_count` shared slots.
##
## `private` is `[{prov: int, values: Array}]` — one entry per use site, `prov` the slot it came
## from or -1 for a curve minted in the studio. `sites` is `CurveExplode.use_sites`'s shape,
## whose `priv` indexes `private`. `residue` is `[{index, values}]`, the slots nothing
## references, which are carried back to their original indices.
##
## Returns `{ok, table: Array, indices: Array, error}`. `indices[i]` is the slot `sites[i]`
## should now point at, or -1 for a site that had no curve.
##
## REFUSAL IS THE POINT OF THE CAP. A table full of distinct
## shapes with another one still to place cannot be expressed in a 4-bit index, so the save is
## refused BY NAME. Silently dropping the fifteenth-and-first curve would leave an effect whose
## emitters point at a shape that is not there.
static func compile(private: Array, sites: Array, residue: Array,
		slot_count: int = MAX_SLOTS) -> Dictionary:
	if slot_count <= 0 or slot_count > MAX_SLOTS:
		return {"ok": false, "table": [], "indices": [],
			"error": ("curves: %d slots is outside the 1..%d an emitter's index nibble can "
				+ "address") % [slot_count, MAX_SLOTS]}

	var table: Array = []
	table.resize(slot_count)
	for r in residue:
		if not (r is Dictionary):
			continue
		var at: int = int(r.get("index", -1))
		if at >= 0 and at < slot_count:
			table[at] = _as_bytes(r.get("values", []))

	var indices: Array = []
	for s in sites:
		var priv: int = int(s.get("priv", -1)) if s is Dictionary else -1
		if priv < 0 or priv >= private.size():
			indices.append(-1)
			continue
		var curve: Dictionary = private[priv]
		var values: PackedByteArray = _as_bytes(curve.get("values", []))
		var prov: int = int(curve.get("prov", -1))
		var placed: int = -1

		# 1. PROVENANCE. The slot this curve came from, when it is free or already holds
		#    exactly this shape. This is what makes an untouched effect round-trip, duplicate
		#    slots and all.
		if prov >= 0 and prov < slot_count and (table[prov] == null or table[prov] == values):
			table[prov] = values
			placed = prov

		# 2. DEDUP. Some slot already holds this shape. See the header: the corpus scores this
		#    clause at nothing, and it is the authored case that needs it.
		if placed < 0:
			for j in range(slot_count):
				if table[j] != null and table[j] == values:
					placed = j
					break

		# 3. A FREE SLOT.
		if placed < 0:
			for j in range(slot_count):
				if table[j] == null:
					table[j] = values
					placed = j
					break

		if placed < 0:
			return {"ok": false, "table": [], "indices": [],
				"error": ("curves: more than %d distinct curve shapes are in use, and an "
					+ "emitter's index nibble cannot address a %dth") % [slot_count, slot_count + 1]}
		indices.append(placed)

	# A slot nothing claimed is the identity curve, which is what an unreferenced ROM slot
	# mostly already is (71.9% of them are all-zero — `CurveExplode`'s own census).
	for j in range(slot_count):
		if table[j] == null:
			var blank: PackedByteArray = PackedByteArray()
			blank.resize(CURVE_LENGTH)
			table[j] = blank
	return {"ok": true, "table": table, "indices": indices, "error": ""}


## Write the compiled `indices` back into the EMITTER blocks — `curve_indices_raw` for the
## fifteen params, `color_curves` for r/g/b — so `EffectWriteEmitters` lands them.
##
## THE TWO CONVENTIONS DIFFER AND THE DIFFERENCE IS MEASURED, NOT ASSUMED. A param nibble
## stores `index + 1` because 0 means "no curve"; a COLOUR nibble stores the index DIRECTLY,
## with no such sentinel. Encoding colours the param way leaves the curve TABLE byte-identical
## and reds the index arm on **all 399** effects — which is exactly why the arm checks the
## emitter bytes and not only the table.
static func repack_indices(emitters: Array, sites: Array, indices: Array) -> void:
	for i in range(mini(sites.size(), indices.size())):
		var site = sites[i]
		if not (site is Dictionary):
			continue
		var e: int = int(site.get("emitter_index", -1))
		if e < 0 or e >= emitters.size() or not (emitters[e] is Dictionary):
			continue
		var idx: int = int(indices[i])
		var slot: String = str(site.get("slot", ""))
		if str(site.get("kind", "")) == "colour":
			var colours = emitters[e].get("color_curves", null)
			if colours is Dictionary and colours.has(slot):
				colours[slot] = maxi(0, idx)
			continue
		if not PARAM_NIBBLES.has(slot):
			continue
		var raw = emitters[e].get("curve_indices_raw", null)
		if not (raw is Array) or raw.size() < 8:
			continue
		var spec: Array = PARAM_NIBBLES[slot]
		var byte: int = int(spec[0])
		var shift: int = int(spec[1])
		var mask: int = int(spec[2])
		var stored: int = 0 if idx < 0 else idx + 1
		raw[byte] = (int(raw[byte]) & ~(mask << shift)) | ((stored & mask) << shift)


## The curves section's bytes: the u32 count, then each slot's 160 samples.
static func build_section(table: Array) -> PackedByteArray:
	var out: PackedByteArray = PackedByteArray()
	out.resize(COUNT_BYTES)
	out.encode_u32(0, table.size())
	for slot in table:
		out.append_array(_as_bytes(slot))
	return out


## Partial-patch the curve table from `block` — `curves.json`'s shape, the SAME
## `EffectReadCurves.parse` returns.
##
## IDENTITY IS DEGENERATE HERE. The block is the section's own
## bytes read back as integers, so `BIN -> parse -> serialize -> BIN` is trivially equal and
## proves only the geometry — the same standing `texture` and `sound_def` already have in
## `EffectBinWriterCorpusTest`'s header. What the corpus arm DOES score here is that the count
## word and the 160-byte stride are right; what scores the compiler is `compile`'s own round
## trip, and what scores that this writer writes at all is the perturbation-sensitivity arm.
##
## The count is NOT taken from the block: a block shorter than the section would otherwise
## shrink the table and orphan every emitter index above it, and this section does not resize.
static func patch_into(buf: PackedByteArray, header: Dictionary, block) -> String:
	if not (block is Array):
		return ""
	var base: int = int(header.get("anim_table_ptr", 0))
	if base <= 0 or base + COUNT_BYTES > buf.size():
		return "curves: no section (anim_table_ptr=%d)" % base
	var count: int = buf.decode_u32(base)
	if count <= 0 or count > MAX_SLOTS:
		return "curves: the file declares %d curves, outside 1..%d" % [count, MAX_SLOTS]
	for i in range(mini(count, block.size())):
		if not (block[i] is Dictionary):
			continue
		var values = block[i].get("values", null)
		if not (values is Array):
			continue
		var offset: int = base + COUNT_BYTES + i * CURVE_LENGTH
		if offset + CURVE_LENGTH > buf.size():
			break
		for j in range(mini(CURVE_LENGTH, values.size())):
			buf[offset + j] = int(values[j]) & 0xFF
	return ""


## One curve's 160 bytes from whatever the caller holds — u8 integers straight from
## `curves.json`, or the 0..1 FLOATS `EffectCurve.samples` carries.
##
## THE FLOAT PATH ROUNDS, IT DOES NOT TRUNCATE. `EffectData.load_from_directory` stores
## `value / 255.0`, and `int(x * 255.0)` loses a step on most values where `roundi` recovers
## every one of the 256 exactly. A truncating conversion round-trips 0 and 255 and almost
## nothing between, which is the shape of bug that passes a spot check.
static func _as_bytes(values) -> PackedByteArray:
	var out: PackedByteArray = PackedByteArray()
	out.resize(CURVE_LENGTH)
	if not (values is Array) and not (values is PackedByteArray):
		return out
	for j in range(mini(CURVE_LENGTH, values.size())):
		var v = values[j]
		if v is float:
			out[j] = clampi(roundi(float(v) * 255.0), 0, 255)
		else:
			out[j] = int(v) & 0xFF
	return out
