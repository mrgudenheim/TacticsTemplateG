extends "res://addons/exmateria_effects/subsystem/ColorSubsystem.gd"
## Runtime SCREEN channel — the background gradient (sky/void). Single-channel ColorSubsystem,
## DECLARATIVE: mirrors PSX `FUN_80090258 @0x80090258`, the SAME 11-mode engine as the CLUT applier in
## 8-bit framebuffer space (ADR-0067 — one colour model). ONE continuous op stream (build_stream)
## folds the map's TOP/BOTTOM baselines — no seam pop. Two archetypes, ctrl bit 7: Blend SET = the
## 11-mode recolor of the SHARED param over each vertex's own baseline; Gradient CLEAR = an ABSOLUTE
## set of the endpoints to the keyframe's RGB (`screen_gradient_color_setter @0x80090048`) — a REAL
## write, not a no-op (refuted "FADE": SCREEN_KEYFRAME_BLEND_GRADIENT_E173_NIGHTSWORD.md). Ramp Time*8.
## Vault: [[Color Screen Opcode]]
## Vault: [[Display Space Blend Fold]]
## Vault: [[Screen Effect Gradient System]]
## vault: .vaults/comments/exmateria_effects/screen-subsystem-lane.md

const ScreenData = preload("res://addons/exmateria_effects/file_model/ScreenData.gd")

## Backdrop overlay reached through its PORT: a member may name no autoload at all (ADR-0308 dec. 1);
## the bare `ScreenEffectOverlay` reach was one of the three `known_failures.tsv` cascade rows.
const ScreenOverlayPort = preload("res://addons/exmateria_effects/install/ScreenOverlayPort.gd")

const ColorStackClass = ExMateriaSchema.ColorStack

## Same façade as ColorStack — the schema's generic-English globals collapsed onto one (ADR-0212 dec. 1).
const ColorRecipe = ExMateriaSchema.ColorRecipe

const CHANNEL := "screen"

## Which backdrop endpoint a fold targets — a Gradient sets the two stops INDEPENDENTLY (TOP folds
## start_r/g/b, BOTTOM folds end_r/g/b), so the stream is built once per endpoint; Blend is endpoint-agnostic.
const ENDPOINT_TOP := 0
const ENDPOINT_BOTTOM := 1

## Folded gradient endpoints (0-1): the map's default TOP/BOTTOM baseline through the op stream at the current frame.
var top_color: Color = Color.BLACK
var bottom_color: Color = Color.BLACK
var _default_top: Color = Color.BLACK
var _default_bottom: Color = Color.BLACK

var screen_data = null


func initialize(data, default_top: Color = Color.BLACK, default_bottom = null) -> void:
	"""Initialize with parsed screen-keyframe data + the map's default gradient TOP and
	BOTTOM baselines (ScreenEffectOverlay's default corners). If default_bottom is
	omitted it defaults to default_top (a flat background)."""
	screen_data = data
	_default_top = default_top
	_default_bottom = default_top if default_bottom == null else default_bottom
	top_color = _default_top
	bottom_color = _default_bottom
	_setup_channels([CHANNEL])


## One ColorStack spanning all started phases at their absolute offsets; 8-bit profile (quantize=false, param_max=255).
func build_stream(phase_starts: Dictionary, endpoint: int = ENDPOINT_TOP) -> ColorStackClass:
	var stack := ColorStackClass.new()
	stack.set_quantize(false)   # 8-bit framebuffer, full float
	stack.set_param_max(255)    # screen gradient applier is 8-bit (FUN_80090258)
	for phase in EffectPhaseClass.ALL:
		# Studio Solo/Mute: a muted screen lane (screen:<phase>) excludes its phase's ops; muting all phases ⇒ neutral backdrop.
		if phase_starts.has(phase) and not _muted_ops.has(phase):
			_push_phase_ops(stack, phase, phase_starts[phase], endpoint)
	return stack


## Push one phase's keyframes onto `stack` at base_offset + cumulative start; Blend = an 11-mode apply, Gradient = an absolute-set — BOTH consume the duration.
func _push_phase_ops(stack: ColorStackClass, phase: String, base_offset: int, endpoint: int = ENDPOINT_TOP) -> void:
	var ch = screen_data.get_channel(phase)
	if not ch or ch.keyframes.is_empty():
		return
	var start_frame := 0
	# Keyframe window = 0..max_keyframe-2, IDENTICAL to the palette stepper: `advance_screen_color_track @0x801A45C8` and its for_each twin
	# `for_each_phase_timeline_tick @0x801A3408` break on `index < max_keyframe-1` (live E173 §2.1/§5; the retired wider window refuted).
	var last_idx: int = mini(ch.keyframes.size(), maxi(0, ch.max_keyframe - 1))
	for i in range(last_idx):
		var kf = ch.get_keyframe(i)
		var dur := maxi(1, kf.duration_frames)
		if kf.mode == ScreenData.ScreenMode.BLEND:  # Blend (ctrl bit 7 set): a real 11-mode apply
			# The screen Blend applies the signed param DOUBLED (`start << 1`) — the 8-bit applier's convention (live E173 §2); the palette CLUT path does not.
			stack.push_op(kf.blend_mode, kf.start_r_raw, kf.start_g_raw, kf.start_b_raw,
				kf.time_value, base_offset + start_frame, ColorStackClass.MASK_WHOLE, dur, true)
		else:  # Gradient (ctrl bit 7 clear): absolute-set this endpoint's stop
			_push_gradient_op(stack, kf, base_offset + start_frame, dur, endpoint)
		start_frame += dur


## One Gradient (ctrl bit-7-clear) keyframe: an ABSOLUTE set of this endpoint's stop to its explicit bytes — start_r/g/b
## for TOP, end_r/g/b for BOTTOM — ramped linearly over dur (Time*8); mirrors `screen_gradient_color_setter @0x80090048`
## re-targeting the shared gradient block. Modeled affine scale-0, bias=target: the fold ramps whatever the backdrop is
## toward the target, discarding the per-vertex baseline, so top+bottom land on the SAME target. All 32,510 shipped
## keyframes have start==end; the split shows only if the studio authors top≠bottom (#255 scope B).
func _push_gradient_op(stack: ColorStackClass, kf, now: int, dur: int, endpoint: int = ENDPOINT_TOP) -> void:
	var target: Vector3
	if endpoint == ENDPOINT_BOTTOM:
		target = Vector3(kf.end_r_raw, kf.end_g_raw, kf.end_b_raw) / 255.0
	else:
		target = Vector3(kf.start_r_raw, kf.start_g_raw, kf.start_b_raw) / 255.0
	stack.push_layer(ColorRecipe.affine(Vector3.ZERO, target), now, dur, ColorStackClass.MASK_WHOLE)


func _evaluate(_channel: String, _phase: String) -> void:
	"""No-op: the screen timeline is DECLARATIVE (build_stream + the ColorStack DDA),
	like the palette. _deliver_output rebuilds and folds the stream each frame.
	Overridden empty because the base marks _evaluate abstract."""
	pass


func _reset_outputs() -> void:
	"""Reset the folded gradient endpoints to the map defaults."""
	top_color = _default_top
	bottom_color = _default_bottom


func _deliver_output() -> void:
	"""Self-deliver the screen gradient to ScreenEffectOverlay (ADR-0014). Folds the
	map's TOP and BOTTOM baselines through the one screen op stream at the absolute
	effect frame (PSX-faithful, no seam pop), delivered as a top/bottom-delta layer."""
	top_color = _fold_color(build_stream(_phase_first_frame, ENDPOINT_TOP), _default_top)
	bottom_color = _fold_color(build_stream(_phase_first_frame, ENDPOINT_BOTTOM), _default_bottom)
	ScreenOverlayPort.update_layer_gradient(owner_id,
		_delta(top_color, _default_top), _delta(bottom_color, _default_bottom))


func _delta(folded: Color, base: Color) -> Color:
	return Color(folded.r - base.r, folded.g - base.g, folded.b - base.b, 1.0)


## Probe the folded TOP backdrop at the parked frame WITHOUT delivering to the overlay — the #255 WYSIWYG solver reuses this exact forward path; pure read.
func fold_top() -> Color:
	return _fold_color(build_stream(_phase_first_frame), _default_top)


## Fold one baseline through the stream at the absolute frame, clamped to [0,1] (the PSX applier clamps to [0,255]).
func _fold_color(stream: ColorStackClass, base: Color) -> Color:
	var v: Vector3 = stream.fold(Vector3(base.r, base.g, base.b), 0, _frame)
	return Color(clampf(v.x, 0, 1), clampf(v.y, 0, 1), clampf(v.z, 0, 1), 1.0)
