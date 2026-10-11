extends RefCounted
## PARTICLE-TIMELINE reader for `E###.BIN` (#1329) — GDScript port of
## `parse_effect.parse_timeline` plus the cinematic-timing derivation `extract_effect` applies
## on top of it. The read mirror of `writers/EffectWriteParticleTimeline.gd`.
## Vault: [[Effect File Format]]
##
## A 12-byte header then 15 particle channels (5 `for_each` + 5 `phase1` + 5 `phase2`), each
## 128 bytes of SoA arrays: 25 s16 times at +0x00, 25 u8 emitter ids at +0x31, 25 u16 action
## flags at +0x4A, and an s16 watermark at +0x7E.
##
## 🔴 `time[]` AND `emitter_id[]` PHYSICALLY SHARE BYTE 0x31. `time[]` is 25 s16 spanning
## 0x00..0x31 and `emitter_id[]` starts AT 0x31, so `time[24]`'s high byte is `emitter_id[0]`.
## The reader has it easy — it reads both views and both are "right" — but this is why
## `EffectWriteParticleTimeline` must write `time[]` before `emitter_id[]`, and why `time[24]`
## is a phantom slot no real data reaches (`max_keyframe` never gets to 24).
##
## 🔴 THREE OF THE HEADER'S NINE FIELDS ARE NOT IN THIS SECTION AT ALL. `first_hit_frame`,
## `for_each_delay` and `total_frames` are DERIVED by simulating the runtime `PhaseBlock` walk
## over the `for_each` channels — and `total_frames` additionally needs the CAMERA section's
## phase2 keyframes. `parse_timeline` seeds them camera-less and `extract_effect` then
## RECOMPUTES them with the camera in hand, so a straight port of `parse_timeline` alone does
## not match `timeline.json` on any effect with a walkable phase2 camera. That is why this
## reader calls `EffectReadCamera` itself: the committed leaf is the post-recompute one, and
## the reader has to produce what the leaf holds, not what one Python function returns.
##
## ⚠️ THE KEYFRAME TIMES ARE CUMULATIVE, NOT ABSOLUTE. A channel sits in keyframe N for
## `kf[N].time - kf[N-1].time` frames at 30 Hz. An earlier derivation used the absolute reading
## (`base + kf.time`) and disagreed with the runtime by hundreds of frames per effect; the
## runtime is authoritative because `EffectViewer` plays these back through `PhaseBlock`. The
## walk below mirrors `PhaseBlock` verbatim, zero-duration-still-costs-a-frame included.
##
## `EffectWriteParticleTimeline` writes only the channels' SoA arrays and their watermarks, so
## referee B is blind to all nine header fields — the six stored ones as well as the three
## derived — and `timeline.json` is their only oracle.
##
## ⚠️ THE LEAF IS `timeline.json` while the section is `particle_timeline`; one of the three
## name mismatches `SECTION_SOURCES` exists to carry.
##
## ABSENT IS `null`. A section under 12 bytes returns an empty header and no channels, then
## still gets the three derived fields stamped on — exactly as `extract_effect` does, because
## its `.update()` is unconditional.
##
## 🔴 `last_fire_frame` NEVER DOMINATES ON THIS CORPUS, AND `parse_effect.py` SAYS IT DOES.
## Its docstring names E032 Haste as a spell whose lone HIT_REACT sits past the camera return
## so that the AoE-sweep bound wins. Measured two ways — deleting the branch here is green
## across all 400, and recomputing `_derive_cinematic_timing` in Python with the branch
## suppressed changes `total_frames` for 0 of 401 effects. E032 itself: `first_hit_frame` 48,
## `for_each_delay` 1, so `last_fire_frame` is 55 against a `camera_visible_end` of 96. The
## branch is ported because the orchestrator's teardown really does gate on `total_frames` and
## a future effect could need it — but nothing here exercises it, and `UNITS_PER_BATTLE_FALLBACK`
## is unguarded for the same reason (8 -> 4 is green too).
##
## No `class_name` (ADR-0004) — file_model members stay path-preloaded.

const Layout = preload("res://addons/exmateria_effects/file_model/EffectBinLayout.gd")
const ReadCamera = preload("res://addons/exmateria_effects/file_model/readers/EffectReadCamera.gd")

## The header's six STORED fields: key -> s16 offset from `timeline_section_ptr`.
const HEADER_FIELDS: Dictionary = {
	"unknown_00": 0x00, "unknown_02": 0x02, "phase1_duration": 0x04,
	"spawn_delay": 0x06, "unknown_08": 0x08, "phase2_delay": 0x0A,
}

const HEADER_BYTES: int = 12

## The three lane groups, in the order `parse_timeline` appends them — which is the order
## `particle_channels` arrives in and therefore the order referee A compares.
const CHANNEL_CONTEXTS: Array = ["for_each", "phase1", "phase2"]

## 🔴 BITS 0-2 ARE ONE 3-BIT FIELD, NOT THREE FLAGS, AND THE ROM READS THEM AS ONE.
## `action_flags[i]` is read at exactly two sites in BATTLE.BIN — `ram:801A3578` and
## `ram:801A40F0` — and both do `andi v0,v0,0x7` immediately. The masked value is a CALLBACK
## SLOT SELECTOR: `0` fires nothing, `1..4` select `callback_ptrs[slot-1]` at `+0xD4` of the
## emitter runtime struct, which is `jalr`'d, and `callback_state[slot-1]` is set to 3
## ("ending"). Both of those fields are already typed in
## `fft-ghidra/content/types_particle_emitter.h`, and both arrays are FOUR long — which is why
## selector values 5..7 are unaddressable and, measured, never appear.
##
## That the read site is the right one is corroborated by its neighbour: the same function
## loads `emitter_id[i]` from `+0x31` with the same index, and both offsets are this file's own
## (`PARTICLE_OFF_EMITTER_ID`, `PARTICLE_OFF_ACTION_FLAGS`).
##
## 📏 Over all 9,044 live keyframes: selector 0 = 8,774, 1 = 109, 2 = 73, 3 = 57, 4 = 31,
## and 5/6/7 = ZERO. #449's census read this as "bit 0 = 166, bit 1 = 130, bit 2 = 31", which
## is the same data decomposed wrongly — bit 0 is values {1,3} = 166, bit 1 is {2,3} = 130,
## bit 2 is {4} = 31. Detail and the install path (an effect-SCRIPT `load_callback` opcode,
## `slot = flags >> 2`) in `research/working_documents/EFFECT_ACTION_FLAGS.md`.
const ACTION_SELECTOR_MASK: int = 0x07

## The most callback slots an effect has, so the most a selector can name.
## `types_particle_emitter.h`: `void *callback_ptrs[4]`.
const MAX_CALLBACK_SLOTS: int = 4

## The `action_flags` bit that means "this keyframe lands the hit". Measured over all 401
## effects respecting `max_keyframe`: 223 real HIT_REACT keyframes, every one in `for_each`
## context and NONE in phase1/phase2 — which is why the derivation scans `for_each` only.
##
## ⚠️ NO ROM READ SITE HAS BEEN FOUND FOR THIS BIT, OR FOR 3, 5 OR 6. Two probes looked: every
## `andi` in BATTLE.BIN with mask 0x08/0x10/0x20/0x40 resolved back to the instruction that
## produced its source (none takes a `+0x4A` load), and both reading functions load `+0x4A`
## exactly once and mask it only with 0x7. That is *no read site found*, NOT "engine-ignored" —
## a value stashed in a saved register, or tested by shift-and-branch instead of `andi`, would
## defeat both. `frameset.header_flags` earned the `na` verdict on stronger ground: there the
## field's only reader was found and shown to step over it.
const HIT_REACT_FLAG: int = 0x10

## The selector value at keyframe `i`, or 0 for "fire nothing" — the `andi …,0x7` the ROM does.
static func action_slot(action_flags: int) -> int:
	return action_flags & ACTION_SELECTOR_MASK

## The orchestrator stamps `fire_frame = first_hit_frame + N * for_each_delay` per target, and
## tears down on `timer >= total_frames`, so the bound has to reach the LAST target's fire or
## that target's damage never lands. Worst case is a full battle minus the caster.
const UNITS_PER_BATTLE_FALLBACK: int = 8

## Loop bound for the PhaseBlock simulation — a malformed channel must not hang the reader.
const SIMULATION_GUARD: int = 100000


## The whole timeline block — `timeline.json`'s shape — or `null` when the section is out of
## bounds.
static func parse(buf: PackedByteArray, header: Dictionary):
	var timeline_ptr: int = int(header.get("timeline_section_ptr", 0))
	if timeline_ptr <= 0 or timeline_ptr >= buf.size():
		return null

	var head: Dictionary = {}
	var channels: Array = []
	if timeline_ptr + HEADER_BYTES <= buf.size():
		for key in HEADER_FIELDS:
			head[key] = buf.decode_s16(timeline_ptr + int(HEADER_FIELDS[key]))
		# Five LANES per context, not 25 — `PARTICLE_SLOTS` is the keyframes inside one lane.
		for context in CHANNEL_CONTEXTS:
			for i in range(Layout.PARTICLE_FOR_EACH_OFFSETS.size()):
				var offset: int = Layout.particle_channel_offset(timeline_ptr, context, i)
				if offset < 0:
					break
				if offset + Layout.PARTICLE_CHANNEL_SIZE > buf.size():
					continue
				channels.append(parse_channel(buf, offset, context, i))

	# The camera-aware recompute `extract_effect` performs. Unconditional there, so
	# unconditional here — a degenerate section still carries the three derived fields.
	var derived: Dictionary = derive_cinematic_timing(head, channels, ReadCamera.parse(buf, header))
	for key in derived:
		head[key] = derived[key]
	return {"header": head, "particle_channels": channels}


## One 128-byte particle channel at `offset`.
static func parse_channel(buf: PackedByteArray, offset: int, context: String,
		channel_idx: int) -> Dictionary:
	var keyframes: Array = []
	for i in range(Layout.PARTICLE_SLOTS):
		keyframes.append({
			"time": buf.decode_s16(offset + Layout.PARTICLE_OFF_TIME + i * 2),
			"emitter_id": buf[offset + Layout.PARTICLE_OFF_EMITTER_ID + i],
			"action_flags": buf.decode_u16(offset + Layout.PARTICLE_OFF_ACTION_FLAGS + i * 2),
		})
	return {
		"context": context,
		"channel_index": channel_idx,
		"keyframes": keyframes,
		"max_keyframe": buf.decode_s16(offset + Layout.PARTICLE_OFF_MAX_KEYFRAME),
	}


## `{"hit_cfs": Array, "last_active_cf": int}` — where HIT_REACT fires across every `for_each`
## channel, and the last frame any of them was still running, both in PhaseBlock frames
## relative to the for_each open edge.
##
## Mirrors `PhaseBlock` exactly: `initialize()` emits `kf[1].action_flags` at cf 0; then each
## call decrements the current duration and, when it hits zero, advances and emits the NEW
## keyframe's flags at the CURRENT cf before cf increments. Initial duration is `kf[1].time`,
## so a channel with `kf[1].time == T` advances out of keyframe 1 at `cf = max(0, T - 1)`.
static func simulate_for_each(channels: Array) -> Dictionary:
	var hit_cfs: Array = []
	var last_active_cf: int = 0
	for ch in channels:
		if not (ch is Dictionary) or str(ch.get("context", "")) != "for_each":
			continue
		var max_kf: int = int(ch.get("max_keyframe", 0))
		if max_kf < 1:
			continue
		var kfs = ch.get("keyframes", [])
		if not (kfs is Array) or kfs.size() <= max_kf:
			continue

		if (int(kfs[1].get("action_flags", 0)) & HIT_REACT_FLAG) != 0:
			hit_cfs.append(0)

		var current_kf: int = 1
		var dur: int = int(kfs[1].get("time", 0))
		var cf: int = 0
		var guard: int = 0
		while current_kf <= max_kf:
			guard += 1
			if guard > SIMULATION_GUARD:
				break
			dur -= 1
			if dur <= 0:
				current_kf += 1
				if current_kf > max_kf:
					last_active_cf = maxi(last_active_cf, cf)
					break
				dur = int(kfs[current_kf].get("time", 0)) - int(kfs[current_kf - 1].get("time", 0))
				if (int(kfs[current_kf].get("action_flags", 0)) & HIT_REACT_FLAG) != 0:
					hit_cfs.append(cf)
			cf += 1
	hit_cfs.sort()
	return {"hit_cfs": hit_cfs, "last_active_cf": last_active_cf}


## The three cinematic-orchestrator fields, in CPU effect_frame units (30 Hz). `camera` may be
## `null`, which is the pre-recompute reading and is NOT what `timeline.json` holds.
static func derive_cinematic_timing(head: Dictionary, channels: Array, camera) -> Dictionary:
	var phase1_duration: int = int(head.get("phase1_duration", 0))
	var phase2_delay: int = int(head.get("phase2_delay", 0))

	var sim: Dictionary = simulate_for_each(channels)
	var hit_cfs: Array = sim["hit_cfs"]
	var last_active_cf: int = int(sim["last_active_cf"])

	var first_hit_frame: int = phase1_duration + int(hit_cfs[0]) if not hit_cfs.is_empty() else 0
	var for_each_delay: int = maxi(1, int(hit_cfs[1]) - int(hit_cfs[0])) \
		if hit_cfs.size() >= 2 else 1

	# The camera's phase2 leg is the return to strategy view; once its last walkable keyframe
	# passes, the camera holds and the cinematic is visually done.
	var phase2_visible_end: int = -1
	if camera is Dictionary and camera.get("phase2") is Dictionary:
		var phase2: Dictionary = camera["phase2"]
		var max_kf: int = int(phase2.get("max_keyframe", 0))
		var kfs = phase2.get("keyframes", [])
		if kfs is Array:
			for i in range(kfs.size()):
				if i > max_kf:
					break
				phase2_visible_end = maxi(phase2_visible_end, int(kfs[i].get("end_frame", 0)))
	var camera_visible_end: int = phase1_duration + phase2_delay + phase2_visible_end \
		if phase2_visible_end > 0 else -1

	var last_fire_frame: int = first_hit_frame \
		+ (UNITS_PER_BATTLE_FALLBACK - 1) * for_each_delay if first_hit_frame > 0 else 0
	var for_each_block_end: int = phase1_duration + last_active_cf

	var total_frames: int = maxi(camera_visible_end, last_fire_frame) \
		if camera_visible_end > 0 else maxi(for_each_block_end, last_fire_frame)

	return {
		"first_hit_frame": first_hit_frame,
		"for_each_delay": for_each_delay,
		"total_frames": total_frames,
	}
