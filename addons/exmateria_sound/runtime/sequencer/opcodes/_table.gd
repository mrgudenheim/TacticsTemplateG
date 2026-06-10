class_name SequencerOpcodeTable
## Dictionary[int, Callable] dispatch table — the music-side analog of
## FFT's smd_opcode_jumptable @ 0x80028B0C. One entry per implemented
## opcode byte (0x80..0xFF range); unhandled opcodes route to
## SequencerOpStubNoop.apply.
##
## Refactor Pass 3b: every entry is a `_pt_<hex>` passthrough Callable
## that delegates to the existing `_op_*` method on the sequencer
## instance. Pass 4 migrates each handler body out into its own
## opcodes/<name>.gd file and rebinds the table entry directly to
## `Callable(_<X>, "apply")`.
##
## All `apply` signatures are uniform:
##   func apply(sequencer, ts, params)
##
## sequencer + ts are typed Variant — TrackState is a sequencer inner
## class and can't be preload-imported without a cycle.

const _StubNoop = preload("res://addons/exmateria_sound/runtime/sequencer/opcodes/_stub_noop.gd")

# Migrated cluster — direct preloads of opcodes/<name>.gd.
const _Dynamics = preload("res://addons/exmateria_sound/runtime/sequencer/opcodes/dynamics.gd")
const _VolLfoDepth = preload("res://addons/exmateria_sound/runtime/sequencer/opcodes/vol_lfo_depth.gd")
const _FlagSetE6 = preload("res://addons/exmateria_sound/runtime/sequencer/opcodes/flag_set_e6.gd")
const _Pan = preload("res://addons/exmateria_sound/runtime/sequencer/opcodes/pan.gd")

# Migrated cluster — direct preloads of opcodes/<name>.gd.
const _ConditionalSeqFlag = preload("res://addons/exmateria_sound/runtime/sequencer/opcodes/conditional_seq_flag.gd")
# Pass 7.D.g (§I.2): real 0xD2 handler. The ConditionalSeqFlag binding
# above was based on a misread label; FFT's actual 0xD2 is PitchBendRel.
const _PitchBendRel = preload("res://addons/exmateria_sound/runtime/sequencer/opcodes/pitch_bend_rel.gd")
const _PitchLfoDepth = preload("res://addons/exmateria_sound/runtime/sequencer/opcodes/pitch_lfo_depth.gd")
const _PitchLfoInit = preload("res://addons/exmateria_sound/runtime/sequencer/opcodes/pitch_lfo_init.gd")
const _FlagSetDa = preload("res://addons/exmateria_sound/runtime/sequencer/opcodes/flag_set_da.gd")
const _FlagClearDb = preload("res://addons/exmateria_sound/runtime/sequencer/opcodes/flag_clear_db.gd")

# Migrated cluster — direct preloads of opcodes/<name>.gd.
const _AdsrAttack = preload("res://addons/exmateria_sound/runtime/sequencer/opcodes/adsr_attack.gd")
const _AdsrAttackMode = preload("res://addons/exmateria_sound/runtime/sequencer/opcodes/adsr_attack_mode.gd")
const _AdsrSustainRate = preload("res://addons/exmateria_sound/runtime/sequencer/opcodes/adsr_sustain_rate.gd")
const _AdsrRelease = preload("res://addons/exmateria_sound/runtime/sequencer/opcodes/adsr_release.gd")
const _Adsr1LowNibbleSlide = preload("res://addons/exmateria_sound/runtime/sequencer/opcodes/adsr1_low_nibble_slide.gd")
const _AdsrDecayRate = preload("res://addons/exmateria_sound/runtime/sequencer/opcodes/adsr_decay_rate.gd")
const _AdsrDecaySustain = preload("res://addons/exmateria_sound/runtime/sequencer/opcodes/adsr_decay_sustain.gd")
const _AdsrDecay = preload("res://addons/exmateria_sound/runtime/sequencer/opcodes/adsr_decay.gd")
const _AdsrSustainLevel = preload("res://addons/exmateria_sound/runtime/sequencer/opcodes/adsr_sustain_level.gd")

# Migrated cluster — direct preloads of opcodes/<name>.gd.
const _Instrument = preload("res://addons/exmateria_sound/runtime/sequencer/opcodes/instrument.gd")
const _SlurOn = preload("res://addons/exmateria_sound/runtime/sequencer/opcodes/slur_on.gd")
const _SlurOff = preload("res://addons/exmateria_sound/runtime/sequencer/opcodes/slur_off.gd")
const _ReverbOn = preload("res://addons/exmateria_sound/runtime/sequencer/opcodes/reverb_on.gd")
const _ReverbOff = preload("res://addons/exmateria_sound/runtime/sequencer/opcodes/reverb_off.gd")

# Migrated cluster — direct preloads of opcodes/<name>.gd.
const _TimeSignature = preload("res://addons/exmateria_sound/runtime/shared/opcodes/time_signature.gd")
const _Tempo = preload("res://addons/exmateria_sound/runtime/shared/opcodes/tempo.gd")

# Migrated cluster — direct preloads of opcodes/<name>.gd.
const _Rest = preload("res://addons/exmateria_sound/runtime/sequencer/opcodes/rest.gd")
const _Fermata = preload("res://addons/exmateria_sound/runtime/sequencer/opcodes/fermata.gd")
const _Endbar = preload("res://addons/exmateria_sound/runtime/sequencer/opcodes/endbar.gd")
const _Loop = preload("res://addons/exmateria_sound/runtime/sequencer/opcodes/loop.gd")
const _Octave = preload("res://addons/exmateria_sound/runtime/sequencer/opcodes/octave.gd")
const _RaiseOctave = preload("res://addons/exmateria_sound/runtime/sequencer/opcodes/raise_octave.gd")
const _LowerOctave = preload("res://addons/exmateria_sound/runtime/sequencer/opcodes/lower_octave.gd")
const _Repeat = preload("res://addons/exmateria_sound/runtime/sequencer/opcodes/repeat.gd")
const _Coda = preload("res://addons/exmateria_sound/runtime/sequencer/opcodes/coda.gd")
const _RepeatBreak = preload("res://addons/exmateria_sound/runtime/sequencer/opcodes/repeat_break.gd")

# Bound coverage uplift — shared/opcodes/* bodies routed through
# _dispatch_shared. Each one is FFT-faithful and music can fire it
# (FFT's opcode VM is one table for music + SFX bytecodes alike).
# Music's 4 baselines (MUSIC_10/28/31/34) don't fire most of these,
# but other music files may.
const _SharedSaveLoopTarget = preload("res://addons/exmateria_sound/runtime/shared/opcodes/save_loop_target.gd")
const _SharedByte7a = preload("res://addons/exmateria_sound/runtime/shared/opcodes/byte_7a.gd")
const _SharedByte76 = preload("res://addons/exmateria_sound/runtime/shared/opcodes/byte_76.gd")
const _SharedFmodEnable = preload("res://addons/exmateria_sound/runtime/shared/opcodes/fmod_enable.gd")
const _SharedFmodDisable = preload("res://addons/exmateria_sound/runtime/shared/opcodes/fmod_disable.gd")
const _SharedNoiseEnable = preload("res://addons/exmateria_sound/runtime/shared/opcodes/noise_enable.gd")
const _SharedAdsr1HighArm = preload("res://addons/exmateria_sound/runtime/shared/opcodes/adsr1_high_arm.gd")
const _SharedNoiseEnableNoArm = preload("res://addons/exmateria_sound/runtime/shared/opcodes/noise_enable_no_arm.gd")
const _SharedNoiseDisable = preload("res://addons/exmateria_sound/runtime/shared/opcodes/noise_disable.gd")
const _SharedPitchBendSet = preload("res://addons/exmateria_sound/runtime/shared/opcodes/pitch_bend_set.gd")
const _SharedPitchBendAdd = preload("res://addons/exmateria_sound/runtime/shared/opcodes/pitch_bend_add.gd")
const _SharedPitchBendAdd16bit = preload("res://addons/exmateria_sound/runtime/shared/opcodes/pitch_bend_add_16bit.gd")
const _SharedPortamentoInit = preload("res://addons/exmateria_sound/runtime/shared/opcodes/portamento_init.gd")
const _SharedChan6Bit2Toggle = preload("res://addons/exmateria_sound/runtime/shared/opcodes/chan6_bit2_toggle.gd")
const _SharedDetune = preload("res://addons/exmateria_sound/runtime/shared/opcodes/detune.gd")
const _SharedLfo = preload("res://addons/exmateria_sound/runtime/shared/opcodes/lfo.gd")
const _SharedPortaStop = preload("res://addons/exmateria_sound/runtime/shared/opcodes/porta_stop.gd")
const _SharedDynamicsAdd = preload("res://addons/exmateria_sound/runtime/shared/opcodes/dynamics_add.gd")
const _SharedVolScale = preload("res://addons/exmateria_sound/runtime/shared/opcodes/vol_scale.gd")
const _SharedE5_3param = preload("res://addons/exmateria_sound/runtime/shared/opcodes/e5_3param.gd")
const _SharedClearSubslot1Active = preload("res://addons/exmateria_sound/runtime/shared/opcodes/clear_subslot1_active.gd")
const _SharedPanLfoDepth = preload("res://addons/exmateria_sound/runtime/shared/opcodes/pan_lfo_depth.gd")
const _SharedLfoArmSubslot2 = preload("res://addons/exmateria_sound/runtime/shared/opcodes/lfo_arm_subslot2.gd")
const _SharedPanLfo = preload("res://addons/exmateria_sound/runtime/shared/opcodes/pan_lfo.gd")
const _SharedClearSubslot2 = preload("res://addons/exmateria_sound/runtime/shared/opcodes/clear_subslot2.gd")
const _SharedLfoSubslotSelect = preload("res://addons/exmateria_sound/runtime/shared/opcodes/lfo_subslot_select.gd")
const _SharedLfoSubslotUpdate = preload("res://addons/exmateria_sound/runtime/shared/opcodes/lfo_subslot_update.gd")
const _SharedLfoSubslotDynDepth = preload("res://addons/exmateria_sound/runtime/shared/opcodes/lfo_subslot_dyn_depth.gd")
const _SharedLfoSubslotActivate = preload("res://addons/exmateria_sound/runtime/shared/opcodes/lfo_subslot_activate.gd")
const _SharedLfoSubslotDynDisable = preload("res://addons/exmateria_sound/runtime/shared/opcodes/lfo_subslot_dyn_disable.gd")
const _SharedArmSubslot1PitchLfo = preload("res://addons/exmateria_sound/runtime/shared/opcodes/arm_subslot1_pitch_lfo.gd")
const _SharedInstrumentReload = preload("res://addons/exmateria_sound/runtime/shared/opcodes/instrument_reload.gd")


# Generic adapter for shared/opcodes/*.apply. Music dispatches via
# (sequencer, ts, params); shared/opcodes use (dispatcher, channel,
# slot, OpcodeEvent, voice_writes). This adapter bridges the two —
# bind() in build() pre-binds the shared class + opcode byte per
# table entry. voice_writes is hardcoded true since music channels
# are never silent_driver (that's an SFX-only state).
static func _dispatch_shared(sequencer, ts, params, shared_class, op_byte: int) -> void:
	if ts.ctx == null:
		return
	var op := SMDOpcodes.OpcodeEvent.new()
	op.opcode = op_byte
	op.params = params
	shared_class.apply(sequencer, ts.ctx.channel, ts.ctx.slot, op, true)


# Passthrough trampolines — one per implemented opcode. Each calls the
# matching _op_* method on the sequencer instance. Pass 4 removes
# trampolines as bodies move into opcodes/<name>.gd.



# Cached on first build(). Static — all sequencer instances share it.
static var _TABLE: Dictionary = {}


static func build() -> Dictionary:
	if not _TABLE.is_empty():
		return _TABLE
	_TABLE = {
		0x80: Callable(_Rest, "apply"),
		0x81: Callable(_Fermata, "apply"),
		0x90: Callable(_Endbar, "apply"),
		0x91: Callable(_Loop, "apply"),
		0x94: Callable(_Octave, "apply"),
		0x95: Callable(_RaiseOctave, "apply"),
		0x96: Callable(_LowerOctave, "apply"),
		0x97: Callable(_TimeSignature, "apply"),
		0x98: Callable(_Repeat, "apply"),
		0x99: Callable(_Coda, "apply"),
		0x9A: Callable(_RepeatBreak, "apply"),
		0xA0: Callable(_Tempo, "apply"),
		0xAC: Callable(_Instrument, "apply"),
		0xB0: Callable(_SlurOn, "apply"),
		0xB1: Callable(_SlurOff, "apply"),
		0xBA: Callable(_ReverbOn, "apply"),
		0xBB: Callable(_ReverbOff, "apply"),
		# 0xC0 was originally bound to _AdsrReset which cleared ts.adsr_*
		# _override fields. Those fields were deleted in Pass D2 (ADSR
		# opcodes write channel.adsr1/2 directly now), so the music body
		# would crash if invoked. FFT FUN_8001613c (PC 0x8001613c)
		# disasm reads chan+0x2C as the instrument byte and calls
		# Hyp_instrument_data_loader → InstrumentReload semantic. Rebind
		# to the FFT-faithful shared body.
		0xC0: Callable(SequencerOpcodeTable, "_dispatch_shared").bind(_SharedInstrumentReload, 0xC0),
		0xC2: Callable(_AdsrAttack, "apply"),
		0xC3: Callable(_AdsrDecayRate, "apply"),
		0xC4: Callable(_AdsrSustainRate, "apply"),
		0xC5: Callable(_AdsrRelease, "apply"),
		0xC6: Callable(_Adsr1LowNibbleSlide, "apply"),
		0xC7: Callable(_AdsrDecaySustain, "apply"),
		0xC8: Callable(_AdsrAttackMode, "apply"),
		0xC9: Callable(_AdsrDecay, "apply"),
		0xCA: Callable(_AdsrSustainLevel, "apply"),
		0xD2: Callable(_PitchBendRel, "apply"),
		0xD7: Callable(_PitchLfoDepth, "apply"),
		0xD8: Callable(_PitchLfoInit, "apply"),
		0xDA: Callable(_FlagSetDa, "apply"),
		0xDB: Callable(_FlagClearDb, "apply"),
		0xE0: Callable(_Dynamics, "apply"),
		0xE3: Callable(_VolLfoDepth, "apply"),
		# 0xE4 was originally bound to _VolLfoInit which called the C++
		# mixer.init_voice_volume_lfo path — same C++-engine anti-pattern
		# we migrated music's pitch LFO away from in Pass 7.D.d. FFT's
		# FUN_800166C8 disasm (PC 0x800166c8-0x80016748) explicitly
		# writes channel.lfo_sub_*[1] fields (mode=1 → vol-class LFO via
		# advance_lfo's sub-slot iterator → contributes to chan_88_value
		# which feeds the vol formula's env_sample). Rebind to the FFT-
		# faithful shared body via _dispatch_shared.
		0xE4: Callable(SequencerOpcodeTable, "_dispatch_shared").bind(_SharedArmSubslot1PitchLfo, 0xE4),
		0xE6: Callable(_FlagSetE6, "apply"),
		0xE8: Callable(_Pan, "apply"),
		# --- Coverage uplift: shared/opcodes/* via _dispatch_shared
		# adapter. These were unbound in music (treated as noop via
		# _StubNoop). FFT's bytecode VM is one table for both music
		# and SFX; music bytecodes can fire any of these.
		0x9B: Callable(SequencerOpcodeTable, "_dispatch_shared").bind(_SharedSaveLoopTarget, 0x9B),
		0xA9: Callable(SequencerOpcodeTable, "_dispatch_shared").bind(_SharedByte7a, 0xA9),
		0xAD: Callable(SequencerOpcodeTable, "_dispatch_shared").bind(_SharedByte76, 0xAD),
		0xB2: Callable(SequencerOpcodeTable, "_dispatch_shared").bind(_SharedFmodEnable, 0xB2),
		0xB3: Callable(SequencerOpcodeTable, "_dispatch_shared").bind(_SharedFmodDisable, 0xB3),
		0xB4: Callable(SequencerOpcodeTable, "_dispatch_shared").bind(_SharedNoiseEnable, 0xB4),
		0xB5: Callable(SequencerOpcodeTable, "_dispatch_shared").bind(_SharedAdsr1HighArm, 0xB5),
		0xB6: Callable(SequencerOpcodeTable, "_dispatch_shared").bind(_SharedNoiseEnableNoArm, 0xB6),
		0xB7: Callable(SequencerOpcodeTable, "_dispatch_shared").bind(_SharedNoiseDisable, 0xB7),
		0xD0: Callable(SequencerOpcodeTable, "_dispatch_shared").bind(_SharedPitchBendSet, 0xD0),
		0xD1: Callable(SequencerOpcodeTable, "_dispatch_shared").bind(_SharedPitchBendAdd, 0xD1),
		0xD3: Callable(SequencerOpcodeTable, "_dispatch_shared").bind(_SharedPitchBendAdd16bit, 0xD3),
		0xD4: Callable(SequencerOpcodeTable, "_dispatch_shared").bind(_SharedPortamentoInit, 0xD4),
		0xD5: Callable(SequencerOpcodeTable, "_dispatch_shared").bind(_SharedChan6Bit2Toggle, 0xD5),
		0xD6: Callable(SequencerOpcodeTable, "_dispatch_shared").bind(_SharedDetune, 0xD6),
		0xD9: Callable(SequencerOpcodeTable, "_dispatch_shared").bind(_SharedLfo, 0xD9),
		0xDC: Callable(SequencerOpcodeTable, "_dispatch_shared").bind(_SharedPortaStop, 0xDC),
		0xE1: Callable(SequencerOpcodeTable, "_dispatch_shared").bind(_SharedDynamicsAdd, 0xE1),
		0xE2: Callable(SequencerOpcodeTable, "_dispatch_shared").bind(_SharedVolScale, 0xE2),
		0xE5: Callable(SequencerOpcodeTable, "_dispatch_shared").bind(_SharedE5_3param, 0xE5),
		0xE7: Callable(SequencerOpcodeTable, "_dispatch_shared").bind(_SharedClearSubslot1Active, 0xE7),
		0xEB: Callable(SequencerOpcodeTable, "_dispatch_shared").bind(_SharedPanLfoDepth, 0xEB),
		0xEC: Callable(SequencerOpcodeTable, "_dispatch_shared").bind(_SharedLfoArmSubslot2, 0xEC),
		0xED: Callable(SequencerOpcodeTable, "_dispatch_shared").bind(_SharedPanLfo, 0xED),
		0xEF: Callable(SequencerOpcodeTable, "_dispatch_shared").bind(_SharedClearSubslot2, 0xEF),
		0xF0: Callable(SequencerOpcodeTable, "_dispatch_shared").bind(_SharedLfoSubslotSelect, 0xF0),
		0xF1: Callable(SequencerOpcodeTable, "_dispatch_shared").bind(_SharedLfoSubslotUpdate, 0xF1),
		0xF2: Callable(SequencerOpcodeTable, "_dispatch_shared").bind(_SharedLfoSubslotDynDepth, 0xF2),
		0xF6: Callable(SequencerOpcodeTable, "_dispatch_shared").bind(_SharedLfoSubslotActivate, 0xF6),
		0xF7: Callable(SequencerOpcodeTable, "_dispatch_shared").bind(_SharedLfoSubslotDynDisable, 0xF7),
	}
	return _TABLE


static func dispatch(opcode: int, sequencer, ts, params) -> void:
	## FFT analog: `jal smd_opcode_jumptable[opcode - 0x80]` — indexed
	## lookup → indirect call → unknowns fall to the LAB_8001586c
	## shared stub.
	var table: Dictionary = build()
	var cb: Callable = table.get(opcode, Callable())
	if cb.is_valid():
		cb.call(sequencer, ts, params)
	else:
		_StubNoop.apply(sequencer, ts, params)
