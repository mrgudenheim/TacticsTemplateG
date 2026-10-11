extends RefCounted
## The derived effect END — the frame the engine REAPs the cast, NOT the last authored
## keyframe: wind-down sees active_particle_count == 0, falls through to op_end
## (research/wiki_articles/effect_state.txt); screen/palette/camera/sound do NOT hold
## it open. EffectScoreModel.max_frame = authored bound; this = faithful runtime end —
## SIMULATED (ADR-0070 replay harness), FIXED seed = one representative end. No class_name (ADR-0004).
## vault: .vaults/comments/exmateria_effects/effect-end-model.md

const ParticleSubsystemClass = preload("res://addons/exmateria_effects/subsystem/ParticleSubsystem.gd")
const EffectTimelineClass = preload("res://addons/exmateria_effects/cast/EffectTimeline.gd")

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

	# Step fixed frames (seek pumps the delta) until the cast settles.
	var f := 0
	while f < frame_cap:
		f += 1
		tl.seek(f)
		if _settled(mgr, f):
			return f
	return frame_cap


## PAST the last spawn frame AND zero particles. NOT is_done(): ActiveEmitters linger
## in the pool and phase blocks stall with their window open; particle count is the
## signal the engine reaps on.
static func _settled(mgr, frame: int) -> bool:
	if frame <= mgr.get_last_active_effect_frame():
		return false
	return mgr.get_active_particle_count() == 0
