class_name EmitterKeyframe
extends Resource

@export var time: int = -1 # frames
@export var emitter_id: int = -1
@export var flags: PackedByteArray = []
@export var display_damage: bool = false
@export var status_change: bool = false
@export var target_animation: bool = false
@export var use_global_target: bool = false
@export var callback_slot: int = -1
@export var animation_param: int = 0
var unused_flag_80: bool = false
