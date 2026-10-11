@tool
extends EditorPlugin
## ExMateria Render — Godot editor plugin entry.
##
## There is nothing to install here that this file can install. The bracket is
## reached through `ExMateriaRender.FoldSurface` — a constant on the addon's one
## global name (ADR-0212 dec. 1), which a caller constructs; the port
## (`PSXDisplay`) is an autoload, and an autoload is a `project.godot` entry the
## HOST writes — the same shape as ADR-0134's "an addon cannot ship a root
## scene". `EditorPlugin.add_autoload_singleton()` exists and would do it, but
## only for a plugin the host has ENABLED, and this project enables neither of
## its addons (`project.godot` has no `[editor_plugins]` section at all). Wiring
## the registration to a switch nobody has thrown would make the port's
## availability depend on editor state. The host registers the name; the addon
## owns the implementation.
##
## This file exists so the directory is a real addon with a promotion path
## (ADR-0121 dec. 7 / ADR-0139 dec. 10), not so it does work.

func _enter_tree() -> void:
	pass

func _exit_tree() -> void:
	pass
