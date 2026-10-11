class_name ScreenBackgroundQuad
extends MeshInstance3D
## TacticsG's background gradient, shaped the way the effects addon requires: a node named
## `ScreenBackground` under the current `Camera3D` whose `material_override` exposes
## `color_tl/tr/bl/br` plus the ColorStack uniforms. Without it the addon push_errors every
## frame and no effect can recolour the background.
##
## It does NOT replace `BattleManager.background_gradient`, a CanvasLayer `TextureRect`
## covering the whole window — this quad paints only inside the battle view, which is a
## SubViewport while the editor is open. `set_gradient()` keeps the two at one colour.

## The addon looks this name up literally, so renaming the node stops every effect from
## recolouring the background — with a push_error as the only symptom.
const NODE_NAME: StringName = &"ScreenBackground"

## The addon autoload that sends us each frame's background colours. Reached by path, not
## by the global identifier, so this script still compiles in a tree that never registered
## it.
const OVERLAY_NODE: NodePath = ^"/root/ScreenEffectOverlay"

const SHADER: Shader = preload("res://src/shaders/screen_background.gdshader")

## The vertex shader bypasses the MVP, so neither value decides what is drawn — they
## only keep the mesh's AABB sane. `extra_cull_margin` is what prevents frustum culling.
const QUAD_SIZE: Vector2 = Vector2(40, 20)
const QUAD_OFFSET_Z: float = -100.0

var _material: ShaderMaterial
var _top: Color = Color.BLACK
var _bottom: Color = Color.BLACK


## Build (or return) the background under `camera`. Idempotent: a second call hands back the
## existing node rather than stacking another opaque fullscreen quad.
static func attach(camera: Camera3D) -> ScreenBackgroundQuad:
	if camera == null:
		return null
	var existing: Node = camera.get_node_or_null(NodePath(NODE_NAME))
	if existing is ScreenBackgroundQuad:
		var found: ScreenBackgroundQuad = existing
		found._prime_overlay()
		return found
	if existing != null:
		# Something else owns the name the addon looks up: it would find that instead, fail
		# the ShaderMaterial cast, and recolour nothing for the rest of the run.
		push_error("ScreenBackgroundQuad: %s already exists under %s and is not one of these"
			% [NODE_NAME, camera.name])
		return null
	var quad := ScreenBackgroundQuad.new()
	quad.name = NODE_NAME
	camera.add_child(quad)
	return quad


func _init() -> void:
	var quad := QuadMesh.new()
	quad.size = QUAD_SIZE
	mesh = quad
	position.z = QUAD_OFFSET_Z
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# The shader throws the MVP away, but the ENGINE still culls the untransformed AABB.
	extra_cull_margin = 16384.0
	_material = ShaderMaterial.new()
	_material.shader = SHADER
	# Cosmetic: the shader's depth write is what orders it.
	_material.render_priority = -100
	# `material_override`, NOT `material`: the addon reads only the former.
	material_override = _material
	_write_corners(_top, _top, _bottom, _bottom)


func _ready() -> void:
	_prime_overlay()


## The two colours `Scenario.background_gradient_top` / `_bottom` carry; the addon wants
## four corners, so each goes to both of its own.
func set_gradient(top: Color, bottom: Color) -> void:
	_top = top
	_bottom = bottom
	var overlay: Node = _overlay()
	if overlay != null:
		# An effect's own colours are applied on top of these and only the difference is
		# sent, so a wrong default mistints every effect too.
		overlay.set_defaults(top, top, bottom, bottom)
		if overlay.is_active():
			# An effect is driving the corners and will rewrite them on its next frame.
			return
	_write_corners(top, top, bottom, bottom)


func gradient_top() -> Color:
	return _top


func gradient_bottom() -> Color:
	return _bottom


## The four corner colours as the material actually holds them — the only way to tell
## "an effect drove the background" from "nothing was written".
func corners() -> PackedColorArray:
	var out := PackedColorArray()
	for key: String in ["color_tl", "color_tr", "color_bl", "color_br"]:
		var v: Variant = _material.get_shader_parameter(key)
		var c := Vector3.ZERO if v == null else (v as Vector3)
		out.append(Color(c.x, c.y, c.z, 1.0))
	return out


## `c_` prefixes because a bare `tr` shadows `Object.tr()`, which this project errors on.
func _write_corners(c_tl: Color, c_tr: Color, c_bl: Color, c_br: Color) -> void:
	_material.set_shader_parameter("color_tl", Vector3(c_tl.r, c_tl.g, c_tl.b))
	_material.set_shader_parameter("color_tr", Vector3(c_tr.r, c_tr.g, c_tr.b))
	_material.set_shader_parameter("color_bl", Vector3(c_bl.r, c_bl.g, c_bl.b))
	_material.set_shader_parameter("color_br", Vector3(c_br.r, c_br.g, c_br.b))


func _overlay() -> Node:
	if not is_inside_tree():
		return null
	var node: Node = get_tree().root.get_node_or_null(OVERLAY_NODE)
	if node == null or not node.has_method(&"set_defaults"):
		# `has_method` is load bearing: the overlay is not @tool, so in the editor the
		# autoload is a placeholder answering to the name with no methods.
		return null
	return node


## Hand the addon this material rather than letting it search for one. Being an autoload,
## its own search goes through `get_viewport().get_camera_3d()` on the ROOT viewport, which
## reports NO camera while `battle_view` sits in the editor's SubViewport. The `in` guards
## fall back to that search if the addon renames these methods, rather than throwing.
func _prime_overlay() -> void:
	var overlay: Node = _overlay()
	if overlay == null:
		return
	if "_material" in overlay and "_initialized" in overlay:
		overlay._material = _material
		overlay._initialized = true
	# This may be the first moment the addon can reach a renderer at all.
	overlay.set_defaults(_top, _top, _bottom, _bottom)
