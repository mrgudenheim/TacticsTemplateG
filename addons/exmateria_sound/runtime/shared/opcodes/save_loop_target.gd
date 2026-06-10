class_name SharedOpSaveLoopTarget
## FFT analog: smd_loop @ LAB_800159DC (alias smd_save_loop_target)
##                (jumptable @ 0x80028B50)

const _CH = preload("res://addons/exmateria_sound/runtime/shared/channel_state.gd")
const _SS = preload("res://addons/exmateria_sound/runtime/shared/slot_state.gd")


static func apply(_dispatcher, channel: _CH, slot: _SS,
		_op: SMDOpcodes.OpcodeEvent, _voice_writes: bool) -> void:
	## SaveLoopTarget — LAB_800159DC (jumptable 0x80028B50).
	## 0 params. Mirror L800159DC:
	##   sw v0, 0x1c(a2)  ; slot+0x1c = next-opcode-ptr (caller a0)
	##   sb v1, 0x2b(a2)  ; slot+0x2b = byte at slot+0x7e
	## In Godot, "next-opcode-ptr" is just the current opcode_pos
	## (pointer is post-0x91, which is where the dispatcher's
	## opcode_pos already points after consuming 0x91). Any
	## non-zero value works for the EndBar predicate; we use the
	## actual position for fidelity.
	channel.saved_loop_target_pos = channel.opcode_pos
	if channel.saved_loop_target_pos == 0:
		# opcode_pos==0 would never happen in practice, but
		# guard the predicate's "!= 0" semantics — set to 1 as
		# a marker.
		channel.saved_loop_target_pos = 1
	slot.byte_2b = slot.byte_7e & 0xFF
