class_name UnitSpritesManager
extends Node3D
## Owns the three paletted sprite materials a unit paints with, and registers them so
## anything can recolour the unit — spell effects among them — through the id handed to
## `bind_tint_surface`.

const LAYERING_OFFSET: float = 0.001
const UNIT_SPRITE_SHADER: Shader = preload("uid://cdcosdsn4y30b")

## The three separately-colourable parts of a unit, in the order
## `color_stack.gdshaderinc` names them. A colour change carries a 3-bit mask over exactly
## these, so giving all three materials one id makes "all three" (`MASK_WHOLE`, 0x7) and
## "just the first" (`MASK_SURFACE0`, 0x1) impossible to tell apart.
const SURFACE_BODY: int = 0
const SURFACE_WEAPON: int = 1
const SURFACE_EFFECT: int = 2

## Loaded for its constants only: it has no `register_surface` of its own, so the
## registration calls below go to the `TintedSurfaces` autoload instead.
const TintedSurfacesPort := preload("res://addons/exmateria_effects/install/TintedSurfacesPort.gd")

@export var sprite_primary: Sprite3D
@export var sprite_weapon: Sprite3D
@export var sprite_effect: Sprite3D
@export var sprite_text: Sprite3D

@export var sprite_item: Sprite3D
var item_initial_pos: Vector3 = Vector3(0, -0.714, 0)
@export var sprite_background: Sprite3D

var _primary_material: ShaderMaterial
var _weapon_material: ShaderMaterial

## The per-unit duplicate, not the scene's: that one is a SubResource every unit SHARES,
## so registering it would put one unit's flash on all of them.
var _effect_material: ShaderMaterial

## The id these materials are registered under, or 0 — which is reserved for
## `SURFACE_MAP` and is never a real `get_instance_id()`.
var _tint_token: int = 0


func _ready() -> void:
	_primary_material = ShaderMaterial.new()
	_primary_material.shader = UNIT_SPRITE_SHADER
	_primary_material.set_shader_parameter("depth_mode", VfxConstants.DepthMode.UNIT)
	_primary_material.set_shader_parameter("color_surface_id", SURFACE_BODY)
	sprite_primary.material_override = _primary_material

	_weapon_material = ShaderMaterial.new()
	_weapon_material.shader = UNIT_SPRITE_SHADER
	_weapon_material.set_shader_parameter("depth_mode", VfxConstants.DepthMode.UNIT)
	_weapon_material.set_shader_parameter("color_surface_id", SURFACE_WEAPON)
	sprite_weapon.material_override = _weapon_material

	# `Unit._enter_tree` fires before this, so the first `bind_tint_surface` only records
	# the id; on a re-entry `_ready` does not run and `_enter_tree` does it all.
	_register_tint_materials()


func set_primary_texture(tex: Texture2D) -> void:
	sprite_primary.texture = tex
	_primary_material.set_shader_parameter("sprite_texture", tex)


func set_weapon_texture(tex: Texture2D) -> void:
	sprite_weapon.texture = tex
	_weapon_material.set_shader_parameter("sprite_texture", tex)


## TacticsG's own single ADDITIVE highlight, which is not a substitute for an effect's
## recolouring: the shaders apply that to the palette entry first, then add this on top.
func set_tint(tint: Vector3) -> void:
	_primary_material.set_shader_parameter("unit_tint", tint)
	_weapon_material.set_shader_parameter("unit_tint", tint)


## Hand over the per-unit duplicate of the EFFECT sprite's material. It goes through here
## rather than straight onto `sprite_effect` so that it is stamped with its part id and
## joins the registration; `initialize_unit()` can re-run, so the material list is rebuilt
## rather than appended to.
func set_effect_material(material: ShaderMaterial) -> void:
	sprite_effect.material_override = material
	_effect_material = material
	if material != null:
		material.set_shader_parameter("color_surface_id", SURFACE_EFFECT)
	if _tint_token != 0:
		bind_tint_surface(_tint_token)


## Register this unit's sprite materials together under `token`.
##
## `token` MUST be `char_body.get_instance_id()`. An effect recolours whichever node the
## cast was handed, and that is always `char_body`, because a `Unit` is never positioned.
## Passing the `Unit`'s own id compiles, runs, and recolours nothing.
##
## Idempotent: re-binding after the material set changes rebuilds rather than grows.
func bind_tint_surface(token: int) -> void:
	if token == TintedSurfacesPort.SURFACE_MAP:
		push_error("UnitSpritesManager: refusing to bind the reserved SURFACE_MAP token "
			+ "%d. `get_instance_id()` never returns it, so this is a caller that has "
			% TintedSurfacesPort.SURFACE_MAP
			+ "no `char_body` and would otherwise fold the MAP's tint onto a unit.")
		return
	if _tint_token != 0 and _tint_token != token:
		unbind_tint_surface()
	if _tint_token == token and is_instance_valid(TintedSurfaces):
		# A rebuild: drop the old material list so a replaced material cannot linger.
		TintedSurfaces.unregister_surface(token)
	_tint_token = token
	_register_tint_materials()


## Drop the registration and clear any colour already applied. `unregister_surface` writes
## an empty ColorStack first, so a unit leaving the tree mid-cast does not keep a tint
## stuck in its shader uniforms.
func unbind_tint_surface() -> void:
	if _tint_token == 0:
		return
	if is_instance_valid(TintedSurfaces):
		TintedSurfaces.unregister_surface(_tint_token)
	_tint_token = 0


## The id anything wanting to recolour this unit passes to `TintedSurfaces`, or 0.
func tint_surface_token() -> int:
	return _tint_token


## Push whichever of the three materials exist. Null-tolerant: which exist depends on how
## far through `_ready` / `initialize_unit` we are.
func _register_tint_materials() -> void:
	if _tint_token == 0 or not is_instance_valid(TintedSurfaces):
		return
	for material: ShaderMaterial in [_primary_material, _weapon_material, _effect_material]:
		if material != null:
			TintedSurfaces.register_surface(_tint_token, material)


func reset_sprites() -> void:
	# reset position
	self.position = Vector3.ZERO
	sprite_item.position = item_initial_pos
	sprite_item.rotation = Vector3.ZERO
	sprite_item.frame = 32
	
	# reset layer priority
	sprite_primary.position.z = -2 * LAYERING_OFFSET
	sprite_weapon.position.z = -3 * LAYERING_OFFSET
	sprite_weapon.frame = (sprite_weapon.hframes * sprite_weapon.vframes) - 1 # TODO fix setting blank, set visible = false?
	#sprite_weapon.visible = false
	sprite_effect.position.z = -1 * LAYERING_OFFSET
	sprite_effect.frame = (sprite_effect.hframes * sprite_effect.vframes) - 1 # TODO fix setting blank, set visible = false?
	#sprite_effect.visible = false
	sprite_text.position.z = 0 * LAYERING_OFFSET
	
	sprite_primary.rotation_degrees.z = 0
	sprite_weapon.rotation_degrees.z = 0
	sprite_effect.rotation_degrees.z = 0
	sprite_text.rotation_degrees.z = 0
	
	# reset flip_h
	sprite_primary.flip_h = false
	sprite_weapon.flip_h = false
	sprite_effect.flip_h = false
	sprite_text.flip_h = false
	
	# reset flip_v
	sprite_primary.flip_v = false
	sprite_weapon.flip_v = false
	sprite_effect.flip_v = false
	sprite_text.flip_v = false


func flip_h() -> void:
	sprite_primary.flip_h = not sprite_primary.flip_h
	sprite_weapon.flip_h = not sprite_weapon.flip_h
	sprite_effect.flip_h = not sprite_effect.flip_h
	sprite_item.flip_h = not sprite_item.flip_h
