extends RefCounted
## The display-space fold's userland seed/resolve passes (ADR-0074, CONTEXT.md "Fold surface").
##
## Pure render-target plumbing that brackets the engine's held-out fold pass. Ignorant of producers
## and carriers — it only owns the two fullscreen passes. The bracket sits *before* the transparent pass
## (ADR-0080) so modern linear-alpha transparents composite over the folded PSX result:
##   Pass A (POST_OPAQUE)      seeds   = opaque scene color -> a GAME-OWNED display-space texture
##                                       (linear->display), bound as the layer's `seed_texture`;
##                                       the engine copies it into the held-out target before
##                                       Pass B. Reuses foldsurface_seed.
##   Pass B (ENGINE)           folds   = the `compositor_layer` carriers, hardware add/sub/mix, drawn
##                                       over the seed into the engine-owned target (not ours). The engine
##                                       runs it between Pass A and Pass C — after the POST_OPAQUE seed,
##                                       before the PRE_TRANSPARENT resolve (Fold.FOLD_LAYER.stage=POST_OPAQUE).
##   Pass C (PRE_TRANSPARENT)  resolves = the engine-owned target (read via get_layer_texture) ->
##                                       color layer (display->linear + quantize to
##                                       `quantize_levels`), for EVERY PIXEL, reusing
##                                       foldsurface_resolve. Runs before the transparent
##                                       pass, so transparents then draw over the resolved PSX layer.
##
## There is no coverage mark: the PlayStation's framebuffer was 15-bit for the whole screen, so the
## fold crushes the whole screen (ADR-0309, which deletes the mark and records the stencil
## alternative it was weighed against).
##
## Migrated (wayfinder ticket 15) off the old magic-string `compositor_fold`/`color` scratch onto the
## general `compositor_layer` primitive: the held-out target is now engine-owned and keyed by the
## shared `Fold.FOLD_LAYER` resource; the seed is handed to the engine as a bound `Texture2DRD`.
##
## Split out of the old EngineFoldCompositor (which fused this scratch lifecycle with the per-frame
## carrier rebuild — two jobs that change for different reasons). EngineFoldCompositor now installs
## one of these via setup(camera) and keeps only the carrier loop.
##
## MUST run under the compositor_layer-capable engine + Forward+ (the engine Pass B + `compositor_layer`
## render_mode are Forward+-only; see RenderingServer.is_compositor_layer_supported()).
##
## Vault: [[Display Space Blend Fold]]

## This script, reached the way the addon reaches all its own internals after
## ADR-0212 dec. 1: by `preload` path, never by a global name.
##
## `ResolvePass._quantize_levels()` needs `quantize_levels`, and an INNER class
## cannot see the outer script's statics implicitly — it used to spell that
## `FoldSurface.quantize_levels`, through the `class_name` this addon no longer
## declares. PROBED under the 4.8 fork rather than reasoned: a self-`preload`
## binds, carries no cycle through `ExMateriaRender` (which preloads this file),
## and the read stays LIVE — mutating `quantize_levels` afterwards is visible
## through it, which is exactly what `tests/FoldSurfaceTest.gd` asserts when it
## sets `7.0` and reads the pass back.

## ADR-0212 dec. 1 — `addons/exmateria_schema` used to declare six bare globals,
## every one of them generic English (`Fold`, `DepthMode`, `ColorStack`,
## `ColorRecipe`, `CellMarking`, `TerrainCell`). It now declares only
## `ExMateriaSchema`, so these lines are what keep the use sites below spelled the
## way they were (ADR-0211 dec. 4).
const Fold = ExMateriaSchema.Fold

const _Self = preload("res://addons/exmateria_render/fold_bracket/FoldSurface.gd")

## Framebuffer quantization applied by Pass C, as **steps-1 per channel**.
##
## `31.0` is the PSX RGB555 framebuffer, and it is a **compromise, not vocabulary**
## (goal #8, ADR-0152): the PlayStation stored 5 bits per channel because of the
## hardware it had, and a consumer of this bracket may want the display-space fold
## without the 5-bit crush. Set `0.0` to resolve at full precision.
##
## It is a policy the bracket is GIVEN rather than a constant welded into its GLSL —
## which is the whole of goal #8's code half. It stays `31.0` by default because
## `Render` is the PlayStation look (ADR-0117 dec. 6, ADR-0150) and dropping it here
## is a regression, not progress. Changing it is a KNOWN DROP and owes a register
## entry at epilogue E1.
static var quantize_levels: float = 31.0

var _seed: CompositorEffect
var _resolve: CompositorEffect


## Install the Pass A/C passes on `cam` via a Compositor. Call once at setup. The Compositor
## (and the CompositorEffects it holds) is retained by the camera; this FoldSurface keeps its own
## references so a caller holding the FoldSurface keeps the passes alive.
func setup(cam: Camera3D) -> void:
	if cam == null:
		push_warning("[fold-surface] no camera — display-space fold disabled")
		return
	_seed = SeedPass.new()
	_resolve = ResolvePass.new()
	var comp := Compositor.new()
	comp.compositor_effects = [_seed, _resolve]
	cam.compositor = comp


# ============================================================================================
# ONE implementation, TWO adapters.
#
# Pass A and Pass C were two 90-line classes that differed in five values. Everything else — the
# `_rd / _shader / _pipeline / _fb_format / _sampler / _ready` field set, `_setup()`, `_disabled_blend()`,
# and the eight-step render callback (guard the callback type, lazy setup, fetch the
# RenderSceneBuffersRD, size check, pick source + destination, rebuild the pipeline when the
# framebuffer format moves, build the uniform set, draw three vertices with a 16-byte push constant)
# — was byte-identical, twice.
#
# So the pass is one thing and an adapter is a SPEC: which stage, which shader, what to read, what
# to write, and what quantization to send. Everything below the seam is `FullscreenPass`; everything
# genuinely per-adapter (the seed texture's lifecycle, the resolve's layer declaration) stays with
# its adapter, because it does not generalise — there is no third pass it would serve.
#
# This is an INTERNAL seam. The addon's published interface is `setup(cam)` above, and it did not move.
# ============================================================================================
class FullscreenPass:
	extends CompositorEffect
	var _rd: RenderingDevice
	var _shader: RID
	var _pipeline: RID
	var _fb_format: int = -1
	var _sampler: RID
	var _ready := false

	# --- the spec an adapter fills in ---------------------------------------------------------
	# (The stage is the adapter's `effect_callback_type`, set in its own `_init`.)

	## The `.glsl` this pass runs.
	func _shader_path() -> String:
		return ""

	## The texture this pass READS, sampled at binding 0. Invalid = nothing to do this frame.
	func _source_texture(_rb: RenderSceneBuffersRD) -> RID:
		return RID()

	## The texture this pass WRITES, as the single colour attachment. Invalid = nowhere to draw.
	## Called with the internal render size so an adapter that owns its target can (re)allocate.
	func _destination_texture(_rb: RenderSceneBuffersRD, _size: Vector2i) -> RID:
		return RID()

	## Push-constant slot 3 — the framebuffer quantization policy (ADR-0152). Seed does not
	## quantize; resolve reads the static every frame so a consumer setting it takes effect
	## without rebuilding the pass.
	func _quantize_levels() -> float:
		return 0.0

	# --- the shared implementation -------------------------------------------------------------

	## The 16-byte push constant both passes send: the render size, then the quantization policy in
	## slot 3 (it was `_pad` before ADR-0152), then one remaining pad word. The size is exact —
	## the shaders declare Params as vec2 + vec2. Pure and static, so the wire format is testable
	## without a RenderingDevice.
	static func push_constant(size: Vector2i, quantize: float) -> PackedByteArray:
		return PackedFloat32Array([float(size.x), float(size.y), quantize, 0.0]).to_byte_array()

	func _setup() -> void:
		_rd = RenderingServer.get_rendering_device()
		if _rd == null:
			return
		var f: RDShaderFile = load(_shader_path())
		if f != null:
			_shader = _rd.shader_create_from_spirv(f.get_spirv())
		var ss := RDSamplerState.new()
		ss.min_filter = RenderingDevice.SAMPLER_FILTER_NEAREST
		ss.mag_filter = RenderingDevice.SAMPLER_FILTER_NEAREST
		ss.repeat_u = RenderingDevice.SAMPLER_REPEAT_MODE_CLAMP_TO_EDGE
		ss.repeat_v = RenderingDevice.SAMPLER_REPEAT_MODE_CLAMP_TO_EDGE
		_sampler = _rd.sampler_create(ss)
		_ready = true

	func _disabled_blend() -> RDPipelineColorBlendState:
		var b := RDPipelineColorBlendState.new()
		var a := RDPipelineColorBlendStateAttachment.new()
		a.enable_blend = false
		b.attachments = [a]
		return b

	func _render_callback(cb: int, rd_data: RenderData) -> void:
		if cb != effect_callback_type:
			return
		if not _ready:
			_setup()
		if _rd == null or not _shader.is_valid():
			return
		var rb := rd_data.get_render_scene_buffers() as RenderSceneBuffersRD
		if rb == null:
			return
		var size := rb.get_internal_size()
		if size.x == 0 or size.y == 0:
			return
		var src := _source_texture(rb)
		if not src.is_valid():
			return
		var dst := _destination_texture(rb, size)
		if not dst.is_valid():
			return
		var fb := FramebufferCacheRD.get_cache_multipass([dst], [], 1)
		var fmt := _rd.framebuffer_get_format(fb)
		if not _pipeline.is_valid() or _fb_format != fmt:
			if _pipeline.is_valid():
				_rd.free_rid(_pipeline)
			_pipeline = _rd.render_pipeline_create(_shader, fmt, RenderingDevice.INVALID_FORMAT_ID,
				RenderingDevice.RENDER_PRIMITIVE_TRIANGLES, RDPipelineRasterizationState.new(),
				RDPipelineMultisampleState.new(), RDPipelineDepthStencilState.new(),
				_disabled_blend())
			_fb_format = fmt
		var u := RDUniform.new()
		u.uniform_type = RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE
		u.binding = 0
		u.add_id(_sampler)
		u.add_id(src)
		var uset := UniformSetCacheRD.get_cache(_shader, 0, [u])
		var pc := push_constant(size, _quantize_levels())
		var dl := _rd.draw_list_begin(fb)
		_rd.draw_list_bind_render_pipeline(dl, _pipeline)
		_rd.draw_list_bind_uniform_set(dl, uset, 0)
		_rd.draw_list_set_push_constant(dl, pc, pc.size())
		_rd.draw_list_draw(dl, false, 1, 3)
		_rd.draw_list_end()


# ============================================================================================
# Pass A — author the opaque scene color (linear→display, coverage α=0) into a GAME-OWNED texture
# bound as Fold.FOLD_LAYER.seed_texture, reusing the shipped foldsurface_seed fullscreen shader.
# The engine copies this texture into the held-out target before Pass B, then folds carriers over it.
# ============================================================================================
class SeedPass:
	extends FullscreenPass
	# The game-owned display-space seed: an RD texture we render into, wrapped in a Texture2DRD so the
	# engine (compositor_layer primitive) can read its current RD rid and copy it into the target.
	var _seed_tex: RID
	var _seed_t2d: Texture2DRD
	var _seed_size := Vector2i.ZERO

	func _init() -> void:
		effect_callback_type = EFFECT_CALLBACK_TYPE_POST_OPAQUE

	func _shader_path() -> String:
		return "res://addons/exmateria_render/fold_bracket/foldsurface_seed.glsl"

	## Reads the opaque scene colour...
	func _source_texture(rb: RenderSceneBuffersRD) -> RID:
		return rb.get_color_layer(0)

	## ...and writes the game-owned seed texture, sized to this frame.
	func _destination_texture(_rb: RenderSceneBuffersRD, size: Vector2i) -> RID:
		_ensure_seed_texture(size)
		return _seed_tex

	# (Re)allocate the game-owned seed texture to match the internal render size, and (re)bind it on the
	# shared layer resource. Format R8G8B8A8_UNORM + size + single layer match the engine-owned target by
	# construction (fold_layer.tres format=1 / FORMAT_RGBA8), so the engine's ticket-13 seed-copy exact
	# format/size check passes. R8G8B8A8_UNORM (not A2B10G10R10) because a Texture2DRD can only wrap an RD
	# format with an Image::Format equivalent, and it is UNORM so PSX additive saturation is preserved.
	# CAN_COPY_FROM lets the engine copy out of it; COLOR_ATTACHMENT lets us render the seed into it.
	#
	# Does NOT generalise — the resolve reads an ENGINE-owned target and owns no texture at all.
	func _ensure_seed_texture(size: Vector2i) -> void:
		if _seed_tex.is_valid() and _seed_size == size:
			return
		if _seed_tex.is_valid():
			_rd.free_rid(_seed_tex)
			_seed_tex = RID()
		var tf := RDTextureFormat.new()
		tf.format = RenderingDevice.DATA_FORMAT_R8G8B8A8_UNORM
		tf.texture_type = RenderingDevice.TEXTURE_TYPE_2D
		tf.width = size.x
		tf.height = size.y
		tf.depth = 1
		tf.array_layers = 1
		tf.mipmaps = 1
		tf.usage_bits = (RenderingDevice.TEXTURE_USAGE_COLOR_ATTACHMENT_BIT
			| RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT
			| RenderingDevice.TEXTURE_USAGE_CAN_COPY_FROM_BIT)
		_seed_tex = _rd.texture_create(tf, RDTextureView.new())
		_seed_size = size
		if _seed_t2d == null:
			_seed_t2d = Texture2DRD.new()
		# Live per-frame handle: updating the wrapped rid in place keeps the same object bound, so the
		# engine reads whatever we authored this frame (Texture2DRD does not own/free the rid — we do).
		_seed_t2d.texture_rd_rid = _seed_tex
		# Bind through a local — GDScript rejects assigning a property directly on the static reference.
		# UNTYPED `=`, never `:=`. Since #721 `Fold.FOLD_LAYER` is a lazy `static var` whose getter
		# returns an untyped value on purpose (naming `CompositorRenderLayer` in the kernel would put
		# back the parse-time fork dependency the laziness exists to remove — ADR-0191 dec. 14), so
		# `:=` here is `Cannot infer the type of "layer" variable`, a PARSE ERROR that takes this whole
		# addon down on the fork as well as off it.
		var layer = Fold.FOLD_LAYER
		layer.seed_texture = _seed_t2d

	func _notification(what: int) -> void:
		if what == NOTIFICATION_PREDELETE and _rd != null and _seed_tex.is_valid():
			# Unbind the stale rid first so the engine falls back to CLEAR rather than reading a freed
			# texture until the next FoldSurface rebinds a fresh seed.
			var layer = Fold.FOLD_LAYER   # untyped — see the note in _ensure_seed
			if layer.seed_texture == _seed_t2d:
				layer.seed_texture = null
			if _seed_t2d != null:
				_seed_t2d.texture_rd_rid = RID()
			_rd.free_rid(_seed_tex)
			_seed_tex = RID()


# ============================================================================================
# Pass C — resolve the engine-owned held-out target (seed + folded carriers) back into the color
# layer (display→linear + RGB555 quantize + coverage discard), reusing foldsurface_resolve. Reads the
# target via get_layer_texture(Fold.FOLD_LAYER) instead of the old magic-string scratch lookup.
# ============================================================================================
class ResolvePass:
	extends FullscreenPass

	func _init() -> void:
		effect_callback_type = EFFECT_CALLBACK_TYPE_PRE_TRANSPARENT
		# Declare which held-out layer this effect consumes (editor association + the documented
		# get_layer_texture contract). The same shared resource the fold carriers reference.
		# Does NOT generalise — the seed declares no layer; it BINDS one.
		#
		# `set()`, never `render_layers = ...`. `render_layers` is a fork-only member of
		# CompositorEffect, and GDScript resolves a bare member on `self` at PARSE time — so the
		# direct spelling is a parse error off-fork that takes this whole file, the two façades
		# above it and the CompositorAutopilot autoload with it. Deferring to run time is the same
		# fix ADR-0191 dec. 14 made for RenderingServer.is_compositor_layer_supported(); nothing
		# here runs off-fork anyway, because CompositorAutopilot._attach is behind `if not active`.
		set("render_layers", [Fold.FOLD_LAYER])

	func _shader_path() -> String:
		return "res://addons/exmateria_render/fold_bracket/foldsurface_resolve.glsl"

	## Reads the engine-owned held-out target for our layer (seed copied in + carriers folded over by
	## the engine's Pass B). Valid only inside this callback; INVALID if no carrier drew this frame,
	## which is the shared template's "nothing to do" exit.
	func _source_texture(_rb: RenderSceneBuffersRD) -> RID:
		# `call()`, never the direct call — same parse-time trap as `render_layers` in _init above.
		return call("get_layer_texture", Fold.FOLD_LAYER)

	## ...and writes back over the scene colour layer.
	func _destination_texture(rb: RenderSceneBuffersRD, _size: Vector2i) -> RID:
		return rb.get_color_layer(0)

	func _quantize_levels() -> float:
		return _Self.quantize_levels
