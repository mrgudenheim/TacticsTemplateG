extends RefCounted

## The CPU source of truth for one consumer's colour transform — ADR-0067's unified
## colour model, the DepthMode.gd analog. A ColorStack holds an ordered list of
## colour layers (a ColorRecipe + a timeline + a surface mask), evaluates each
## layer's progress at a given `now` via the byte-exact DDA, and packs the bounded
## uniform arrays that the shared shader include (color_stack.gdshaderinc) folds:
##
##   color_layer_rgb0[i] = (affine scale | luma delta5).xyz , .w = progress
##   color_layer_rgb1[i] = affine bias.xyz                  , .w = luma div (0 ⇒ affine)
##   color_layer_meta[i] = surface mask[2:0] | recipe source[3] (affine & luma)
##   color_layer_count
##
## The stack is re-derived from the layer timelines every frame (never an accumulated
## colour buffer), so any `now` is directly evaluable — park / rewind / scrub come for
## free. Drivers (ScenarioVM, EffectTimeline) are thin: they push layers and evaluate.
##
## See docs/adr/0067-color-modes-are-one-model.md and the "Color modes" cluster in
## CONTEXT.md.

## The recipe a colour layer holds — reached by `preload` path, because this
## addon names its own internals by path and never by a global (ADR-0212 dec. 1).
## `class Layer`'s `var recipe:` below is an inner class reading this outer
## top-level const as a TYPE, which was probed under the 4.8 fork before it shipped.
const ColorRecipe = preload("res://addons/exmateria_schema/colour_model/ColorRecipe.gd")

const MAX_COLOR_LAYERS := 8

## Surface-mask bit for a single-surface consumer (map, background, UI) and the
## whole-unit tint every shipped FFT effect uses (body|weapon|effect).
const MASK_SURFACE0 := 0x1
const MASK_WHOLE := 0x7


## One colour layer: a recipe faded in (or out, for a restore) over a frame window.
## Endpoints are implicitly {identity, recipe}; progress(now) is a pure function of
## the window, so the layer stores no "from" colour (ADR-0067).
class Layer extends RefCounted:
	var recipe: ColorRecipe
	var start_frame: int
	var duration_frames: int
	var mask: int
	# A restore (mode 8/10) runs this same layer's progress back DOWN to 0 over
	# [restore_start, restore_start+restore_dur], then the layer is expired.
	var restoring: bool = false
	var restore_start: int = 0
	var restore_dur: int = 0
	# The layer's progress at the instant the restore began — the restore eases from
	# HERE down to 0, so interrupting a still-fading-in layer never snaps it to full.
	# 1.0 (a settled layer) is the common case and the identity default.
	var restore_from: float = 1.0
	# Set by _restore when, at the restore instant, a SETTLED base-reading layer (mode
	# 4/5/9 or 6/7) sits above this one and fully covers its mask. Such a layer masks
	# this one — it contributes nothing to the settled composite — and PSX's single CLUT
	# no longer remembers it. So from the restore onward this layer must stay dormant:
	# ramping the mask's progress down must NOT re-surface it (the E173 map "red dip").
	var restore_shadowed: bool = false
	# For the transitional mirror path: a layer whose progress is supplied externally
	# (e.g. a luma cross-fade weight computed by ScenarioColorTint) rather than derived
	# from a timeline. -1 = timeline-driven.
	var fixed_progress: float = -1.0

	func progress_at(now: int) -> float:
		if fixed_progress >= 0.0:
			return fixed_progress
		# A layer contributes nothing before it starts — restoring or not. The ramp DDA
		# already yields 0 for a not-yet-started FADE (negative elapsed clamps to 0), but
		# a SNAP layer (duration 0) reads "0-length ramp == fully applied" unconditionally,
		# so without this guard a keyframe authored for a later frame is wrongly active from
		# frame 0. This MUST sit above the restoring branch: a mode-8 restore flips every
		# prior layer `restoring` with restore_start = the restore op's frame, and for a
		# now before that frame the restoring branch returns restore_from(1.0) — resurrecting
		# a not-yet-started white snap and painting the map white (Ramuh E066 via the plain
		# path; Meteor E047 via this restoring path).
		if now < start_frame:
			return 0.0
		# Symmetric with is_expired (now >= restore_start + restore_dur): a restore flips
		# every prior layer `restoring` at BUILD time with restore_start = the restore op's
		# frame, but the frames between a layer's start and that restore predate the restore
		# and must use the NORMAL fade-in progress. Without the `now >= restore_start` guard
		# they hit the restoring branch and return restore_from(=1.0), resurrecting the layer
		# to full for every earlier frame (the Holy/E015 map "clicking": the flood layer
		# painted white across all frames from its start up to the restore).
		if restoring and now >= restore_start:
			return restore_from * (1.0 - ColorRecipe.progress_at(now - restore_start, restore_dur))
		return ColorRecipe.progress_at(now - start_frame, duration_frames)

	## True once a restore has fully run down — the layer no longer contributes and
	## drops from the packing (a backward seek before restore_start re-activates it).
	func is_expired(now: int) -> bool:
		return restoring and now >= restore_start + restore_dur

	## True while this layer is shadowed by a settled base-reading layer above it and the
	## restore has begun — it contributes nothing from restore_start onward and drops from
	## the fold (a backward seek before restore_start still shows its natural ramp, so the
	## pre-restore composite is untouched). Keeps the shadowed tint from leaking back through
	## the restore ramp-down. Symmetric with the `now >= restore_start` guard in progress_at.
	func is_dormant(now: int) -> bool:
		return restore_shadowed and now >= restore_start


var _layers: Array[Layer] = []

## Per-consumer 5-bit fidelity (ADR-0067): true = quantize the final colour to the
## PSX CLUT (byte-exact parity path), false = full float (game effects).
var _quantize: bool = false

## Per-consumer PARAM/luma integer ceiling handed to ColorRecipe.from_mode: 31 for the
## 5-bit CLUT (palette, default), 255 for the 8-bit framebuffer (screen). ADR-0067
## slice 5b — lets the screen share this one stack engine (the "8-bit reduction").
var _param_max: int = 31

# Packed uniform arrays, recomputed by evaluate().
var _rgb0: Array[Vector4] = []
var _rgb1: Array[Vector4] = []
var _meta: Array[int] = []
var _count: int = 0


## Push a colour layer onto the stack. `start_frame` + `duration_frames` define the
## fade window (duration 0 = snap, instantly at full progress); `mask` gates which
## sub-surfaces it touches (default whole-surface).
func push_layer(recipe: ColorRecipe, start_frame: int, duration_frames: int, mask: int = MASK_WHOLE) -> void:
	var layer := Layer.new()
	layer.recipe = recipe
	layer.start_frame = start_frame
	layer.duration_frames = duration_frames
	layer.mask = mask
	_layers.append(layer)


## Push a layer whose progress is supplied directly (the transitional mirror path:
## ScenarioColorTint computes the effective spec incl. a luma cross-fade weight, which
## maps to a fixed layer progress). Timeline-driven push_layer/push_op are the target
## model; this bridges while the old driver stays authoritative under the flag.
func push_fixed_layer(recipe: ColorRecipe, progress: float, mask: int = MASK_WHOLE) -> void:
	var layer := Layer.new()
	layer.recipe = recipe
	layer.mask = mask
	layer.fixed_progress = progress
	_layers.append(layer)


## Driver entry: apply one PSX Color op at `now`. Reduces (mode, r, g, b) to a recipe
## and either pushes a new fade-in layer or, for a restore mode (8 "palette absolute"
## / 10 "reset"), runs the active masked layers' progress back to base over `time`.
## `time` is the raw Color op Time byte; `mask` gates which sub-surfaces it touches.
## `dur` overrides the ramp length when >= 0. The 5-bit CLUT applier ramps over the
## fast/slow DDA tables (ramp_frames_for_time, the default), but the 8-bit screen
## gradient applier (FUN_80090258) ramps linearly over Time*8 = the keyframe's
## duration — the screen consumer passes that explicitly.
func push_op(mode: int, r: int, g: int, b: int, time: int, now: int, mask: int = MASK_WHOLE, dur: int = -1, double_param: bool = false) -> void:
	if dur < 0:
		dur = ColorRecipe.ramp_frames_for_time(time)
	if mode == 8 or mode == 10:
		_restore(mask, now, dur)
		return
	push_layer(ColorRecipe.from_mode(mode, r, g, b, _param_max, double_param), now, dur, mask)


## Restore (mode 8/10): fade every active layer whose mask intersects `mask` back to
## base over `dur` frames from `now` (snap if dur==0), then expire it.
##
## LIMITATION: a layer carries ONE restore window (restore_start/dur/from). Re-restoring
## a still-restoring layer (a second mode-8/10 before the first expires) OVERWRITES it, so
## the [first_restore_start, now] sub-window is no longer representable — a backward seek
## into it reads the plain ramp, not the first restore's partial ramp-down. No shipped
## driver emits overlapping restores on one layer (a restore is terminal), so this stays a
## documented corner rather than a multi-window redesign.
func _restore(mask: int, now: int, dur: int) -> void:
	# Bottom-up: when layer i is processed, the layers above it (j > i) are not yet
	# flipped, so _is_shadowed reads their NATURAL progress at `now`.
	for i in range(_layers.size()):
		var layer := _layers[i]
		if layer.is_expired(now) or (layer.mask & mask) == 0:
			continue
		layer.restore_shadowed = _is_shadowed(i, now)
		layer.restore_from = layer.progress_at(now)  # capture current before flipping
		layer.restoring = true
		layer.restore_start = now
		layer.restore_dur = dur


## True when a SETTLED (full-progress) base-reading layer sits above layer `idx` and its
## mask fully covers `idx`'s surfaces — that layer masks `idx` in the fold, so `idx`
## contributes nothing to the settled composite. Callers restore-shadow such layers so they
## stay dormant through the restore ramp-down (the PSX single-CLUT model forgets them).
func _is_shadowed(idx: int, now: int) -> bool:
	var lower := _layers[idx]
	for j in range(idx + 1, _layers.size()):
		var upper := _layers[j]
		if upper.is_expired(now) or not upper.recipe.reads_base():
			continue
		if upper.progress_at(now) < 1.0:
			continue  # a mid-fade mask only partly covers -> the layer below still shows
		if (upper.mask & lower.mask) == lower.mask:
			return true
	return false


## Re-derive the packed uniform arrays for time `now` from the layer timelines.
## Contiguous SETTLED (progress≥1) affine layers of the same mask are symbolically
## merged into one entry so repeated additive ops never overflow the layer budget;
## the merge happens only in the packed output — the source timeline is untouched,
## so a backward seek re-derives everything (ADR-0067).
func evaluate(now: int) -> void:
	_rgb0.clear()
	_rgb1.clear()
	_meta.clear()
	# A pending run of settled same-mask affines waiting to flush as one entry.
	var run: ColorRecipe = null
	var run_mask := 0
	for layer in _layers:
		if layer.is_expired(now) or layer.is_dormant(now):
			_flush_run(run, run_mask)  # a break in contiguity
			run = null
			continue
		var p := layer.progress_at(now)
		var recipe := layer.recipe
		var settled_affine := recipe.luma_div == 0 and p >= 1.0
		if settled_affine and run != null and layer.mask == run_mask:
			run = ColorRecipe.merge(run, recipe)  # extend the run
			continue
		_flush_run(run, run_mask)
		if settled_affine:
			run = recipe
			run_mask = layer.mask
		else:
			run = null
			_pack(recipe, p, layer.mask)
	_flush_run(run, run_mask)
	_count = _rgb0.size()


## Flush a merged run of settled affines as one packed entry (progress 1).
func _flush_run(run: ColorRecipe, mask: int) -> void:
	if run != null:
		_pack(run, 1.0, mask)


## Append one recipe to the packed uniform arrays at the given progress + mask.
func _pack(recipe: ColorRecipe, p: float, mask: int) -> void:
	if recipe.luma_div == 0:
		_rgb0.append(Vector4(recipe.scale.x, recipe.scale.y, recipe.scale.z, p))
		_rgb1.append(Vector4(recipe.bias.x, recipe.bias.y, recipe.bias.z, 0.0))
		# Meta bit 3 doubles as the affine source (0=current, 1=base); it is the luma
		# source only when div!=0, and a layer is affine XOR luma, so the bit is
		# unambiguous per layer. Base-source affines (modes 4/5/9) read `base`.
		var source_bit := (1 << 3) if recipe.affine_from_base else 0
		_meta.append(mask | source_bit)
	else:
		_rgb0.append(Vector4(recipe.luma_delta5.x, recipe.luma_delta5.y, recipe.luma_delta5.z, p))
		_rgb1.append(Vector4(0.0, 0.0, 0.0, float(recipe.luma_div)))
		var source_bit := (1 << 3) if recipe.luma_from_base else 0
		_meta.append(mask | source_bit)


func count() -> int:
	return _count


func rgb0() -> Array[Vector4]:
	return _rgb0


func rgb1() -> Array[Vector4]:
	return _rgb1


func meta() -> Array[int]:
	return _meta


## Set the per-consumer 5-bit quantization fidelity (pushed as quantize).
func set_quantize(on: bool) -> void:
	_quantize = on


## Set the per-consumer PARAM/luma ceiling for from_mode reductions: 31 (5-bit CLUT,
## default) or 255 (8-bit framebuffer/screen). Call once at consumer setup, before
## pushing ops. ADR-0067 slice 5b.
func set_param_max(m: int) -> void:
	_param_max = m


## {66} Commit Palette — fold the stack over every entry of a palette image and
## quantize to 5-bit in place, returning the baked copy. This is the one base-mutating,
## irreversible op: it redefines base so a later source=base recipe reads the committed
## tint (ADR-0067). Routing it through fold() means it handles luma commits too, not
## just the affine case the legacy MapComposer.bake_field_tint covered. Alpha preserved.
func commit_bake(src: Image, now: int) -> Image:
	if src == null:
		return null
	var w := src.get_width()
	var h := src.get_height()
	var out := Image.create(w, h, false, Image.FORMAT_RGBA8)
	for y in range(h):
		for x in range(w):
			var c := src.get_pixel(x, y)
			# The source IS a 5-bit BGR555 CLUT stored in an 8-bit texture, so
			# get_pixel returns byte/255, not exactly n/31. Snap to the true 5-bit
			# entry BEFORE the affine — the PSX committer (and the old inline
			# bake_field_tint) quantize the source first, so a scale!=1 field bakes
			# byte-exact only if we fold the snapped value, not the raw sample.
			var src5 := (Vector3(c.r, c.g, c.b).clamp(Vector3.ZERO, Vector3.ONE) * 31.0).round() / 31.0
			var folded := fold(src5, 0, now)
			# Quantize to the 5-bit CLUT (the committed palette IS 5-bit BGR555).
			var q := (folded.clamp(Vector3.ZERO, Vector3.ONE) * 31.0).round() / 31.0
			out.set_pixel(x, y, Color(q.x, q.y, q.z, c.a))
	return out


## CPU mirror of the shader's color_apply: evaluate at `now`, then fold the packed
## stack over `base` for one surface exactly as the GLSL include does — mask filter,
## c = mix(c, recipe(c), progress), quantize last. The single source of the fold shape
## is ColorRecipe.apply (shared with the GLSL). Used by the {66} commit bake (slice 4)
## and as the byte-exact test oracle proving the shader port is a no-op.
func fold(base: Vector3, surface_id: int, now: int) -> Vector3:
	evaluate(now)
	return fold_packed(_rgb0, _rgb1, _meta, _count, base, surface_id, _quantize, _param_max)


## Fold PRE-PACKED layer arrays over `base` for one surface — the CPU mirror of
## apply_packed (which pushes the same arrays to a material). This is the readback
## oracle for a concatenated multi-owner snapshot (e.g. a unit's stored TintedSurfaces
## layers): given the packed (rgb0, rgb1, meta) and count, it reproduces exactly what
## the shader's color_apply computes, byte-exact and GPU-free. `fold` delegates
## here after evaluating its own layers, so the fold shape has one definition.
##
## `param_max` is the LUMA/quantize integer ceiling (31 = 5-bit CLUT, 255 = 8-bit screen).
## IMPORTANT: the GLSL mirror (color_stack.gdshaderinc) is hardcoded 5-bit, so a
## param_max != 31 luma stack is byte-exact on the CPU ONLY. That is fine because the one
## 8-bit consumer (ScreenSubsystem) folds CPU-side and renders a gradient quad — it never
## routes through color_apply/apply_packed. A future GPU consumer of an 8-bit luma
## stack would need param_max threaded into the shader too (ColorStackGpuParityTest only
## covers the 5-bit path). Affine layers are unaffected (bias is pre-normalized in the pack).
static func fold_packed(rgb0: Array, rgb1: Array, meta: Array, count: int,
		base: Vector3, surface_id: int, quantize: bool, param_max: int = 31) -> Vector3:
	var c := base
	var surface_bit := 1 << surface_id
	for i in range(count):
		if (meta[i] & surface_bit) == 0:
			continue
		var recipe: ColorRecipe
		if rgb1[i].w == 0.0:
			var from_base: bool = (int(meta[i]) & (1 << 3)) != 0
			var s := Vector3(rgb0[i].x, rgb0[i].y, rgb0[i].z)
			var b := Vector3(rgb1[i].x, rgb1[i].y, rgb1[i].z)
			recipe = ColorRecipe.affine_base(s, b) if from_base else ColorRecipe.affine(s, b)
		else:
			var from_base: bool = (int(meta[i]) & (1 << 3)) != 0
			# Luma re-derives from the integer delta, so it needs the consumer's bit
			# ceiling (31 palette / 255 screen) — the affine bias above is already
			# normalized in the pack, but luma is not.
			recipe = ColorRecipe.luma(
				int(rgb1[i].w),
				Vector3i(roundi(rgb0[i].x), roundi(rgb0[i].y), roundi(rgb0[i].z)),
				from_base, param_max)
		c = c.lerp(recipe.apply(base, c), rgb0[i].w)  # rgb0.w = progress
	if quantize:
		var q := float(maxi(1, param_max))  # guard the divisor (symmetric with from_mode)
		c = (c.clamp(Vector3.ZERO, Vector3.ONE) * q).round() / q
	return c


## Push PRE-EVALUATED packed layer arrays onto a material — the multi-owner overlay
## path, where several consumers' ColorStack snapshots are concatenated into one
## layer list before folding. Mirrors apply()'s uniform contract (padded to the
## fixed size), but takes raw packed arrays instead of one live stack. `count` is
## the concatenated length, clamped to the budget; an empty list pushes count 0 and
## quantize false so an idle consumer is a true no-op (the include quantizes base
## even with zero layers). Consumers over budget are dropped — the caller logs it.
static func apply_packed(material, rgb0: Array, rgb1: Array, meta: Array, quantize: bool) -> void:
	var n := mini(rgb0.size(), MAX_COLOR_LAYERS)
	var p0 := PackedVector4Array()
	var p1 := PackedVector4Array()
	var pm := PackedInt32Array()
	p0.resize(MAX_COLOR_LAYERS)
	p1.resize(MAX_COLOR_LAYERS)
	pm.resize(MAX_COLOR_LAYERS)
	for i in range(n):
		p0[i] = rgb0[i]
		p1[i] = rgb1[i]
		pm[i] = meta[i]
	material.set_shader_parameter("color_layer_rgb0", p0)
	material.set_shader_parameter("color_layer_rgb1", p1)
	material.set_shader_parameter("color_layer_meta", pm)
	material.set_shader_parameter("color_layer_count", n)
	material.set_shader_parameter("quantize", quantize and n > 0)


## Evaluate at `now` and push the full uniform contract onto a ShaderMaterial: the
## four layer arrays (padded to the fixed uniform size so Godot accepts them), the
## live layer count, and the quantization flag. The DepthMode.apply() analog.
func apply(material, now: int) -> void:
	evaluate(now)
	var rgb0 := PackedVector4Array()
	var rgb1 := PackedVector4Array()
	var meta_arr := PackedInt32Array()
	rgb0.resize(MAX_COLOR_LAYERS)
	rgb1.resize(MAX_COLOR_LAYERS)
	meta_arr.resize(MAX_COLOR_LAYERS)
	for i in range(_count):
		rgb0[i] = _rgb0[i]
		rgb1[i] = _rgb1[i]
		meta_arr[i] = _meta[i]
	material.set_shader_parameter("color_layer_rgb0", rgb0)
	material.set_shader_parameter("color_layer_rgb1", rgb1)
	material.set_shader_parameter("color_layer_meta", meta_arr)
	material.set_shader_parameter("color_layer_count", _count)
	material.set_shader_parameter("quantize", _quantize)
