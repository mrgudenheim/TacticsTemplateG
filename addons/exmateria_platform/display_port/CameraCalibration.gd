extends RefCounted
## FFT affine zoom ↔ Godot KEEP_HEIGHT orthographic span (ADR-0091 §2).
## At unity, one FFT world unit projects to one native pixel; one Godot tile
## contains 28 FFT units. Pixel aspect belongs to the display, not this span.
## MAP085 live map packets reject the former empirical 12.6 (0.680272× scale).
## Both directions share the law so seeding from a free camera preserves its view.

## The sibling this layer sits on top of, aliased back through the façade — the
## ADR-0211 dec. 4 idiom, used here for an in-addon sibling (ADR-0212 dec. 1).
const PsxMagnitude = ExMateriaPlatform.PsxMagnitude

## Native frame height in tile-sized world units, at raw zoom 4096.
const GODOT_CAMERA_SIZE := ExMateriaPlatform.DisplayPort.NATIVE_VIEWPORT_HEIGHT / PsxMagnitude.UNITS_PER_TILE

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
