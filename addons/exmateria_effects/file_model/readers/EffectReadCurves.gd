extends RefCounted
## ANIMATION-CURVE reader for `E###.BIN` — GDScript port of `parse_effect.parse_curves`.
## Vault: [[Particle Curve Indices]]
##
## A u32 count at `anim_table_ptr`, then that many 160-byte curves of raw u8 samples. An
## emitter's `curves` dict indexes into this table (0 means NO curve and reads as -1; N means
## curve N-1 — see `EffectReadEmitters.decode_curve_index`), so this is what those indices
## point AT. 4.77% of the corpus's bytes, the largest single thing GDScript could not read.
##
## THE WRITE HALF LANDED (#274) AND THIS IS NOW A REGISTERED SECTION. It used to say curves
## were "the one section with NO WRITER IN ANY LANGUAGE" — 2,400 bytes of every effect that
## could be read and never saved, which is issue #448 in as many words. `EffectWriteCurves.gd`
## is the writer, and the compiler beside it packs the studio's exploded per-use-site curves
## back into this shared 15-slot table.
##
## ⚠️ REFEREE B IS WEAK HERE AND THAT HAS NOT CHANGED. The block this reader returns IS the
## section's own bytes read back as integers, so `BIN -> parse -> serialize -> BIN` is
## trivially equal — the same degenerate standing `texture` and `sound_def` carry. What the
## round trip scores is the count word and the 160-byte stride; what scores the pack is
## `explode -> compile` identity over the corpus, and what scores that anything is written at
## all is the perturbation-sensitivity arm. Do not read "16 sections round-trip" as
## "16 sections proven two ways".
##
## ⚠️ UNWRITABLE WAS NEVER UNUSED, and the two used to get confused here. Curves are read all
## over the addon — `EffectCurve.gd`, `CurveExplode.gd`, `EffectEmitter.gd`, `EffectData.gd`
## and six callbacks — and every emitter's `curves` dict indexes into this table.
##
## THE SAMPLES ARE RAW BYTES, DELIBERATELY. `parse_curves` stores all 160 u8 values with no
## interpretation — no scaling, no signedness, no envelope semantics. `EffectCurve.gd` is what
## gives them meaning downstream. A reader that "improved" on that would stop matching the
## extract.
##
## ABSENT IS `null`; a section too small to hold the count reads as `[]`, the same split as
## `frames` and `animation`.
##
## No `class_name` (ADR-0004) — file_model members stay path-preloaded.

## Bytes per curve (`parse_effect.CURVE_LENGTH`).
const CURVE_LENGTH: int = 160

## The u32 count sits first; the curves follow it.
const COUNT_BYTES: int = 4


## The curves section's own size. It runs from `anim_table_ptr` to `time_scale_ptr` when the
## optional time-scale section is present, and to `effect_flags_ptr` when it is not — the same
## either/or `EffectBinHeader.calculate_sections` applies, where `AnimCurves` absorbs the span.
static func section_size(header: Dictionary) -> int:
	var start: int = int(header.get("anim_table_ptr", 0))
	var time_scale_ptr: int = int(header.get("time_scale_ptr", 0))
	var end: int = time_scale_ptr if time_scale_ptr != 0 else int(header.get("effect_flags_ptr", 0))
	return maxi(0, end - start)


## Every curve — `curves.json`'s shape — or `null` when the section is out of bounds.
static func parse(buf: PackedByteArray, header: Dictionary):
	var base: int = int(header.get("anim_table_ptr", 0))
	if base <= 0 or base + COUNT_BYTES > buf.size():
		return null
	if section_size(header) < COUNT_BYTES:
		return []

	var count: int = buf.decode_u32(base)
	var out: Array = []
	for i in range(count):
		var offset: int = base + COUNT_BYTES + i * CURVE_LENGTH
		# The Python breaks rather than truncating the last curve — a partial curve is not a
		# curve, and stopping keeps the array's indices meaning what the emitter table thinks.
		if offset + CURVE_LENGTH > buf.size():
			break
		var values: Array = []
		for j in range(CURVE_LENGTH):
			values.append(buf[offset + j])
		out.append({"index": i, "values": values})
	return out
