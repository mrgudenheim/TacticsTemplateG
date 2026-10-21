@tool
extends EditorPlugin
## ExMateria Effects — Godot editor plugin entry. Registers three autoloads;
## that is this addon's whole install step (ADR-0262 dec. 6: the scripts
## travel with the addon).
##
## THE `[autoload]` LINE STAYS THE CONSUMER'S (ADR-0262 dec. 6): an addon
## cannot write another project's project.godot; `has_setting` stops the duplicate.
## NODE-PATH REACH IS NOT A REASON TO DROP AN ENTRY: the node exists only if
## the `[autoload]` line exists.
## NO `global uniform` DECLARED, SO NONE PROVIDED (ADR-0220 dec. 1, ADR-0190):
## the names this addon's shaders read live in `exmateria_platform` — enable it.
## IN THIS REPO THIS CODE NEVER RUNS: no `[editor_plugins]` section
## (ADR-0203 dec. 4). The oracle is a stranger rig (ADR-0194).
## vault: .vaults/comments/exmateria_effects/plugin-install-history.md
##
## Everything else in this addon is reached through `ExMateriaEffects`
## (ADR-0212 dec. 1). See README.md.

const AUTOLOADS := [
	["EffectMultiMeshPool", "res://addons/exmateria_effects/render/EffectMultiMeshPool.gd"],
	["ScreenEffectOverlay", "res://addons/exmateria_effects/overlay/ScreenEffectOverlay.gd"],
	["TintedSurfaces", "res://addons/exmateria_effects/overlay/TintedSurfaces.gd"],
	# THE RENDER ROUTER (#1453). It probes the build, derives the route, and keeps
	# `EngineFoldCompositor` attached to the live camera across scene changes. It was
	# 142 lines of HOST code, and `EngineFoldCompositor` is the sole materializer of
	# transparent prims on BOTH routes — `EffectParticleRenderer` fills only the opaque
	# MultiMesh — so a consumer who installed this addon and did not write the router
	# themselves lost the transparent half of every effect, SILENTLY: the opaque pass
	# keeps drawing and nothing errors (#1352's shape, in that file's own docstring).
	# Filed under `render/` and not `install/`: this addon files its REGISTERED
	# autoloads by function, and `install/` holds what a host SUPPLIES.
	["CompositorAutopilot", "res://addons/exmateria_effects/render/CompositorAutopilot.gd"],
]

## Only the ones THIS plugin added: removing on the way out what a consumer
## declared on its own would delete their line from their project file.
var _added: Array[String] = []


func _enter_tree() -> void:
	for entry in AUTOLOADS:
		if not ProjectSettings.has_setting("autoload/" + entry[0]):
			add_autoload_singleton(entry[0], entry[1])
			_added.append(entry[0])


func _exit_tree() -> void:
	for autoload_name in _added:
		remove_autoload_singleton(autoload_name)
	_added.clear()
