extends RefCounted
## Effect data container - loads pre-converted JSON from parser
## Vault: [[Effect File Format]]
## Vault: [[Effect Frame Pacing]]
## Vault: [[Effect Texture Upload]]
## Vault: [[Embedded MIPS Effect Code]]

const _Self = preload("res://addons/exmateria_effects/file_model/EffectData.gd")
const EffectCurve = preload("res://addons/exmateria_effects/file_model/EffectCurve.gd")
const EffectEmitter = preload("res://addons/exmateria_effects/file_model/EffectEmitter.gd")

# Preload to ensure class is available (avoids load order issues)
const TimelineDataClass = preload("res://addons/exmateria_effects/file_model/TimelineData.gd")
const ScreenDataClass = preload("res://addons/exmateria_effects/file_model/ScreenData.gd")
const PaletteDataClass = preload("res://addons/exmateria_effects/file_model/PaletteData.gd")
const CameraDataClass = preload("res://addons/exmateria_effects/file_model/CameraData.gd")
const CurveExplode = preload("res://addons/exmateria_effects/file_model/CurveExplode.gd")

## ADR-0318 dec. 7 — the FEDS bank arrives through the PLATFORM PORT, not a `preload`
## of the `Audio` package's façade.
##
## The DEPENDENCY is unchanged and is not the thing that was wrong: `Effects` reads
## `Audio`'s `feds.bin` under the blueprint's Format-owner rule (ADR-0288 dec. 8) and
## that stands. What was wrong is the CARRIER. `preload` is compile-time, so a façade
## preload made an OPTIONAL artifact a compile-time REQUIREMENT of this file — with
## `exmateria_sound` absent, this file failed to parse and took
## `callbacks/CallbackManager.gd` down with it (ADR-0318 §1.1, the parser's own
## attribution). One of the four preloads that made "install Effects without the audio
## package" a parse-error cascade rather than a configuration.
##
## `ExMateriaPlatform.SfxPort` resolves at RUNTIME and answers `null` when no engine is
## registered, so the absent package is now the same state as an effect with no
## `feds.bin` — a state every reader of `feds_bank` in the tree already handles, because
## most effects ship no bank. `feds_bank` was already declared untyped (see its
## declaration below), so no annotation downstream changes.
##
## ⚠️ The FEDS **opcode table** does NOT come with it. Decision 7 moves a LOAD, not a
## decode: `EffectReadSoundDef.gd` states the rule from the file-format side — the raw
## blob is a patchable unit `Effects` can read, and the decode table exists twice under a
## drift guard, so a third copy here would be one that guard does not know about.
const SfxPort = ExMateriaPlatform.SfxPort

var name: String = ""
var emitters: Array[EffectEmitter] = []
var curves: Array[EffectCurve] = []
                            # ONE PRIVATE CURVE PER USE SITE after the explode (ADR-0089
                            # curve-ownership amendment): load hands every (emitter, slot)
                            # its own copy at its own index, so painting one moves nothing
                            # else. The array is UNBOUNDED — median ~22 entries, max 67 —
                            # and the ROM's shared, indexed, <=15 table is what the deferred
                            # compiler produces on PSX export, never what authoring holds.
var curve_residue: Array = []  # [{index: int, curve: EffectCurve}] — curve slots NOTHING
                            # references, set aside by the explode (6.5 per effect on
                            # average). Not use sites: unreachable, so nothing renders them,
                            # but a byte-exact export carries them back to their original
                            # slots rather than silently dropping them (28% are distinct
                            # real shapes, not all-zero padding).
var animations: Array = []
var framesets: Array = []
var texture: Texture2D = null
var texture_meta: Dictionary = {}
                            # texture_meta.json — the texture section's 4-byte VRAM upload
                            # header (#280 follow-up): pixel_data_size, stride_flag,
                            # row_bytes, height, vram_x. `vram_y` is null by design: the
                            # file does not encode one (the +0x400 word is a SIZE).
var authored_texture_tga: PackedByteArray = PackedByteArray()
                            # #280: the RGBA .tga an author imported this session,
                            # kept verbatim so EffectTextureSaver can hand it to the
                            # Python quantizer (which owns the index delta — it needs
                            # the original indexed plane, which lives only in the BIN).
                            # Empty when the sheet is still the ROM's.
var timeline = null  # TimelineData - untyped to avoid load order issues
var screen = null   # ScreenData — background color animation
var palette = null  # PaletteData — unit/map color animation
var camera = null   # CameraData — camera angle/position/zoom animation
var sound: Dictionary = {}  # sound.json { phase -> [channel dicts] } — SFX keyframes
                            # (the addon's EffectSoundController owns runtime playback;
                            # this raw copy is for the Effect Studio score projection).
var sound_containers: Dictionary = {}  # sound_containers.json { "containers": [ {mode,
                            # id_a, id_b, id_c, index}, ... ] } — the shared, effect-global
                            # TIER-2 SoundContainers (ADR-0085). Single source of truth: the
                            # studio edits this in place through EffectEditSession, and the
                            # resolver/ghost/views/writer all read this SAME reference.
var feds_bank = null        # FedsBank (feds.bin) — the TIER-3 byte truth (ADR-0085). A
                            # RefCounted shared by the studio env, playback (EffectInstance
                            # re-points its loader's bank here) and the SoundDefChannel
                            # encoder, so an in-place raw patch is seen by every reader.
var time_scale: Dictionary = {}  # Time scale curve data (optional)
var flags: Dictionary = {}  # effect_flags.json — the GLOBAL flags byte (#272, ADR-0092):
                            # {flags_byte, terrain_height_adjust, audio_fade,
                            # time_scale_pattern1, time_scale_pattern2}. The raw flags_byte
                            # is the round-trip source of truth; bits 5/6 also mirror into
                            # time_scale.flags (EffectFlagsChannel keeps them in sync on edit).
var callback_slots: Array = []  # [{slot: int, callback_id: int}, ...]
var script_ops: Array = []  # Raw script opcodes from script.json (for pattern detection)
var script_code_format: bool = false  # header.json is_code_format — CODE-format effects have a
                                       # MIPS-executable script; the pattern swap (#273, ADR-0094)
                                       # is DATA-only, so a CODE effect shows the mode read-only.
var frameset_group_offsets: Array[int] = [0]  # Cumulative offset per frameset group

# Particle header (pre-converted)
var gravity: Vector3 = Vector3(0.0, -0.036, 0.0)
var inertia_threshold: float = 512.0

# Cache loaded EffectData by directory path to avoid re-reading files from disk
static var _cache: Dictionary = {}  # dir_path -> EffectData


static func load_from_directory(dir_path: String) -> _Self:
	"""Load effect from directory containing parser output JSON files.
	Results are cached — repeated calls with the same path return the cached instance."""
	if _cache.has(dir_path):
		return _cache[dir_path]

	var data = _Self.new()
	data.name = dir_path.get_file()

	# Load particle header
	var header_path = dir_path.path_join("particle_header.json")
	var header = _load_json(header_path)
	if header:
		var grav = header.get("gravity", [0, -0.036, 0])
		data.gravity = Vector3(float(grav[0]), float(grav[1]), float(grav[2]))
		data.inertia_threshold = float(header.get("inertia_threshold", 512.0))

	# Load emitters
	var emitters_path = dir_path.path_join("emitters.json")
	var emitters_data = _load_json(emitters_path)
	if emitters_data and emitters_data is Array:
		for emitter_json in emitters_data:
			data.emitters.append(EffectEmitter.from_json(emitter_json))

	# Load curves
	var curves_path = dir_path.path_join("curves.json")
	var curves_data = _load_json(curves_path)
	if curves_data and curves_data is Array:
		for i in range(curves_data.size()):
			var curve_obj = curves_data[i]
			if curve_obj is Dictionary:
				# Curve is {index, values: [...]}
				var values = curve_obj.get("values", [])
				# Normalize 0-255 to 0-1
				var normalized: Array[float] = []
				for v in values:
					normalized.append(float(v) / 255.0)
				data.curves.append(EffectCurve.from_array(normalized, i))
			elif curve_obj is Array:
				data.curves.append(EffectCurve.from_array(curve_obj, i))

	# EXPLODE the shared table into one private curve per use site (ADR-0089 curve-
	# ownership amendment, decision 2). It runs HERE — after both emitters and curves
	# are loaded — because a use site is an (emitter, slot) pair, so it needs both. The
	# de-share is eager rather than copy-on-write at first edit: eager makes privacy
	# structural, so no future write path can forget to fork. The read path is unchanged
	# (a use site still resolves by index through get_curve).
	CurveExplode.explode(data)

	# Load animations
	var anims_path = dir_path.path_join("animations.json")
	var anims_data = _load_json(anims_path)
	if anims_data and anims_data is Array:
		data.animations = anims_data

	# Load frames (framesets)
	var frames_path = dir_path.path_join("frames.json")
	var frames_data = _load_json(frames_path)
	if frames_data and frames_data is Array:
		data.framesets = frames_data

	# Load frameset group sizes and compute cumulative offsets
	var groups_path = dir_path.path_join("frameset_groups.json")
	var groups_data = _load_json(groups_path)
	if groups_data and groups_data is Array:
		var offsets: Array[int] = []
		var cumulative := 0
		for size in groups_data:
			offsets.append(cumulative)
			cumulative += int(size)
		data.frameset_group_offsets = offsets

	var tex_meta = _load_json(dir_path.path_join("texture_meta.json"))
	if tex_meta is Dictionary:
		data.texture_meta = tex_meta

	# Load texture from effect directory (now consolidated with JSON files)
	var tex_path = dir_path.path_join("texture.tga")
	# Load the imported texture (the .tga is imported lossless — compress/mode=0,
	# no mipmaps — so this is the same pixels, but the optimized/export-safe path).
	# ResourceLoader.exists() gates on it being imported, so an un-imported tga is
	# skipped instead of emitting the "loaded as image file" warning.
	if ResourceLoader.exists(tex_path):
		data.texture = load(tex_path)

	# Load timeline
	var timeline_path = dir_path.path_join("timeline.json")
	var timeline_data = _load_json(timeline_path)
	if timeline_data:
		data.timeline = TimelineDataClass.from_json(timeline_data)

	# Load screen-subsystem keyframes (optional — background color animation)
	var screen_path = dir_path.path_join("screen.json")
	var screen_data = _load_json(screen_path)
	if screen_data:
		data.screen = ScreenDataClass.from_json(screen_data)

	# Load palette-subsystem keyframes (optional — unit/map color animation)
	var palette_path = dir_path.path_join("palette.json")
	var palette_data = _load_json(palette_path)
	if palette_data:
		data.palette = PaletteDataClass.from_json(palette_data)

	# Load camera-subsystem keyframes (optional — angle/position/zoom animation)
	var camera_path = dir_path.path_join("camera.json")
	var camera_data = _load_json(camera_path)
	if camera_data:
		data.camera = CameraDataClass.from_json(camera_data)

	# Load sound-subsystem keyframes (optional — SFX trigger timeline). The addon's
	# EffectSoundController loads this itself for playback; the Effect Studio score
	# reads this raw copy to draw the sound lanes. Shape: { phase -> [channel dicts] }.
	var sound_path = dir_path.path_join("sound.json")
	var sound_data = _load_json(sound_path)
	if sound_data and sound_data is Dictionary:
		data.sound = sound_data

	# Load the shared, effect-global TIER-2 SoundContainers (optional). Same single-source
	# reasoning as `sound` above: the addon's resolver loads this for playback, but the
	# Effect Studio edits it in place through the choke point and the score/ghost/views read
	# THIS reference — so it lives on EffectData rather than being re-parsed per consumer.
	var containers_path = dir_path.path_join("sound_containers.json")
	var containers_data = _load_json(containers_path)
	if containers_data and containers_data is Dictionary:
		data.sound_containers = containers_data

	# The FEDS bank (feds.bin) — TIER-3 byte truth (ADR-0085). Loaded here so the
	# SoundDefChannel encoder, the studio env and playback all share ONE object. Through
	# the port since ADR-0318 dec. 7, so `null` now covers TWO absences — no file, and no
	# audio package installed — and the readers were already written for the first.
	var feds_path = dir_path.path_join("feds.bin")
	if FileAccess.file_exists(feds_path):
		data.feds_bank = SfxPort.load_feds_bank(feds_path)

	# Load time scale (optional - for dramatic slowdown effects)
	var time_scale_path = dir_path.path_join("time_scale.json")
	var time_scale_data = _load_json(time_scale_path)
	if time_scale_data and time_scale_data is Dictionary:
		data.time_scale = time_scale_data

	# Load effect flags (the GLOBAL flags byte — #272). Present in every effect, so
	# unconditional; the projector reads data.flags.flags_byte the way #271 reads data.timeline.
	var flags_path = dir_path.path_join("effect_flags.json")
	var flags_data = _load_json(flags_path)
	if flags_data and flags_data is Dictionary:
		data.flags = flags_data

	# Parse callback slots from script.json (CODE-format effects with MIPS callbacks)
	var script_path = dir_path.path_join("script.json")
	var script_data = _load_json(script_path)
	if script_data and script_data is Array:
		data.script_ops = script_data
		for op in script_data:
			if op is Dictionary and op.get("name") == "load_callback":
				data.callback_slots.append({
					"slot": int(op.get("flags", 0)) / 2,
					"callback_id": int(op.get("arg1", 0))
				})

	# CODE-vs-DATA format (header.json is_code_format) — gates the #273 pattern swap
	# read-only for CODE effects (their script is MIPS, not editable bytecode).
	var effect_header_path = dir_path.path_join("header.json")
	var effect_header = _load_json(effect_header_path)
	if effect_header and effect_header is Dictionary:
		data.script_code_format = bool(effect_header.get("is_code_format", false))

	_cache[dir_path] = data
	return data


static func _load_json(path: String):
	"""Load and parse JSON file"""
	if not FileAccess.file_exists(path):
		return null

	var file = FileAccess.open(path, FileAccess.READ)
	if not file:
		return null

	var content = file.get_as_text()
	file.close()

	var json = JSON.new()
	var error = json.parse(content)
	if error != OK:
		push_error("Failed to parse JSON: " + path)
		return null

	return json.data


func get_curve(index: int) -> EffectCurve:
	"""Get curve by index, or null if invalid"""
	if index < 0 or index >= curves.size():
		return null
	return curves[index]


func get_emitter(index: int) -> EffectEmitter:
	"""Get emitter by index, or null if invalid"""
	if index < 0 or index >= emitters.size():
		return null
	return emitters[index]


func frameset_group_offset(group: int) -> int:
	"""Cumulative frameset offset for a frameset GROUP (an emitter's anim_param).

	The ONE derivation of emitter → group → absolute frameset. A sequence's FRAME
	opcode stores a frameset index RELATIVE to the group, so the absolute index into
	`framesets` is `opcode.frameset + frameset_group_offset(emitter.anim_param)` —
	which means the same opcode resolves to a DIFFERENT sprite depending on which
	emitter plays it. Out-of-range degrades to 0 (group 0's offset is always 0, since
	the cumulative sum starts there), so a garbage u8 anim_param reads as "no shift"
	rather than erroring.

	This function had four independent copies before the drill-down work (ADR-0073
	amendment, 2026-08-18): ActiveEmitter._get_group_offset, an inline copy in
	ParticleSubsystem.spawn_child, another in the studio's EmitterSpriteColor, and the
	one the frameset links needed. They agreed, but "documented truth with an
	unenumerated consumer" is exactly the shape that produced the last two bugs on this
	branch, so they now all route here. Add a caller, do not add a fifth copy.
	"""
	if group < 0 or group >= frameset_group_offsets.size():
		return 0
	return frameset_group_offsets[group]


func estimate_pool_size() -> int:
	"""Estimate mesh pool size needed from emitter data.

	Per-emitter: max_concurrent = particle_count * (lifetime / interval).
	Sum across emitters, multiply by max_frames_per_frameset * 2 (dual-pass).
	Lifetime -1 (animation-driven) treated as 30 frames. Minimum 64.
	"""
	var total_concurrent: int = 0
	for emitter in emitters:
		var count: int = maxi(emitter.particle_count_start, emitter.particle_count_end)
		var life: int = maxi(emitter.lifetime_max_start, emitter.lifetime_max_end)
		if life <= 0:
			life = 30  # Animation-driven: conservative estimate
		var interval: int = maxi(1, emitter.spawn_interval_start)
		total_concurrent += ceili(float(life) / float(interval)) * count

	var max_frames: int = 1
	for fs in framesets:
		if fs is Dictionary:
			var frames = fs.get("frames", [])
			if frames.size() > max_frames:
				max_frames = frames.size()

	return maxi(64, total_concurrent * max_frames * 2)


func get_animation_duration(anim_index: int, _anim_param: int = 0) -> int:
	"""Get animation duration in frames by summing FRAME opcode durations.

	In FFT, particles with Life=-1 use animation-driven lifetime.
	Duration = sum of all FRAME opcode durations until LOOP.

	Args:
		anim_index: Animation index to look up
		_anim_param: Reserved for future use (frame group selection)

	Returns:
		Total duration in frames, or 60 as fallback
	"""
	if anim_index < 0 or anim_index >= animations.size():
		return 60  # Default fallback

	var anim = animations[anim_index]
	if not anim is Dictionary or not anim.has("opcodes"):
		return 60

	var total_duration: int = 0
	for opcode in anim.opcodes:
		if opcode is Dictionary:
			if opcode.get("type") == "FRAME":
				total_duration += int(opcode.get("duration", 0))
			elif opcode.get("type") == "LOOP":
				break  # Stop at loop

	return maxi(1, total_duration)


func get_animation_display_length(anim_index: int) -> int:
	"""The BAKED play length in GAME frames — the actual lifespan of an animation-driven
	(Life=-1) particle, and the honest window for its over-life colour curves. MIRRORS
	ParticleAnimator baking: each FRAME opcode displays for maxi(1, (duration + 1) >> 1)
	game frames (FFT frame_timer decrements by 2/frame, and the halving ROUNDS UP — the
	ROM at 0x801AA1F8 advances only once the sign-extended timer is < 1, so an odd
	duration gets one more call; a duration=0 opcode is terminal = 1
	frame), summed over every FRAME opcode (LOOP is a no-op marker, not a stop — matching
	the baker). Distinct from get_animation_duration above, which sums RAW durations until
	LOOP (2x too large + no per-frame floor). Returns -1 when the animation can't be
	resolved, so the caller falls back to the whole 160-sample curve rather than invent a
	length. Guarded ≡ ParticleAnimator.get_animation_duration in EffectAnimationDisplayLengthTest."""
	if anim_index < 0 or anim_index >= animations.size():
		return -1
	var anim = animations[anim_index]
	if not anim is Dictionary or not anim.has("opcodes"):
		return -1
	var total: int = 0
	var saw_frame: bool = false
	for opcode in anim.get("opcodes", []):
		if opcode is Dictionary and opcode.get("type") == "FRAME":
			total += maxi(1, (int(opcode.get("duration", 1)) + 1) >> 1)
			saw_frame = true
	return total if saw_frame else -1
