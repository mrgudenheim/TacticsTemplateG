extends RefCounted
## Parsed screen-subsystem keyframe data — background color animation.
## Renamed from ScreenTrackData as part of the Track→Subsystem migration (#31).
##
## Parses the on-disk JSON (`screen.json`, renamed from `screen_tracks.json` in
## #31) organized by timeline phase (for_each, phase1, phase2). Screen has
## a single implicit channel — the whole screen — so there is one Channel per
## phase context.

const _Self = preload("res://addons/exmateria_effects/file_model/ScreenData.gd")

const EffectPhaseClass = preload("res://addons/exmateria_effects/cast/EffectPhase.gd")


# Screen tween kinds (ADR-0071 / CONTEXT "Blend / Gradient"). BLEND (ctrl bit-7
# set, on-disk "TINT") recolors the whole backdrop through one of 11 blend modes;
# GRADIENT (ctrl bit-7 clear, on-disk "FADE") sets the two stops to explicit top/
# bottom colors — a real write, not a no-op. On-disk labels stay "TINT"/"FADE" (the
# parser output); this enum carries the corrected names. Ordinals unchanged.
enum ScreenMode { GRADIENT, BLEND }


static func parse_mode(mode_str: String) -> ScreenMode:
	match mode_str:
		"TINT": return ScreenMode.BLEND
		_: return ScreenMode.GRADIENT


## Inverse of parse_mode — the on-disk label for a ScreenMode (BLEND → "TINT",
## GRADIENT → "FADE"), so a written screen.json matches the parser's output.
static func mode_to_string(mode: int) -> String:
	return "TINT" if mode == ScreenMode.BLEND else "FADE"


class Keyframe:
	## Single keyframe in the screen channel
	var index: int = 0
	var time_value: int = 0
	var duration_frames: int = 1
	var start_color: Color = Color.BLACK
	var end_color: Color = Color(0.5, 0.5, 0.5)  # 128/255 = neutral gray
	var mode: int = _Self.ScreenMode.GRADIENT
	var blend_mode: int = 0
	var ctrl: int = 0
	# Raw unsigned byte values (0-255) for PSX signed-char interpretation. Both
	# stops are RETAINED (not just start) so the model can write a faithful
	# screen.json back — the authoritative bytes the BIN writer serializes (#254).
	var start_r_raw: int = 0
	var start_g_raw: int = 0
	var start_b_raw: int = 0
	var end_r_raw: int = 128
	var end_g_raw: int = 128
	var end_b_raw: int = 128
	# AUTHORING-ONLY session stash (ADR-0087 dec. 11, the ADR-0085 anchor_offset
	# pattern): the pre-disable bytes the screen Enabled toggle restores on re-enable. Rides
	# the keyframe OBJECT (so insert/delete renumbers can't orphan it; delete drops it; a
	# fresh parse — effect load — starts clean) and is NEVER serialized: to_json/the BIN
	# writer read only the raw fields above, so a disabled tween saves as its identity
	# no-op bytes — what plays IS what saves. Empty = no stash (a cold no-op).
	var disabled_stash: Dictionary = {}

	static func from_json(data: Dictionary) -> Keyframe:
		var kf = Keyframe.new()
		kf.index = int(data.get("index", 0))
		kf.time_value = int(data.get("time_value", 0))
		kf.duration_frames = int(data.get("duration_frames", 1))
		# Store raw unsigned bytes for signed interpretation in TINT mode
		kf.start_r_raw = int(data.get("start_r", 0))
		kf.start_g_raw = int(data.get("start_g", 0))
		kf.start_b_raw = int(data.get("start_b", 0))
		kf.end_r_raw = int(data.get("end_r", 128))
		kf.end_g_raw = int(data.get("end_g", 128))
		kf.end_b_raw = int(data.get("end_b", 128))
		# RGB 0-255 to Color 0-1
		kf.start_color = Color(
			kf.start_r_raw / 255.0,
			kf.start_g_raw / 255.0,
			kf.start_b_raw / 255.0,
			1.0
		)
		kf.end_color = Color(
			kf.end_r_raw / 255.0,
			kf.end_g_raw / 255.0,
			kf.end_b_raw / 255.0,
			1.0
		)
		kf.mode = _Self.parse_mode(data.get("mode", "FADE"))
		kf.blend_mode = int(data.get("blend_mode", 0))
		kf.ctrl = int(data.get("ctrl", 0))
		return kf

	## Inverse of from_json: the on-disk keyframe dict (flat fields, the raw bytes
	## verbatim). Mirrors parse_effect's per-keyframe output so a written screen.json
	## round-trips to the same file it was loaded from.
	func to_json() -> Dictionary:
		return {
			"index": index,
			"time_value": time_value,
			"duration_frames": duration_frames,
			"start_r": start_r_raw,
			"start_g": start_g_raw,
			"start_b": start_b_raw,
			"end_r": end_r_raw,
			"end_g": end_g_raw,
			"end_b": end_b_raw,
			"ctrl": ctrl,
			"mode": _Self.mode_to_string(mode),
			"blend_mode": blend_mode,
		}


class Channel:
	## The screen's single implicit channel — keyframes for one phase. Screen
	## has only one channel (the whole screen), so this inner class is also
	## effectively the phase block's content for screen.
	var context: String = EffectPhaseClass.PHASE_FOR_EACH
	var keyframes: Array = []  # Array of Keyframe
	var max_keyframe: int = 0

	static func from_json(data: Dictionary) -> Channel:
		var channel = Channel.new()
		channel.context = data.get("context", EffectPhaseClass.PHASE_FOR_EACH)
		channel.max_keyframe = int(data.get("max_keyframe", 0))
		var kf_array = data.get("keyframes", [])
		for kf_data in kf_array:
			channel.keyframes.append(Keyframe.from_json(kf_data))
		return channel

	func get_keyframe(index: int) -> Keyframe:
		if index < 0 or index >= keyframes.size():
			return null
		return keyframes[index]

	## Inverse of from_json: the on-disk channel dict (context, max_keyframe, and
	## the 33 keyframes as flat dicts).
	func to_json() -> Dictionary:
		var kfs := []
		for kf in keyframes:
			kfs.append(kf.to_json())
		return {"context": context, "max_keyframe": max_keyframe, "keyframes": kfs}


# Maps phase context name to Channel (one channel per phase since screen is
# single-channel; the dict-of-Channel mirrors PaletteData's dict-of-{channel→Channel}
# shape while collapsing the inner per-channel dimension).
var channels_by_context: Dictionary = {}


static func from_json(data: Dictionary):
	"""Parse screen.json into ScreenData (renamed from screen_tracks.json
	in #31; re-run the parser with --force to regenerate)."""
	var script = load("res://addons/exmateria_effects/file_model/ScreenData.gd")
	var screen_data = script.new()
	for context in EffectPhaseClass.ALL:
		if data.has(context):
			var channel = Channel.from_json(data[context])
			screen_data.channels_by_context[context] = channel
	return screen_data


## Inverse of from_json: the screen.json dict (one block per present context, in
## for_each / phase1 / phase2 order). The game→JSON half of the byte-perfect save
## loop; the CLI writer lowers this to the E###.BIN screen section.
func to_json() -> Dictionary:
	var out := {}
	for context in channels_by_context:
		out[context] = channels_by_context[context].to_json()
	return out


func get_channel(context: String) -> Channel:
	"""Get the screen's channel for the given phase context, or null."""
	return channels_by_context.get(context)


func has_channel(context: String) -> bool:
	"""Check if the screen has a channel for the given phase context."""
	return channels_by_context.has(context)
