class_name SequencerOpFermata
## FFT analog: smd_fermata @ LAB_8001588c
##                (opcode 0x81)


static func apply(_sequencer, ts, params) -> void:
	# Pass 7.D — FFT chan+0x78 idle_timeout += byte.
	ts.ctx.channel.idle_timeout += params[0] if params.size() > 0 else 0
