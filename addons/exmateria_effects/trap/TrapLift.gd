extends RefCounted
## TRAP → E### lift (ADR-0369). A TRAP handler is CODE in the ROM — a charge-effect
## handler that spawns from 0x2E-byte configs at 0x801b8564 on hardcoded ticks — so no
## E###.BIN exists for it. This builds the E### form of one handler IN MEMORY: an
## EffectData the ordinary runtime (EffectInstance) and the Effect Studio read unchanged.
## Godot-only: nothing here writes a BIN, and a lifted document's Save is disabled.
##
## What each piece of handler code becomes:
##   spawn ticks + max_particles cap  → for_each particle-channel spans + a count curve
##   0x2E config                      → an EffectEmitter with FLAT curves, spawn_model TRAP
##   element / per-handler CLUT       → one frameset GROUP per CLUT row (anim_param)
##   flash RGB 0xFF (2× overbright)    → flat 255 colour curves
##   white flash (inline, §14)        → a target palette track (mode 5 snap, mode 8 fade)
##   sounds 0x6A/0xDB/0xB8/0xDC/0x28  → sound lanes + 3 containers (silent: no FEDS bank)
##   handler 13's rising +0x0C        → a linear position curve
##   handlers 4 / 22 (procedural)     → callbacks TrapChargeLine / TrapOrbital
##
## HANDLER NUMBERING: the g_charge_effect_handlers[] FUNCTION IDS 2–22 (the vault), not parse_trap_effect.py's charge_effect_handler_N ordinals 1–5.
##
## ELEMENT is a document SETTING, not part of the id: one document per handler variant,
## and set_element re-points the element-driven CLUT groups and line colour in place, so
## edits carry across elements.
##
## TIME: a TRAP slot counts an animation frame's duration down by 1 per tick, E### by 2
## per frame (ParticleAnimator), so lifted durations are doubled to keep the TRAP pacing.
## Referee: the live melee capture in TRAP_HIT_CLOUD_RENDER_PARITY.md (colour, variant,
## spawn counts). The hand-written TrapEffect this replaced was retired on that evidence.
## No class_name (ADR-0004).
## Vault: [[Footstep Dust Particle System]]
## Vault: [[Footstep Hard Surface Particle System]]
## Vault: [[Unit White Flash Reaction Handler]]

const EffectData = preload("res://addons/exmateria_effects/file_model/EffectData.gd")
const EffectEmitter = preload("res://addons/exmateria_effects/file_model/EffectEmitter.gd")
const EffectCurve = preload("res://addons/exmateria_effects/file_model/EffectCurve.gd")
const TimelineData = preload("res://addons/exmateria_effects/file_model/TimelineData.gd")
const PaletteData = preload("res://addons/exmateria_effects/file_model/PaletteData.gd")
const EffectsContent = preload("res://addons/exmateria_effects/install/EffectsContent.gd")
const CallbackRegistry = preload("res://addons/exmateria_effects/callbacks/CallbackRegistry.gd")
const EffectTimeline = preload("res://addons/exmateria_effects/cast/EffectTimeline.gd")
const TextureTga = preload("res://addons/exmateria_effects/file_model/TextureTga.gd")

const PsxMagnitude = ExMateriaPlatform.PsxMagnitude

const DOCUMENT_PREFIX := "TRAP_"
const ELEMENT_NAMES: Array[String] = ["none", "fire", "lightning", "ice", "wind", "earth",
	"water", "holy", "dark"]

## Callback ids for the two procedural handlers — Godot-only, above the ROM's 2..197.
const CB_CHARGE_LINES := CallbackRegistry.CB_TRAP_CHARGE_LINES
const CB_ORBITAL := CallbackRegistry.CB_TRAP_ORBITAL

## Handler 17's element → CLUT row (DAT_801b88dc: elements 1–5 → 0x7ACA–0x7ACE).
const ELEMENT_PARTICLE_PALETTES := {1: 10, 2: 11, 3: 12, 4: 13, 5: 14}
## Flash configs render 2× overbright (the handler writes RGB 0xFF after spawn).
const OVERBRIGHT_CONFIGS: Array[int] = [1, 9, 11]
const FLASH_PALETTE := 10
## A palette rule is an int CLUT row or ELEMENT (the dust rule: row = element index).
const ELEMENT := -1
const ELEMENT_17 := -2

## THE LIFT TABLE — handler → configs (with their CLUT rule) + the code-only extras.
## Variant "h02m" is handler 2 with sub-type 3: flash config 9, no white flash (§14).
const HANDLERS := {
	"h02": {"handler": 2, "label": "Hit Clouds", "element": true, "white_flash": true,
		"sounds": true, "configs": [[0, ELEMENT], [1, FLASH_PALETTE]]},
	"h02m": {"handler": 2, "label": "Hit Clouds (sub-type 3)", "element": true,
		"sounds": true, "configs": [[0, ELEMENT], [9, FLASH_PALETTE]]},
	"h03": {"handler": 3, "label": "Elemental Puffs", "configs": [[16, 13]]},
	"h04": {"handler": 4, "label": "Spell Charge Lines", "element": true,
		"configs": [[12, 15]], "callback": CB_CHARGE_LINES},
	"h06": {"handler": 6, "label": "Charge+X", "configs": [[10, 11]]},
	"h08": {"handler": 8, "label": "Charge Particles A", "configs": [[6, 9]]},
	"h09": {"handler": 9, "label": "Footstep Puffs", "configs": [[7, 11]]},
	"h12": {"handler": 12, "label": "Hit Dust", "configs": [[8, 12]]},
	"h13": {"handler": 13, "label": "Rising Burst", "configs": [[5, 11]], "rising": true},
	"h15": {"handler": 15, "label": "Charge Drift", "configs": [[4, 15]]},
	"h17": {"handler": 17, "label": "Element Particles", "element": true, "configs": [[3, ELEMENT_17]]},
	"h19": {"handler": 19, "label": "Teleport", "configs": [[15, 11]]},
	"h21": {"handler": 21, "label": "Knight Break", "configs": [[11, 10]]},
	"h22": {"handler": 22, "label": "Orbital Summon Orbs", "configs": [], "callback": CB_ORBITAL,
		"callback_config": [14, 12]},
}

## Handler 13 (0x801b2d28) writes −8 into config 5 +0x0C and subtracts 3 per tick: the
## spawn centre rises 8 → 8 + 3·15 PSX units over its 15-tick window.
const RISING_START_Y := 8.0
const RISING_STEP_Y := 3.0
const RISING_TICKS := 15

## Timeline span lengths the handlers get from the CALLER in the ROM (the charge ends when
## the cast does). A lifted document has no caller, so it picks one; the span is editable.
const CHARGE_TICKS := 90
const ORBIT_TICKS := 90

const _HEADER_FIELDS := ["unknown_00", "unknown_02", "phase1_duration", "spawn_delay",
	"unknown_08", "phase2_delay", "first_hit_frame", "for_each_delay", "total_frames"]
const _KEYFRAME_SLOTS := 25

## Where a lifted document keeps its setting (see set_element).
const META := &"trap_lift"

static var _cache: Dictionary = {}
static var _runtime_cache: Dictionary = {}
static var _tables: Dictionary = {}

## A charge the GAME holds open until the cast releases it (EffectInstance.release):
## long enough that no real charge outlives it — 5 minutes of 30 Hz ticks.
const HOLD_TICKS := 9000


## The callback span (timeline frames) whose CLEANUP lands where the ROM's loader
## finalizes a charge held `hold_vsyncs` vsyncs: after handler tick 1 + hold. The handler
## ticks twice a frame (EffectTimeline.SECONDARY_TICKS_PER_FRAME) from tick 1 at frame 0's
## invoke, and the manager sets CLEANUP when 2 frames of the span remain (CallbackManager).
static func charge_span_frames(hold_vsyncs: int) -> int:
	return ceili(float(hold_vsyncs) / EffectTimeline.SECONDARY_TICKS_PER_FRAME) + 2
static var _atlas_cache: Dictionary = {}


## Every document id the studio can open, in picker order: one per handler variant.
## The element is NOT part of the id — it is a document setting (set_element).
static func document_ids() -> Array[String]:
	var out: Array[String] = []
	for key in HANDLERS:
		out.append(DOCUMENT_PREFIX + key)
	return out


static func is_document(id: String) -> bool:
	return id.begins_with(DOCUMENT_PREFIX)


## {variant} for an id, or {} when it names no handler.
static func parse_document(id: String) -> Dictionary:
	if not is_document(id):
		return {}
	var variant := id.trim_prefix(DOCUMENT_PREFIX)
	if not HANDLERS.has(variant):
		return {}
	return {"variant": variant}


static func label_for(id: String) -> String:
	var doc := parse_document(id)
	if doc.is_empty():
		return id
	var spec: Dictionary = HANDLERS[doc["variant"]]
	return "TRAP h%02d %s" % [int(spec["handler"]), str(spec["label"])]


## The lifted EffectData for a document id — cached, so the studio page and the host
## that plays it hold the SAME object (the edit session's single-source rule). Null
## when the id is not a document or the TRAP tables are missing.
static func load_document(id: String) -> EffectData:
	if _cache.has(id):
		return _cache[id]
	var doc := parse_document(id)
	if doc.is_empty():
		return null
	var tables := _load_tables()
	if tables.is_empty():
		return null
	var data := build(str(doc["variant"]), 0, tables)
	if data == null:
		return null
	data.name = id
	_cache[id] = data
	return data


## Drop the cache so the next load rebuilds from the tables (a studio "revert").
static func forget(id: String = "") -> void:
	if id.is_empty():
		_cache.clear()
	else:
		_cache.erase(id)


## The EffectData GAMEPLAY plays for a handler variant at an element — cached per
## (variant, element, hold) and shared by every cast, like an E### directory's data; never
## the studio's editable document (load_document), so an author's edits cannot leak into
## a battle. `hold_ticks > 0` makes a charge's callback span (and h04's repeating sparkle
## cycles) that long, for a charge the caller ends with EffectInstance.release().
static func runtime_data(variant: String, element: int, hold_ticks: int = 0) -> EffectData:
	# Keyed on the content root too: the tables are the host's install (ADR-0202 dec. 5),
	# and a different root is different content.
	var key := "%s|%s|%d|%d" % [EffectsContent.trap_table_path(""), variant, element, hold_ticks]
	if _runtime_cache.has(key):
		return _runtime_cache[key]
	var tables := _load_tables()
	if tables.is_empty():
		return null
	var data := build(variant, element, tables, hold_ticks)
	if data == null:
		return null
	data.name = DOCUMENT_PREFIX + variant
	_runtime_cache[key] = data
	return data


static func _load_tables() -> Dictionary:
	var root := EffectsContent.trap_table_path("")
	if _tables.has(root):
		return _tables[root]
	var out := {}
	for key in ["emitters", "frames", "animations", "particle_header"]:
		var path := EffectsContent.trap_table_path(key + ".json")
		if path.is_empty() or not FileAccess.file_exists(path):
			push_error("TrapLift: missing TRAP table %s.json (parse_trap_effect.py)" % key)
			return {}
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
		if parsed == null:
			push_error("TrapLift: unparseable %s" % path)
			return {}
		out[key] = parsed
	_tables[root] = out
	return out


## Pure over its inputs (the texture aside), so a test can drive it with fixture tables.
static func build(variant: String, element: int, tables: Dictionary, hold_ticks: int = 0) -> EffectData:
	if not HANDLERS.has(variant):
		return null
	var spec: Dictionary = HANDLERS[variant]
	var configs: Array = tables.get("emitters", [])
	var data := EffectData.new()
	data.name = DOCUMENT_PREFIX + variant

	var header: Dictionary = tables.get("particle_header", {})
	var grav = header.get("gravity", [0.0, -0.035714, 0.0])
	data.gravity = Vector3(float(grav[0]), float(grav[1]), float(grav[2]))
	data.inertia_threshold = float(header.get("inertia_threshold", 560))

	data.animations = _lift_animations(tables.get("animations", []))

	# One frameset GROUP per CLUT rule: a fixed row is shared, an element rule owns its
	# group, so switching the element re-points that group without moving any other.
	var lifted: Array = []  # [{config, rule, callback?}]
	for pair in spec.get("configs", []):
		lifted.append({"config": int(pair[0]), "rule": int(pair[1])})
	var cb_config: Array = spec.get("callback_config", [])
	if not cb_config.is_empty():
		lifted.append({"config": int(cb_config[0]), "rule": int(cb_config[1]), "callback": true})
	var rules: Array[int] = []
	for e in lifted:
		if not (int(e["rule"]) in rules):
			rules.append(int(e["rule"]))
	if rules.is_empty():
		rules.append(0)
	var palettes: Array[int] = []
	for r in rules:
		palettes.append(_resolve_palette(r, element))
	_lift_framesets(data, tables.get("frames", []), palettes)
	data.texture = _atlas(palettes)

	var channels: Array = []
	for e in lifted:
		var config_idx: int = int(e["config"])
		if config_idx < 0 or config_idx >= configs.size():
			push_error("TrapLift: %s names config %d, table has %d" % [variant, config_idx, configs.size()])
			return null
		var config: Dictionary = configs[config_idx]
		var emitter := _lift_emitter(data, config, data.emitters.size(), rules.find(int(e["rule"])),
			config_idx in OVERBRIGHT_CONFIGS)
		data.emitters.append(emitter)
		if e.get("callback", false):
			continue
		var life := _lifetime_ticks(config, tables.get("animations", []))
		var schedule := spawn_schedule(config, life)
		if variant == "h04":
			schedule = repeat_schedule(schedule, life, hold_ticks if hold_ticks > 0 else CHARGE_TICKS)
		_apply_count_curve(data, emitter, schedule)
		if spec.get("rising", false):
			_apply_rising_curve(data, emitter)
		channels.append(_particle_channel(channels.size(), emitter.index, schedule, 0))

	match int(spec.get("callback", -1)):
		CB_CHARGE_LINES:
			var line := _charge_line_emitter(data.emitters.size(), element)
			data.emitters.append(line)
			_flat_colour(data, line, TrapChargeLineColours.rgb(element))
			channels.append(_callback_channel(channels.size(), line.index, hold_ticks if hold_ticks > 0 else CHARGE_TICKS))
			data.callback_slots.append({"slot": 0, "callback_id": CB_CHARGE_LINES})
		CB_ORBITAL:
			var orb: EffectEmitter = data.emitters[data.emitters.size() - 1]
			orb.callback_params = {"param_A8": 24, "param_AA": 24, "param_AC": 61, "param_AE": 3}
			channels.append(_callback_channel(channels.size(), orb.index, hold_ticks if hold_ticks > 0 else ORBIT_TICKS))
			data.callback_slots.append({"slot": 0, "callback_id": CB_ORBITAL})

	var end_frame := _end_frame(data, channels, tables.get("animations", []))
	data.timeline = TimelineData.from_json(_timeline_json(channels, end_frame))
	if spec.get("white_flash", false):
		data.palette = PaletteData.from_json(_white_flash_json())
	if spec.get("sounds", false):
		_lift_sounds(data)
	data.flags = {"flags_byte": 0, "terrain_height_adjust": false, "audio_fade": false,
		"time_scale_pattern1": false, "time_scale_pattern2": false}
	# The document setting's state rides the object itself (metadata, not an EffectData
	# field): the element, the group → rule table set_element re-resolves, and the line
	# emitter whose colour is the element's.
	var line_idx := -1
	if int(spec.get("callback", -1)) == CB_CHARGE_LINES:
		line_idx = data.emitters.size() - 1
	data.set_meta(META, {"variant": variant, "element": clampi(element, 0, 8), "rules": rules,
		"palettes": palettes, "line_emitter": line_idx})
	return data


## Does this document take an element (the setting exists)? False for anything not lifted.
static func takes_element(data) -> bool:
	if data == null or not data.has_meta(META):
		return false
	return bool(HANDLERS[data.get_meta(META)["variant"]].get("element", false))


## The document's element (0–8), or -1 when it is not a lifted document.
static func element_of(data) -> int:
	if data == null or not data.has_meta(META):
		return -1
	return int(data.get_meta(META)["element"])


## The frameset groups whose CLUT row the element decides (indices into rules/palettes).
static func _element_groups(meta: Dictionary) -> Array[int]:
	var out: Array[int] = []
	var rules: Array = meta["rules"]
	for g in range(rules.size()):
		if int(rules[g]) == ELEMENT or int(rules[g]) == ELEMENT_17:
			out.append(g)
	return out


static func _group_range(data, g: int) -> Vector2i:
	var start: int = data.frameset_group_offset(g)
	var stop: int = data.frameset_group_offsets[g + 1] if g + 1 < data.frameset_group_offsets.size() \
		else data.framesets.size()
	return Vector2i(start, stop)


## Everything set_element writes, captured so an undo can put it back exactly: the element,
## the per-group rows, the atlas object, every element-group frame's palette_id, and the
## line emitter's colour samples. {} when the document takes no element.
static func capture_element_state(data) -> Dictionary:
	if not takes_element(data):
		return {}
	var meta: Dictionary = data.get_meta(META)
	var frame_rows: Array = []
	for g in _element_groups(meta):
		var r := _group_range(data, g)
		for i in range(r.x, r.y):
			for fr in data.framesets[i].get("frames", []):
				frame_rows.append(int(fr.get("palette_id", 0)))
	var line_samples := {}
	var line: int = int(meta["line_emitter"])
	if line >= 0:
		var cc: Dictionary = data.emitters[line].color_curves
		for ch in ["r", "g", "b"]:
			var curve = data.get_curve(int(cc.get(ch, -1)))
			if curve:
				line_samples[ch] = curve.samples.duplicate()
	return {"element": int(meta["element"]), "palettes": (meta["palettes"] as Array).duplicate(),
		"texture": data.texture, "frame_rows": frame_rows, "line_samples": line_samples}


static func restore_element_state(data, snap: Dictionary) -> void:
	if snap.is_empty() or not takes_element(data):
		return
	var meta: Dictionary = data.get_meta(META)
	var k := 0
	for g in _element_groups(meta):
		var r := _group_range(data, g)
		for i in range(r.x, r.y):
			for fr in data.framesets[i].get("frames", []):
				fr["palette_id"] = int(snap["frame_rows"][k])
				k += 1
	var line: int = int(meta["line_emitter"])
	if line >= 0:
		var cc: Dictionary = data.emitters[line].color_curves
		for ch in snap["line_samples"]:
			var curve = data.get_curve(int(cc.get(ch, -1)))
			if curve:
				curve.samples = (snap["line_samples"][ch] as Array[float]).duplicate()
	data.texture = snap["texture"]
	meta["element"] = int(snap["element"])
	var palettes: Array[int] = []
	for v in snap["palettes"]:
		palettes.append(int(v))
	meta["palettes"] = palettes


## What a switch would OVERWRITE: the pieces the element owns that no longer hold what the
## current element put there — i.e. hand edits. "palette rows" when an element group's
## frame reads a row other than its element's; "line colour" when the charge line's
## samples are not the flat element RGB. [] when nothing was hand-edited.
static func element_overrides(data) -> Array[String]:
	var out: Array[String] = []
	if not takes_element(data):
		return out
	var meta: Dictionary = data.get_meta(META)
	var palettes: Array = meta["palettes"]
	var rows_edited := false
	for g in _element_groups(meta):
		var r := _group_range(data, g)
		for i in range(r.x, r.y):
			for fr in data.framesets[i].get("frames", []):
				if int(fr.get("palette_id", 0)) != int(palettes[g]):
					rows_edited = true
	if rows_edited:
		out.append("palette rows")
	var line: int = int(meta["line_emitter"])
	if line >= 0:
		var c := TrapChargeLineColours.rgb(int(meta["element"]))
		var cc: Dictionary = data.emitters[line].color_curves
		for pair in [["r", c.r8], ["g", c.g8], ["b", c.b8]]:
			var curve = data.get_curve(int(cc.get(pair[0], -1)))
			if curve == null:
				continue
			var want := float(pair[1]) / 255.0
			var edited := false
			for v in curve.samples:
				if not is_equal_approx(v, want):
					edited = true
					break
			if edited:
				out.append("line colour")
				break
	return out


## Switch a lifted document's element IN PLACE: the element groups' CLUT rows (their
## frames' palette_id + the atlas band) and the charge line's colour curves. Everything
## else — every edit made so far — is untouched, because nothing else depends on it.
## Replaces `data.texture` when a row changed, so a live renderer must refresh_texture().
## Returns false when there is nothing to switch.
static func set_element(data, element: int) -> bool:
	if not takes_element(data):
		return false
	element = clampi(element, 0, 8)
	var meta: Dictionary = data.get_meta(META)
	var rules: Array = meta["rules"]
	var palettes: Array[int] = []
	for r in rules:
		palettes.append(_resolve_palette(int(r), element))
	for g in range(palettes.size()):
		if palettes[g] == int(meta["palettes"][g]):
			continue
		var r := _group_range(data, g)
		for i in range(r.x, r.y):
			for fr in data.framesets[i].get("frames", []):
				fr["palette_id"] = palettes[g]
	if palettes != meta["palettes"]:
		var tex := _atlas(palettes)
		if tex != null:
			data.texture = tex
	var line: int = int(meta["line_emitter"])
	if line >= 0:
		var c := TrapChargeLineColours.rgb(element)
		var cc: Dictionary = data.emitters[line].color_curves
		for pair in [["r", c.r8], ["g", c.g8], ["b", c.b8]]:
			var curve = data.get_curve(int(cc.get(pair[0], -1)))
			if curve:
				curve.samples.fill(float(pair[1]) / 255.0)
	meta["element"] = element
	meta["palettes"] = palettes
	return true


static func _resolve_palette(rule: int, element: int) -> int:
	if rule == ELEMENT:
		return clampi(element, 0, 8)
	if rule == ELEMENT_17:
		return int(ELEMENT_PARTICLE_PALETTES.get(element, 0))
	return rule


# --- animations / framesets / texture ---------------------------------------------------

## TRAP durations count one per tick; E###'s animator counts two per frame. Doubling
## keeps the TRAP pacing; duration 0 (terminal) stays 0.
static func _lift_animations(src: Array) -> Array:
	var out: Array = []
	for anim in src:
		var ops: Array = []
		for op in anim.get("opcodes", []):
			var o: Dictionary = op.duplicate(true)
			if str(o.get("type", "")) == "FRAME":
				o["duration"] = int(o.get("duration", 0)) * 2
			ops.append(o)
		out.append({"index": int(anim.get("index", out.size())), "opcodes": ops})
	return out


## One copy of the 107 framesets per CLUT row, each row's copy reading its own band of
## the stacked atlas. A particle picks its row through its emitter's anim_param (the
## frameset GROUP), which is how E### already selects between frameset sets.
static func _lift_framesets(data: EffectData, frames: Array, palettes: Array[int]) -> void:
	var band := _sheet_height()
	data.framesets = []
	var offsets: Array[int] = []
	for g in range(palettes.size()):
		offsets.append(data.framesets.size())
		for fs in frames:
			var copy: Dictionary = fs.duplicate(true)
			for fr in copy.get("frames", []):
				fr["palette_id"] = palettes[g]
				var uv: Dictionary = fr.get("uv", {})
				uv["y"] = int(uv.get("y", 0)) + g * band
			data.framesets.append(copy)
	data.frameset_group_offsets = offsets


static func _sheet_height() -> int:
	var tex := _indexed_sheet()
	return tex.get_height() if tex else 0


static func _indexed_sheet() -> Texture2D:
	var path := EffectsContent.trap_tex_path()
	# From disk, not through the importer, so the content root may sit outside res://.
	return TextureTga.load_texture(path) if not path.is_empty() else null


## TRAP1 is an indexed sheet (R = index × 17) plus a 16-row CLUT; E### wants an RGBA
## sheet. Bake one band per used row, top to bottom, copying the CLUT's RGBA verbatim so
## the STP-in-alpha discard rules see exactly what the paletted path sees.
static func _atlas(palettes: Array[int]) -> Texture2D:
	var key := str(palettes)
	if _atlas_cache.has(key):
		return _atlas_cache[key]
	var sheet := _indexed_sheet()
	var clut_path := EffectsContent.trap_palette_path()
	if sheet == null or clut_path.is_empty():
		return null
	var clut_tex: Texture2D = TextureTga.load_texture(clut_path)
	if clut_tex == null:
		return null
	var src := sheet.get_image()
	var clut := clut_tex.get_image()
	if src == null or clut == null:
		return null
	src.convert(Image.FORMAT_RGBA8)
	clut.convert(Image.FORMAT_RGBA8)
	var w := src.get_width()
	var h := src.get_height()
	var src_bytes := src.get_data()
	var clut_bytes := clut.get_data()
	var clut_w := clut.get_width()
	var out := PackedByteArray()
	out.resize(w * h * 4 * palettes.size())
	for g in range(palettes.size()):
		var row_base: int = palettes[g] * clut_w * 4
		var band_base := g * w * h * 4
		for i in range(w * h):
			var idx := clampi(int(round(src_bytes[i * 4] / 17.0)), 0, 15)
			var c := row_base + idx * 4
			var o := band_base + i * 4
			out[o] = clut_bytes[c]
			out[o + 1] = clut_bytes[c + 1]
			out[o + 2] = clut_bytes[c + 2]
			out[o + 3] = clut_bytes[c + 3]
	var img := Image.create_from_data(w, h * palettes.size(), false, Image.FORMAT_RGBA8, out)
	var tex := ImageTexture.create_from_image(img)
	_atlas_cache[key] = tex
	return tex


# --- emitters ------------------------------------------------------------------------------

static func _pair(v) -> Array:
	if v is Array and v.size() >= 2:
		return [float(v[0]), float(v[1])]
	return [float(v), float(v)]


static func _v3(v) -> Array:
	return [float(v[0]), float(v[1]), float(v[2])] if v is Array and v.size() >= 3 else [0.0, 0.0, 0.0]


static func _lift_emitter(data: EffectData, config: Dictionary, index: int, group: int,
		overbright: bool) -> EffectEmitter:
	var raw: Dictionary = config.get("raw", {})
	var radius := _pair(config.get("radius", 0))
	var weight := _pair(config.get("weight", 0))
	var lifetime := _pair(config.get("lifetime", -1))
	var pos := _v3(config.get("position_scatter", [0, 0, 0]))
	var axes := _v3(config.get("velocity", [0, 0, 0]))
	var angle := _v3(config.get("vel_range", [0, 0, 0]))
	var half := _v3(config.get("scatter_half_range", [0, 0, 0]))
	var rv := [radius[0] / PsxMagnitude.RADIAL_VELOCITY_DIVISOR, radius[1] / PsxMagnitude.RADIAL_VELOCITY_DIVISOR]
	var zero := [0.0, 0.0, 0.0]
	var flags: Dictionary = config.get("flags", {})
	var json := {
		"index": index,
		"anim_index": int(config.get("anim_index", 0)),
		"anim_param": group,
		"byte_00": 0, "byte_05": 0,
		# TARGET-anchored (direction_flags 0x0600): motion 0x80 = target anchor TARGET,
		# animation_target 0x06 = emitter anchor TARGET, spherical spread, sprite mode 0.
		"motion_type_flag": 0x80, "animation_target_flag": 0x06,
		"emitter_flags_lo": 0x40 if overbright else 0, "emitter_flags_hi": 0,
		"curves": _no_curves(),
		"color_curves": {"r": -1, "g": -1, "b": -1},
		"position": {"start": pos, "end": pos},
		"spread": {"start": axes, "end": axes},
		"velocity_base_angle": {"start": angle, "end": angle},
		"velocity_direction_spread": {"start": half, "end": half},
		"radial_velocity": {"min_start": rv[0], "max_start": rv[1], "min_end": rv[0], "max_end": rv[1]},
		"inertia": {"min_start": 4096, "max_start": 4096, "min_end": 4096, "max_end": 4096},
		"weight": {"min_start": weight[0], "max_start": weight[1], "min_end": weight[0], "max_end": weight[1]},
		"acceleration": {"min_start": zero, "max_start": zero, "min_end": zero, "max_end": zero},
		"drag": {"min_start": zero, "max_start": zero, "min_end": zero, "max_end": zero},
		"lifetime": {"min_start": lifetime[0], "max_start": lifetime[1], "min_end": lifetime[0], "max_end": lifetime[1]},
		"target_offset": {"start": zero, "end": zero},
		"spawn": {"particle_count_start": int(config.get("spawn_rate", 1)),
			"particle_count_end": int(config.get("spawn_rate", 1)), "interval_start": 1, "interval_end": 1},
		"homing_strength": {"min_start": 0.0, "max_start": 0.0, "min_end": 0.0, "max_end": 0.0},
		"child_emitter_on_death": 255, "child_emitter_mid_life": 255,
		"callback_params": {},
		"raw": {
			"trap_config_addr": str(raw.get("config_addr", "")),
			"position_start": raw.get("position_scatter", [0, 0, 0]),
			"position_end": raw.get("position_scatter", [0, 0, 0]),
			"spread_start": raw.get("velocity", [0, 0, 0]), "spread_end": raw.get("velocity", [0, 0, 0]),
			"angle_start": raw.get("vel_range", [0, 0, 0]), "angle_end": raw.get("vel_range", [0, 0, 0]),
			"vel_spread_start": raw.get("scatter_half_range", [0, 0, 0]),
			"vel_spread_end": raw.get("scatter_half_range", [0, 0, 0]),
			"radial_min_start": int(radius[0]), "radial_max_start": int(radius[1]),
			"radial_min_end": int(radius[0]), "radial_max_end": int(radius[1]),
		},
		"flags": {
			"spawn_model": "TRAP",
			"trap_velocity_mode": str(flags.get("velocity_mode", "")),
			"trap_direction_mode": str(flags.get("direction_mode", "")),
			"trap_max_particles": int(config.get("max_particles", 0)),
			"align_to_velocity": false, "target_anchor_mode": "TARGET", "spread_mode": "SPHERICAL",
			"emitter_anchor_mode": "TARGET", "color_curve_enabled": overbright,
			"velocity_inward": false, "child_death_enabled": false, "child_midlife_enabled": false,
			"align_to_facing": false, "homing_arrival_threshold": 0,
		},
	}
	var emitter := EffectEmitter.from_json(json)
	if overbright:
		_flat_colour(data, emitter, Color8(255, 255, 255))
	return emitter


static func _no_curves() -> Dictionary:
	var out := {}
	for k in ["position", "spread", "velocity_base_angle", "velocity_dir_spread", "inertia",
			"weight", "radial_velocity", "acceleration", "drag", "lifetime", "target_offset",
			"particle_count", "spawn_interval", "homing_strength", "homing_blend"]:
		out[k] = -1
	return out


static func _add_curve(data: EffectData, samples: Array) -> int:
	var arr: Array[float] = []
	for v in samples:
		arr.append(float(v))
	var idx := data.curves.size()
	data.curves.append(EffectCurve.from_array(arr, idx))
	return idx


static func _flat(value: float) -> Array:
	var a: Array = []
	a.resize(160)
	a.fill(value)
	return a


## A flat colour: one private curve per channel (ADR-0089 curve ownership), in byte/255.
static func _flat_colour(data: EffectData, emitter: EffectEmitter, c: Color) -> void:
	emitter.color_curves = {"r": _add_curve(data, _flat(c.r8 / 255.0)),
		"g": _add_curve(data, _flat(c.g8 / 255.0)), "b": _add_curve(data, _flat(c.b8 / 255.0))}
	emitter.flags["color_curve_enabled"] = true
	emitter.raw_data["emitter_flags_lo"] = int(emitter.raw_data.get("emitter_flags_lo", 0)) | 0x40


## Handler 13's rising centre as a position curve over the spawn counter. 255 / 15 = 17,
## so every step is an exact u8 sample.
static func _apply_rising_curve(data: EffectData, emitter: EffectEmitter) -> void:
	var start := PsxMagnitude.tile_to_game(RISING_START_Y)
	var end := PsxMagnitude.tile_to_game(RISING_START_Y + RISING_STEP_Y * RISING_TICKS)
	emitter.position_start = Vector3(0.0, start, 0.0)
	emitter.position_end = Vector3(0.0, end, 0.0)
	emitter.raw_data["position_start"] = [0, -int(RISING_START_Y), 0]
	emitter.raw_data["position_end"] = [0, -int(RISING_START_Y + RISING_STEP_Y * RISING_TICKS), 0]
	var samples: Array = []
	for i in range(160):
		samples.append(float(mini(i, RISING_TICKS) * (255 / RISING_TICKS)) / 255.0)
	emitter.curves["position"] = _add_curve(data, samples)


# --- the spawn schedule --------------------------------------------------------------------

## A TRAP particle's life in TICKS: its config lifetime, or — when animation-driven (−1)
## — the animation's summed durations. A random lifetime uses the midpoint.
static func _lifetime_ticks(config: Dictionary, animations: Array) -> int:
	var life := _pair(config.get("lifetime", -1))
	if life[0] >= 0 and life[1] >= 0:
		return maxi(1, int((life[0] + life[1]) / 2.0))
	var anim_idx := int(config.get("anim_index", 0))
	if anim_idx < 0 or anim_idx >= animations.size():
		return 1
	var total := 0
	for op in animations[anim_idx].get("opcodes", []):
		if str(op.get("type", "")) == "FRAME":
			total += int(op.get("duration", 0))
	return maxi(1, total)


## Per-tick spawn counts over the config's window, with the handler's max_particles cap
## applied the way handler 2 applies it (count the living, spawn up to the cap). The cap
## has no E### field, so it is compiled into the schedule here. Returns [[tick, count]].
static func spawn_schedule(config: Dictionary, life_ticks: int) -> Array:
	var window: Array = config.get("spawn_window", [0, 4])
	var rate := int(config.get("spawn_rate", 1))
	var cap := int(config.get("max_particles", 8))
	var deaths: Array[int] = []
	var out: Array = []
	for t in range(int(window[0]), int(window[1]) + 1):
		var living: Array[int] = []
		for d in deaths:
			if d > t:
				living.append(d)
		deaths = living
		var n := mini(rate, cap - deaths.size())
		if n > 0:
			out.append([t, n])
			for _i in range(n):
				deaths.append(t + life_ticks)
	return out


## The charge-line sparkles restart each time the last sparkle dies (the retired
## TrapChargeLineEffect's behaviour),
## for as long as the charge runs: the schedule repeats every (last spawn tick + life).
static func repeat_schedule(schedule: Array, life_ticks: int, until: int) -> Array:
	if schedule.is_empty():
		return schedule
	var cycle: int = maxi(1, int(schedule[schedule.size() - 1][0]) + life_ticks)
	var out: Array = []
	var base := 0
	while base < until:
		for e in schedule:
			var t: int = base + int(e[0])
			if t < until:
				out.append([t, int(e[1])])
		base += cycle
	return out


## Encode a schedule's per-tick counts as the emitter's particle count: flat when every
## count is the same, else a count curve over the channel's spawn counter.
static func _apply_count_curve(data: EffectData, emitter: EffectEmitter, schedule: Array) -> void:
	if schedule.is_empty():
		return
	var hi := 0
	var lo := 1 << 30
	for e in schedule:
		hi = maxi(hi, int(e[1]))
		lo = mini(lo, int(e[1]))
	emitter.particle_count_start = hi
	emitter.particle_count_end = lo
	if hi == lo:
		return
	var samples := _flat(0.0)
	var counter := 0
	var prev_tick := -2
	for e in schedule:
		# The spawn counter restarts at every span (PhaseBlock._advance_keyframe).
		counter = counter + 1 if int(e[0]) == prev_tick + 1 else 0
		prev_tick = int(e[0])
		if counter < samples.size():
			samples[counter] = float(hi - int(e[1])) / float(hi - lo)
	emitter.curves["particle_count"] = _add_curve(data, samples)


# --- timeline ------------------------------------------------------------------------------

static func _keyframe(time: int, emitter_id: int, action_flags: int = 0) -> Dictionary:
	return {"time": time, "emitter_id": emitter_id, "action_flags": action_flags}


## One for_each particle channel: a span per run of consecutive spawn ticks. A keyframe's
## `time` is the END of its span (PhaseBlock: duration = time − previous time).
static func _particle_channel(channel_index: int, emitter_index: int, schedule: Array,
		action_flags: int) -> Dictionary:
	var kfs: Array = [_keyframe(0, 0)]
	var run_start := -1
	var prev := -2
	var cursor := 0
	for e in schedule + [[-100, 0]]:
		var t: int = int(e[0])
		if t != prev + 1 and run_start >= 0:
			if run_start > cursor:
				kfs.append(_keyframe(run_start, 0))
			kfs.append(_keyframe(prev + 1, emitter_index + 1, action_flags))
			cursor = prev + 1
			run_start = -1
		if t >= 0 and run_start < 0:
			run_start = t
		prev = t
	return _channel(channel_index, kfs)


static func _callback_channel(channel_index: int, emitter_index: int, ticks: int) -> Dictionary:
	# action_flags low bits = callback selector 1 → loaded slot 0.
	return _channel(channel_index, [_keyframe(0, 0), _keyframe(ticks, emitter_index + 1, 1)])


static func _channel(channel_index: int, kfs: Array) -> Dictionary:
	var max_kf := kfs.size() - 1
	while kfs.size() < _KEYFRAME_SLOTS:
		kfs.append(_keyframe(0, 0))
	return {"context": "for_each", "channel_index": channel_index, "max_keyframe": max_kf, "keyframes": kfs}


static func _end_frame(data: EffectData, channels: Array, animations: Array) -> int:
	var last := 0
	for ch in channels:
		var kfs: Array = ch["keyframes"]
		last = maxi(last, int(kfs[int(ch["max_keyframe"])]["time"]))
	var life := 0
	for e in data.emitters:
		life = maxi(life, maxi(e.lifetime_max_start, e.lifetime_min_start))
		life = maxi(life, data.get_animation_display_length(e.anim_index))
	if not data.callback_slots.is_empty():
		life = maxi(life, 64)  # the callbacks' own fade-out tails (lines 39, orbs 61)
	return last + life


static func _timeline_json(channels: Array, end_frame: int) -> Dictionary:
	var header := {}
	for k in _HEADER_FIELDS:
		header[k] = 0
	header["for_each_delay"] = 1
	header["total_frames"] = end_frame
	return {"header": header, "particle_channels": channels}


# --- palette + sound -----------------------------------------------------------------------

## charge_effect_handler_2's inline flash (deep dive §14, 0x801b153c): tick 0
## apply_unit_palette_effect(5, 0, unit, 31, 31, 31) snaps white; tick 1 (8, 2, unit, 0…)
## fades back over the fast 8-frame ramp. mode = blend_mode, the second arg = the Time byte.
static func _white_flash_json() -> Dictionary:
	var kfs := [
		{"index": 0, "time_value": 0, "duration_frames": 1, "rgb": [31, 31, 31],
			"rgb_signed": [31, 31, 31], "ctrl": 0x85, "enabled": true, "blend_mode": 5},
		{"index": 1, "time_value": 2, "duration_frames": 8, "rgb": [0, 0, 0],
			"rgb_signed": [0, 0, 0], "ctrl": 0x88, "enabled": true, "blend_mode": 8},
	]
	# PaletteSubsystem walks keyframes [0, max_keyframe − 1), so two keyframes → 3.
	return {"for_each": {"target": {"context": "for_each", "channel_name": "target",
		"max_keyframe": kfs.size() + 1, "keyframes": kfs}}}


## FUN_8008a924's hit sounds (sounds.json). A timeline has at most 4 containers (the
## resolver's counters, DAT_801b9250), and there are 5 ids, so: container 0 = the impact
## 0x6A; containers 1/2 = the first/second sync hit with the ATTACK id in id_a and the
## ITEM alternate in id_b. Mode 0 plays id_a — the ROM picks by hit type, which no
## container mode expresses, so the item ids are carried as data, not played. Lane 0
## fires the impact at tick 0; lane 1 the two sync hits at ticks 0 and 17. Timeline
## sound_id N plays container N − 2. The ids are global battle SEs, not FEDS pairs, so
## playback is silent; the lanes are the score.
## ⚠️ Attribution: FUN_8008a924 is the SEQ reaction handler; §14 found it does NOT run on
## the Throw Stone TRAP path, so these may belong to the caller, not to handler 2.
const HIT_SOUNDS := [[0x6A, 0], [0xDB, 0xDC], [0xB8, 0x28]]


static func _lift_sounds(data: EffectData) -> void:
	var containers: Array = []
	for i in range(HIT_SOUNDS.size()):
		containers.append({"mode": 0, "id_a": HIT_SOUNDS[i][0], "id_b": HIT_SOUNDS[i][1], "id_c": 0, "index": i})
	data.sound_containers = {"containers": containers}
	var lanes := [
		[{"duration_frames": 1, "sound_id": 2}],
		[{"duration_frames": 17, "sound_id": 3}, {"duration_frames": 1, "sound_id": 4}],
	]
	var channels: Array = []
	for ci in range(lanes.size()):
		var kfs: Array = lanes[ci].duplicate(true)
		kfs.append({"duration_frames": 600, "sound_id": 0})
		channels.append({"channel_index": ci, "max_keyframe": kfs.size() - 1, "keyframes": kfs})
	data.sound = {"for_each": channels}


# --- callbacks -----------------------------------------------------------------------------

## The charge-line callback's emitter: a parameter block, not a particle emitter (the ROM
## callbacks' convention). Its four s16 callback params are the studio-editable knobs.
static func _charge_line_emitter(index: int, _element: int) -> EffectEmitter:
	var emitter := EffectEmitter.new()
	emitter.index = index
	emitter.curves = _no_curves()
	emitter.flags = {"emitter_anchor_mode": "TARGET", "target_anchor_mode": "TARGET",
		"spread_mode": "SPHERICAL", "color_curve_enabled": true}
	emitter.raw_data = {"motion_type_flag": 0x80, "animation_target_flag": 0x06,
		"emitter_flags_lo": 0x40, "emitter_flags_hi": 0, "byte_00": 0, "byte_05": 0}
	# param_A8 ring radius (PSX SCREEN pixels), AA line life (ticks), AC max concurrent lines
	# — params row 0 at 0x801b8880; AE convergence height above the anchor (PSX units): the
	# caster's sprite height + 8, 44 for the captured Black Mage (SPELL_CHARGE_LINES.md §3).
	emitter.callback_params = {"param_A8": 256, "param_AA": 32, "param_AC": 10, "param_AE": 44}
	emitter.lifetime_min_start = 1
	emitter.lifetime_max_start = 1
	emitter.lifetime_min_end = 1
	emitter.lifetime_max_end = 1
	return emitter


## The element RGB table at 0x801b84C0 (deep dive §15), which the charge lines tint by. It
## is indexed by COLOUR INDEX — none, Fire, Water, Earth, Wind, Holy, Dark, Ice, Lightning —
## which the handler takes from the ABILITY's element byte, first set bit in that order
## (`battle_effect_get_ninja_ball`, masks 0x801b8544; SPELL_CHARGE_LINES.md §7 [S·D-seed]).
## It is NOT the game's element id (AbilityVisual.ELEMENT_NAME_TO_ID, ELEMENT_NAMES above):
## that one would show Lightning cyan and Ice orange.
class TrapChargeLineColours:
	const RGB := [[160, 160, 160], [255, 80, 64], [64, 192, 192], [224, 136, 48],
		[64, 255, 80], [160, 160, 160], [192, 64, 192], [64, 80, 255], [192, 192, 64]]
	## FFT element names → their bit in `range_data.element`.
	const ELEMENT_BITS := {"Fire": 0x80, "Lightning": 0x40, "Ice": 0x20, "Wind": 0x10,
		"Earth": 0x08, "Water": 0x04, "Holy": 0x02, "Dark": 0x01}

	static func rgb(colour_index: int) -> Color:
		var c: Array = RGB[clampi(colour_index, 0, RGB.size() - 1)]
		return Color8(int(c[0]), int(c[1]), int(c[2]))

	## The ability's element byte → the colour index the lines take.
	static func index_for_element_byte(element_byte: int) -> int:
		return preload("res://addons/exmateria_effects/callbacks/ChargeLineModel.gd").colour_index(element_byte)

	## The element byte an ability's element NAMES spell (any order).
	static func element_byte(names: Array) -> int:
		var b := 0
		for n in names:
			b |= int(ELEMENT_BITS.get(str(n), 0))
		return b
