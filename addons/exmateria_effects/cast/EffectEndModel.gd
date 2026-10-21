extends RefCounted
## The derived effect END — the frame the engine REAPs the cast, NOT the last authored
## keyframe. A 3-phase root runs opcode 41 (0x801A4838) until `timeline_bound` (the
## 0x801A2C7C branch), then winds down until `active_particle_count` (+0x1C) is 0 and
## hits op_end; the main loop (0x801A18D8) frees the slot at 0x801A1D9C. Screen/palette/sound
## do NOT hold it open. The camera does not EITHER, but `advance_camera_tracks` (0x801AD198)
## runs on every opcode-41 tick, so the camera plays to the bound, and authoring puts the
## camera inside it (188 of 190 effects whose camera outlasts the particles). PCSX,
## Raise/E005: particles gone at ~f128, camera through f139, root freed at f140 = T.
## EffectScoreModel.max_frame = authored bound; this = faithful runtime end —
## SIMULATED (ADR-0070 replay harness), FIXED seed = one representative end, ONE target.
## No class_name (ADR-0004).
## vault: .vaults/comments/exmateria_effects/effect-end-model.md

const ParticleSubsystemClass = preload("res://addons/exmateria_effects/subsystem/ParticleSubsystem.gd")
const EffectTimelineClass = preload("res://addons/exmateria_effects/cast/EffectTimeline.gd")

const OP_BRANCH_ANIM_DONE_COMPLEX: int = 30

const MARKER_SEED: int = 0
# Never-dying particle cast would spin forever: 3600 = 2 min @ 30 Hz effect clock.
const HARD_CAP: int = 3600


## First frame where every phase block has stopped scheduling spawns AND zero particles
## remain; 0 for null/empty, `frame_cap` if it never settles.
static func derived_end_frame(effect_data, seed_value: int = MARKER_SEED, frame_cap: int = HARD_CAP) -> int:
	if effect_data == null:
		return 0

	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value

	var mgr = ParticleSubsystemClass.new()
	mgr.rng = rng
	mgr.initialize(effect_data, 512)
	mgr.set_anchors(Vector3.ZERO, Vector3.ZERO, Vector3.ZERO, Vector3.ZERO)

	var tl = EffectTimelineClass.new()
	var p1d := 0
	var p2s := 0
	if effect_data.timeline:
		p1d = effect_data.timeline.phase1_duration
		p2s = p1d + effect_data.timeline.phase2_delay
	tl.setup(p1d, p2s, effect_data.time_scale)
	tl.set_rng(rng, seed_value)   # so the harness re-seeds identically to the live cast
	tl.set_subsystems([mgr])
	mgr.timeline = tl
	tl.start()

	var bound := timeline_bound(effect_data)
	var f := 0
	while f < frame_cap:
		f += 1
		tl.seek(f)
		if f >= bound and settled(mgr, f):
			return f
	return frame_cap


## The frame a 3-phase root leaves its opcode-41 loop: `op_branch_anim_done_complex`
## (0x801A2C7C) branches out once the timeline counter reaches
## hdr+2 + hdr+4 + (targets-1)*hdr+6 + hdr+0xA, read off `timeline_section_ptr`. One
## target here, so the spawn_delay term is 0. 0 when the root does not use opcode 30
## (1-phase roots branch on hdr+0xA alone via 0x801A2C28, which reaps later on all 161).
static func timeline_bound(effect_data) -> int:
	if effect_data == null or effect_data.timeline == null:
		return 0
	var uses_complex := false
	for op in effect_data.script_ops:
		if op is Dictionary and int(op.get("opcode", -1)) == OP_BRANCH_ANIM_DONE_COMPLEX:
			uses_complex = true
			break
	if not uses_complex:
		return 0
	var h: Dictionary = effect_data.timeline.header
	return int(h.get("unknown_02", 0)) + int(h.get("phase1_duration", 0)) \
		+ int(h.get("phase2_delay", 0))


## PAST the last spawn frame AND zero particles. NOT is_done(): ActiveEmitters linger
## in the pool and phase blocks stall with their window open; particle count is the
## signal the engine reaps on.
static func settled(mgr, frame: int) -> bool:
	if frame <= mgr.get_last_active_effect_frame():
		return false
	return mgr.get_active_particle_count() == 0
