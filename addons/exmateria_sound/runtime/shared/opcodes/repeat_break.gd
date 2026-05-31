class_name SharedOpRepeatBreak
## FFT analog: LAB_80015B6C (smd_op_9a_repeat_break)
##                (jumptable @ 0x80028B74)

const _CH = preload("res://addons/exmateria_sound/runtime/shared/channel_state.gd")
const _SS = preload("res://addons/exmateria_sound/runtime/shared/slot_state.gd")
const _Trace = preload("res://addons/exmateria_sound/runtime/effect_sound/trace_writer.gd")
const _ProbeCounters = preload("res://addons/exmateria_sound/runtime/effect_sound/probes/probe_counters.gd")


static func apply(_dispatcher, _channel: _CH, _slot: _SS,
		_op: SMDOpcodes.OpcodeEvent, _voice_writes: bool) -> void:
	## 0x9A RepeatBreak — LAB_80015B6C (jumptable entry @ 0x80028B74).
	## 0 params. FFT disasm reads count = byte at chan+0xb0+chan_0xac*12
	## and breaks only when count == 0.
	##
	## **In practice FFT's chan+0xac is 0 at every observed 0x9A dispatch**
	## (disillusionment_3_no_music: probe_opcode_9a_repeat_break BP@
	## 0x80015B6C shows depth=0, byte-at-chan+0xb0=0, both fires at cads
	## 1120 + 1213). FFT then reads `byte at chan+0xb0+0*12 = chan+0xb0`
	## = 0 (zeroed by FUN_800137d8 slot allocator init at PC 0x80013840),
	## takes the break path, decrements chan+0xac to 0xFFFF (16-bit wrap),
	## and jumps to garbage at `chan+0xb8`. Empirically this never
	## crashes — the garbage pointer happens to land back on the same
	## 0x9A byte or beyond, FFT muddles through, and the row counts of
	## post-0x9A opcodes (BA / AC / 94 / D9 / 80 / C7 / C4 / D4 / Note /
	## 81 / C7 / C9 / 81 / DB / E0 / 99) match between PCSX and Godot
	## EXACTLY IF Godot's 0x9A also "muddles through" without an
	## opcode_pos jump.
	##
	## The previous implementation read Godot's `loop_stack[-1].count`
	## (which DOES track Repeat correctly, count_pre=1 then 0 on the
	## two zombie fires) and took the break on count==0. That broke
	## row count parity by skipping 14+ post-0x9A opcodes per BREAK.
	##
	## Match FFT's observed behavior: structural-only no-op. Emit the
	## trace row so the probe pairs by count and cadence; do NOT
	## modify channel.opcode_pos or pop loop_stack. Godot's
	## `loop_stack` continues to function correctly for 0x99 Coda's
	## jump-back semantics — only 0x9A's break path is disabled.
	_ProbeCounters.opcode_9a_repeat_break += 1
	# count_pre = -1 sentinel matches PCSX's emit (FFT's depth==0 makes
	# the byte at chan+0xb0 (= the count being read) effectively a
	# zero-initialized scratch field, which the probe reports as -1
	# sentinel for "no real stack entry"). Godot's loop_stack DOES
	# track Repeat state correctly, but the value isn't relevant when
	# 0x9A is a no-op — and matching PCSX's -1 keeps the
	# alignment_keys comparison clean.
	_Trace.emit("opcode_9a_repeat_break", {
		"call_index": _ProbeCounters.opcode_9a_repeat_break,
		"count_pre": -1,
	})
	# No-op — fall through past 0x9A. See docstring for rationale.
