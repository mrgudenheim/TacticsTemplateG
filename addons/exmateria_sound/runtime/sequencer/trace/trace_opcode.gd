class_name SequencerTraceOpcode
## Opcode-dispatch trace emit + lookup helpers.
##
## `trace_opcode` mirrors the row shape used by per-opcode dispatch
## counters in `workspace/regression/sequencer_refactor_baseline/`. Every
## sequencer opcode handler should call this BEFORE mutating TrackState
## so the trace records the dispatch even if the body early-exits.

const _TraceWriter = preload("res://addons/exmateria_sound/runtime/sequencer/trace/trace_writer.gd")


static func opcode_name(op: int) -> String:
	if SMDOpcodes.OPCODE_INFO.has(op):
		return String(SMDOpcodes.OPCODE_INFO[op][0])
	return "Unknown_%02X" % op


static func params_to_array(params: PackedInt32Array) -> Array:
	var out: Array = []
	for value in params:
		out.append(value)
	return out


static func trace_opcode(sequencer, ts, event) -> void:
	_TraceWriter.trace(sequencer, ts, "opcode", {
		"opcode": event.opcode,
		"opcode_name": opcode_name(event.opcode),
		"params": params_to_array(event.params),
	})
