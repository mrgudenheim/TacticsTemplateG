extends RefCounted
## Parsed camera-subsystem keyframe data (angle, position, zoom). Renamed
## from CameraTrackData as part of the Track→Subsystem migration (#31).
##
## Parses `camera.json` (renamed from `camera_tracks.json` in #31) organized
## by phase table (phase1, for_each, phase2). Keyframes carry a
## `channel_mask` bitmask that selects which of {angle, position, zoom} the
## keyframe activates.

class Keyframe:
	## Single keyframe in a camera phase table
	var index: int = 0
	var end_frame: int = 0
	var angle: Vector3i = Vector3i.ZERO    # pitch, yaw, roll (raw PSX 4096=360)
	var position: Vector3i = Vector3i.ZERO  # X, Y, Z (raw PSX 28 units/tile)
	var zoom: Vector3i = Vector3i.ZERO      # zoom value in [0], others unused
	var command_raw: int = 0
	var channel_mask: int = 0               # bitmask: 1=angle, 2=position, 4=zoom
	var source_mode: String = "TARGET"
	var interpolation: String = "IMMEDIATE"
	var param_index: int = 0
	var flags: int = 0

	static func from_json(data: Dictionary) -> Keyframe:
		var kf = Keyframe.new()
		kf.index = int(data.get("index", 0))
		kf.end_frame = int(data.get("end_frame", 0))
		var angle_arr = data.get("angle", [0, 0, 0])
		kf.angle = Vector3i(int(angle_arr[0]), int(angle_arr[1]), int(angle_arr[2]))
		var pos_arr = data.get("position", [0, 0, 0])
		kf.position = Vector3i(int(pos_arr[0]), int(pos_arr[1]), int(pos_arr[2]))
		var zoom_arr = data.get("zoom", [0, 0, 0])
		kf.zoom = Vector3i(int(zoom_arr[0]), int(zoom_arr[1]), int(zoom_arr[2]))
		kf.command_raw = int(data.get("command_raw", 0))
		kf.channel_mask = int(data.get("channel_mask", 0))
		kf.source_mode = str(data.get("source_mode", "TARGET"))
		kf.interpolation = str(data.get("interpolation", "IMMEDIATE"))
		kf.param_index = int(data.get("param_index", 0))
		kf.flags = int(data.get("flags", 0))
		return kf


class PhaseTable:
	## Collection of keyframes for one phase (phase1, for_each, or phase2).
	var table_name: String = ""
	var max_keyframe: int = 0
	var keyframes: Array = []  # Array of Keyframe

	static func from_json(data: Dictionary, name: String) -> PhaseTable:
		var table = PhaseTable.new()
		table.table_name = name
		table.max_keyframe = int(data.get("max_keyframe", 0))
		var kf_array = data.get("keyframes", [])
		for kf_data in kf_array:
			table.keyframes.append(Keyframe.from_json(kf_data))
		return table

	func get_keyframe(index: int) -> Keyframe:
		if index < 0 or index >= keyframes.size():
			return null
		return keyframes[index]


# Maps phase name to PhaseTable ("phase1", "for_each", "phase2")
var tables: Dictionary = {}


static func from_json(data: Dictionary):
	"""Parse camera.json into CameraData."""
	var script = load("res://addons/exmateria_effects/file_model/CameraData.gd")
	var camera_data = script.new()
	for table_name in ["phase1", "for_each", "phase2"]:
		if data.has(table_name):
			var table = PhaseTable.from_json(data[table_name], table_name)
			camera_data.tables[table_name] = table
	return camera_data


func get_table(name: String) -> PhaseTable:
	"""Get phase table by name, or null if not present"""
	return tables.get(name)


func has_table(name: String) -> bool:
	"""Check if phase table exists"""
	return tables.has(name)


func has_active_keyframes() -> bool:
	"""Check if any table has active keyframes (max_keyframe > 0)"""
	for table in tables.values():
		if table.max_keyframe > 0:
			return true
	return false
