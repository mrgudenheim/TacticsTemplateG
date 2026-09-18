@tool
extends RefCounted
## The display-calibration PORT SIGNATURE — what an addon may name instead of the
## autoload beside this file.
##
## `PSXDisplay.gd` is registered by the HOST's `project.godot [autoload]` block,
## so naming it from inside an addon is the same standalone-parse break as naming
## the tunable registry, and `check_addon_portability.py` arm 2 counted it the
## same way. This class is `TunePort`'s shape for the other port half: a
## `class_name` an installed addon carries, soft-bound to the singleton by node
## path at call time (ADR-0175 dec. 2).
##
## Four members, each added when an addon actually reached for it — two live
## mirrors the cursor divides one by the other, the camera-angle push #590 moved
## onto this port, and the camera-angle READ #848 found the sprite rig needed.
## Everything else the autoload exposes is read by the host, by a debug panel, or
## by the port itself, and none of those are addon code.
##
## The CONSTANTS below are the other half of what this file is for, and they are
## soft-bound to nothing: they are PSX display geometry, the same number whether or
## not the autoload is there. `NATIVE_VIEWPORT_HEIGHT` / `VERTICAL_DATUM_PX` are here
## for the reason the verbs are — the gameplay camera lives in a sibling ADDON and the
## cinematic camera lives in the HOST's `src/`, so this addon is the only file both
## may name.
##
## 🔴 **THE PUSH SHIPPED WITHOUT ITS READ, AND THAT IS WHAT #848 TURNED OUT TO
## BE.** #590 moved `set_camera_angle` onto this port and left the mirror it writes
## reachable only as a PROPERTY on the autoload — which serves the host and cannot
## serve an addon. So
## `addons/exmateria_sprite_rig/render/CameraRelativeRenderer.gd` went on naming the
## bare `PSXDisplay` identifier, did not parse in a project without the `[autoload]`
## line, and was the sprite rig's last goal #5 install-half debt (ADR-0234). A port
## half is not shipped until BOTH directions of the value are on it, and a push-only
## half reads as complete for exactly as long as nobody outside the host wants the
## value back.
##
## 🔴 **The fallbacks are the identity values, and that is a decision.** With no
## autoload there is no `[shader_globals]` boot value to source a default from —
## the addon cannot read the consuming project's `project.godot`, which is the
## whole reason this class exists. `1.0` is "no stretch": a consumer installing
## this addon into a project with no display calibration gets the geometry
## unmodified rather than a `null` propagated into a `maxf`.
##
## It also decouples 3 call sites from the autoload's SPELLING.
## [#583](https://github.com/timbermania/fft-monorepo/issues/583) renames
## `PSXDisplay` to `DisplayCalibration` (ADR-0171 dec. 4); after this port, that
## rename reaches the node path on the line below and nothing in any addon.

## No stretch. The `psx_*_stretch` family's `[shader_globals]` boot value in this
## repo's own `project.godot`, and the value at which the fold's billboard math
## is a no-op.
const NO_STRETCH := 1.0

## The PSX 3D framebuffer's height in native pixels — FFT renders 256x240 and the
## display stretches the WIDTH to 4:3 (ADR-0036), so the height is un-stretched and
## this is the denominator that turns a native-pixel screen offset into a fraction of
## an orthographic camera's vertical world extent (KEEP_HEIGHT: `Camera3D.size` IS
## that extent, so `world_shift = (px / 240) * size`).
const NATIVE_VIEWPORT_HEIGHT := 240.0

## FFT frames its optical centre LOW: 40 native px BELOW the 240-frame midpoint 120.
##
## The GTE translation decomposes as `TR = -R*work_position + (256, 160, 640)` (the
## datum is `DAT_800a77b0`), so the point the camera aims at projects to native
## (128, 160) — horizontally centred, vertically 160. A Godot ortho rig centres at 120
## and therefore lands every subject 40 px too HIGH. Vault: [[Scenario Camera Framing]].
##
## The design reason, so the number is not a mystery to the next reader: the anchor is
## at the subject's FEET while the sprite, the floating damage numbers, the cast poses
## and the spell blooms all live above it, so a low anchor buys headroom (160 px above
## vs 80 below) and puts the subject's visual mass near optical centre; in isometric
## projection world height maps to screen-up, so the terrain the cursor is about to
## climb recedes toward the top and a low aim keeps the up-slope in frame; and the
## bottom strip is UI (the AT list / info window).
##
## 🔴 THIS LIVES HERE BECAUSE TWO RIGS FRAME THE SAME TILE. `src/scenarios/
## ScenarioCameraDirector.gd` (the cinematic rig) and
## `addons/exmateria_battlefield/camera/PlayerCamera.gd` (the gameplay rig) both apply
## it, and they are in different packages — the host's `src/` and a sibling addon — so
## the platform addon is the only home either may name. A copy on each side is two
## framings for one tile, which is the bug this constant closes.
##
## 🔴 AND IT MUST BE APPLIED IN THE CAMERA'S LOCAL-UP BASIS, POST-ROTATION. A constant
## WORLD-space nudge was tried and deleted (ADR-0057): its projected screen shift
## `(-d.right, -d.up)` rotates with the camera, so one tuned value is wrong at every
## other pose. The GTE adds `TR` after the rotation; so must we.
const VERTICAL_DATUM_PX := 40.0

## Resolved singleton, or `null`. Same cache discipline as `TunePort`: never
## caches a negative, and `has_method` rejects the editor's non-`@tool`
## placeholder, which answers to the name and carries none of the methods.
static var _port: Node = null


static func _resolve() -> Node:
	if _port != null and is_instance_valid(_port):
		return _port
	var loop := Engine.get_main_loop()
	if loop == null or not (loop is SceneTree):
		return null
	var root: Window = (loop as SceneTree).root
	if root == null:
		return null
	var n := root.get_node_or_null(^"PSXDisplay")
	if n == null or not n.has_method(&"set_camera_angle"):
		return null
	_port = n
	return n


## Test seam — see `TunePort._forget_port` for why `is_instance_valid` is not the
## same question as "does the lookup still succeed".
static func _forget_port() -> void:
	_port = null


## The live WORLD-side PAR scrub (`live_par`), the mirror `live_ui_par` parallels on
## the UI side. Added when extraction #9 reached for it: `ScenarioDialogueBoxPool`
## multiplies a dialogue-box offset by the world PAR so the box responds to a scrub
## (ADR-0036), and naming `PSXDisplay` from inside an addon is the standalone-parse
## break this class exists to end (ADR-0308 dec. 1). ADR-0234 dec. 1's rule is that a
## member is added when an addon actually reaches for it, which is this.
##
## `NO_STRETCH` without a port, for `live_ui_par`'s reason: PAR is a MULTIPLIER, so
## the absent value is the multiplicative identity and a portless consumer renders
## unscrubbed rather than at zero width.
static func live_par() -> float:
	var p := _resolve()
	if p == null:
		return NO_STRETCH
	return p.live_par


## The live per-effect sprite stretch (`psx_fx_stretch`). A verb, not a property:
## a static var cannot carry the soft-bind's absent branch.
static func live_fx_stretch() -> float:
	var p := _resolve()
	if p == null:
		return NO_STRETCH
	return p.live_fx_stretch


## The live cursor sprite stretch (`psx_cursor_stretch`).
static func live_cursor_stretch() -> float:
	var p := _resolve()
	if p == null:
		return NO_STRETCH
	return p.live_cursor_stretch


## The live 12-bit PSX camera yaw (0..0xFFF) — the READ half of
## `set_camera_angle` below, which is what holds this mirror.
##
## `0` without the port, and unlike `NO_STRETCH` above that is NOT a chosen
## identity: it is the autoload's own boot value for `live_camera_angle`, and it is
## the fallback the one call site already spelled before this verb existed. An
## absent calibration therefore puts every unit on the baseline pose octant — a
## defined, uniform pose rather than a `null` propagated into
## `AnimationStateController.get_pose_octant`.
static func live_camera_angle() -> int:
	var p := _resolve()
	if p == null:
		return 0
	return p.live_camera_angle


## The live UI pixel-aspect ratio — the per-element MESH-WIDTH multiplier ui3
## elements scale their geometry by. Distinct from `live_fx_stretch` (a sprite
## billboard width) and from world PAR (a shader-side clip-X stretch): they are
## parallel systems and are not necessarily tuned to the same value.
##
## `NO_STRETCH` without the port, and here that is BOTH of the reasons the other
## fallbacks on this file cite, which is unusual and worth saying. It is the
## identity — square UI pixels, geometry unmodified. It is ALSO the autoload's own
## boot value: `PSXDisplay._ui_par_default` is `1.0` and its comment says that
## default *"has ONE home here"*.
##
## 🔴 **THE CALL SITES SPELL 1.25 AND THAT NUMBER IS STALE.** `UIChar`, `UIFrame`,
## `UIPortrait`, `UIText` and `DialogueBox` each carry `1.25` as an `@export`
## initial or an explicit editor-preview fallback, so the `live_camera_angle` rule
## on this file — take the fallback the call site already spelled — would pick it.
## It must not: 1.25 is the ADR-0036 initial value that `live_ui_par` OVERWRITES on
## the first PAR notify, and `TurnQueueHud` re-measured this and recorded that the
## PAR the game actually runs at is 1.0. Taking 1.25 would render a consuming
## project at a ratio the host game never runs at. The editor-preview branches keep
## 1.25 because the autoload is non-`@tool` and genuinely absent there; that is a
## different question from a project without the `[autoload]` line.
static func live_ui_par() -> float:
	var p := _resolve()
	if p == null:
		return NO_STRETCH
	return p.live_ui_par


## Subscribe `c` to `live_ui_par_changed(value)` so an element rebuilds when the PAR
## is scrubbed. Returns `true` when the subscription is live.
##
## Idempotent, which is why this verb is a `connect_` and not a signal getter: all
## six call sites spelled `if not ....is_connected(c): ....connect(c)`, because a UI
## element removed and re-added to the tree runs `_ready()` again and `Signal.connect`
## raises on a duplicate. The guard belongs on the port once, not at six call sites.
static func connect_live_ui_par_changed(c: Callable) -> bool:
	var p := _resolve()
	if p == null or not p.has_signal(&"live_ui_par_changed"):
		return false
	if p.is_connected(&"live_ui_par_changed", c):
		return true
	return p.connect(&"live_ui_par_changed", c) == OK


## Hand the port a 12-bit PSX camera angle (0..0xFFF); it pushes the
## `psx_camera_angle` global and holds the runtime mirror. No-op without the
## port — the global is the port's to push (ADR-0171 dec. 1), so with no port
## there is nothing that owns the write.
static func set_camera_angle(psx_12bit: int) -> void:
	var p := _resolve()
	if p == null:
		return
	p.set_camera_angle(psx_12bit)
