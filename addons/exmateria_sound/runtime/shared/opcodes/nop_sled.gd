class_name SharedOpNopSled
## FFT analog: LAB_8001586C (`jr ra; _move v0, a0`)
##                (jumptable @ 0x80028B78 for 0x9B)
##
## 0x9B is the canonical NOP byte FFT emits in BATTLE.BIN-extracted
## SFX bytecodes (6 hits in global_sfx_bank_cat0001.feds). Routed to
## the same shared no-op handler that 21 other reserved opcode
## jumptable entries point at.

const _CH = preload("res://addons/exmateria_sound/runtime/shared/channel_state.gd")
const _SS = preload("res://addons/exmateria_sound/runtime/shared/slot_state.gd")


static func apply(_dispatcher, _channel: _CH, _slot: _SS,
		_op: SMDOpcodes.OpcodeEvent, _voice_writes: bool) -> void:
	pass
