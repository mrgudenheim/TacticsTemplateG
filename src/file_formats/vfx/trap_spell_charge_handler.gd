class_name TrapSpellChargeHandler
extends TrapChargeHandlerBase
## PSX Handler 4 — Spell charge lines.
## Gouraud-shaded line trails contract from a ring toward the caster with cosine ease-in-out,
## plus sparkle particles. Lines rendered via ImmediateMesh in TrapEffectInstance.

const HEIGHT_OVERSHOOT: float = 8.0  # PSX adds 8 units above head
const SPARKLE_EMITTER_INDEX: int = 12
const SPARKLE_PALETTE_ID: int = 15
const MAX_SPARKLES: int = 14

var sparkles_to_spawn: int = 0
var active_sparkle_count: int = 0
var element_id: int = 0


func start(p_element_id: int, p_sprite_height: float = DEFAULT_HEIGHT) -> void:
	element_id = p_element_id
	convergence_y = (p_sprite_height + HEIGHT_OVERSHOOT) / VfxEmitter.POSITION_DIVISOR

	element_color = TrapEffectData.get_element_color(element_id)

	restart()


func tick() -> void:
	match state:
		State.ACTIVE:
			_try_spawn_line()
			_try_spawn_sparkle()
			_update_lines()
		State.ENDING:
			_update_lines()
			if active_line_count == 0:
				state = State.DONE
		State.DONE, State.INIT:
			return


func _on_restart() -> void:
	sparkles_to_spawn = 0
	active_sparkle_count = 0


func _interpolate_y(_slot: LineSlot, _factor: float) -> float:
	return convergence_y


func _try_spawn_sparkle() -> void:
	sparkles_to_spawn = 0
	if active_sparkle_count < MAX_SPARKLES:
		sparkles_to_spawn = 1
