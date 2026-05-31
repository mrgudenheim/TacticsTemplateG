class_name SharedOpStubNoop
## FFT analog: LAB_8001586c (`jr ra; move v0,a0`) — the shared true
## no-op handler that 21 reserved opcode jumptable entries point at.
## See ARCHITECTURE_MAP.md and the smd_opcode_jumptable disassembly
## at ram:80028b0c.
##
## In the Godot port this also serves as the fallback for the `_:`
## match arm — every byte without a registered handler routes here.


static func apply(_dispatcher, _channel, _slot, _op, _voice_writes: bool) -> void:
	pass
