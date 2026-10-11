extends RefCounted
## The thin, CALIBRATED render/camera layer atop `PsxMagnitude` (ADR-0091 §2).
##
## Published as `ExMateriaPlatform.CameraCalibration`, with no global of its own
## (ADR-0212 dec. 1). It was `class_name CameraCalibration` under `src/effects/` until
## extraction #7 (ADR-0290 dec. 5, #1220); the abbreviation went with the move,
## because what this file holds IS the dialled-in mapping and `Calib` reads as a verb
## stem. It lands beside `DisplayPort`/`PSXDisplay` rather than with the fixed-point
## pair, because `GODOT_CAMERA_SIZE` is a CALIBRATION — which is exactly what the
## charter below says the magnitude seam refuses.
##
## `PsxMagnitude` owns the pure PSX magnitude↔game conversions and stays free of
## calibration (mirroring PsxNum's "no calibration" charter). The camera zoom↔
## orthographic-size mapping is NOT pure: it carries `GODOT_CAMERA_SIZE = 12.6`, a
## value dialled in to match PSX FFT tile coverage at 4:3, so it lives here instead.
## `ZOOM_UNITY` is the PSX 20.12 fixed-point one (4096 = 1.0×) — numerically the
## shared base, referenced from PsxMagnitude so 4096 still lives in exactly one place.
##
## Pure and stateless. Both directions: zoom→ortho for rendering, ortho→zoom for
## the studio round-trip / byte-exact writes.

## The sibling this layer sits on top of, aliased back through the façade — the
## ADR-0211 dec. 4 idiom, used here for an in-addon sibling (ADR-0212 dec. 1).
const PsxMagnitude = ExMateriaPlatform.PsxMagnitude

## Orthographic size that renders PSX FFT tile coverage at 4:3 for a 1.0× zoom.
const GODOT_CAMERA_SIZE := 12.6

## PSX zoom unity: raw 4096 = 1.0× (20.12 fixed-point one; == the shared 4096 base).
const ZOOM_UNITY := float(PsxMagnitude.FULL_TURN)


## Raw PSX zoom (4096 = 1.0×) → Godot orthographic camera size. Higher zoom =
## smaller ortho (more zoomed in). A non-positive zoom guards to the 1.0× size.
static func zoom_to_ortho_size(zoom_raw: float) -> float:
	if zoom_raw <= 0.0:
		return GODOT_CAMERA_SIZE
	return GODOT_CAMERA_SIZE / (zoom_raw / ZOOM_UNITY)


## Godot orthographic camera size → raw PSX zoom (game→raw write side). A
## non-positive size guards to 1.0× (raw ZOOM_UNITY).
static func ortho_size_to_zoom(size: float) -> float:
	if size <= 0.0:
		return ZOOM_UNITY
	return ZOOM_UNITY * GODOT_CAMERA_SIZE / size
