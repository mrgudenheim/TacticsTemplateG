extends RefCounted
## The PSX↔Godot **sign axis**: handedness, and nothing else (ADR-0052 / ADR-0057).
##
## PSX world space is Y-DOWN and Godot's is Y-UP, which is a 180° rotation about X.
## That rotation is not a magnitude and it is not a calibration, so neither sibling
## will take it: `PsxMagnitude` says so in its own charter (*"This is the MAGNITUDE
## axis; sign/chirality (the Y-flip, ADR-0052/0057) is a separate axis applied by the
## caller"*) and `CameraCalibration` holds only the dialled-in zoom↔ortho mapping.
## Before #1220 the axis therefore had no address at all — every caller applied it
## inline, or routed through a façade that described itself as pure delegation. This
## file is that address.
##
## Published as `ExMateriaPlatform.PsxChirality`; no `class_name` of its own
## (ADR-0212 dec. 1). Alias it back where a bare spelling reads better
## (ADR-0211 dec. 4):
##
##     const PsxChirality = ExMateriaPlatform.PsxChirality
##
## 🔴 IT WAS `class_name PSXCameraConvert` AND IT WAS NOT A FAÇADE, which is the one
## correction #1220 carries. ADR-0290 dec. 5 folded this file into
## `CameraCalibration` on the ground that *"it publishes no arithmetic of its own"* —
## reading its own header, which called it *"a thin FACADE over the consolidated
## seams … kept as a facade so its call sites don't churn."* gl-ADR-0295 dec. 4
## measured the call sites instead of reading the header, and the header was wrong
## about the file it was on. Re-measured at this commit, excluding the definition:
##
##     42  pure delegation  — psx_angle_to_deg 3, deg_to_psx_angle 18,
##                            psx_zoom_to_ortho_size 11, ortho_size_to_psx_zoom 10
##     43  ITS OWN AXIS     — psx_position_to_godot 11, godot_position_to_psx 17,
##                            psx_angles_to_godot_rotation 15
##
## The 42 are gone: those call sites now name `PsxMagnitude` and `CameraCalibration`
## directly. A delegate exists to stop call sites churning, and this move churns all
## 85 anyway — keeping it would have paid the cost AND kept the indirection. What is
## left is exactly the Y-negate and the `-pitch`, so the trio stays three names and
## completes ADR-0091 §2's split instead of compressing it.
##
## ⚠️ gl-ADR-0295 dec. 4 priced the own-axis half at **38** and the whole at **70**
## (its own 21 + 21 + 38 sums to 80, not 70 — the denominators already disagreed with
## each other). Measured here: 42 + 43 = **85**, with the pass-through half exact.
## The direction is the same and the conclusion is stronger, not weaker; the number
## is corrected rather than inherited (ADR-0290 dec. 10).
##
## Pure and stateless. The MAGNITUDE conversions it composes with are
## `PsxMagnitude`'s; this file contributes only the signs.
## Vault: [[Embedded MIPS Effect Code]]
## Vault: [[Scenario Camera Framing]]

## The magnitude seam this axis composes with, aliased back through the façade.
const PsxMagnitude = ExMateriaPlatform.PsxMagnitude


## PSX position → Godot world position: magnitude through `PsxMagnitude`, plus the
## Y-negate that is this file's whole reason for existing (PSX −Y = up).
static func psx_position_to_godot(pos: Vector3) -> Vector3:
	return Vector3(PsxMagnitude.tile_to_game(pos.x),
		-PsxMagnitude.tile_to_game(pos.y),
		PsxMagnitude.tile_to_game(pos.z))


## Godot world position → PSX position (the write side of the same flip).
static func godot_position_to_psx(pos: Vector3) -> Vector3:
	return Vector3(PsxMagnitude.game_to_tile(pos.x),
		-PsxMagnitude.game_to_tile(pos.y),
		PsxMagnitude.game_to_tile(pos.z))


## PSX pitch/yaw/roll → Godot rotation (radians). PSX pitch 302 ≈ 26.5° down, PSX
## yaw 3584 ≈ 315°.
##
## The sign work is the `-pitch`. Camera yaw is an Orientation (ADR-0057) and is
## consumed RAW: the prior `yaw_deg - 360.0` subtracted a full turn — a no-op
## rotation kept only to explain the ADR-0052 chirality investigation — so it is
## dropped for the identity. (The once-considered `-yaw_deg` was a
## double-correction: the 180°-about-X rotation already mirrors camera and world
## together, so a raw yaw is correct and a second flip blacks the scene. That is the
## Orientation rule, not an empirical quirk.)
static func psx_angles_to_godot_rotation(pitch: float, yaw: float, _roll: float) -> Vector3:
	var pitch_deg := PsxMagnitude.angle_to_deg(pitch)
	var yaw_deg := PsxMagnitude.angle_to_deg(yaw)
	return Vector3(deg_to_rad(-pitch_deg), deg_to_rad(yaw_deg), 0)
