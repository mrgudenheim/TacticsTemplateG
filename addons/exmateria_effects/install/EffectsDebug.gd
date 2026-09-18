extends RefCounted

## `Effects`' diagnostics, read through the PLATFORM PORT instead of the
## host's `Debug` system. Not instantiated: a namespace of statics.
## 🔴 The flags were already `Tune` tunables behind `DebugConfig`'s facades:
## reading the slug is the same registry, one fewer dependency
## (ADR-0288 dec. 1: transcription, not design).
## 🔴 Slugs keep the host's `debug.*` spelling — one registry, one value
## (ADR-0141 dec. 2: Debug is non-counting for SELECTION; the install register counts it).
## 🔴 `iteration`/`camera` are host-wide shared slugs; host readers' lazy
## `DebugConfig._dbg_get` re-declares them after a reset.
## vault: .vaults/comments/exmateria_effects/effects-debug-severance.md

const TunePort = ExMateriaPlatform.TunePort

## Spelled `debug.*` to match `DebugConfig`'s registration: one registry, one spelling.
const SLUG_PARTICLE := "debug.particle_debug_enabled"
const SLUG_ITERATION := "debug.iteration_debug_enabled"
const SLUG_TIMELINE := "debug.timeline_debug_enabled"
const SLUG_CAMERA := "debug.camera_debug_enabled"


## Bind at class load - house shape for a static-only tunable owner (check_tune_owner_self_registration.py S1).
static func _static_init() -> void:
	if Engine.is_editor_hint():
		return
	register_tunables()


## Register all four slugs so the readers below can PULL-read.
## 🔴 NOT OPTIONAL BOILERPLATE: a pull-read asserts a prior bind and nothing
## else declares these — without it, every reader below asserts.
## Two binds of one slug is the supported shape: first-write-wins, same literal.
## `false`: `DebugConfig`'s code default; a rival type makes the owners disagree.
static func register_tunables() -> void:
	if Engine.is_editor_hint():
		return
	TunePort.bind(SLUG_PARTICLE, false)
	TunePort.bind(SLUG_ITERATION, false)
	TunePort.bind(SLUG_TIMELINE, false)
	TunePort.bind(SLUG_CAMERA, false)


## Every slug this file owns - the set-equal test against `DebugConfig` runs on this.
## 🔴 A TYPO IN A SLUG LITERAL BINDS A *NEW* SLUG RATHER THAN FAILING: it reads
## `false` forever and detaches verbosity from the host panel silently.
static func slugs() -> Array[String]:
	return [SLUG_PARTICLE, SLUG_ITERATION, SLUG_TIMELINE, SLUG_CAMERA]


## Read one flag, re-declaring it first if the registry has forgotten it.
## 🔴 A ONE-TIME BIND IS NOT ENOUGH: `Tune.reset()` drops the declarations and
## a pull-read asserts a prior bind. Guard, not unconditional bind: the re-bind
## cost is paid once per reset, not per read; `particle()` is read per frame.
static func _read(slug: String) -> bool:
	if not TunePort.is_registered(slug):
		TunePort.bind(slug, false)
	return bool(TunePort.get_value(slug, false))


## Particle-system tracing — emitters, pools, the multimesh renderer, TRAP.
static func particle() -> bool:
	return _read(SLUG_PARTICLE)


## Verbose per-frame iteration tracing. Host-wide.
static func iteration() -> bool:
	return _read(SLUG_ITERATION)


## Effect timeline / phase-block / callback-schedule tracing.
static func timeline() -> bool:
	return _read(SLUG_TIMELINE)


## Cinematic camera tracing. Host-wide.
static func camera() -> bool:
	return _read(SLUG_CAMERA)
