class_name TextureAnimation
extends Resource

enum AnimType {
	UV,
	PALETTE,
	OTHER,
}

enum AnimTechnique {
	LOOP_FORWARD,
	LOOP_PING_PONG,
	ONE_SHOT_FORWARD,
	ONE_SHOT_REVERSE,
	OTHER,
}

@export var animation_type: AnimType = AnimType.OTHER
@export var anim_technique: AnimTechnique = AnimTechnique.OTHER
@export var is_script_animation: bool = false
@export var num_frames: int = -1
@export var frame_duration: float = -1.0 # seconds

# UV Animation
@export var canvas_position: Vector2i = Vector2i.ONE * -1
@export var canvas_size: Vector2i = Vector2i.ONE * -1
@export var frame1_position: Vector2i = Vector2i.ONE * -1

# Palette Animation
@export var palette_id_to_animate: int = -1
@export var animation_starting_index: int = -1


func _init(fft_texture_animation: FftMapData.TextureAnimationData = null) -> void:
	if fft_texture_animation == null:
		return

	if fft_texture_animation.animation_type == 0:
		animation_type = AnimType.UV
	elif fft_texture_animation.animation_type == 1:
		animation_type = AnimType.PALETTE
	else:
		animation_type = AnimType.OTHER

	if [1, 3].has(fft_texture_animation.anim_technique):
		anim_technique = AnimTechnique.LOOP_FORWARD
	elif [2, 4].has(fft_texture_animation.anim_technique):
		anim_technique = AnimTechnique.LOOP_PING_PONG
	elif [5, 13].has(fft_texture_animation.anim_technique):
		anim_technique = AnimTechnique.ONE_SHOT_FORWARD
	elif [15, 0].has(fft_texture_animation.anim_technique):
		anim_technique = AnimTechnique.ONE_SHOT_REVERSE
	else:
		anim_technique = AnimTechnique.OTHER
	
	if [0, 13, 5, 15].has(fft_texture_animation.anim_technique):
		is_script_animation = true
	
	num_frames = fft_texture_animation.num_frames
	frame_duration = fft_texture_animation.frame_duration / 30.0

	canvas_position.x = fft_texture_animation.canvas_x
	canvas_position.y = fft_texture_animation.canvas_y + (256 * fft_texture_animation.texture_page)
	canvas_size.x = fft_texture_animation.canvas_width
	canvas_size.y = fft_texture_animation.canvas_height
	frame1_position.x = fft_texture_animation.frame1_x
	frame1_position.y = fft_texture_animation.frame1_y + (256 * fft_texture_animation.frame1_texture_page)
	
	palette_id_to_animate = fft_texture_animation.palette_id_to_animate
	animation_starting_index = fft_texture_animation.animation_starting_index
