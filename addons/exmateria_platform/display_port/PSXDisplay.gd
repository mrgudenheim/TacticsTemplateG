extends Node

## Owns runtime PAR (pixel aspect ratio) state per ADR-0036.
##
## PSX renders at 256x240 (16:15) but displays at 4:3, so each PSX pixel
## is ~1.25× wide × 1 tall. Reproducing that on a square-pixel display means
## stretching opt-in content horizontally by 1.25. This autoload hosts:
##
##   - the world-side runtime scrub (`live_par`), whose setter writes the
##     project-wide `pixel_aspect` global shader parameter that every opt-in
##     Pattern 1/2 world shader reads after MVP,
##   - the UI-side runtime scrub (`live_ui_par`), the parallel mesh-width
##     multiplier UI3 elements (UIChar / UIText / UIPortrait / UIFrame) read
##     and subscribe to.
##   - the per-taxonomy sprite-WIDTH stretches (`live_cursor_stretch` /
##     `live_unit_stretch` / `live_fx_stretch`, ADR-0044), each writing its own
##     `psx_*_stretch` global — the billboard-width component layered on the
##     shared `pixel_aspect` anchor for Pattern-2 sprites.
##
## World and UI scrubs are independent on purpose — there's no single "PAR
## knob"; each surface tunes for its own evidence. The world-side scrubs live on
## the F3 Registry page (ADR-0068 dec. 9); UIDisplayDebugPanel is the host's
## hand-built UI-side one.
##
## Vault: [[Scenario Camera Framing]]

# INTERNAL_WIDTH / INTERNAL_HEIGHT / DISPLAY_WIDTH / PAR were DELETED here (ADR-0152).
# Four constants with zero readers anywhere in the tree, and `PAR := 1.25` was
# documented above as "the canonical constant" while the value the game actually runs
# is `project.godot [shader_globals] pixel_aspect`, which reads 1.0. A dead literal that
# contradicts the live one is a rival source of truth that this file's own single-home
# argument forbids. The PSX display geometry lives in the HOST's project.godot, which
# is already goal #8's "a policy the host supplies".

## The tunable port, reached the way this addon reaches all its own internals
## after ADR-0212 dec. 1: by `preload` path, never by a global name. `TunePort.gd`
## used to declare `class_name TunePort`; this addon now declares only
## `ExMateriaPlatform`, and the sixteen calls below are spelled exactly as they
## were. Not routed through the façade — the façade preloads this addon's files,
## so an internal reaching back through it would be a cycle for no gain.
const TunePort = preload("res://addons/exmateria_platform/tunables/TunePort.gd")


## Single source of truth (Option A / ADR-0036): the shader-backed mirrors below
## (`live_par` / `live_cursor_stretch` / `live_unit_stretch` / `live_fx_stretch`)
## own no default of their own — the number lives ONLY in `project.godot`
## `[shader_globals]`, sourced back at startup so nothing is duplicated.
##
## All four are Tune tunables (ADR-0068): `live_par` was the pilot migration and
## the three stretch siblings followed (the keystone slice). Each keeps its ONE
## project.godot home — sourced into `_<name>_default` in `_ready` — but the live
## value coalesces a committed `render.*` override over it: `_ready` `bind_update`s the
## slug (registering the `_<name>_default` literal AND the `_apply_*` push), the getter
## pull-reads it via `Tune.get_value(slug)`, the setter routes writes through
## `Tune.set_value`, and the `_apply_*` callback (the on_update half of the bind_update) is
## what pushes the matching global shader parameter + emits the `*_changed` signal.
## So a scrub or a boot-loaded override drives the shader the same way, and
## PSXDisplaySingleSourceTest checks each mirror against its coalesced value. The
## generated ADR-0068 Tunables card supersedes the hand-built panel scrubs that
## used to drive these.
##
## We source from `ProjectSettings` (`shader_globals/<name>`), NOT
## `RenderingServer.global_shader_parameter_get`: the RenderingServer's runtime
## registry only reflects values pushed via `global_shader_parameter_set` and
## returns null for the project.godot boot defaults. `ProjectSettings` is exactly
## where project.godot stores `[shader_globals]`, so it is the true single home.
##
## `live_ui_par` is NOT a shader global — it's a GDScript-only mesh-width
## multiplier for UI3 — so it keeps its own constant default and is not sourced
## here.
func _ready() -> void:
	register_tunables()


## Source each mirror's default from its project.godot home and bind_update the slug (register
## + push). Split out from _ready so a test that clears the registry via Tune.reset() can
## re-establish the binds (re-calling is a first-write-wins no-op on the registry; it does add
## a duplicate owner-scoped on_update, harmless in a short-lived test — production calls it once).
func register_tunables() -> void:
	_par_default = shader_global_default(&"pixel_aspect")
	# Affordance hint (ADR-0068 decision 11): the generated Tunables card renders a
	# clamped 0.5–2.0 spinbox, matching the hand-built PAR scrub it replaced.
	TunePort.bind_update(self, "render.pixel_aspect", _par_default, _apply_par,
		{"min": 0.5, "max": 2.0, "step": 0.01})
	# The three sprite-stretch siblings (ADR-0044) are Tune tunables too, sharing
	# the `render.*` namespace and the same 0.5–2.0 affordance hint as pixel_aspect so
	# the generated Tunables card renders identical clamped spinboxes.
	_cursor_stretch_default = shader_global_default(&"psx_cursor_stretch")
	TunePort.bind_update(self, "render.psx_cursor_stretch", _cursor_stretch_default,
		_apply_cursor_stretch, {"min": 0.5, "max": 2.0, "step": 0.01})
	_unit_stretch_default = shader_global_default(&"unit_stretch")
	TunePort.bind_update(self, "render.unit_stretch", _unit_stretch_default,
		_apply_unit_stretch, {"min": 0.5, "max": 2.0, "step": 0.01})
	_fx_stretch_default = shader_global_default(&"psx_fx_stretch")
	TunePort.bind_update(self, "render.psx_fx_stretch", _fx_stretch_default,
		_apply_fx_stretch, {"min": 0.5, "max": 2.0, "step": 0.01})
	# PSX color calibration (ADR-0068): the sRGB→linear gamma exponent, a global shader param.
	# Owned here so a committed override applies at boot in EVERY scene. The panel that
	# used to view this was pure declaration and is deleted (ADR-0151); the Registry page
	# renders the slug from this bind. Default from project.godot.
	# (psx_brightness was RETIRED in the ADR-0074 fold endgame: every fold now bakes its
	# ÷255→÷128 display-gouraud gain per-producer, so there is no shared brightness global left.)
	_gamma_default = shader_global_default(&"texel_blend_gamma")
	TunePort.bind_update(self, "render.texel_blend_gamma", _gamma_default, _apply_gamma,
		{"min": 0.5, "max": 3.0, "step": 0.1})
	# UI-side PAR (mesh-width multiplier, GDScript-only), same facade as pixel_aspect.
	TunePort.bind_update(self, "render.ui_pixel_aspect", _ui_par_default, _apply_ui_par,
		{"min": 0.5, "max": 2.0, "step": 0.01})


## The project.godot `[shader_globals]` boot value for `name` — the single home
## for these defaults (see `_ready`). Used by the reset buttons / panels too, so
## "reset" resolves the same source instead of hardcoding a rival literal.
##
## 🔴 AN ABSENT NAME IS REPORTED, NOT SERVED — ADR-0203 dec. 7. This read used to be
## `get_setting("shader_globals/" + name, {})` followed by `decl.get("value", 0.0)`, so a
## name the project does not declare came back as **`0.0`**, indistinguishable from a name
## declared `0.0`. That is not a cosmetic gap: `pixel_aspect` is a mesh-width MULTIPLIER, and a
## `pixel_aspect` of 0 collapses every vertex's x — the screen goes blank with no error anywhere.
## The install register's Class E is exactly the population that can be missing here
## (ADR-0202 dec. 8), and THIS addon's own `plugin.gd` provides all six at enable time
## (ADR-0220 dec. 1/2), so in a correctly installed project this branch never runs. It
## exists for the project where the addon was copied in and never enabled, which is the
## case that used to present as a blank screen.
##
## 🔴 THE PROVIDER USED TO BE `exmateria_battlefield`, AND THAT WAS THE LAYERING
## INVERSION, WRITTEN INTO THIS FILE'S OWN ERROR STRING. Every name read here is declared
## in `addons/exmateria_platform/`, but the `PROVIDED_GLOBALS` array that supplied them
## lived in a sibling SYSTEM addon — so a consumer that installed only fork+kernel+port
## got the declarations and none of the values, and the message below told them to enable
## a battlefield addon they had no reason to want. `exmateria_sprite_rig` is exactly that
## consumer, and it was uninstallable for as long as the rig has existed. ADR-0220 dec. 1
## rules that the addon which DECLARES a `global uniform` provides it; the declarations
## and the provide now live in one addon, which is why this text no longer names another.
##
## The return stays `0.0` because the signature is `-> float` and there is no honest
## substitute: inventing a `1.0` here would be the "rival literal" the paragraph above
## rules out, in the one place that would then disagree with every reset button. The
## degenerate value still ships; what changes is that it now says so.
static func shader_global_default(name: StringName) -> float:
	var decl: Variant = ProjectSettings.get_setting("shader_globals/" + name, null)
	if decl == null:
		push_error(("PSXDisplay: shader global `%s` is not declared. Enable the "
			+ "`exmateria_platform` plugin, whose `plugin.gd` provides every global "
			+ "uniform this addon declares (ADR-0220 dec. 1) — or declare it in the "
			+ "consuming project's `[shader_globals]`. Falling back to 0.0, which for "
			+ "`pixel_aspect` collapses every vertex's x.") % name)
		return 0.0
	if not (decl is Dictionary) or not (decl as Dictionary).has("value"):
		push_error(("PSXDisplay: shader global `%s` is declared but carries no `value` — got "
			+ "%s. Falling back to 0.0.") % [name, str(decl)])
		return 0.0
	return float((decl as Dictionary)["value"])

# Live PAR value, backed by the Tune tunable "render.pixel_aspect" (ADR-0068). The
# getter coalesces override-over-default; the setter routes writes through Tune;
# and `_apply_par` (bound in `_ready`) pushes the `pixel_aspect` global shader
# parameter (ADR-0036) + emits live_par_changed. All Pattern 1/2 shaders read
# that global, so a scrub re-stretches the whole opt-in surface in one move. The
# default has ONE home — project.godot `[shader_globals]`, sourced into
# `_par_default` in `_ready` (see PSXDisplaySingleSourceTest).
var _par_default: float = 0.0
var _par_applied: float = NAN  # last value pushed to shader/signal, for dedup

var live_par: float:
	get:
		return TunePort.get_value("render.pixel_aspect", _par_default)
	set(value):
		if is_equal_approx(live_par, value):
			return
		TunePort.set_value("render.pixel_aspect", value)


## Bound to "render.pixel_aspect" in `_ready`: push the coalesced value to the world
## shaders' `pixel_aspect` global and notify subscribers. Deduped so an unchanged
## re-apply is a no-op (preserves the old setter's semantics).
func _apply_par(v: float) -> void:
	if is_equal_approx(v, _par_applied):
		return
	_par_applied = v
	RenderingServer.global_shader_parameter_set(&"pixel_aspect", v)
	live_par_changed.emit(v)


# PSX color calibration global (ADR-0068), sourced from project.godot [shader_globals].
# (psx_brightness retired — ADR-0074 fold endgame; only texel_blend_gamma remains.)
var _gamma_default: float = 0.0


## Bound to "render.texel_blend_gamma" in `_ready`: push the coalesced value to the
## `texel_blend_gamma` global shader param.
func _apply_gamma(v: float) -> void:
	RenderingServer.global_shader_parameter_set(&"texel_blend_gamma", v)

# Live UI PAR value. UI3 elements (UIChar / UIText / UIPortrait / UIFrame)
# compute mesh-width as `source_width * live_ui_par * pixels_per_unit` and
# subscribe to `live_ui_par_changed` to rebuild on the fly. Distinct from
# `live_par` (the world shaders' clip-X stretch) because UI PAR is a per-element
# mesh-width multiplier, not a shader-side post-MVP multiply — they're parallel
# systems and not necessarily tuned to the same value (a debug font might want
# UI PAR = 1.0 while world PAR stays at 1.25, or vice-versa).
# Backed by the Tune tunable "render.ui_pixel_aspect" (ADR-0068), same facade shape as
# live_par: the getter coalesces override-over-default, the setter routes writes
# through Tune, and `_apply_ui_par` (bound in `_ready`) emits live_ui_par_changed so
# UI3 elements rebuild. NOT a shader global — a GDScript-only mesh-width multiplier.
# Default (1.0 — square UI PAR for alignment work; was PAR 1.25) has ONE home here.
var _ui_par_default: float = 1.0
var _ui_par_applied: float = NAN

var live_ui_par: float:
	get:
		return TunePort.get_value("render.ui_pixel_aspect", _ui_par_default)
	set(value):
		if is_equal_approx(live_ui_par, value):
			return
		TunePort.set_value("render.ui_pixel_aspect", value)


## Bound to "render.ui_pixel_aspect" in `_ready`: notify UI3 subscribers of the coalesced
## value. Deduped so an unchanged re-apply is a no-op (preserves the old setter).
func _apply_ui_par(v: float) -> void:
	if is_equal_approx(v, _ui_par_applied):
		return
	_ui_par_applied = v
	live_ui_par_changed.emit(v)

# --- Sprite stretch (ADR-0044) ---------------------------------------------
# Per-taxonomy horizontal billboard-WIDTH multiplier for Pattern-2 sprites,
# layered on top of the shared `pixel_aspect` anchor (so the sprite still tracks the
# map). Distinct from World PAR (anchor + Pattern-1 stretch) and UI PAR (UI
# mesh-width). Each defaults to 1.0 = native art (the ADR-0036 "sprites don't
# stretch" default), so nothing changes until a scrub moves it. One global per
# taxonomy because the buckets must stretch independently (cursor may want a
# stretch units shouldn't get). Setters write the matching `psx_*_stretch`
# global shader parameter; Pattern-2 shaders read their bucket's global.
# Backed by the Tune tunable "render.psx_cursor_stretch" (ADR-0068), same shape as
# live_par: the getter coalesces override-over-default, the setter routes writes
# through Tune, and `_apply_cursor_stretch` (bound in `_ready`) pushes the
# `psx_cursor_stretch` global + emits the changed signal. Default has ONE home
# (project.godot), sourced into `_cursor_stretch_default` in `_ready`.
var _cursor_stretch_default: float = 0.0
var _cursor_stretch_applied: float = NAN

var live_cursor_stretch: float:
	get:
		return TunePort.get_value("render.psx_cursor_stretch", _cursor_stretch_default)
	set(value):
		if is_equal_approx(live_cursor_stretch, value):
			return
		TunePort.set_value("render.psx_cursor_stretch", value)


func _apply_cursor_stretch(v: float) -> void:
	if is_equal_approx(v, _cursor_stretch_applied):
		return
	_cursor_stretch_applied = v
	RenderingServer.global_shader_parameter_set(&"psx_cursor_stretch", v)
	live_cursor_stretch_changed.emit(v)

# Backed by the Tune tunable "render.unit_stretch" (ADR-0068) — see
# live_cursor_stretch for the shape. Default has ONE home (project.godot).
var _unit_stretch_default: float = 0.0
var _unit_stretch_applied: float = NAN

var live_unit_stretch: float:
	get:
		return TunePort.get_value("render.unit_stretch", _unit_stretch_default)
	set(value):
		if is_equal_approx(live_unit_stretch, value):
			return
		TunePort.set_value("render.unit_stretch", value)


func _apply_unit_stretch(v: float) -> void:
	if is_equal_approx(v, _unit_stretch_applied):
		return
	_unit_stretch_applied = v
	RenderingServer.global_shader_parameter_set(&"unit_stretch", v)
	live_unit_stretch_changed.emit(v)

# Backed by the Tune tunable "render.psx_fx_stretch" (ADR-0068) — see
# live_cursor_stretch for the shape. Default has ONE home (project.godot).
var _fx_stretch_default: float = 0.0
var _fx_stretch_applied: float = NAN

var live_fx_stretch: float:
	get:
		return TunePort.get_value("render.psx_fx_stretch", _fx_stretch_default)
	set(value):
		if is_equal_approx(live_fx_stretch, value):
			return
		TunePort.set_value("render.psx_fx_stretch", value)


func _apply_fx_stretch(v: float) -> void:
	if is_equal_approx(v, _fx_stretch_applied):
		return
	_fx_stretch_applied = v
	RenderingServer.global_shader_parameter_set(&"psx_fx_stretch", v)
	live_fx_stretch_changed.emit(v)

## The 12-bit PSX camera angle (0..0xfff), the SIXTH global shader parameter this
## port pushes — and the only one that is NOT a Tune tunable, which is why it has
## no `_default`, no `bind_update` and no `*_changed` signal. The five above are
## knobs a human scrubs; this one is per-frame camera state `PlayerCamera`
## computes and hands over (ADR-0171 dec. 1 — the port "pushes the result to
## global shader parameters it does not declare"; the declaration is the
## battlefield addon's `fft_visible_angles.gdshaderinc`).
##
## `live_camera_angle` is a MIRROR of the global, kept here because
## `RenderingServer.global_shader_parameter_get` is editor-only and spams a
## "severely damage performance" warning every frame at runtime. It lived on
## `DebugConfig.psx_camera_angle_12bit` until #590, where it was the last thing
## making a `Debug` autoload a global variable for camera state — and the reason
## `Battlefield`, `Sprite Rig` and `Battle` each named `Debug` (ADR-0175 dec. 4).
##
## The push is UNCONDITIONAL, unlike the five dedup'd `_apply_*` above: the
## caller recomputes it every frame from live yaw, and a dedup cache here would
## go stale against a RenderingServer whose registry a scene change can reset.
var live_camera_angle: int = 0


## Push the camera angle to the `psx_camera_angle` global AND hold the runtime
## mirror. Replaces both halves of what `PlayerCamera` used to do inline (#590).
func set_camera_angle(psx_12bit: int) -> void:
	live_camera_angle = psx_12bit
	RenderingServer.global_shader_parameter_set(&"psx_camera_angle", psx_12bit)


signal live_par_changed(value: float)
signal live_ui_par_changed(value: float)
signal live_cursor_stretch_changed(value: float)
signal live_unit_stretch_changed(value: float)
signal live_fx_stretch_changed(value: float)
