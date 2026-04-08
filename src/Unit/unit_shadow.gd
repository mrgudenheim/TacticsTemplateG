extends Sprite3D
## Sets up multiply-blend shadow shader for correct depth sorting.

const SHADOW_SHADER = preload("res://src/Unit/shaders/unit_shadow.gdshader")

func _ready() -> void:
	var mat := ShaderMaterial.new()
	mat.shader = SHADOW_SHADER
	mat.set_shader_parameter("shadow_texture", texture)
	mat.set_shader_parameter("depth_bias", VfxConstants.DEPTH_BIAS_SHADOW)
	material_override = mat
