extends RefCounted
## Semantic callback metadata for editor/parser surfaces.
## Runtime instantiation stays in CallbackRegistry; this registry tells authoring tools
## which emitter fields/tables a callback-backed emitter event exposes.

const EffectsContent = preload("res://addons/exmateria_effects/install/EffectsContent.gd")

const ACTION_SELECTOR_MASK := 0x07

const UNKNOWN_KIND := "unknown_callback"
const NOT_CALLBACK_CHOICE := {"value": 0, "label": "Not callback", "tooltip": "Spawn ordinary particles; do not invoke a callback slot."}

## The PSX ABR names, indexed by the two-bit selector. The bit PLACEMENT is refereed on
## the ROM — both callback families build the prim word identically, `(param & 3) << 5 |
## 0x86` into tpage+0x1a with `param & 4` clearing the command byte's ABE bit (clear means
## semi-transparency ON): E015 FUN_801c39f8 for the radial stack (emitter+0x24) and E015
## FUN_801c4fc8 for the screen flash (emitter+0x4C), byte-for-byte the same construction.
## The blend ARITHMETIC per value is the PSX hardware convention, not something either
## routine shows — which is why the deleted `blend_mode_choices()` could label ABR 0
## "additive" and nothing caught it.
const _ABR_NAMES := ["B/2+F/2", "B+F additive", "B−F subtractive", "B+F/4 additive quarter"]

# The ROM clamps the ordering-table index into this window before `AddPrim`.
const _OT_INDEX_MIN := 1
const _OT_INDEX_MAX := 0x17F

const _SCHEMAS := {
	"world_tube": {
		"kind": "world_tube",
		"label": "Radial stack",
		"class_name": "WorldTubeCallback",
		"callback_ids": [2, 4, 5, 6, 7, 8, 22, 29, 32, 34, 38, 55, 56],
		"row_field": "vel_spread_start[2]",
		"row_source": {"bag": "raw_data", "key": "vel_spread_start", "index": 2},
		"tables": ["brightness_table"],
		"params": [
			{"label": "Attach to", "bag": "packed", "key": "emitter_anchor_mode", "format": "anchor", "field": "emitter_anchor_mode", "editor": "enum", "choices": "anchor_mode"},
			{"label": "Offset start X", "bag": "raw_data", "key": "position_start", "index": 0, "format": "signed", "field": "position_start_x", "type": "s16"},
			{"label": "Offset start Y", "bag": "raw_data", "key": "position_start", "index": 1, "format": "signed", "field": "position_start_y", "type": "s16"},
			{"label": "Offset start Z", "bag": "raw_data", "key": "position_start", "index": 2, "format": "signed", "field": "position_start_z", "type": "s16"},
			{"label": "Offset end X", "bag": "raw_data", "key": "position_end", "index": 0, "format": "signed", "field": "position_end_x", "type": "s16"},
			{"label": "Offset end Y", "bag": "raw_data", "key": "position_end", "index": 1, "format": "signed", "field": "position_end_y", "type": "s16"},
			{"label": "Offset end Z", "bag": "raw_data", "key": "position_end", "index": 2, "format": "signed", "field": "position_end_z", "type": "s16"},
			{"label": "PSX blend code", "bag": "raw_data", "key": "spread_start", "index": 2, "format": "abr_blend"},
			{"label": "Core radius · start", "bag": "callback_params", "key": "param_A8", "format": "fixed4096", "field": "callback_param_A8", "type": "s16"},
			{"label": "Core radius · end (curve-dependent)", "bag": "callback_params", "key": "param_AC", "format": "fixed4096", "field": "callback_param_AC", "type": "s16"},
			{"label": "Spin speed · start", "bag": "raw_data", "key": "radial_min_start", "format": "signed", "field": "radial_velocity_min_start", "type": "s16"},
			{"label": "Spin speed · end (curve-dependent)", "bag": "raw_data", "key": "radial_min_end", "format": "signed", "field": "radial_velocity_min_end", "type": "s16"},
			{"label": "UV width", "bag": "raw_data", "key": "spread_start", "index": 0, "format": "pixels", "field": "spread_start_x", "type": "s16"},
			{"label": "UV wrap height", "bag": "raw_data", "key": "spread_start", "index": 1, "format": "pixels", "field": "spread_start_y", "type": "s16"},
			{"label": "UV offset U · start", "bag": "raw_data", "key": "angle_start", "index": 0, "format": "signed", "field": "velocity_base_angle_start_x", "type": "s16"},
			{"label": "UV offset V · start", "bag": "raw_data", "key": "angle_start", "index": 1, "format": "signed", "field": "velocity_base_angle_start_y", "type": "s16"},
			{"label": "UV offset U · end", "bag": "raw_data", "key": "angle_end", "index": 0, "format": "signed", "field": "velocity_base_angle_end_x", "type": "s16"},
			{"label": "UV offset V · end", "bag": "raw_data", "key": "angle_end", "index": 1, "format": "signed", "field": "velocity_base_angle_end_y", "type": "s16"},
			{"label": "UV scroll speed", "bag": "raw_data", "key": "angle_start", "index": 2, "format": "signed", "field": "velocity_base_angle_start_z", "type": "s16"},
			{"label": "Radius growth acceleration · start", "bag": "raw_data", "key": "accel_min_start", "index": 0, "format": "signed", "field": "acceleration_min_start_x", "type": "s16"},
			{"label": "Section spacing · start", "bag": "raw_data", "key": "accel_min_start", "index": 1, "format": "signed", "field": "acceleration_min_start_y", "type": "s16"},
			{"label": "Radius step per section · start", "bag": "raw_data", "key": "accel_min_start", "index": 2, "format": "signed", "field": "acceleration_min_start_z", "type": "s16"},
			{"label": "Radius growth acceleration · end", "bag": "raw_data", "key": "accel_min_end", "index": 0, "format": "signed", "field": "acceleration_min_end_x", "type": "s16"},
			{"label": "Section spacing · end", "bag": "raw_data", "key": "accel_min_end", "index": 1, "format": "signed", "field": "acceleration_min_end_y", "type": "s16"},
			{"label": "Radius step per section · end", "bag": "raw_data", "key": "accel_min_end", "index": 2, "format": "signed", "field": "acceleration_min_end_z", "type": "s16"},
			{"label": "Radius growth speed · start", "bag": "raw_data", "key": "drag_min_start", "index": 0, "format": "signed", "field": "drag_min_start_x", "type": "s16"},
			{"label": "Radius growth speed · end", "bag": "raw_data", "key": "drag_min_end", "index": 0, "format": "signed", "field": "drag_min_end_x", "type": "s16"},
		],
		"texture_fields": [],
		"curves": [
			{"label": "Offset curve", "field": "curve_position"},
			{"label": "Spin curve", "field": "curve_radial_velocity"},
			{"label": "Core radius curve", "field": "curve_callback_world_tube_base_radius"},
			{"label": "Section shape curve", "field": "curve_acceleration"},
			{"label": "Radius growth curve", "field": "curve_drag"},
		],
		"preview": "world_tube",
	},
	"dome_shell": {
		"kind": "dome_shell",
		"label": "Dome shell",
		"class_name": "E071Callback",
		"callback_ids": [27, 33],
		"row_field": "vel_spread_start[2]",
		"row_source": {"bag": "raw_data", "key": "vel_spread_start", "index": 2},
		"tables": ["brightness_table"],
		"params": [
			{"label": "Brightness row", "bag": "raw_data", "key": "vel_spread_start", "index": 2, "format": "row", "field": "velocity_direction_spread_start_z", "type": "s16"},
			{"label": "Core radius", "bag": "callback_params", "key": "param_A8", "format": "fixed4096", "field": "callback_param_A8", "type": "s16"},
			{"label": "UV width", "bag": "raw_data", "key": "spread_start", "index": 0, "format": "pixels", "field": "spread_start_x", "type": "s16"},
			{"label": "UV wrap height", "bag": "raw_data", "key": "spread_start", "index": 1, "format": "pixels", "field": "spread_start_y", "type": "s16"},
		],
		"texture_fields": [],
		"curves": [],
		"preview": "dome_9x16",
	},
	"screen_grid_flash": {
		"kind": "screen_grid_flash",
		"label": "Screen flash",
		"class_name": "ScreenGridCallback",
		"callback_ids": [9, 15, 16, 20, 25, 26, 28, 31, 57, 60, 68, 110, 149],
		"row_field": "param_4E",
		"tables": ["brightness_table"],
		# A callback-owned emitter is not a particle emitter: the same 196 bytes are the
		# effect's own parameter block, so `position_start` here is a UV ORIGIN and
		# `weight_min_start` is an ordering-table index. The field refs still route through
		# EmitterChannel's particle-named writers — which also refresh a converted cache in
		# tile/angle units that means nothing to this callback. Harmless (ScreenGridCallback
		# reads `raw_data`, never the cache) and deliberately not "corrected": the units on
		# THESE rows are the callback's, per `tools/effect_callback_semantics.py`.
		"params": [
			{"label": "PSX blend code", "bag": "callback_params", "key": "param_4C", "format": "abr_blend"},
			{"label": "Attach to", "bag": "packed", "key": "emitter_anchor_mode", "format": "screen_pinned_anchor"},
			{"label": "Brightness row", "bag": "callback_params", "key": "param_4E", "format": "row", "field": "callback_param_4E", "type": "u8"},
			{"label": "UV origin X", "bag": "raw_data", "key": "position_start", "index": 0, "format": "pixels", "field": "position_start_x", "type": "s16"},
			{"label": "UV origin Y", "bag": "raw_data", "key": "position_start", "index": 1, "format": "pixels", "field": "position_start_y", "type": "s16"},
			{"label": "UV window width", "bag": "callback_params", "key": "param_A8", "format": "halved_pixels", "field": "callback_param_A8", "type": "s16"},
			{"label": "UV window height", "bag": "callback_params", "key": "param_AA", "format": "halved_pixels", "field": "callback_param_AA", "type": "s16"},
			{"label": "Scroll speed · start", "bag": "raw_data", "key": "radial_min_start", "format": "signed", "field": "radial_velocity_min_start", "type": "s16"},
			{"label": "Scroll speed · end", "bag": "raw_data", "key": "radial_min_end", "format": "signed", "field": "radial_velocity_min_end", "type": "s16"},
			{"label": "Scroll direction · start", "bag": "raw_data", "key": "angle_start", "index": 1, "format": "signed", "field": "velocity_base_angle_start_y", "type": "s16"},
			{"label": "Scroll direction · end", "bag": "raw_data", "key": "angle_end", "index": 1, "format": "signed", "field": "velocity_base_angle_end_y", "type": "s16"},
			{"label": "Draw order", "bag": "direct", "key": "weight_min_start", "format": "ot_index"},
			{"label": "Flash envelope", "bag": "color_curves", "key": "rgb", "format": "curve_triplet"},
		],
		"texture_fields": [],
		"curves": [
			{"label": "Scroll speed curve", "field": "curve_radial_velocity"},
			{"label": "Scroll direction curve", "field": "curve_velocity_base_angle"},
		],
		"preview": "screen_grid_4x4",
	},
	# TRAP handlers lifted into E### form (ADR-0369). Godot-only ids (1000 + handler);
	# the params are callback_params' four editable s16 slots — no ROM byte layout.
	"trap_charge_lines": {
		"kind": "trap_charge_lines",
		"label": "TRAP charge lines",
		"class_name": "TrapChargeLineCallback",
		"callback_ids": [1004],
		"row_field": "",
		"tables": [],
		"params": [
			{"label": "Ring radius (screen px)", "bag": "callback_params", "key": "param_A8", "format": "signed", "field": "callback_param_A8", "type": "s16"},
			{"label": "Contraction time (ticks)", "bag": "callback_params", "key": "param_AA", "format": "signed", "field": "callback_param_AA", "type": "s16"},
			{"label": "Max concurrent lines", "bag": "callback_params", "key": "param_AC", "format": "signed", "field": "callback_param_AC", "type": "s16"},
			{"label": "Convergence height (PSX units)", "bag": "callback_params", "key": "param_AE", "format": "signed", "field": "callback_param_AE", "type": "s16"},
			{"label": "Line colour", "bag": "color_curves", "key": "rgb", "format": "curve_triplet"},
		],
		"texture_fields": [],
		"curves": [],
		"preview": "unknown",
	},
	"trap_orbital": {
		"kind": "trap_orbital",
		"label": "TRAP summon orbs",
		"class_name": "TrapOrbitalCallback",
		"callback_ids": [1022],
		"row_field": "",
		"tables": [],
		"params": [
			{"label": "Orbit height (PSX units)", "bag": "callback_params", "key": "param_A8", "format": "signed", "field": "callback_param_A8", "type": "s16"},
			{"label": "Ramp-up frames", "bag": "callback_params", "key": "param_AA", "format": "signed", "field": "callback_param_AA", "type": "s16"},
			{"label": "Fade frames", "bag": "callback_params", "key": "param_AC", "format": "signed", "field": "callback_param_AC", "type": "s16"},
			{"label": "Ring count", "bag": "callback_params", "key": "param_AE", "format": "signed", "field": "callback_param_AE", "type": "s16"},
		],
		"texture_fields": [],
		"curves": [],
		"preview": "unknown",
	},
}


static func schema_for_callback_id(callback_id: int) -> Dictionary:
	for key in _SCHEMAS:
		var schema: Dictionary = _SCHEMAS[key]
		if callback_id in schema.get("callback_ids", []):
			return schema.duplicate(true)
	return {
		"kind": UNKNOWN_KIND,
		"label": "Unknown callback",
		"class_name": "",
		"callback_ids": [callback_id],
		"row_field": "",
		"tables": [],
		"params": [],
		"texture_fields": [],
		"preview": "unknown",
	}


static func slot_for_action_flags(action_flags: int) -> int:
	return int(action_flags) & ACTION_SELECTOR_MASK


static func callback_id_for_slot(effect_data, selector_slot: int) -> int:
	if effect_data == null or selector_slot <= 0:
		return -1
	var loaded_slot := selector_slot - 1
	for entry in effect_data.callback_slots:
		if int(entry.get("slot", -1)) == loaded_slot:
			return int(entry.get("callback_id", -1))
	return -1


static func event_view(effect_data, action_flags: int) -> Dictionary:
	var slot := slot_for_action_flags(action_flags)
	if slot == 0:
		return {"slot": 0, "callback_id": -1, "schema": {}, "label": "Not callback"}
	var cb_id := callback_id_for_slot(effect_data, slot)
	var schema := schema_for_callback_id(cb_id) if cb_id >= 0 else schema_for_callback_id(-1)
	var label := "%s · CB%02d" % [str(schema.get("label", "Unknown callback")), cb_id] if cb_id >= 0 else "Unknown callback slot %d" % slot
	return {"slot": slot, "callback_id": cb_id, "schema": schema, "label": label}


static func callback_data(effect_data, callback_id: int) -> Dictionary:
	if effect_data == null or callback_id < 0:
		return {}
	var path := EffectsContent.callback_data_path(str(effect_data.name), callback_id)
	if path.is_empty() or not FileAccess.file_exists(path):
		return {}
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var txt := f.get_as_text()
	f.close()
	var j := JSON.new()
	if j.parse(txt) != OK or not (j.data is Dictionary):
		return {}
	return j.data


static func selected_row(emitter, schema: Dictionary) -> int:
	if emitter == null:
		return -1
	var source: Dictionary = schema.get("row_source", {})
	if not source.is_empty():
		return int(_read_emitter_value(emitter, source, -1))
	var row_field := str(schema.get("row_field", ""))
	if row_field.is_empty() or not emitter.callback_params.has(row_field):
		return -1
	return int(emitter.callback_params.get(row_field, -1))


static func semantic_param_rows(emitter, emitter_index: int, schema: Dictionary) -> Array:
	var out: Array = []
	if emitter == null:
		return out
	for spec in schema.get("params", []):
		if not (spec is Dictionary):
			continue
		var raw = _read_emitter_value(emitter, spec, null)
		var formatted := _format_value(raw, str(spec.get("format", "raw")))
		var tooltip := "%s.%s%s raw=%s" % [str(spec.get("bag", "")), str(spec.get("key", "")),
			("[%d]" % int(spec.get("index", -1))) if spec.has("index") else "", str(raw)]
		if spec.has("field"):
			var row := {
				"name": "%s · %s" % [str(spec.get("label", spec.get("key", "Param"))), formatted],
				"shape": "edit", "editor": str(spec.get("editor", "int")), "type": str(spec.get("type", "s16")),
				"value": int(raw) if raw != null else 0,
				"field_ref": {"channel": "emitter", "emitter_index": emitter_index, "field": str(spec["field"])},
				"tooltip": tooltip,
			}
			if str(spec.get("choices", "")) == "anchor_mode":
				row["choices"] = anchor_mode_choices()
			out.append(row)
		else:
			out.append({
				"name": str(spec.get("label", spec.get("key", "Param"))),
				"shape": "const",
				"value": formatted,
				"tooltip": tooltip,
			})
	return out


static func anchor_mode_choices() -> Array:
	return [
		{"value": 0, "label": "WORLD"},
		{"value": 1, "label": "CURSOR"},
		{"value": 2, "label": "ORIGIN"},
		{"value": 3, "label": "TARGET"},
		{"value": 4, "label": "PARENT"},
		{"value": 5, "label": "CAMERA"},
		{"value": 6, "label": "TRACKED"},
	]



static func _read_emitter_value(emitter, spec: Dictionary, fallback = 0):
	var bag_name := str(spec.get("bag", "callback_params"))
	var key := str(spec.get("key", ""))
	if bag_name == "packed" and key == "emitter_anchor_mode":
		return (int(emitter.raw_data.get("animation_target_flag", 0)) >> 1) & 0x7
	# `weight`/`inertia` never reach `raw_data`: EffectReadEmitters parses them to raw
	# ATTRIBUTES (EffectEmitter.weight_min_start) because the particle physics formula
	# consumes them unconverted. `EmitterChannel._DIRECT` writes them the same way.
	if bag_name == "direct":
		var direct = emitter.get(key)
		return direct if direct != null else fallback
	if bag_name == "color_curves":
		return [int(emitter.color_curves.get("r", -1)), int(emitter.color_curves.get("g", -1)),
			int(emitter.color_curves.get("b", -1))]
	var bag: Dictionary = emitter.callback_params if bag_name == "callback_params" else emitter.raw_data
	if key.is_empty() or not bag.has(key):
		return fallback
	var val = bag.get(key)
	if spec.has("index"):
		var idx := int(spec.get("index", -1))
		if val is Array and idx >= 0 and idx < val.size():
			return val[idx]
		return fallback
	return val


static func _format_value(raw, fmt: String) -> String:
	if raw == null:
		return "missing"
	if fmt == "curve_triplet":
		if not (raw is Array) or raw.size() < 3:
			return "missing"
		var parts: Array[String] = []
		for i in 3:
			parts.append("none" if int(raw[i]) < 0 else str(int(raw[i])))
		return "r/g/b curves %s (edit on the colour track)" % "/".join(parts)
	var v := int(raw)
	match fmt:
		"anchor": return ["WORLD", "CURSOR", "ORIGIN", "TARGET", "PARENT", "CAMERA", "TRACKED"][clampi(v, 0, 6)]
		"screen_pinned_anchor":
			return "%s (not honoured — this callback pins to the camera)" % \
				["WORLD", "CURSOR", "ORIGIN", "TARGET", "PARENT", "CAMERA", "TRACKED"][clampi(v, 0, 6)]
		"abr_blend":
			var txt := "%d → ABR %d · %s (not previewed; drawn additive)" % [v, v & 3, _ABR_NAMES[v & 3]]
			if (v & 4) != 0:
				txt += " · opaque (ABE off)"
			return txt
		"ot_index":
			return "%d → OT bucket %d (not honoured — our depth is a constant, #1530)" % [
				v, clampi(v, _OT_INDEX_MIN, _OT_INDEX_MAX)]
		"hex": return "0x%02X" % v
		"fixed4096": return "%d (%.3f × 4096)" % [v, float(v) / 4096.0]
		"pixels": return "%d px" % v
		"halved_pixels":
			# `ScreenGridCallback.halve_toward_zero` owns this rule — PSX `(x - (x >> 31)) >> 1`,
			# which truncates rather than floors. No corpus emitter carries a negative wrap, so
			# the signed branch exists to keep the two spellings from disagreeing, not for data.
			return "%d → %d px (halved toward zero)" % [v, -((-v) >> 1) if v < 0 else v >> 1]
		"row": return "row %d" % v
		"signed": return "%+d" % v
	return str(raw)


static func table_row(effect_data, callback_id: int, table_name: String, row_index: int) -> Array:
	if row_index < 0:
		return []
	var data := callback_data(effect_data, callback_id)
	var table: Array = data.get(table_name, [])
	if row_index >= table.size():
		return []
	var row = table[row_index]
	return row if row is Array else []


static func slot_choices(effect_data) -> Array:
	var out: Array = [NOT_CALLBACK_CHOICE.duplicate(true)]
	if effect_data == null:
		return out
	for entry in effect_data.callback_slots:
		var loaded_slot := int(entry.get("slot", -1))
		var cb_id := int(entry.get("callback_id", -1))
		if loaded_slot < 0:
			continue
		var selector_slot := loaded_slot + 1
		var schema := schema_for_callback_id(cb_id)
		var label := "%s · CB%02d" % [str(schema.get("label", "Unknown callback")), cb_id]
		out.append({
			"value": selector_slot,
			"label": label,
			"tooltip": "Callback selector %d invokes loaded slot %d; writes action_flags low selector bits" % [selector_slot, loaded_slot],
			"callback_id": cb_id,
			"kind": schema.get("kind", UNKNOWN_KIND),
		})
	return out
