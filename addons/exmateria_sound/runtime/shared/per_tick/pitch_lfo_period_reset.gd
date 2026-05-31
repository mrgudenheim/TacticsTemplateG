class_name SharedPerTickPitchLfoPeriodReset
## FFT analog: pitch_lfo_period_reset @ FUN_80016DC0 (PC 0x80016DC0-E8)
##
## Single-sub-slot helper called by arm opcodes after they seed
## depth_reload (chan+0x1A) and delay_reload (chan+0x16). Writes 5
## sub-slot fields atomically per the FFT body:
##   sub+0x04 (accumulator)       = 0
##   sub+0x10 (countdown)         = 1
##   sub+0x14 (delay_counter)     = sub+0x16 (delay_reload)
##   sub+0x18 (depth)             = sub+0x1A (depth_reload / our depth_delta)
##   sub+0x1E (active_dir)       &= ~0xC  (clear bits 0x4 + 0x8)
##
## NOT the same as `lfo_period_reset.gd` — that's the per-tick note-on
## reset gated at FUN_8001517C PC 0x800157AC. This helper mirrors the
## function FFT calls from the LFO arm opcodes (D8 / D9 / E4 / EC / F2 /
## F6 etc.). See MUSIC_ITER36_PITCH_LFO_DEPTH_EXPOSED_BUGS.md §4.

const _CH = preload("res://addons/exmateria_sound/runtime/shared/channel_state.gd")


static func apply(channel: _CH, sub_idx: int) -> void:
	if sub_idx < 0 or sub_idx >= _CH.LFO_SUB_SLOT_COUNT:
		return
	channel.lfo_sub_accumulator[sub_idx] = 0
	channel.lfo_sub_countdown[sub_idx] = 1
	channel.lfo_sub_delay_counter[sub_idx] = channel.lfo_sub_delay_reload[sub_idx]
	channel.lfo_sub_depth[sub_idx] = channel.lfo_sub_depth_delta[sub_idx]
	channel.lfo_sub_dir_flags[sub_idx] = channel.lfo_sub_dir_flags[sub_idx] & 0xF3
