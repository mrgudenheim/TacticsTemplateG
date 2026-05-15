class_name ExportRomDataButton
extends Button

@export var rom_file_dialog: FileDialog
@export var destination_file_dialog: FileDialog

var rom_path: String
var destination_path: String

func _ready() -> void:
	rom_file_dialog.file_selected.connect(_on_rom_path_selected)
	destination_file_dialog.dir_selected.connect(_on_destination_path_selected)


func _pressed() -> void:
	rom_file_dialog.visible = true


func _on_rom_path_selected(path: String) -> void:
	rom_path = path
	rom_file_dialog.visible = false
	destination_file_dialog.visible = true

func _on_destination_path_selected(path: String) -> void:
	destination_path = path
	destination_file_dialog.visible = false
	
	# TODO progress bar/timings
	#RomReader.on_load_rom_dialog_file_selected(path)
	
	RomReader.export_data(destination_path)
	push_warning("data export complete: " + destination_path)
