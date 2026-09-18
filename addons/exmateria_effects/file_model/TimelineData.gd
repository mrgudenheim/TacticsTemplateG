extends RefCounted
## Timeline data container - controls emitter start/stop timing
##
## The timeline determines when emitters START and STOP spawning particles.
## Each channel processes keyframes independently, and multiple channels can
## be active simultaneously (spawning different emitters).
## Vault: [[Effect Execution Model]]

const EffectPhaseClass = preload("res://addons/exmateria_effects/cast/EffectPhase.gd")


class Keyframe:
	## A single keyframe in a timeline channel
	var time: int = 0           # Frame when keyframe activates
	var emitter_id: int = 0     # 0=skip, N=spawn emitter (N-1)
	var action_flags: int = 0   # Game event triggers (not implemented)
	# Session-only stash for the studio Enabled toggle (ADR-0089 particle_timeline): disabling
	# a span moves emitter_id → 0 (the ROM's only "off"), remembering the prior N here so the
	# span stays drawn dimmed + re-enables losslessly. NEVER serialized — a saved-disabled span
	# reloads as an ordinary gap (emitter_id conflates value and enable, no spare bit).
	var remembered_emitter_id: int = 0

	static func from_json(data: Dictionary) -> Keyframe:
		var kf = Keyframe.new()
		kf.time = int(data.get("time", 0))
		kf.emitter_id = int(data.get("emitter_id", 0))
		kf.action_flags = int(data.get("action_flags", 0))
		return kf


class Channel:
	## A timeline channel - processes keyframes independently
	var context: String = EffectPhaseClass.PHASE_FOR_EACH
	var channel_index: int = 0            # 0-4 for particle channels
	var keyframes: Array[Keyframe] = []
	var max_keyframe: int = 0             # Last valid keyframe index

	static func from_json(data: Dictionary) -> Channel:
		var ch = Channel.new()
		ch.context = data.get("context", EffectPhaseClass.PHASE_FOR_EACH)
		ch.channel_index = int(data.get("channel_index", 0))
		ch.max_keyframe = int(data.get("max_keyframe", 0))

		# Parse keyframes
		var kf_array = data.get("keyframes", [])
		for kf_data in kf_array:
			ch.keyframes.append(Keyframe.from_json(kf_data))

		return ch


# Header data
var header: Dictionary = {}

# Phase timing (exposed for ParticleSubsystem)
var phase1_duration: int = 0   # Frames until phase1 ends and for_each starts
var spawn_delay: int = 0       # Delay between spawns for multi-target effects
var phase2_delay: int = 0      # Delay from for_each start until phase2 starts

# All channels organized by context
var channels_by_context: Dictionary = {}  # context -> Array[Channel]


static func from_json(data: Dictionary):
	"""Parse timeline.json into TimelineData"""
	var script = load("res://addons/exmateria_effects/file_model/TimelineData.gd")
	var tl = script.new()

	# Store header and extract phase timing
	tl.header = data.get("header", {})
	tl.phase1_duration = int(tl.header.get("phase1_duration", 0))
	tl.spawn_delay = int(tl.header.get("spawn_delay", 0))
	tl.phase2_delay = int(tl.header.get("phase2_delay", 0))

	# Parse channels and organize by context
	var channels_array = data.get("particle_channels", [])
	for ch_data in channels_array:
		var channel = Channel.from_json(ch_data)

		# Initialize context array if needed
		if not tl.channels_by_context.has(channel.context):
			tl.channels_by_context[channel.context] = []

		tl.channels_by_context[channel.context].append(channel)

	return tl


func get_channels(context: String) -> Array:
	"""Get all channels for a specific context (e.g., 'for_each')"""
	return channels_by_context.get(context, [])
