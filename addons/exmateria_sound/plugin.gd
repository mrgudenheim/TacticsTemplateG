@tool
extends EditorPlugin
## ExMateria Sound — Godot editor plugin entry.
##
## The runtime is autoload-free by design: a game scene instantiates
## SoundTrackController (or SMDPlayer for music-only) directly and
## passes it asset paths. See README.md for the public API.

func _enter_tree() -> void:
	pass

func _exit_tree() -> void:
	pass
