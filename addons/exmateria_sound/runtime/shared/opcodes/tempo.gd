class_name SharedOpTempo
## FFT analog: smd_tempo @ 0x80015CB0
##                (opcode 0xA0)


static func apply(sequencer, ts, params) -> void:
	var tempo_byte: int = int(params[0]) & 0xFF if params.size() > 0 else 0
	sequencer.tempo_bpm = SMDOpcodes.fft_tempo_to_bpm(tempo_byte) if params.size() > 0 else 120.0
	sequencer._update_timing()
	# Pass 8 phase 2 — FFT-faithful smd_tempo writes onto the entity:
	#   smd_tempo @ ram:80015cb0
	#     lh   v1, 0x8a(a1)     ; v1 = entity+0x8a (tick_rate = 0x30/ppqn)
	#     mult v0, v1           ; LO = tempo_byte * tick_rate
	#     sll  v0, v0, 0x10     ; v0 = tempo_byte << 16
	#     sw   v0, 0x7c(a1)     ; entity+0x7c = tempo_byte << 16
	#     mflo v0
	#     sw   v0, 0x78(a1)     ; entity+0x78 = tempo_byte * tick_rate
	# The +0x78 word is the per-IRQ decrement applied to +0x74 by
	# spu_updater_tick's catchup loop. Faster tempo = larger decrement
	# = more catchup iters per IRQ = more bytecode advance per second.
	# Runtime.tick() consumes it; Sequencer.tick() does not (yet).
	if sequencer.music_entity != null:
		var ent = sequencer.music_entity
		ent.tempo_high = (tempo_byte & 0xFFFF) << 16
		ent.sub_tick_budget = (tempo_byte & 0xFFFF) * (ent.tick_rate & 0xFFFF)
