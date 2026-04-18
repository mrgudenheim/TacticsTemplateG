extends Sprite3D
## Sets up PSX depth-sorted multiply shader for the drop shadow.

const SHADOW_SHADER = preload("res://src/shaders/psx_depth_multiply.gdshader")

func _ready() -> void:
	var mat := ShaderMaterial.new()
	mat.shader = SHADOW_SHADER
	mat.set_shader_parameter("sprite_texture", texture)
	mat.set_shader_parameter("depth_mode", VfxConstants.DepthMode.UNIT)
	material_override = mat
