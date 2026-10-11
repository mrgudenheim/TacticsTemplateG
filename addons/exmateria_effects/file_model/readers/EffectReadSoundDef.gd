extends RefCounted
## FEDS SOUND-DEFINITION reader for `E###.BIN` (#1329) — GDScript port of
## `parse_effect.parse_feds`'s slice half, the read mirror of
## `EffectBinWriter.serialize_sound_def`.
## Vault: [[Effect File Format]]
##
## The TIER-3 effect-sound section: the raw FEDS blob occupying
## `[sound_def_ptr, texture_ptr)`. That blob IS the registry block — `serialize_sound_def`
## takes a `PackedByteArray` and splices it back, and `feds.bin` is the committed copy of
## exactly these bytes.
##
## 🔴 THIS IS THE ONLY `RESIZING_SECTIONS` MEMBER, SO REFEREE B MEANS SOMETHING ELSE HERE. For
## every other section a round-trip is an in-place overwrite and byte equality proves the
## offsets. For this one the writer may SHIFT the whole tail and repoint `texture_ptr`. An
## unedited round-trip never resizes — measured, all 401 corpus sections are 4-aligned and the
## writer's padding is a no-op on every one — so the corpus arm degenerates to a pure splice
## and proves only the span. What it does NOT exercise is relocation; that needs an edited
## blob, which is why `_test_a_resized_sound_def_relocates_and_reads_back` exists as its own
## arm rather than being left to the corpus.
##
## ⚠️ `feds.json` IS DELIBERATELY NOT PORTED, and this is a design decision rather than an
## omission. Decoding the blob into opcodes needs the FEDS opcode table, and that table already
## exists TWICE — in `addons/exmateria_sound/runtime/sound_opcodes.gd`, which is the one that
## actually PLAYS `feds.bin`, and in `parse_effect.py`, which mirrors it. Those two are pinned
## against each other by `test_feds_opcode_drift.py` (ADR-0085 amendment 2026-08-11) because a
## param-count drift desyncs a decode mid-track. A third copy inside `exmateria_effects` would
## be a copy the drift guard does not know about — strictly worse than not having it. The blob
## is the patchable unit; the decode belongs to whoever owns the table.
##
## ABSENT IS `null`: no section (`sound_def_ptr <= 0` or an empty span), or a blob that does
## not open with the `feds` magic. The Python returns `(None, None)` for the same two cases and
## `serialize_sound_def` refuses a magic-less blob, so a reader that handed back a headless
## slice would produce a block the writer must reject.
##
## No `class_name` (ADR-0004) — file_model members stay path-preloaded.

## The four ASCII bytes every FEDS section opens with. Measured: all 401 corpus effects have
## one, so the magic check never fires here — it exists for a caller holding a foreign file.
const FEDS_MAGIC: String = "feds"

## `parse_feds_blob` refuses anything shorter than its own fixed header.
const MIN_BLOB_BYTES: int = 24


## The FEDS blob — `feds.bin`'s exact bytes — or `null` when the section is absent or is not a
## FEDS section.
static func parse(buf: PackedByteArray, header: Dictionary):
	var start: int = int(header.get("sound_def_ptr", 0))
	var end: int = mini(int(header.get("texture_ptr", 0)), buf.size())
	if start <= 0 or end <= start:
		return null
	var blob: PackedByteArray = buf.slice(start, end)
	if blob.size() < MIN_BLOB_BYTES:
		return null
	if blob.slice(0, 4).get_string_from_ascii() != FEDS_MAGIC:
		return null
	return blob
