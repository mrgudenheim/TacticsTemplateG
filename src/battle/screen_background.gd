class_name ScreenBackground
extends TextureRect
## The battle's background gradient, and the surface the effects addon recolours. A shader
## draws it from four corner colours `ScreenEffectOverlay` writes; the shipped
## `GradientTexture2D` is the editor preview and the source of the starting colours.

## Reached by path, not the global name, so this compiles where the autoload is absent.
const OVERLAY_NODE: NodePath = ^"/root/ScreenEffectOverlay"

const SHADER: Shader = preload("res://src/shaders/screen_background.gdshader")

var _material: ShaderMaterial


func _ready() -> void:
	_material = ShaderMaterial.new()
	_material.shader = SHADER
	material = _material
	var overlay: Node = _overlay()
	if overlay != null:
		overlay.set_background_material(_material)
	# `Gradient.colors[0]` is the bottom colour and `[1]` is the top.
	var initial: PackedColorArray = (texture as GradientTexture2D).gradient.colors
	if initial.size() >= 2:
		set_gradient(initial[1], initial[0])


## The two colours `Scenario.background_gradient_top` / `_bottom` carry; the addon wants
## four corners, so each goes to both of its own. An effect's own colours are applied on
## top of these and only the difference is sent, so a wrong default mistints every effect.
func set_gradient(top: Color, bottom: Color) -> void:
	var overlay: Node = _overlay()
	if overlay != null:
		overlay.set_default_gradient(top, bottom)
	else:
		_write_corners(top, top, bottom, bottom)


## The four corner colours the material holds.
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
	return get_tree().root.get_node_or_null(OVERLAY_NODE)
