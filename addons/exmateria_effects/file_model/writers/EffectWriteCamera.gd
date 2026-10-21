extends RefCounted
## Byte-exact CAMERA-TIMELINE writer for `E###.BIN` (#267) — GDScript port of
## `tools/write_effect_camera.py`.
##
## Three SoA tables (`for_each` / `phase1` / `phase2`) of angle/position/zoom keyframes plus a
## command word. All three base at the header's `timeline_section_ptr` DIRECTLY — NOT `+8` like
## the screen/palette `for_each` channels.
##
## All three zoom slots are written even though only `[0]` is engine-used, so the two
## engine-ignored slots round-trip verbatim. Tables absent from `block` are left untouched, as
## are the trailing bytes past the last table.

const Layout = preload("res://addons/exmateria_effects/file_model/EffectBinLayout.gd")


## Write one camera SoA table's raw arrays into `buf` — the byte-exact inverse of
## `parse_camera_phase_table`. Returns `""` on success, else the refusal message.
##
## THE TABLES ARE FIXED NATIVE-SLOT ARRAYS. ADR-0085's add/delete verbs express a count
## change as a moved `max_keyframe` watermark plus shifted slot contents, never a longer list.
## A table that overflows the native slots — or whose watermark points past them — cannot be
## section-written, because the ROM has no slot to hold it. Refuse loudly rather than silently
## truncate the tail.
static func serialize_table(buf: PackedByteArray, base: int, table: Dictionary,
		offsets: Dictionary) -> String:
	var count: int = int(offsets["count"])
	var keyframes: Array = table["keyframes"]
	if keyframes.size() > count:
		return ("camera table has %d keyframes, over the %d native slots — over-capacity "
			+ "cannot be section-written (ADR-0085 Faithful capacity)") % [keyframes.size(), count]
	var max_kf: int = int(table["max_keyframe"])
	if max_kf < 0 or max_kf >= count:
		return "camera table max_keyframe %d is outside the native slots [0, %d)" % [max_kf, count]

	var off_end: int = int(offsets["end_frame"])
	var off_angle: int = int(offsets["angle"])
	var off_pos: int = int(offsets["position"])
	var off_zoom: int = int(offsets["zoom"])
	var off_cmd: int = int(offsets["command"])
	for i in range(count):
		var kf: Dictionary = keyframes[i]
		buf.encode_u16(base + off_end + i * 2, int(kf["end_frame"]) & 0xFFFF)
		var a: Array = kf["angle"]
		var p: Array = kf["position"]
		var z: Array = kf["zoom"]
		for j in range(3):
			buf.encode_u16(base + off_angle + i * 6 + j * 2, int(a[j]) & 0xFFFF)
			buf.encode_u16(base + off_pos + i * 6 + j * 2, int(p[j]) & 0xFFFF)
			buf.encode_u16(base + off_zoom + i * 6 + j * 2, int(z[j]) & 0xFFFF)
		buf.encode_u16(base + off_cmd + i * 2, int(kf["command_raw"]) & 0xFFFF)

	buf.encode_u16(base + int(offsets["max_keyframe"]), max_kf & 0xFFFF)
	return ""


## Partial-patch the camera SoA tables of `buf` IN PLACE from `block`.
static func patch_into(buf: PackedByteArray, header: Dictionary, block) -> String:
	if not (block is Dictionary):
		return ""
	var timeline_ptr: int = int(header["timeline_section_ptr"])
	for table_name in Layout.CAMERA_TRACK_TABLES:
		if not block.has(table_name):
			continue
		var err: String = serialize_table(buf, timeline_ptr, block[table_name],
			Layout.CAMERA_TRACK_TABLES[table_name])
		if not err.is_empty():
			return "%s: %s" % [table_name, err]
	return ""
