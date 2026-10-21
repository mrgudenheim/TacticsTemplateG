extends RefCounted
## Duck-typed contract for an effect-cast **subsystem** — the runtime that turns
## parsed keyframe frames into output. Vocab: CONTEXT.md "Effect orchestration".
## Parsed data: per-cast `camera.json`, `palette.json`, `screen.json`, particle
## channels from `timeline.json`.
## Documented, not enforced: all conformers are `RefCounted`; none extends
## `Subsystem`. `PaletteSubsystem`/`ScreenSubsystem` extend `ColorSubsystem` by
## path per ADR-0004 (class-cache safety).
## Pumped by [EffectTimeline] once per fixed frame; the timeline owns clock +
## phase state, subsystems own everything keyframe-shaped (ADR-0014 dec. 2).
## vault: .vaults/comments/exmateria_effects/subsystem-contract.md


func advance(_frame: int, _phase: Array) -> void:
	"""Advance to `(frame, phase)`; fire any signals due this tick."""
	push_error("Subsystem.advance must be overridden")


func reset() -> void:
	"""Just-initialised state: cursors zero, channel state cleared, pending output dropped."""
	push_error("Subsystem.reset must be overridden")


func is_done() -> bool:
	"""True once the last output is produced; the timeline may treat it as finished."""
	push_error("Subsystem.is_done must be overridden")
	return false
