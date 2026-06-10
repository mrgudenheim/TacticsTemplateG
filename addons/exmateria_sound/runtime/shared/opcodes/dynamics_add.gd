class_name SharedOpDynamicsAdd
## FFT analog: smd_dynamics_add @ LAB_80016640
##                (opcode 0xE1)

const _CH = preload("res://addons/exmateria_sound/runtime/shared/channel_state.gd")
const _SS = preload("res://addons/exmateria_sound/runtime/shared/slot_state.gd")
const _Trace = preload("res://addons/exmateria_sound/runtime/effect_sound/trace_writer.gd")
const _ProbeCounters = preload("res://addons/exmateria_sound/runtime/effect_sound/probes/probe_counters.gd")
const _LfoStepCalc = preload("res://addons/exmateria_sound/runtime/shared/helpers/lfo_step_calc.gd")
const _LfoPrng = preload("res://addons/exmateria_sound/runtime/shared/helpers/lfo_prng.gd")


static func apply(_dispatcher, channel: _CH, slot: _SS, op: SMDOpcodes.OpcodeEvent, voice_writes: bool) -> void:
	## Dynamics_Add — opcode 0xE1, FFT smd_dynamics_add at PC 0x80016640.
	## Signed-byte accumulating sibling of 0xE0 Dynamics. FFT body:
	##   lb   v0, 0x0(a0)       ; v0 = signed byte (s8)
	##   lw   v1, 0x98(a2)      ; v1 = chan+0x98 (expression accumulator)
	##   sll  v0, v0, 0x18      ; v0 = sb << 24
	##   addu v0, v0, v1        ; v0 = old + (sb << 24)
	##   and  v0, v0, 0x7FFFFFFF; mask to 31-bit positive
	##   sw   v0, 0x98(a2)      ; chan+0x98 = new
	##   lhu  v0, 0x2(a2)
	##   ori  v0, v0, 0x100     ; chan_word_1 |= 0x100  (vol prestage)
	##   andi v1, v1, 0xfff7    ; chan+0x6 &= ~0x8       (disarm 0xE2 burst)
	##   sh   v0, 0x2(a2); sh v1, 0x6(a2)
	## Differs from 0xE0 in two ways:
	##   1. Accumulates (adds (sb<<24)) instead of overwriting.
	##   2. Param is SIGNED — negative values subtract from chan+0x98.
	## See research/effect_sound/working_documents/ICE_V21_COS_DIST_PHASE_DRIFT_INVESTIGATION.md
	## §"What we don't know" — discovered as a gap when auditing
	## global_sfx_bank_cat0001.feds (3 hits across BATTLE.BIN status SFX).
	_ProbeCounters.opcode_e1_dynamics_add += 1
	var raw: int = (op.params[0] if op.params.size() > 0 else 0) & 0xFF
	var sb: int = raw if raw < 0x80 else raw - 0x100  # sign-extend s8
	_Trace.emit("opcode_e1_dynamics_add", {
		"call_index": _ProbeCounters.opcode_e1_dynamics_add,
		"dynamics_add_byte": sb,
		"channel_idx": channel.channel_idx,
		"voice_writes": 1 if voice_writes else 0,
	})
	if op.params.size() <= 0:
		return
	# Mirror FFT semantics: signed-byte add to the upper byte of the
	# accumulator, mask to 31-bit positive. Wrap the intermediate sum
	# to MIPS 32-bit semantics before masking so signed overflow
	# matches FFT exactly.
	var delta: int = (sb << 24) & 0xFFFFFFFF
	var sum: int = (channel.expression_acc_s32 + delta) & 0xFFFFFFFF
	channel.expression_acc_s32 = sum & 0x7FFFFFFF
	channel.channel_word_1 |= _SS.CHAN1_VOL_PRESTAGE
	# Disarm any in-flight 0xE2 burst (chan+0x6 bit 0x8). Same
	# diag_vol_burst_transition emit as 0xE0 to keep PCSX/Godot
	# probe-pair parity for either disarm path.
	var _was_active_e1: bool = channel.vol_burst_active
	channel.vol_burst_active = false
	if _was_active_e1:
		_ProbeCounters.diag_vol_burst_transition += 1
		_Trace.emit("vol_burst_transition", {
			"call_index": _ProbeCounters.diag_vol_burst_transition,
			"channel_idx": channel.channel_idx,
			"transition": "disarm",
			"cause": "e1",
			"counter": channel.vol_burst_counter,
		})
