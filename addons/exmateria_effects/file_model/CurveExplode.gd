extends RefCounted
## The **curve explode** (ADR-0089 curve-ownership amendment, decision 2) — what load
## does to the ROM's shared 15-slot curve table.
##
## A curve belongs to its **use site**: an `(emitter, slot)` pair, where slot is a param
## name or one of colour r/g/b. Every curve reference resolves through an emitter's two
## dicts (the callback `emitter+0x08` nibbles are lerp *parameters*, not table indices),
## so this walk over `emitters[*].curves` + `color_curves` is the COMPLETE census.
##
## The explode hands every use site its own private copy at a new index; after it, no two
## use sites share an index — privacy is STRUCTURAL, because an edit-in-place would
## restyle every other emitter still sharing the curve.
##
## **The array grows; the read path does not change.** Each use site gets its own INDEX
## rather than its own accessor, so every `EffectData.get_curve` caller is untouched.
##
## Two things are carried, not dropped:
##   • **Provenance** — the copy remembers its source slot in `EffectCurve.index`, so the
##     deferred compiler restores an untouched effect's original indices by provenance
##     first, value-dedup second. Nothing reads it yet — a knowingly carried cost,
##     recorded in the ADR.
##   • **Residue** — curves nothing references never enter the authoring model; they are
##     set aside in `curve_residue` so a byte-exact export can carry them back to their
##     original slots instead of silently losing them.
##
## Sharing still exists — in the compiler, as an OUTPUT format. Never here.
##
## No `class_name` (ADR-0004) — preloaded by path.

const EffectCurve = preload("res://addons/exmateria_effects/file_model/EffectCurve.gd")

## The colour slots, in the order the walk visits them. Param slots are visited in sorted
## key order first, so the exploded index a use site gets is a pure function of the effect
## on disk — a stable address for tests and for the compiler's provenance pass.
const COLOUR_SLOTS := ["r", "g", "b"]


## Explode `data`'s shared curve table in place. Idempotent in SHAPE (a second run over an
## already-exploded table produces the same one-curve-per-use-site array), though a re-run
## re-bases provenance onto the exploded indices — which is why this runs exactly once, at
## load, before anything can hold an index.
static func explode(data) -> void:
	if data == null or data.emitters == null or data.curves == null:
		return
	var source: Array = data.curves
	var referenced := {}
	var exploded: Array[EffectCurve] = []
	for e in range(data.emitters.size()):
		var em = data.emitters[e]
		if em == null:
			continue
		if em.curves is Dictionary:
			var params: Array = em.curves.keys()
			params.sort()
			for p in params:
				em.curves[p] = _repoint(source, exploded, referenced, int(em.curves[p]))
		if em.color_curves is Dictionary:
			for chan in COLOUR_SLOTS:
				if em.color_curves.has(chan):
					em.color_curves[chan] = _repoint(source, exploded, referenced,
						int(em.color_curves[chan]))
	var residue: Array = []
	for i in range(source.size()):
		if not referenced.has(i):
			residue.append({"index": i, "curve": source[i]})
	# Keep the pre-explode table addressable for the callbacks, whose curve references are
	# ROM slot ordinals packed into the emitter nibbles, not authoring use sites.
	data.curves_raw = source.duplicate()
	data.curves = exploded
	data.curve_residue = residue


## Every use site in `data` as `{emitter_index, slot, kind, index}`, in the explode's own
## walk order. `kind` is "param" or "colour" — the two dicts an index can live in, which is
## all a caller needs to repoint one. The single enumeration: the shape set, the gauge and
## the tests all count use sites through here rather than re-deriving the walk.
static func use_sites(data) -> Array:
	var out: Array = []
	if data == null or data.emitters == null:
		return out
	for e in range(data.emitters.size()):
		var em = data.emitters[e]
		if em == null:
			continue
		if em.curves is Dictionary:
			var params: Array = em.curves.keys()
			params.sort()
			for p in params:
				out.append({"emitter_index": e, "slot": str(p), "kind": "param",
					"index": int(em.curves[p])})
		if em.color_curves is Dictionary:
			for chan in COLOUR_SLOTS:
				if em.color_curves.has(chan):
					out.append({"emitter_index": e, "slot": chan, "kind": "colour",
						"index": int(em.color_curves[chan])})
	return out


## Read the index a use site currently points at (-1 = no curve).
static func site_index(data, emitter_index: int, slot: String, kind: String) -> int:
	var em = _emitter(data, emitter_index)
	if em == null:
		return -1
	var d: Dictionary = em.color_curves if kind == "colour" else em.curves
	return int(d.get(slot, -1)) if d is Dictionary else -1


## Point a use site at `index` (-1 = no curve). The ONE write to an emitter's curve
## address — the picker's mint and the compiler's repack both go through it, so "which
## dict does this slot live in" is answered in one place.
static func set_site_index(data, emitter_index: int, slot: String, kind: String, index: int) -> void:
	var em = _emitter(data, emitter_index)
	if em == null:
		return
	if kind == "colour":
		em.color_curves[slot] = index
	else:
		em.curves[slot] = index


## Append a fresh private curve for a use site that had none and point the site at it.
## The minted curve is the IDENTITY — all zeros — so adding a curve changes nothing
## until it is painted: with no curve the sim holds the START values, and an all-zero
## curve lerps to `min_start` at every frame (ADR-0089 dec. 5).
## Returns the new index, or the existing one when the site already has a curve.
static func mint_identity(data, emitter_index: int, slot: String, kind: String,
		length: int = 160) -> int:
	var existing := site_index(data, emitter_index, slot, kind)
	if existing >= 0 and existing < data.curves.size():
		return existing
	var curve := EffectCurve.new()
	curve.samples.resize(length)
	curve.samples.fill(0.0)
	# No provenance: a minted curve came from no ROM slot, and -1 says so rather than
	# claiming slot 0. The compiler assigns it an index by dedup.
	curve.index = -1
	data.curves.append(curve)
	var idx: int = data.curves.size() - 1
	set_site_index(data, emitter_index, slot, kind, idx)
	return idx


# --- internals -------------------------------------------------------------

## Copy the slot this use site points at into its own new entry and return that entry's
## index. A reference that does not resolve (E509/E510 point at a curves.json with ZERO
## entries) becomes an explicit -1: it read as "no curve" before the explode (get_curve
## range-checks) and must keep reading that way, which a stale index into a LONGER array
## would not. The ROM nibble in `raw_data.curve_indices_raw` still carries what it
## originally said.
static func _repoint(source: Array, exploded: Array[EffectCurve], referenced: Dictionary,
		slot: int) -> int:
	if slot < 0 or slot >= source.size():
		return -1
	referenced[slot] = true
	var copy := EffectCurve.new()
	copy.index = slot          # provenance: the slot this private curve came from
	copy.samples = source[slot].samples.duplicate()
	exploded.append(copy)
	return exploded.size() - 1


static func _emitter(data, emitter_index: int):
	if data == null or data.emitters == null:
		return null
	if emitter_index < 0 or emitter_index >= data.emitters.size():
		return null
	return data.emitters[emitter_index]
