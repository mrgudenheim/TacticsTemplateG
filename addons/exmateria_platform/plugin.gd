@tool
extends EditorPlugin
## ExMateria Platform — Godot editor plugin entry.
##
## **It provides seven names: the `[shader_globals]` entry for every `global uniform` this
## addon declares.** This file used to say there was "nothing to install here that this
## file can install", and for autoloads and `#include` targets that is still true and the
## reasons are kept below. It was never true of the shader globals. Seven `.gdshaderinc`
## declarations in this addon put seven names on the compile surface of every shader that
## includes one, and a `global uniform` a project has not declared in `[shader_globals]`
## is **SILENT** outside the editor — the shader compiles and the name reads its type's
## zero, which for `pixel_aspect` is a blank screen. ADR-0238 corrects ADR-0169 dec. 4 here;
## the provide matters MORE for it, not less, because nothing fails loudly.
##
## 🔴 ADR-0220 dec. 1: THE ADDON THAT DECLARES A `global uniform` PROVIDES IT. Until #746
## this addon declared all six and provided none; `exmateria_battlefield/plugin.gd`
## provided five of them, off declarations that live here. That is not a detail of
## bookkeeping. An install target is per subject (ADR-0202 dec. 2), and
## `exmateria_sprite_rig`'s target holds this addon and **not** the battlefield — so one
## declaration of `pixel_aspect` was arm-3 GREEN for the battlefield and arm-3 RED for the rig,
## and `unit_stretch` was provided by nothing at all from the day #744 created it.
## Keying the provide to the DECLARER makes the verdict follow the declaration, and
## `check_addon_portability.py` **arm 4c** enforces it.
##
## Paired with arm 4b — *only a non-system addon may DECLARE one* (ADR-0190) — the two
## rules compose: only the port declares, the declarer provides, therefore **only the port
## provides**. That is the whole `[shader_globals]` contract of this addon family, in one
## array, in the addon that owns the seams.
##
## 🔴 THIS ADDON IS ALSO A CONSUMER, WHICH IS WHY "the declarer" AND "the requirer" ARE THE
## SAME FILE HERE. `display_port/PSXDisplay.gd` reads five of these names through
## `shader_global_default()` and pushes six of them to the `RenderingServer`. Before this
## change its own error message told the reader to *"enable `exmateria_battlefield`, whose
## plugin provides it"* — the port directing its consumers at a sibling addon for the
## port's own names, which is exactly the Class C layering inversion ADR-0202 dec. 6 names.
##
## 🔴 `texel_blend_gamma` (`psx_gamma` UNTIL #1373 — ADR-0328) IS HERE NOW, AND ITS ARRIVAL IS
## ADR-0220 dec. 4 CLOSING ON ITS OWN
## CONDITION RATHER THAN BEING OVERRIDDEN. This paragraph used to read: *"`psx_gamma` is
## DELIBERATELY NOT HERE. `PSXDisplay.gd` pushes it and reads its default, but its `global
## uniform` declaration lives in the HOST (`src/ui3/shaders/`), not in any addon — so under
## dec. 1 it is not this addon's to provide, and arm 4c cannot grade it."* Every clause of
## that was true when written, and the LAST one is what expired: extraction #8's move
## (#1270) relocated `src/ui3/shaders/` to `addons/exmateria_ui/shaders/`, so the two
## declaring headers stopped being the host's the moment the `git mv` landed.
##
## They could not stay where they landed either. `UI` is `tier="system"`, and arm 4b rules
## that only a NON-system addon may DECLARE a `global uniform` (ADR-0190) — so the move
## turned a name nobody could grade into a name in the wrong addon. The port is the only
## tier allowed to hold it, which is dec. 1 and 4b composing to the same answer they always
## give: only the port declares, the declarer provides. The declaration is
## `display_port/texel_blend_gamma.gdshaderinc` and the two ex-host headers `#include` it.
##
## ⚠️ ITS THREE READERS ARE ALL IN `exmateria_ui` AND IT IS THE ONLY ROW HERE WITH THAT
## SHAPE — the other six are read across several systems. When a later pass moves those
## three `pow(c.rgb, vec3(texel_blend_gamma))` sites off the global, this row and its header are
## deleted together; nothing else in the tree would notice.
##
## 🔴 `EditorPlugin` BLESSES AUTOLOADS WITH AN API AND BLESSES NOTHING FOR THIS ONE.
## There is no `add_shader_global()`. `ProjectSettings.set_setting()` plus
## `ProjectSettings.save()` is the whole mechanism (ADR-0203 dec. 5).
##
## 🔴 IN THIS REPO THIS CODE NEVER RUNS, AND THAT IS A STATED FACT, NOT AN OVERSIGHT.
## `godot-learning/project.godot` has no `[editor_plugins]` section, so no `plugin.gd` in
## this package has ever had `_enter_tree` called. Two consequences:
##
##   1. The host keeps declaring all six names itself, and SHOULD (ADR-0203 dec. 4).
##      A diff that deletes them from `project.godot` has misread that decision.
##   2. **Booting the game verifies nothing about this file.** The oracle is
##      `tests/PlatformProvidesTest.gd`, which calls `provide_into()` directly against a
##      settings surface it can inspect — and it runs in a STRANGER project
##      (`tests/stranger/exmateria_platform/run.sh`, ADR-0194), which is the only place in
##      this repo where "a project that did nothing for this addon" is real.
##
## 🔴 AND ARM 4c ALONE IS A TAUTOLOGY, for ADR-0203 dec. 4's reason: its predicate is "a
## string appears in `plugin.gd`", and anybody can green it by typing six names into an
## array no code path reaches. The register is the burn-down; the direct-call test is the
## oracle, and dec. 4 requires them to ship together.
##
## FIRST ENABLE IN A BARE PROJECT LOGS SHADER COMPILE ERRORS, and that is documented rather
## than fixed (ADR-0203 dec. 6). Godot imports and compiles shaders when the project OPENS;
## the plugin is enabled after. The honest install sequence is *copy the addons → open →
## enable → reload*, and it is in README.md.
##
## 🔴 AND THIS IS THE ONE PLACE THE COMPILE ERROR IS REAL, which is worth stating now that
## ADR-0238 has shown it is not real anywhere else. `shader_language.cpp` validates a
## `global uniform` only under `Engine::is_editor_hint()`, so the EDITOR OPEN above is
## exactly the path that reports it — and a running game, an exported build or a stranger
## rig reports nothing at all and renders with the name at its type's zero. So the noisy
## case is the benign one (you are about to enable and reload) and the quiet case is the
## damaging one.
##
## The rest of what this addon publishes still installs nothing, and the original reasons
## hold: `PSXDisplay` is an autoload, and an autoload is a `project.godot` entry the HOST
## writes (`addons/exmateria_render/plugin.gd` states the argument); the `.gdshaderinc` are
## `#include` targets a shader names by path; and `PsxNum` is published on
## `exmateria_platform.gd`, the addon's ONE global name, which the parser finds on its own
## (ADR-0212 dec. 1).

const SHADER_GLOBAL_PREFIX: String = "shader_globals/"

## The 7 `global uniform`s this addon DECLARES — `[name, type, default]`.
##
## Every entry pairs with exactly one `global uniform` line under this addon root, and
## `check_addon_portability.py` arm 4c diffs the two sets in both directions: a declaration
## with no entry here is RED, and so is an entry whose name some OTHER addon's `plugin.gd`
## provides. The declaration sites, one per row below:
##
##   `pixel_aspect/pixel_aspect.gdshaderinc:50`          `pixel_aspect`
##   `dither/psx_dither.gdshaderinc:7`              `psx_dither_enabled`
##   `display_port/psx_sprite_stretch.gdshaderinc`  `psx_fx_stretch`, `psx_cursor_stretch`
##   `display_port/unit_stretch.gdshaderinc:24` `unit_stretch`
##   `display_port/psx_camera_angle.gdshaderinc:21` `psx_camera_angle`
##   `display_port/texel_blend_gamma.gdshaderinc:62`    `texel_blend_gamma`
##
## ⚠️ THE DEFAULTS ARE `project.godot`'s, AND `pixel_aspect`'s 1.0 IS LOAD-BEARING. The point of
## a provide is that a bare project BEHAVES like the in-repo one, not merely that the name
## exists — and `PSXDisplay.shader_global_default` falls back to 0.0, where a `pixel_aspect` of
## 0 collapses every vertex's x to zero: a blank screen (ADR-0203 dec. 7). Providing the
## name with a wrong default is that same crash wearing a green register, which is why
## `PlatformProvidesTest` asserts the VALUES and not just the names.
const PROVIDED_GLOBALS: Array = [
	# The project-wide horizontal PAR factor — the one every battle mesh multiplies its
	# clip-space X by (ADR-0036/0060).
	["pixel_aspect", "float", 1.0],
	# Ordered-dither toggle for the display pass.
	["psx_dither_enabled", "bool", true],
	# The three per-taxonomy billboard-WIDTH multipliers (ADR-0044). 1.0 = native art.
	# `unit_stretch` is the sprite rig's, and it is the one that had no provider at
	# all: it was split into its own seam at #744 so a battlefield shader would not pay
	# for a name it does not read, and nothing picked up the provide.
	["psx_fx_stretch", "float", 1.0],
	["psx_cursor_stretch", "float", 1.0],
	["unit_stretch", "float", 1.0],
	# The isometric camera yaw, 0..0xFFF. Changes every frame and is read by every map
	# surface, which is why ADR-0190 dec. 4 declined to make it a material parameter.
	["psx_camera_angle", "int", 0],
	# The exponent a producer applies to a SAMPLED TEXEL just before it modulates and blends
	# it, pushed from the `render.texel_blend_gamma` tunable. It moved here at extraction #8
	# (#1270): its declaration was the host's until `src/ui3/shaders/` became
	# `addons/exmateria_ui/shaders/`, and a `tier="system"` addon may not declare one. It was
	# `psx_gamma` until #1373; ADR-0328 argues the new name, and argues in particular that it
	# must NOT say `srgb` — 1.4 is a hand-calibrated blend exponent and no sRGB decode has it.
	# 1.4 is `project.godot:885`'s value, not a nominal PSX figure.
	["texel_blend_gamma", "float", 1.4],
]

## Only the settings THIS plugin added. Removing on the way out what a consumer declared on
## its own would delete their line from their project file.
var _added: Array[String] = []


func _enter_tree() -> void:
	_added = provide_into(ProjectSettings)
	if not _added.is_empty():
		ProjectSettings.save()


func _exit_tree() -> void:
	revoke_from(ProjectSettings, _added)
	if not _added.is_empty():
		ProjectSettings.save()
	_added.clear()


## Write every name this addon provides that `surface` does not already hold. Returns the
## setting keys actually added, in write order.
##
## 🔴 STATIC, AND IT TAKES THE SURFACE, BECAUSE THAT IS WHAT MAKES IT TESTABLE (ADR-0203
## dec. 4). A test cannot enable a plugin — and it must never write the REAL
## `ProjectSettings`, because `_enter_tree`'s companion `ProjectSettings.save()` would
## rewrite the repo's own `project.godot`. So the surface is a parameter, the test passes a
## dictionary-backed double, and nothing here touches global state on its own.
##
## `surface` needs `has_setting(String) -> bool` and `set_setting(String, Variant)`, which
## is the slice of `ProjectSettings` this uses and all of it.
##
## The `has_setting` guard is ADR-0203 dec. 2's permitted read: it decides whether this
## addon's own write is needed, which is part of the write, not a runtime configuration
## read. The in-repo game declares all six itself and must not get a duplicate.
static func provide_into(surface) -> Array[String]:
	var added: Array[String] = []
	for entry in PROVIDED_GLOBALS:
		var key: String = SHADER_GLOBAL_PREFIX + entry[0]
		if surface.has_setting(key):
			continue
		surface.set_setting(key, {"type": entry[1], "value": entry[2]})
		added.append(key)
	return added


## Remove exactly the keys `provide_into` reported adding, and nothing else.
static func revoke_from(surface, keys: Array[String]) -> void:
	for key in keys:
		surface.set_setting(key, null)


## Every setting key this addon provides — the list `check_addon_install.py`'s arm 3 and
## `check_addon_portability.py`'s arm 4c compare requirements and declarations against.
## Named here so there is one answer to "what does this addon install".
static func provided_keys() -> Array[String]:
	var keys: Array[String] = []
	for entry in PROVIDED_GLOBALS:
		keys.append(SHADER_GLOBAL_PREFIX + entry[0])
	return keys
