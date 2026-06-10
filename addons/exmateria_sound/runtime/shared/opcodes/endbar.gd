class_name SharedOpEndbar
## FFT analog: smd_end_bar @ LAB_800158F8
##                (jumptable @ 0x80028B4C)

const _CH = preload("res://addons/exmateria_sound/runtime/shared/channel_state.gd")
const _SS = preload("res://addons/exmateria_sound/runtime/shared/slot_state.gd")
const _Trace = preload("res://addons/exmateria_sound/runtime/effect_sound/trace_writer.gd")
const _ProbeCounters = preload("res://addons/exmateria_sound/runtime/effect_sound/probes/probe_counters.gd")


static func apply(_dispatcher, channel: _CH, slot: _SS,
		_op: SMDOpcodes.OpcodeEvent, _voice_writes: bool) -> void:
	# probe_opcode_endbar (GOLD #5). Mirror of FFT BP @ 0x800158F8. FFT
	# branch decision: is_loop_active = (slot+0x1C != 0); Godot equivalent
	# is channel.saved_loop_target_pos != 0 (per ARCHITECTURE_MAP.md).
	_ProbeCounters.opcode_endbar += 1
	_Trace.emit("opcode_endbar", {
		"call_index": _ProbeCounters.opcode_endbar,
		"is_loop_active": 1 if channel.saved_loop_target_pos != 0 else 0,
	})
	## EndBar — LAB_800158F8 (jumptable 0x80028B4C). 0 params.
	## The actual 0x90 handler at L800158F8:
	##   if slot+0x1c (= channel.saved_loop_target_pos) != 0:
	##     slot+0x28 += 1  ; loop iteration count++ (no Godot
	##                     ; analog yet)
	##     skip clear
	##   else:
	##     clear slot+0x2 bits 0x1+0x2 (FLAG_PRIMARY_KON+
	##                                  SECONDARY_KON)
	##     build KOFF mask (no Godot analog needed — KOFF flow
	##                      elsewhere)
	##     L800159CC: slot+0x0 = 0  ; THE CLEARER
	if channel.saved_loop_target_pos != 0:
		# Loop-skip path (mirror L80015908..L8001591C): just
		# don't clear. slot+0x28 increment is unmodeled (no
		# Godot analog field; loop iteration counting isn't
		# currently used by any flush logic).
		pass
	else:
		# Clear path (mirror L80015924..L800159CC).
		slot.flag_word &= ~(_SS.FLAG_PRIMARY_KON | _SS.FLAG_SECONDARY_KON)
		channel.channel_word_0 = 0
		# Also clear slot.active_word bit 0x1. FFT's L800159CC
		# writes `sh zero, 0x0(a2)` where a2 = per-channel ptr
		# = slot+0x0 — the SAME field that the walker
		# (FUN_80014590 ram:80014638) and FUN_80015138 state-
		# advance gate on. Godot artificially split slot+0x0
		# into channel.channel_word_0 (consumed by dispatcher
		# entry gate) and slot.active_word (consumed by walker
		# at spu_irq_walker.gd). Clear the slot side so the
		# walker gate activates and silent-driver slots stop
		# iterating after EndBar — matching FFT exactly.
		slot.active_word &= ~0x1
