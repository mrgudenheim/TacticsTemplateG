class_name MusicChannelContext
## Per-track bridge between music's TrackState facade and the FFT-faithful
## ChannelState + SlotState halfword storage adopted from the SFX side.
##
## Pass 7.A introduces this as a *paired companion* to each music
## TrackState. Pass 7.B–C will migrate music's reads then writes onto
## channel/slot fields; Pass 7.D adopts SFX opcode bodies that already
## write into these. Once the migration is complete, TrackState becomes
## a thin set of accessors that delegate into this context, and the
## music dispatch path looks structurally like SFX's.
##
## Why a context wrapper instead of inheriting from a base or using
## TrackState directly: TrackState has Godot-renderer fields like
## `wait_ticks`, `pitch_lfo_active`, `adsr_*_override` that don't fit
## cleanly into the FFT halfword conventions on ChannelState. Keeping
## TrackState alongside (rather than collapsing it) lets each Pass 7
## sub-pass migrate one read or write at a time and verify Gate A at
## each step without forcing a big-bang rewrite.
##
## Field correspondence (to be wired in Pass 7.B+):
##
##   TrackState                     →  channel/slot equivalent
##   ─────────                          ────────────────────────
##   octave (int)                       channel.octave (= byte << 12 in FFT)
##   pan (int)                          channel.pan_offset_ae
##   volume (int)                       channel.expression_acc_s32
##   instrument (int)                   slot.instrument_idx (via 0xAC reload)
##   wait_ticks (int)                   channel.note_duration
##   current_note (int)                 (re-derived from channel.pitch_state)
##   slur (bool)                        channel.channel_word_0 bit 0x800
##   reverb (bool)                      channel.channel_word_0 bit 0x40
##   adsr_attack_override (int)         channel.adsr1 high byte
##   adsr_release_override (int)        channel.adsr2 low 6 bits
##   pitch_lfo_*                        channel.lfo_sub_*[0..3]
##   flag_0xFE (bool)                   channel.channel_word_FE bit 0
##   flag_0x11E (bool)                  channel.flag_word_11E bit 0
##
## Pass 7.A keeps this class as a plain field carrier — no property
## accessors yet. The accessors land cluster-by-cluster in Pass 7.B/C
## so each one is independently bisectable when Gate A drifts.

const _CH = preload("res://addons/exmateria_sound/runtime/shared/channel_state.gd")
const _SS = preload("res://addons/exmateria_sound/runtime/shared/slot_state.gd")

var channel: _CH = null
var slot: _SS = null


func _init(slot_idx: int = 0) -> void:
	channel = _CH.new(slot_idx)
	slot = _SS.new(slot_idx)

	# Default alignment: music's TrackState defaults differ from
	# ChannelState's FFT-faithful initial values on some fields.
	# Override here (music-only — SFX instances aren't affected).
	#
	# - idle_timeout: ChannelState default is -1 (FFT idle marker);
	#   music's ts.note_ticks_remaining starts at 0. Align so reads
	#   from channel.idle_timeout match the music renderer's tick
	#   gate (`> 0` and `<= 0` both behave as if no note is playing).
	channel.idle_timeout = 0
	# - instrument_idx: ChannelState default is -1 (FFT sentinel);
	#   music's note_handler effectively defaults to WAVESET entry 1
	#   (byte_7A=0 + 1). Align so notes fired before any 0xAC opcode
	#   use the same default.
	channel.instrument_idx = 1
