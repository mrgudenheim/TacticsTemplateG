extends RefCounted

## One colour **recipe** — the CPU-side reduction of FFT's 11 PSX `Color` modes to
## two shapes, the pure core of ADR-0067's unified colour model. A recipe is what a
## colour layer computes from its input colour; the shader never sees mode numbers,
## only these two shapes:
##   • affine  {scale, bias}          → recipe(c) = c·scale + bias
##   • luma    {div, delta5, source}  → the integer floor((2R+3G+B)/div)+delta mix
## `luma_div == 0` is the free discriminator: 0 ⇒ affine, else luma.
##
## A recipe is the ABSOLUTE per-op shape applied to the fold's input colour — NOT
## the accumulating (scale,bias) of the old ScenarioColorTint. Composition of
## successive ops is the ColorStack's job (symbolic merge), so from_mode(0) is the
## fixed {scale=1, bias=delta}, never "bias += delta".
##
## See docs/adr/0067-color-modes-are-one-model.md and the "Color modes" cluster in
## CONTEXT.md. Extracted from ScenarioColorTint (kept byte-exact).

## This script, reached the way this addon reaches all its own internals after
## ADR-0212 dec. 1: by `preload` path, never by a global name. The statics below
## RETURN this type and `merge()` TAKES two of it — the deleted `class_name` is
## what used to spell that, and a self-`preload` is what spells it now.
const _Self = preload("res://addons/exmateria_schema/colour_model/ColorRecipe.gd")

## Affine shape: recipe(c) = src·scale + bias, where src is the colour-so-far
## (`affine_from_base == false`, modes 0/1) or the raw base colour
## (`affine_from_base == true`, modes 4/5/9). The absolute-base modes read `base`
## so consecutive same-param ops are IDEMPOTENT (base+delta, not base+N·delta) —
## the PSX palette applier reads the committed base for modes 4/5/6/7/9 (see the
## COMBAT_COLOR_APPLIER_RECONCILIATION Q2). Identity when scale=1, bias=0.
var scale: Vector3 = Vector3.ONE
var bias: Vector3 = Vector3.ZERO
var affine_from_base: bool = false

## Luma shape (Color modes 2/3/6/7). div == 0 means "affine — use scale/bias".
## `luma_from_base` selects the source: false = the colour-so-far (modes 2/3),
## true = the raw base colour (modes 6/7).
var luma_div: int = 0
var luma_delta5: Vector3i = Vector3i.ZERO
var luma_from_base: bool = true

## Integer quantization ceiling for this recipe's PARAM/luma space: 31 for the
## 5-bit CLUT (palette) consumer, 255 for the 8-bit framebuffer (screen) consumer.
## Only the affine `bias` and the luma path read it; the shape math is otherwise
## bit-depth-agnostic (ADR-0067 slice 5b — the "8-bit reduction"). Default 31 keeps
## every existing palette caller byte-exact.
var param_max: int = 31


## Affine recipe: recipe(c) = c·scale + bias (reads the colour-so-far, modes 0/1).
static func affine(s: Vector3, b: Vector3) -> _Self:
	var r := _Self.new()
	r.scale = s
	r.bias = b
	return r


## Absolute-base affine recipe: recipe(_) = base·scale + bias (reads the raw base
## colour, modes 4/5/9). Idempotent under repetition — the fix for the combat Cure
## white-blowout (issue #164): consecutive same-param ops all land on base+delta.
static func affine_base(s: Vector3, b: Vector3) -> _Self:
	var r := _Self.new()
	r.scale = s
	r.bias = b
	r.affine_from_base = true
	return r


## Luma recipe (Color modes 2/3/6/7). `div` is 6 or 12; `from_base` selects the
## source (true = raw base, modes 6/7; false = colour-so-far, modes 2/3). `max_val`
## is the integer luma ceiling (31 = 5-bit palette default, 255 = 8-bit screen).
static func luma(div: int, delta5: Vector3i, from_base: bool, max_val: int = 31) -> _Self:
	var r := _Self.new()
	r.luma_div = div
	r.luma_delta5 = delta5
	r.luma_from_base = from_base
	r.param_max = max_val
	return r


## FFT fast-table ramp length (Time 1..3 → fixed 8 frames regardless of Time).
const RAMP_FAST_FRAMES := 8


## Frame count a given `Time` byte ramps over. Mirrors the two DDA tables: Time<4 →
## fast (8 frames); Time>=4 → slow (32 steps, one every Time>>2 frames). Moved from
## ScenarioColorTint.
static func ramp_frames_for_time(time: int) -> int:
	if time <= 0:
		return 0
	if time < 4:
		return RAMP_FAST_FRAMES
	return 32 * (time >> 2)


## A layer's [0,1] fade weight after `elapsed` of `total` frames — linear DDA. Pure
## function of (elapsed, total) so any `now` is directly evaluable (seek/rewind). A
## zero-length ramp (Time=0 snap) is instantly complete.
static func progress_at(elapsed: int, total: int) -> float:
	if total <= 0:
		return 1.0
	return clampf(float(elapsed) / float(total), 0.0, 1.0)


## Symbolic composition of two settled AFFINE recipes: applying `below` first then
## `above` is one affine, collapsing the run so the live stack stays bounded — done
## reversibly (the source timeline is untouched, ADR-0067). Luma layers never merge
## (at most one is active per surface), so this is affine-only.
##
## The source distinction (current vs base) makes composition source-aware:
##   • above reads BASE  → above ignores `below` entirely; the merge IS `above`
##     (base·s1+b1). This is why a run of absolute-base ops is idempotent.
##   • above reads CURRENT → the classic `{s0·s1, s1·b0+b1}`; the result reads
##     whatever `below` read (base if below is base-source, else current).
static func merge(below: _Self, above: _Self) -> _Self:
	assert(below.luma_div == 0 and above.luma_div == 0, "affine merge is affine-only")
	if above.affine_from_base:
		return above
	var merged := affine(below.scale * above.scale, below.bias * above.scale + above.bias)
	merged.affine_from_base = below.affine_from_base
	return merged


## Byte-exact LUMA transform for one 5-bit CLUT entry — the pure integer core of
## Color modes 2/3/6/7 (the sepia/grey wash). Mix to L = floor((2R+3G+B)/div), then
## out_ch = clamp(L + delta_ch, 0, 31). div is 6 (modes 2/6) or 12 (modes 3/7).
## Verified byte-exact (227/227) vs the live scenario-8 field CLUT — moved verbatim
## from ScenarioColorTint; COLOR_TINT_LUMA_MODE_SEPIA.md §3.4.
static func luma_out5(base5: Vector3i, div: int, delta5: Vector3i) -> Vector3i:
	return luma_out(base5, div, delta5, 31)


## Bit-depth-agnostic luma core: mix to L = floor((2R+3G+B)/div), add per-channel
## delta, clamp to [0, max_val]. `max_val` = 31 (5-bit palette) or 255 (8-bit screen).
## `luma_out5` is the 5-bit alias kept for existing callers.
static func luma_out(base_i: Vector3i, div: int, delta_i: Vector3i, max_val: int) -> Vector3i:
	var l := (2 * base_i.x + 3 * base_i.y + base_i.z) / div  # integer floor
	return Vector3i(
		clampi(l + delta_i.x, 0, max_val),
		clampi(l + delta_i.y, 0, max_val),
		clampi(l + delta_i.z, 0, max_val))


## Sign-extend a param byte (Red/Green/Blue are signed bytes in the PSX applier).
static func _sb(b: int) -> int:
	b = b & 0xFF
	return b - 256 if b >= 128 else b


## Reduce a PSX `Color` mode + raw RGB param bytes to a recipe shape. `param_max` is
## the consumer's integer ceiling: 31 for the 5-bit CLUT (palette, default), 255 for
## the 8-bit framebuffer (screen). It normalizes the signed-byte delta into [0,1] and
## sets the luma space; the mode SHAPE is identical across both (ADR-0067 slice 5b).
static func from_mode(mode: int, r: int, g: int, b: int, param_max: int = 31, double_param: bool = false) -> _Self:
	param_max = maxi(1, param_max)  # guard the normalization denominator (never 0 -> inf)
	var d5 := Vector3i(_sb(r), _sb(g), _sb(b))  # raw signed RGB delta (signed byte)
	# The SCREEN Blend stepper (advance_screen_color_track @0x801A45C8) applies the param
	# DOUBLED: `r = (i8)start << 1` — dynamically PROVEN on E173/savestate9 (idx8 start_r=192
	# -> setter param -128; SCREEN_KEYFRAME_BLEND_GRADIENT_E173_NIGHTSWORD.md §2). The 5-bit
	# CLUT (palette) stepper does NOT double, so this is opt-in and defaults off.
	if double_param:
		d5 *= 2
	var delta := Vector3(d5) / float(param_max)  # normalized to [0,1] channel space
	match mode:
		0:
			# current + delta -> additive affine over the colour-so-far.
			return affine(Vector3.ONE, delta)
		4, 9:
			# base + delta -> additive affine over the ABSOLUTE base (idempotent).
			return affine_base(Vector3.ONE, delta)
		1:
			# (current >> 1) + delta -> dim-then-add over the colour-so-far.
			return affine(Vector3.ONE * 0.5, delta)
		5:
			# (base >> 1) + delta -> dim-then-add over the ABSOLUTE base (idempotent).
			return affine_base(Vector3.ONE * 0.5, delta)
		8, 10:
			# absolute-base / reset -> identity shape (the restore is a stack concern).
			return affine(Vector3.ONE, Vector3.ZERO)
		7:
			return luma(12, d5, true, param_max)
		6:
			return luma(6, d5, true, param_max)
		3:
			return luma(12, d5, false, param_max)
		2:
			return luma(6, d5, false, param_max)
	return affine(Vector3.ONE, Vector3.ZERO)


## True when this recipe reads the raw BASE colour rather than the colour-so-far —
## affine modes 4/5/9 (`affine_from_base`) and luma modes 6/7 (`luma_from_base`). Such
## a recipe at FULL progress ignores `current`, so it MASKS every layer below it in the
## fold (its output depends only on base). ColorStack uses this to keep a shadowed layer
## from re-surfacing when a restore ramps the masking layer's progress down.
func reads_base() -> bool:
	if luma_div == 0:
		return affine_from_base
	return luma_from_base


## Evaluate the recipe against the fold's input. `base` is the surface's base
## colour; `current` is the colour-so-far at this point in the stack. A current-
## source affine (modes 0/1) ignores `base`; a base-source affine (modes 4/5/9)
## reads `base`; luma picks its source via `luma_from_base`.
func apply(base: Vector3, current: Vector3) -> Vector3:
	if luma_div == 0:
		var affine_src := base if affine_from_base else current
		return affine_src * scale + bias
	# Luma: mix the source colour to a single luminance in the consumer's integer
	# space (param_max = 31 palette / 255 screen).
	var src := base if luma_from_base else current
	var m := float(param_max)
	var s5 := Vector3i((src.clamp(Vector3.ZERO, Vector3.ONE) * m).round())
	return Vector3(luma_out(s5, luma_div, luma_delta5, param_max)) / m
