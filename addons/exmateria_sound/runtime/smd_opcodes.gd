class_name SMDOpcodes
## SMD opcode definitions and track decoder.

# Tick durations indexed by (data_byte % 19). Index 0 = read next byte.
const DELTA_TIME_TABLE: PackedInt32Array = [0, 192, 144, 96, 72, 64, 48, 36, 32, 24, 18, 16, 12, 9, 8, 6, 4, 3, 2]

const PPQ := 48  # Pulses per quarter note

# Opcode -> [name, param_count]
const OPCODE_INFO := {
	# 0x80-0x9F: control flow + structure
	0x80: ["Rest", 1], 0x81: ["Fermata", 1], 0x82: ["NOP", 0],
	0x90: ["EndBar", 0], 0x91: ["Loop", 0],
	0x94: ["Octave", 1], 0x95: ["RaiseOctave", 0], 0x96: ["LowerOctave", 0],
	0x97: ["TimeSignature", 2],
	0x98: ["Repeat", 1], 0x99: ["Coda", 0], 0x9A: ["RepeatBreak", 0],
	0x9B: ["NOP_Sled", 0],                  # FFT LAB_8001586c (jr ra; move v0,a0) — true no-op

	# 0xA0-0xAF: tempo + instrument
	0xA0: ["Tempo", 1], 0xA2: ["TempoSlide", 2],
	0xA9: ["FormulaSelector", 1],           # slot+0x7A → switch case L800156D0
	0xAC: ["Instrument", 1],
	0xAD: ["Byte76_Adjust", 1],             # slot+0x76 sign-extended add (was Unknown_AD)
	0xAE: ["PercussionOn", 0], 0xAF: ["PercussionOff", 0],
	# 0xB0-0xBF: slur, FMod, noise, reverb
	0xB0: ["SlurOn", 0], 0xB1: ["SlurOff", 0],
	0xB2: ["FMod_Enable", 0],               # entity+0x68 |= voice_mask
	0xB3: ["FMod_Disable", 0],              # entity+0x68 &= ~voice_mask
	0xB4: ["Noise_EnableAndClock", 1],      # entity+0x6C |= voice; SPUCNT[8-13] = op&0x3F
	0xB5: ["Noise_ClockAdd", 1],            # slot+0x1E += op (mod 64); re-asserts noise
	0xB6: ["Noise_EnableNoArm", 0],         # entity+0x6C |= voice; chan+0x4 |= 0x10 (no clock write)
	0xB7: ["Noise_Disable", 0],             # entity+0x6C &= ~voice_mask
	0xBA: ["ReverbOn", 0], 0xBB: ["ReverbOff", 0],
	# 0xC0-0xCF: ADSR
	0xC0: ["ADSR_Reset", 0], 0xC2: ["ADSR_Attack", 1],
	0xC3: ["ADSR_DecayRate", 1],            # FFT LAB_800161c4 — chan+0x66 = byte, arm ADSR1_MID
	0xC4: ["ADSR_SustainRate", 1], 0xC5: ["ADSR_Release", 1],
	0xC6: ["ADSR1_LowNibble_SlideTarget", 1],
	0xC7: ["ADSR_DecayAndSustainLevel", 2],
	0xC8: ["ADSR_AttackMode", 1],           # FFT LAB_80016260 — chan+0x58 = byte, arm ADSR1_HIGH (lin/exp)
	0xC9: ["ADSR_Decay", 1], 0xCA: ["ADSR_SustainLevel", 1],
	# 0xD0-0xDF: pitch bend, portamento, LFO sub-slot 0
	0xD0: ["SetPitchBend", 1],
	0xD1: ["AddPitchBend", 1],              # chan+0x86 += sb*32 (accumulating)
	0xD2: ["PitchBendRel", 1],              # §I.2 fix: was ConditionalSeqFlag (misnamed label)
	0xD3: ["PitchBend_Add_16bit", 2],       # chan+0x86 += signed 16-bit (high<<8 | low)
	0xD4: ["Portamento_Init", 2],           # param[0]=target, param[1]=rate
	0xD5: ["Chan6_Bit2_Toggle", 0],         # xori chan+0x6, 0x2
	0xD6: ["Detune", 1],
	0xD7: ["PitchLFO_Depth", 1], 0xD8: ["PitchLFO_Init", 3],
	0xD9: ["PitchLFO_Init_Signed", 3],      # sibling of 0xD8 with sign-preserving rate
	0xDA: ["FlagSet_0xFE", 0], 0xDB: ["FlagClear_0xFE", 0],
	0xDC: ["Portamento_Stop", 0],           # clear chan+0x6 bit 0x1
	# 0xE0-0xEF: dynamics, expression, LFO sub-slot 1
	0xE0: ["Dynamics", 1],
	0xE1: ["Dynamics_Add", 1],              # chan+0x98 += (sb<<24); chan_word_1 |= 0x100
	0xE2: ["Expression_VolBurst", 2],       # arms per-tick vol burst (chan+0xA8)
	0xE3: ["VolumeLFO_Depth", 1],
	0xE4: ["VolumeLFO_Init", 3],
	0xE5: ["VolLFO_Init_SubSlot1", 3],      # arms sub-slot 1 mode 1 (vol-L)
	0xE6: ["LFO_SubSlot1_Activate", 0],     # set chan+0x11E bit 0x1 (was FlagSet_0x11E)
	0xE7: ["LFO_SubSlot1_Disable", 0],      # clear chan+0x11E bit 0x1
	0xE8: ["Pan", 1],
	0xEB: ["PanLFO_Depth", 1],              # chan+0x138/0x13A = 256/(param+1) (sub-slot 2 depth)
	0xEC: ["PanLFO_Arm_SubSlot2", 3],       # sub-slot 2 mode 2, hardcoded callback idx 3
	0xED: ["PanLFO_Init_SubSlot2", 3],      # sub-slot 2 mode 2, callback selected from params
	0xEF: ["LFO_SubSlot2_Disable", 0],      # clear chan+0x13E bit 0x1
	# 0xF0-0xFF: dynamic LFO sub-slot machinery
	0xF0: ["LFO_SubSlot_Select_Init", 3],   # selects sub-slot + arms waveform/mode
	0xF1: ["LFO_SubSlot_Update", 3],        # updates depth + 16b signed rate of selected
	0xF2: ["LFO_SubSlot_DynamicDepth", 2],  # sub[+0x1A]=256/(p1+1); sub[+0x16]=p0
	0xF6: ["LFO_SubSlot_Activate", 1],      # activates sub-slot specified by param[0]
	0xF7: ["LFO_SubSlot_DynamicDisable", 1],# chan[+idx*32]+0xFE &= ~0x1 (dynamic E7/EF)
	0xFE: ["BankSelect", 1],
}

# Opcodes with known param counts but UNIMPLEMENTED at the dispatcher
# level — they fall through to `_op_unhandled` (no-op) but consume the
# correct number of param bytes so the byte stream doesn't desync.
# Arg counts derived from FFT size table at ROM 0x80028d0c (table value - 1).
# None of these are encountered in the post-cad-0 bytecode of any effect
# bin we've parsed (audited 2026-05-21 across all 14 effects/*_no_music.bin).
# Most are music-sequencer opcodes (TimeSignature is in OPCODE_INFO but
# unimplemented too — pure parser entry).
const _EXTRA_OPCODES := {
	0x8A: 0, 0x8D: 1, 0x8E: 3, 0x8F: 0,
	0x9C: 3, 0x9D: 3, 0x9E: 3,
	0xA1: 1, 0xA3: 2, 0xA4: 1, 0xA5: 1, 0xA6: 1, 0xA7: 2, 0xAA: 1,
	0xB8: 3, 0xB9: 1,
	0xC1: 3, 0xCF: 0,
	0xE9: 1, 0xEA: 2, 0xEE: 0,
	0xF4: 1, 0xF5: 1,
	0xF8: 3, 0xF9: 2, 0xFB: 1, 0xFC: 2, 0xFD: 1, 0xFF: 0,
}


class NoteEvent:
	var velocity: int
	var relative_key: int  # 0-11 = C..B, 12 = tie, 13 = rest
	var delta_time: int
	var note_byte: int     # raw bytecode 2nd byte; FFT chan+0x92 source (PC 0x800153C4)

	func is_note() -> bool:
		return relative_key < 12

	func is_tie() -> bool:
		return relative_key == 12

	func is_rest() -> bool:
		return relative_key == 13


class OpcodeEvent:
	var opcode: int
	var params: PackedInt32Array


static func decode_track(data: PackedByteArray, length: int = -1) -> Array:
	## Returns Array of NoteEvent and OpcodeEvent.
	if length < 0:
		length = data.size()

	var events: Array = []
	var pos := 0

	while pos < length:
		var byte := data[pos]
		pos += 1

		if byte < 0x80:
			# Note event
			if pos >= length:
				break
			var data_byte := data[pos]
			pos += 1

			var evt := NoteEvent.new()
			evt.velocity = byte
			evt.note_byte = data_byte
			evt.relative_key = data_byte / 19
			var delta_index := data_byte % 19
			evt.delta_time = DELTA_TIME_TABLE[delta_index]

			if evt.delta_time == 0 and pos < length:
				evt.delta_time = data[pos]
				pos += 1

			events.append(evt)
		else:
			# Control opcode
			var param_count := 0
			if byte in OPCODE_INFO:
				param_count = OPCODE_INFO[byte][1]
			elif byte in _EXTRA_OPCODES:
				param_count = _EXTRA_OPCODES[byte]

			var evt := OpcodeEvent.new()
			evt.opcode = byte
			evt.params = PackedInt32Array()
			for _i in range(param_count):
				if pos >= length:
					break
				evt.params.append(data[pos])
				pos += 1

			events.append(evt)

			if byte == 0x90:  # EndBar
				break

	return events


static func fft_tempo_to_bpm(tempo_val: int) -> float:
	if tempo_val == 0:
		return 120.0
	return (tempo_val * 256.0) / 218.0
