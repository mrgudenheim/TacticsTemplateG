extends RefCounted
## The per-section serializer registry for byte-exact `E###.BIN` save (#1326) — GDScript port
## of `tools/effect_writer_registry.py`.
## Vault: [[Effect File Format]]
##
## #1316 put the READ direction's format boundary (the 40-byte header) into GDScript as
## `EffectBinHeader.gd`; this registry is the WRITE direction — it says how to put a section
## back where `EffectBinHeader` says it begins.
##
## A partial patch, not a compiler: bytes outside every parsed section (worst case `E383` at
## 63.8% covered) are embedded MIPS, so the base BIN stays an input. Each serializer rewrites
## only its own section's known fields into a copy of the base; every other byte survives
## verbatim.
##
## The seam is at bytes: `patch_all` is `(base_bytes, sections, header) -> bytes` — no paths,
## no `res://`, nothing about the authoring workspace — which is why it lives in the addon
## beside the reader, not in the host's `src/effects/studio/` (#1316 put `EffectBinHeader.gd`
## here). A Saver owns where files live; this owns bytes.
##
## `anim_curves` (the sixteenth section) has a free identity oracle: `explode -> compile` of
## the ROM's own table reproduces the table and every emitter's index nibbles on 399 of 401
## effects, with no emulator and no golden file. It never resizes — 15 curves, 2,404 bytes,
## zero slack, in all 401; 15 is the cap the emitter's 4-bit index imposes. See
## `EffectWriteCurves.gd`.
##
## Every serializer returns a `String` — empty on success, the refusal message otherwise — and
## `patch_all` returns `{ok, bytes, error}`. An explicit message rather than a falsy sentinel:
## a GDScript runtime error yields the type default, so "returned falsy" would be
## indistinguishable from a crash. An unknown section name is a hard error — a typo must
## surface, not silently drop an edit.
##
## No `class_name` (ADR-0004) — file_model members stay path-preloaded.

const Layout = preload("res://addons/exmateria_effects/file_model/EffectBinLayout.gd")
const BinHeader = preload("res://addons/exmateria_effects/file_model/EffectBinHeader.gd")

const WriteScreen = preload("res://addons/exmateria_effects/file_model/writers/EffectWriteScreen.gd")
const WritePalette = preload("res://addons/exmateria_effects/file_model/writers/EffectWritePalette.gd")
const WriteCamera = preload("res://addons/exmateria_effects/file_model/writers/EffectWriteCamera.gd")
const WriteSound = preload("res://addons/exmateria_effects/file_model/writers/EffectWriteSound.gd")
const WriteContainers = preload("res://addons/exmateria_effects/file_model/writers/EffectWriteContainers.gd")
const WriteEmitters = preload("res://addons/exmateria_effects/file_model/writers/EffectWriteEmitters.gd")
const WriteParticleTimeline = preload("res://addons/exmateria_effects/file_model/writers/EffectWriteParticleTimeline.gd")
const WriteTimelineHeader = preload("res://addons/exmateria_effects/file_model/writers/EffectWriteTimelineHeader.gd")
const WriteFlags = preload("res://addons/exmateria_effects/file_model/writers/EffectWriteFlags.gd")
const WriteTimeScale = preload("res://addons/exmateria_effects/file_model/writers/EffectWriteTimeScale.gd")
const WriteFrames = preload("res://addons/exmateria_effects/file_model/writers/EffectWriteFrames.gd")
const WriteAnimation = preload("res://addons/exmateria_effects/file_model/writers/EffectWriteAnimation.gd")
const WriteTexture = preload("res://addons/exmateria_effects/file_model/writers/EffectWriteTexture.gd")
const WriteScript = preload("res://addons/exmateria_effects/file_model/writers/EffectWriteScript.gd")
const WriteCurves = preload("res://addons/exmateria_effects/file_model/writers/EffectWriteCurves.gd")

## Sections a studio edit can RESIZE. They splice LAST, because every other serializer reads
## fixed offsets out of the same parsed header, valid only while the buffer still has its
## original geometry (ADR-0085 amendment 2026-08-18b). A second resizing section would address
## the pre-splice file, so `patch_all` re-derives the geometry (`_regeometry`) after any
## size-changing splice that has a later serializer — the resize order is not a rule to
## remember. `_regeometry`'s one precondition is that `frames_ptr` has not moved, and it cannot:
## frames is the FIRST section, so a resize shifts only the tail.
const RESIZING_SECTIONS: Array = ["frames", "animation", "sound_def", "script"]

## The `feds` magic a TIER-3 sound-definition blob must open with. A blob without it is a
## mis-addressed splice, not a short one.
const FEDS_MAGIC: String = "feds"

## section name -> `Callable(buf: PackedByteArray, header: Dictionary, block) -> String`.
## Registration order mirrors `effect_writer_registry.py`'s, so `registered_sections()` reports
## the same order on both sides.
static var _registry: Dictionary = {}


static func _ensure_builtins() -> void:
	if not _registry.is_empty():
		return
	_registry["screen"] = WriteScreen.patch_into
	_registry["palette"] = WritePalette.patch_into
	_registry["camera"] = WriteCamera.patch_into
	_registry["sound"] = WriteSound.patch_into
	_registry["sound_def"] = serialize_sound_def
	_registry["sound_containers"] = WriteContainers.patch_into
	_registry["emitters"] = WriteEmitters.patch_into
	_registry["particle_timeline"] = WriteParticleTimeline.patch_into
	# Same geometry base as particle_timeline, DISJOINT bytes: the three phase durations at
	# +0x04/+0x06/+0x0A, while every channel lives at +0x0C and beyond (#271).
	_registry["timeline_header"] = WriteTimelineHeader.patch_into
	_registry["effect_flags"] = WriteFlags.patch_into
	_registry["time_scale"] = WriteTimeScale.patch_into
	# RESIZING since #449 q1 — both re-lay out their whole section rather than patching fields
	# in place, and both need `relocate`, so the splice lives here for the same preload reason
	# `serialize_script` does.
	_registry["frames"] = serialize_frames
	_registry["animation"] = serialize_animation
	_registry["texture"] = WriteTexture.patch_into
	# The curve TABLE's bytes. The pack that decides what goes in it is `EffectWriteCurves.compile`,
	# which a Saver runs BEFORE this — it rewrites the emitter blocks' index nibbles too, so the
	# two sections stay consistent without either serializer reaching into the other's bytes.
	_registry["anim_curves"] = WriteCurves.patch_into
	# RESIZING, and the splice lives here rather than on the writer: it needs `relocate`,
	# and `EffectWriteScript` cannot preload the file that preloads it (#1416).
	_registry["script"] = serialize_script


## Register `fn` as the serializer for `section`. Returns `""` on success, else the refusal —
## re-registering a DIFFERENT function over a live section is refused rather than silently
## clobbered, mirroring the Python registry.
static func register(section: String, fn: Callable) -> String:
	_ensure_builtins()
	if _registry.has(section) and _registry[section] != fn:
		return "serializer for section '%s' already registered" % section
	_registry[section] = fn
	return ""


## Remove a section's serializer (mainly a test seam for probe registrations).
static func unregister(section: String) -> void:
	_ensure_builtins()
	_registry.erase(section)


## The registered serializer for `section`, or an INVALID `Callable` when there is none —
## check with `.is_valid()`. Not `null`: a typed return keeps a caller from `call()`ing a
## default that would look like a no-op success.
static func serializer_for(section: String) -> Callable:
	_ensure_builtins()
	if not _registry.has(section):
		return Callable()
	return _registry[section]


## The section names with a registered serializer, in registration order.
static func registered_sections() -> Array:
	_ensure_builtins()
	return _registry.keys()


## Restore the registry to exactly the built-in sixteen (a test seam, so one test's probe
## registration cannot leak into the next).
static func reset_registry() -> void:
	_registry.clear()
	_ensure_builtins()


## Return a NEW buffer: `base_bytes` with every section in `sections_by_name` partial-patched by
## its registered serializer, all other bytes verbatim.
##
## `sections_by_name` maps section name -> that section's parsed (possibly edited) block.
## `header` is `EffectBinHeader.parse_header`'s output — the ONE geometry source, so no
## serializer hard-codes a section pointer.
##
## Returns `{ok: bool, bytes: PackedByteArray, error: String}`. `ok` is false when a named
## section has no serializer (a typo must surface, not drop the edit) or when a serializer
## refuses; `bytes` is then the untouched base, so a failed save can never write a half-patched
## file.
static func patch_all(base_bytes: PackedByteArray, sections_by_name: Dictionary,
		header: Dictionary) -> Dictionary:
	_ensure_builtins()

	# Stable partition: non-resizing sections keep their insertion order and run first;
	# resizing sections move to the end, where the geometry they invalidate is no longer read.
	var ordered: Array = []
	var deferred: Array = []
	for name in sections_by_name:
		if not _registry.has(name):
			return {"ok": false, "bytes": base_bytes,
				"error": "no serializer registered for section '%s'" % name}
		if RESIZING_SECTIONS.has(name):
			deferred.append(name)
		else:
			ordered.append(name)
	ordered.append_array(deferred)

	var buf: PackedByteArray = base_bytes.duplicate()
	var geometry: Dictionary = header
	for i in range(ordered.size()):
		var name: String = str(ordered[i])
		var fn: Callable = _registry[name]
		var before: int = buf.size()
		var err: String = str(fn.call(buf, geometry, sections_by_name[name]))
		if not err.is_empty():
			return {"ok": false, "bytes": base_bytes, "error": "%s: %s" % [name, err]}
		# A splice that MOVED the file invalidates the map every later serializer reads. Only
		# re-derived when there IS a later serializer: with one resizing section the answer is
		# never consulted, and deriving it anyway would impose a full header on the synthetic
		# geometries a caller is entitled to pass for a single section.
		if buf.size() != before and i < ordered.size() - 1:
			var refreshed: Dictionary = _regeometry(buf, geometry)
			if refreshed.is_empty():
				return {"ok": false, "bytes": base_bytes,
					"error": ("%s: resized the file by %+d but the header no longer describes "
						+ "it, so the sections after it cannot be placed")
						% [name, buf.size() - before]}
			geometry = refreshed
	return {"ok": true, "bytes": buf, "error": ""}


## The header re-read out of `buf` after a splice moved it, or `{}` when it cannot be trusted.
##
## The base is derived the way `relocate` derives it — `frames_ptr` is the header's own first
## field and is always `0x28` from the base — and then checked: `frames_ptr` must come back
## unchanged. Both resizing sections sit after the frames, so their pointer cannot move; the day
## a section resizes ahead of it, this says so instead of quietly re-basing the whole file.
static func _regeometry(buf: PackedByteArray, previous: Dictionary) -> Dictionary:
	if not previous.has("frames_ptr"):
		return {}
	var base: int = int(previous["frames_ptr"]) - Layout.HEADER_SIZE
	if base < 0 or base + Layout.HEADER_SIZE > buf.size():
		return {}
	var refreshed: Dictionary = BinHeader.parse_header(buf, base)
	if int(refreshed["frames_ptr"]) != int(previous["frames_ptr"]):
		return {}
	return refreshed


## FRAMES / FRAMESET section: re-lay the whole section out from `block` and splice it in
## (#449 q1, ADR-0337). `block` is the flat frameset array `EffectReadFrames.parse` returns.
##
## Frames is the FIRST section, so it moves the other nine header pointers: every other
## section begins after `frames_ptr`, and a resize at or after it cannot break a CODE-format
## MIPS prologue — no prologue addresses anything at or past its own header.
##
## The section is ALWAYS REGENERATED, never short-circuited on "nothing changed": identity
## over the corpus — 401 of 401 effects rebuild byte-for-byte — is this writer's referee, and
## a writer that skipped the rebuild when nothing moved would pass that arm while never
## proving the rebuild is byte-exact.
static func serialize_frames(buf: PackedByteArray, header: Dictionary, block) -> String:
	var start: int = int(header.get("frames_ptr", 0))
	var end: int = int(header.get("animation_ptr", 0))
	if start <= 0 or end <= start or end > buf.size():
		return "frames: no section (frames_ptr=%d animation_ptr=%d)" % [start, end]
	var built: Dictionary = WriteFrames.build_section(buf, start, end - start, block)
	if not bool(built["ok"]):
		return str(built["error"])
	return _splice(buf, header, Layout.FRAMES_PTR_OFF, start, end, built["bytes"])


## ANIMATION / SEQUENCE section: same shape, one section later. `block` is the sequence array
## `EffectReadAnimation.parse` returns, and its LENGTH is the count word — so appending a
## sequence is a resize this can express, where `patch_into` could not.
static func serialize_animation(buf: PackedByteArray, header: Dictionary, block) -> String:
	var start: int = int(header.get("animation_ptr", 0))
	var end: int = int(header.get("script_data_ptr", 0))
	if start <= 0 or end <= start or end > buf.size():
		return "animation: no section (animation_ptr=%d script_data_ptr=%d)" % [start, end]
	var built: Dictionary = WriteAnimation.build_section(buf, start, end - start, block)
	if not bool(built["ok"]):
		return str(built["error"])
	return _splice(buf, header, Layout.ANIMATION_PTR_OFF, start, end, built["bytes"])


## Replace `[start, end)` with `section`, repointing the header first when the size changed.
##
## Order matters: `relocate` reads the stored pointers out of `buf` and checks them against
## `header`, so it must run while the buffer still has its original geometry — splice first and
## the check compares a moved file against an unmoved header and refuses, or passes for the
## wrong reason.
##
## The refusal is returned as `relocate` phrased it, unrenamed: `patch_all` already prefixes
## every serializer error with the section's name.
static func _splice(buf: PackedByteArray, header: Dictionary, section_ptr_off: int,
		start: int, end: int, section: PackedByteArray) -> String:
	var delta: int = section.size() - (end - start)
	if delta != 0:
		var err: String = relocate(buf, header, section_ptr_off, delta)
		if not err.is_empty():
			return err
	var tail: PackedByteArray = buf.slice(end)
	buf.resize(start)
	buf.append_array(section)
	buf.append_array(tail)
	return ""


## TIER-3 FEDS sound-definition section: `block` (the edited feds blob) replaces
## `[sound_def_ptr, texture_ptr)`.
##
## Same-size edits splice in place; a resize cannot absorb in place — ADR-0085's amendment
## measured 0-3 bytes of slack per section across all 401 effects, so one added opcode
## overflows a quarter of the corpus. A resize RELOCATES: splice, shift the tail, repoint
## `texture_ptr` (the only header pointer past `sound_def_ptr`), leaving the FEDS section
## immediately before the texture — the invariant `FedsBank._load_from_effect_bin` derives the
## section from.
##
## The blob is padded to a 4-byte multiple first: every FEDS section in the corpus starts,
## ends and sizes 4-aligned, and those slack bytes ARE that padding.
static func serialize_sound_def(buf: PackedByteArray, header: Dictionary, block) -> String:
	if not (block is PackedByteArray):
		return "sound_def: blob must be a PackedByteArray, got %s" % type_string(typeof(block))
	var start: int = int(header["sound_def_ptr"])
	var end: int = mini(int(header["texture_ptr"]), buf.size())
	if start <= 0 or end <= start:
		return "sound_def: no feds section (sound_def_ptr=%d texture_ptr=%d)" % [
			start, int(header["texture_ptr"])]

	var blob: PackedByteArray = block.duplicate()
	if blob.size() < 4 or blob.slice(0, 4).get_string_from_ascii() != FEDS_MAGIC:
		return "sound_def: blob lacks the 'feds' magic — refusing the splice"
	var pad: int = blob.size() % 4
	if pad != 0:
		var padded: PackedByteArray = blob
		padded.resize(blob.size() + (4 - pad))
		blob = padded

	# `texture_ptr` is the only stored pointer greater than `sound_def_ptr` in all 401 corpus
	# effects, so the general rule degenerates to this one-pointer write.
	return _splice(buf, header, Layout.SOUND_DEF_PTR_OFF, start, end, blob)


## EFFECT-SCRIPT section: regenerate the canonical section for the pattern `block` asks for,
## preserving the effect's own prologue, and splice it in (#1416, ADR-0094).
##
## The splice is here and the model in `EffectWriteScript.gd`: this file preloads that one, so
## it cannot preload this one to reach `relocate` (#1416) — `serialize_sound_def` above is the
## same story; the two resizing sections are the two that need the header rewritten, and that
## rewrite lives here.
##
## A refusal is not the same as "nothing to do": 113 of the 401 corpus effects are not
## swappable (ADR-0094 dec. 3), so the block's target pattern is the only signal — the pattern
## the file already has authors nothing (bytes pass through verbatim); a different pattern is
## refused by name with the gate's own reason, because accepting it silently would drop a real
## edit (#1413).
##
## A swappable effect is ALWAYS REGENERATED, never short-circuited on "the pattern did not
## change": identity is the corpus arm's whole assertion (288 effects can actually be scored),
## and skipping the regenerate when nothing moved would pass it without ever proving the
## regenerate is byte-exact.
static func serialize_script(buf: PackedByteArray, header: Dictionary, block) -> String:
	var target: String = WriteScript.target_pattern(block)
	if target.is_empty():
		return ("script: the block must be the parsed root op-list or {pattern: …}, got %s"
			% type_string(typeof(block)))

	var gate: Dictionary = WriteScript.classify_bytes(buf, header)
	if not bool(gate["ok"]):
		var current: String = WriteScript.current_pattern(buf, header)
		if not current.is_empty() and target == current:
			return ""
		return "script: %s" % str(gate["reason"])

	if target != WriteScript.P_1PHASE and target != WriteScript.P_3PHASE:
		return ("script: '%s' is not a canonical pattern, so there is no section to regenerate"
			% target)

	var start: int = int(header["script_data_ptr"])
	var end: int = int(header["effect_data_ptr"])
	var new_section: PackedByteArray = WriteScript.regenerate_section(
		target, int(gate["texture_page"]), gate["callbacks"])
	return _splice(buf, header, Layout.SCRIPT_PTR_OFF, start, end, new_section)


## RELOCATION: a section changed size by `delta`, so every section AFTER it moved (ADR-0337).
##
## Returns `""` on success, else the refusal. Four callers, four shapes: `sound_def` moves one
## pointer, `script` six or seven, `animation` eight, `frames` (the first section) all nine.
##
## THE RULE. Add `delta` to every stored header pointer whose value is strictly GREATER than
## the resized section's own stored pointer, instead of "every pointer after offset X":
##
##  * The section's OWN pointer is `== start`, not `>`, so it stays put: the section still
##    begins where it began; only its END moved. Seeded (`>` -> `>=`): reds on every corpus
##    header and on both synthetic sound_def arms.
##  * A STORED `0` IS AN ABSENT-SECTION SENTINEL — `time_scale_ptr` is 0 in 270 of the 401
##    non-empty corpus effects, `effect_flags_ptr` in 2 (E509/E510 zero both) — and the value
##    rule already excludes it: no section begins at stored 0 (`frames_ptr` is always 0x28),
##    so `0 <= start` for every resize. A separate `stored == 0` clause was MEASURED to
##    discriminate nothing (deleting it leaves the 400-header arm green), so it is not here.
##  * Comparing VALUES rather than offsets is why the sentinel needs no clause of its own: the
##    offset formulation WOULD need one (drop it and the arm reds on E509/E510 and every
##    effect with no time-scale section) — the value rule needs one clause where the offset
##    rule needs two.
##
## GEOMETRY IS CHECKED BEFORE ANYTHING IS WRITTEN. The stored pointers are relative to the
## header base — 0 for DATA-format effects, the MIPS prologue's length for the CODE-format
## ones — while the parsed `header` hands us ABSOLUTES. `frames_ptr` is the header's own first
## field and is always `0x28`, so it names the base exactly (verified against all 401 extracted
## headers); the stored pointer at `section_ptr_off` must resolve to the absolute the caller
## says it is moving, or we refuse.
##
## Only the ten header pointers are written (ADR-0337 decision 6), and the prologue is a
## measurement, not a hope: `research/scripts/effect_code_prologue_refs.py` scanned all 110
## CODE-format prologues two ways (a MIPS decoder that materialises `lui`/`addiu`/`ori`
## constants and propagates the `lui` tag through `addu`, plus a raw scan of every aligned
## `u32` for an in-image address) — 406 in-image references, every one into the prologue's own
## code, ZERO at or past the header, both probes seeded-controlled. So a resize at or after
## `frames_ptr` cannot break a prologue (it is entirely before it and addresses nothing after);
## a resize of the PROLOGUE itself is a different question and nothing here does one.
## `write_effect_script`'s gate still refuses CODE-format, for its own reason — the script
## section IS the executable there.
static func relocate(buf: PackedByteArray, header: Dictionary, section_ptr_off: int,
		delta: int) -> String:
	if delta == 0:
		return ""
	if not header.has("frames_ptr"):
		return ("relocate: a %+d-byte resize has to repoint the sections after it, and this "
			+ "geometry carries no frames_ptr to derive the header base from") % delta
	var base: int = int(header["frames_ptr"]) - Layout.HEADER_SIZE
	if base < 0 or base + Layout.HEADER_SIZE > buf.size():
		return "relocate: header base %d is outside the %d-byte file" % [base, buf.size()]

	# The section being resized, named by BOTH sources, which have to agree.
	var own_key: String = ""
	for entry in Layout.HEADER_POINTERS:
		if int(entry[0]) == section_ptr_off:
			own_key = str(entry[1])
	if own_key.is_empty():
		return "relocate: 0x%02X is not one of the header's section pointers" % section_ptr_off
	var stored_start: int = buf.decode_u32(base + section_ptr_off)
	if base + stored_start != int(header.get(own_key, -1)):
		return ("relocate: refusing a %+d-byte resize — the header at %d puts %s at %d but "
			+ "the geometry says %d") % [delta, base, own_key, base + stored_start,
			int(header.get(own_key, -1))]

	# Two passes: validate every write, then perform them. A relocation that refuses halfway
	# leaves a header describing a file that does not exist.
	#
	# Every pointer about to move is checked against the parsed geometry, not just the
	# section's own — "check the section, trust the rest" would be a quiet loss of strictness
	# as the pointer count grows.
	var new_size: int = buf.size() + delta
	var writes: Array = []
	for entry in Layout.HEADER_POINTERS:
		var off: int = int(entry[0])
		var key: String = str(entry[1])
		var stored: int = buf.decode_u32(base + off)
		if stored <= stored_start:        # covers the absent-section 0 — see the header
			continue
		if header.has(key) and base + stored != int(header[key]):
			return ("relocate: refusing a %+d-byte resize — the file puts %s at %d but the "
				+ "geometry says %d, so the two disagree about what is being moved") % [
				delta, key, base + stored, int(header[key])]
		var moved: int = stored + delta
		if moved < Layout.HEADER_SIZE or base + moved > new_size:
			return ("relocate: %+d would put %s at %d, outside the %d-byte file the resize "
				+ "produces") % [delta, key, base + moved, new_size]
		writes.append([base + off, moved])
	for w in writes:
		buf.encode_u32(int(w[0]), int(w[1]))
	return ""
