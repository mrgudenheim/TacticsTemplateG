class_name ExternalDataSetupPanel
extends PanelContainer

@export var rom_path_line_edit: LineEdit
@export var rom_find_button: Button
@export var rom_file_dialog: FileDialog

@export var destination_path_line_edit: LineEdit
@export var destination_find_button: Button
@export var destination_file_dialog: FileDialog

@export var export_data_button: Button

var rom_path: String
var destination_path: String

func _ready() -> void:
	rom_path_line_edit.text_changed.connect(_on_rom_path_selected)
	rom_find_button.pressed.connect(func() -> void: rom_file_dialog.visible = true)
	rom_file_dialog.file_selected.connect(_on_rom_path_selected)
	
	destination_path_line_edit.text_changed.connect(_on_destination_path_selected)
	destination_find_button.pressed.connect(func() -> void: destination_file_dialog.visible = true)
	destination_file_dialog.dir_selected.connect(_on_destination_path_selected)

	export_data_button.pressed.connect(export_data)

	await get_tree().process_frame

	rom_path = GameData.external_data_paths["ROM_PATH"]
	rom_path_line_edit.text = rom_path
	destination_path = GameData.external_data_paths["EXPORT_PATH"]
	destination_path_line_edit.text = destination_path
	update_export_enabled()


func update_export_enabled() -> void:
	var rom_path_is_valid: bool = rom_path.is_absolute_path()
	var destination_path_is_valid: bool = destination_path.is_absolute_path()
	
	if rom_path_is_valid and destination_path_is_valid:
		export_data_button.disabled = false
		export_data_button.tooltip_text = "Export data from ROM to selected destination"
	else:
		export_data_button.disabled = true
		export_data_button.tooltip_text = ""

		if not rom_path_is_valid:
			export_data_button.tooltip_text += "Invalid path to ROM"
		if not destination_path_is_valid:
			export_data_button.tooltip_text += "Invalid path to export destination"


func _on_rom_path_selected(path: String) -> void:
	rom_path = path
	rom_path_line_edit.text = path
	rom_file_dialog.visible = false
	update_export_enabled()

	GameData.external_data_paths["ROM_PATH"] = rom_path
	GameData.save_data_paths()


func _on_destination_path_selected(path: String) -> void:
	destination_path = path
	destination_path_line_edit.text = path
	destination_file_dialog.visible = false
	update_export_enabled()

	GameData.external_data_paths["EXPORT_PATH"] = destination_path
	GameData.save_data_paths()


func export_data() -> void:
	# TODO progress bar/timings
	RomReader.on_load_rom_dialog_file_selected(rom_path)
	
	RomReader.export_data(destination_path)
	push_warning("data export complete: " + destination_path)
