extends Node2D
## The spell charge lines' SCREEN-SPACE draw: the handler's LINE_G2s as 1-PSX-px gouraud
## lines, blended ADDITIVELY (tpage abr 1, code 0x52), over the 3D scene — the lines are a
## pure 2D overlay on PSX, not geometry in the world (SPELL_CHARGE_LINES.md §4, branch
## research/spell-charge-lines [S·D]).
##
## A canvas item blends in display space, which is where the PSX blends too, so this needs
## nothing from the compositor fold. TrapChargeLineCallback owns it (under its own
## CanvasLayer) and hands it the prims each render frame.
##
## Scale: the PSX display is 240 lines, so one PSX pixel is `viewport height / 240` pixels
## here; the 256-px ring and the 1-px width scale with it and never with camera zoom.

const PSX_DISPLAY_LINES := 240.0

## ChargeLineModel.prims(): centre-relative PSX pixels.
var prims: Array = []
## The centre on this viewport, in pixels.
var centre := Vector2.ZERO
## Viewport pixels per PSX pixel.
var psx_px := 1.0


func _init() -> void:
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	material = mat


static func psx_pixel_size(viewport_height: float) -> float:
	return maxf(1.0, viewport_height / PSX_DISPLAY_LINES)


func _draw() -> void:
	# A PSX line lights whole pixels, both endpoints included: draw pixel centre to pixel
	# centre, then reach half a pixel past each end. The handler's 1-px nudge pulls each far
	# end back one pixel, so the next segment starts on the very next pixel — contiguous,
	# never doubled under the additive blend.
	var half := Vector2(0.5, 0.5) * psx_px
	for p in prims:
		var a: Vector2 = centre + Vector2(p.xy0) * psx_px + half
		var b: Vector2 = centre + Vector2(p.xy1) * psx_px + half
		var ext := (b - a).normalized() * psx_px * 0.5
		a -= ext
		b += ext
		draw_polyline_colors(PackedVector2Array([a, b]),
			PackedColorArray([_rgb(p.rgb0), _rgb(p.rgb1)]), psx_px)


static func _rgb(c: Array) -> Color:
	return Color8(int(c[0]), int(c[1]), int(c[2]))
