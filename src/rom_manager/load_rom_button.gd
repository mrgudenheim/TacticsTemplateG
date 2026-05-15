class_name LoadRomButton
extends Button

@export var load_rom_dialog: FileDialog

signal file_selected(path: String)

func _ready() -> void:
	pressed.connect(show_dialog)
	load_rom_dialog.file_selected.connect(on_file_selected)


func show_dialog() -> void:
	load_rom_dialog.visible = true


func on_file_selected(path: String) -> void:
	file_selected.emit(path)
