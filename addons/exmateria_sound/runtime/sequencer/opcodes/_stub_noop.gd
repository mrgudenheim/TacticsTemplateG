class_name SequencerOpStubNoop
## Fallback handler invoked when `_OpcodeTable.dispatch` looks up an
## opcode byte that has no entry in `_TABLE`. The FFT analog is
## LAB_8001586c — the shared opcode jumptable fallthrough that simply
## returns without touching channel state.
##
## sequencer.gd's _process_opcode already emits the trace row + handles
## the disabled_opcodes early-return, so this handler genuinely is a
## no-op (no side effects, no logging).


static func apply(_sequencer, _ts, _params) -> void:
	pass
