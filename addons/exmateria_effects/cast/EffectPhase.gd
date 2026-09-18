extends RefCounted
## Shared constants for effect timeline phases
## Vault: [[Effect Execution Model]]

const PHASE1 = "phase1"
## The "for-each" phase — runs once per target. Previously kept as the
## Ghidra-annotated name "animate_tick" for ROM-linkage; the ROM has no
## inherent names (Ghidra labels are our annotations) so the value is now
## just `"for_each"`, matching the const.
const PHASE_FOR_EACH = "for_each"
const PHASE2 = "phase2"

## All phases in execution order
const ALL = [PHASE1, PHASE_FOR_EACH, PHASE2]

## Phases that run before for_each
const PRE_PHASES = [PHASE1]

## Phases that can run parallel to for_each
const PARALLEL_PHASES = [PHASE2]


static func open_phases(frame: int, phase1_duration: int, phase2_start: int) -> Array:
	"""The set of authored-window labels open at `frame` (phase model C — see
	CONTEXT.md "Effect orchestration" / ADR-0012). `phase2` overlaps the
	for-each phase, so the result is a set, not one value: {phase1} →
	{for_each} → {for_each, phase2}."""
	if frame < phase1_duration:
		return [PHASE1]
	var open := [PHASE_FOR_EACH]
	if frame >= phase2_start:
		open.append(PHASE2)
	return open


static func dominant(open: Array) -> String:
	"""Reduce an open-set to the single phase a single-valued subsystem (e.g. color)
	plays: phase2 > for_each > phase1."""
	if PHASE2 in open:
		return PHASE2
	if PHASE_FOR_EACH in open:
		return PHASE_FOR_EACH
	return PHASE1
