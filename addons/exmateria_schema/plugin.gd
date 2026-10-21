@tool
extends EditorPlugin
## ExMateria Schema — Godot editor plugin entry.
##
## There is nothing to install. The kernel is a set of types published on the
## `ExMateriaSchema` façade (ADR-0212 dec. 1) and `.gdshaderinc` seams a shader
## `#include`s by path; it registers no
## autoload, no singleton and no editor UI, because a member that installed
## itself into the host would be a port, not a schema (ADR-0118 dec. 2,
## ADR-0139 dec. 4b). This file exists so the directory is a real addon with a
## promotion path (ADR-0121 dec. 7 / ADR-0139 dec. 10), not so it does work.

func _enter_tree() -> void:
	pass

func _exit_tree() -> void:
	pass
