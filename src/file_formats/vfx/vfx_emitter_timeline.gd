class_name EmitterTimeline
extends Resource

# 128 bytes, 25 keyframes
# https://ffhacktics.com/wiki/Effect_File_Timeline#Section_5:_Particle_Channel_Structure_(128_Bytes)

var bytes: PackedByteArray = []
@export var times: PackedInt32Array = []
@export var emitter_ids: PackedInt32Array = []
@export var action_flags: PackedByteArray = []
var num_keyframes: int = 0

@export var keyframes: Array[EmitterKeyframe] = []
var has_unknown_flags: bool = false


func _init(new_bytes: PackedByteArray = []) -> void:
	if new_bytes.is_empty():
		return

	bytes = new_bytes
	# Layout: 25×u16 times (0x00), first emitter_id = 0 then 24×u8 emitter_ids (0x32), 25×u16 action_flags (0x4a), u16 num_kf (0x7E)
	action_flags = bytes.slice(0x4a, 0x4a + 50)
	num_keyframes = bytes.decode_s16(0x7E)

	for idx: int in 25:
		var time: int = bytes.decode_u16(idx * 2)
		times.append(time)

		var emitter_id: int = 0
		if idx > 0:
			emitter_id = bytes.decode_u8(0x31 + idx)
			emitter_ids.append(emitter_id)

		var action_flag: int = action_flags.decode_u16(idx * 2)
		# if not [0, 0x1000, 0x2000, 0x3000, 0x4000, 0x5000, 0x6000, 0x7000].has(action_flag):
		# 	has_unknown_flags = true
		# push_warning(action_flag)

		var new_keyframe: EmitterKeyframe = EmitterKeyframe.new()
		new_keyframe.time = time
		new_keyframe.emitter_id = emitter_id
		new_keyframe.flags = action_flags.slice(idx * 2, (idx + 1) * 2)
		new_keyframe.display_damage = action_flag & 0x1000 == 0x1000
		new_keyframe.status_change = action_flag & 0x2000 == 0x2000
		new_keyframe.target_animation = action_flag & 0x4000 == 0x4000
		new_keyframe.use_global_target = action_flag & 0x0800 == 0x0800
		new_keyframe.callback_slot = ((action_flag & 0x0700) >> 8) - 1 # will give -1 if not using callback
		new_keyframe.animation_param = action_flag & 0x00FF

		new_keyframe.unused_flag_80 = action_flag & 0x8000 == 0x8000

		keyframes.append(new_keyframe)
