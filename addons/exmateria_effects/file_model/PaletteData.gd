extends RefCounted
## Parsed palette-subsystem keyframe data (channels 0-2: affected_units, caster,
## target). Renamed from PaletteTrackData as part of the Track→Subsystem
## migration (#31).
##
## Parses the on-disk JSON (`palette.json`, renamed from `palette_tracks.json`
## in #31) organized by timeline phase (for_each, phase1, phase2) and
## channel (affected_units, caster, target).
##
## Key differences from ScreenData:
## - RGB values (0-255) not start/end pairs
## - 11 blend modes (0-10) vs screen's FADE/TINT
## - Enable flag is bit 7 of ctrl (not mode selector)

const EffectPhaseClass = preload("res://addons/exmateria_effects/cast/EffectPhase.gd")


class Keyframe:
	## Single keyframe in a palette channel
	var index: int = 0
	var time_value: int = 0
	var duration_frames: int = 1
	var rgb: Vector3i = Vector3i.ZERO  # RGB 0-255
	var ctrl: int = 0
	var enabled: bool = false  # bit 7 of ctrl
	var blend_mode: int = 0  # bits 0-6 of ctrl

	static func from_json(data: Dictionary) -> Keyframe:
		var kf = Keyframe.new()
		kf.index = int(data.get("index", 0))
		kf.time_value = int(data.get("time_value", 0))
		kf.duration_frames = int(data.get("duration_frames", 1))
		# RGB as Vector3i (0-255)
		var rgb_arr = data.get("rgb", [0, 0, 0])
		kf.rgb = Vector3i(rgb_arr[0], rgb_arr[1], rgb_arr[2])
		kf.ctrl = int(data.get("ctrl", 0))
		kf.enabled = data.get("enabled", false)
		kf.blend_mode = int(data.get("blend_mode", 0))
		return kf


class Channel:
	## Collection of keyframes for one channel in one phase
	var context: String = EffectPhaseClass.PHASE_FOR_EACH
	var channel_name: String = "affected_units"  # affected_units, caster, target
	var keyframes: Array = []  # Array of Keyframe
	var max_keyframe: int = 0

	static func from_json(data: Dictionary) -> Channel:
		var channel = Channel.new()
		channel.context = data.get("context", EffectPhaseClass.PHASE_FOR_EACH)
		channel.channel_name = data.get("channel_name", "affected_units")
		channel.max_keyframe = int(data.get("max_keyframe", 0))
		var kf_array = data.get("keyframes", [])
		for kf_data in kf_array:
			channel.keyframes.append(Keyframe.from_json(kf_data))
		return channel

	func get_keyframe(index: int) -> Keyframe:
		if index < 0 or index >= keyframes.size():
			return null
		return keyframes[index]


# Channel names (the three palette channels: affected_units, caster, target)
const AFFECTED_UNITS = "affected_units"
const CASTER = "caster"
const TARGET = "target"

const ALL_CHANNELS = [AFFECTED_UNITS, CASTER, TARGET]

# Maps phase -> channel_name -> Channel
var channels: Dictionary = {}


static func from_json(data: Dictionary):
	"""Parse palette.json into PaletteData (renamed from palette_tracks.json
	in #31; re-run the parser with --force to regenerate the asset tree)."""
	var script = load("res://addons/exmateria_effects/file_model/PaletteData.gd")
	var palette_data = script.new()

	for context in EffectPhaseClass.ALL:
		if data.has(context):
			var context_data = data[context]
			palette_data.channels[context] = {}
			for channel_name in ALL_CHANNELS:
				if context_data.has(channel_name):
					var channel = Channel.from_json(context_data[channel_name])
					palette_data.channels[context][channel_name] = channel

	return palette_data


func get_channel(context: String, channel_name: String) -> Channel:
	"""Get channel by phase context and name, or null if not present"""
	if not channels.has(context):
		return null
	var context_channels = channels[context]
	if not context_channels.has(channel_name):
		return null
	return context_channels[channel_name]


func has_channel(context: String, channel_name: String) -> bool:
	"""Check if channel exists for phase context and name"""
	if not channels.has(context):
		return false
	return channels[context].has(channel_name)
