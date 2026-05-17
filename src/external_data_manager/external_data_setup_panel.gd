class_name ExternalDataSetupPanel
extends PanelContainer

@export var import_button: Button

@export var import_path_line_edit: LineEdit
@export var import_find_button: Button
@export var import_file_dialog: FileDialog

@export var rom_path_line_edit: LineEdit
@export var rom_find_button: Button
@export var rom_file_dialog: FileDialog

@export var destination_path_line_edit: LineEdit
@export var destination_find_button: Button
@export var destination_file_dialog: FileDialog

@export var export_data_button: Button


func _ready() -> void:
	rom_path_line_edit.text_changed.connect(_on_rom_path_selected)
	rom_find_button.pressed.connect(func() -> void: rom_file_dialog.visible = true)
	rom_file_dialog.file_selected.connect(_on_rom_path_selected)
	
	destination_path_line_edit.text_changed.connect(_on_destination_path_selected)
	destination_find_button.pressed.connect(func() -> void: destination_file_dialog.visible = true)
	destination_file_dialog.dir_selected.connect(_on_destination_path_selected)

	export_data_button.pressed.connect(export_data)
	import_button.pressed.connect(func() -> void: GameData.import_data(GameData.external_data_paths["IMPORT_PATH"]))

	await get_tree().process_frame

	import_path_line_edit.text = GameData.external_data_paths["IMPORT_PATH"]
	rom_path_line_edit.text = GameData.external_data_paths["ROM_PATH"]
	destination_path_line_edit.text = GameData.external_data_paths["EXPORT_PATH"]
	update_export_enabled()


func update_export_enabled() -> void:
	var rom_path_is_valid: bool = FileAccess.file_exists(GameData.external_data_paths["ROM_PATH"])
	var destination_path_is_valid: bool = DirAccess.dir_exists_absolute(GameData.external_data_paths["EXPORT_PATH"])
	
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
	GameData.external_data_paths["ROM_PATH"] = path
	rom_path_line_edit.text = path
	rom_file_dialog.visible = false

	GameData.save_data_paths()
	update_export_enabled()


func _on_destination_path_selected(path: String) -> void:
	destination_path_line_edit.text = path
	destination_file_dialog.visible = false

	if GameData.external_data_paths["IMPORT_PATH"].is_empty() or GameData.external_data_paths["IMPORT_PATH"] == GameData.external_data_paths["EXPORT_PATH"]:
		import_path_line_edit.text = path
		GameData.external_data_paths["IMPORT_PATH"] = path
	GameData.external_data_paths["EXPORT_PATH"] = path
	
	GameData.save_data_paths()
	update_export_enabled()


func export_data() -> void:
	# TODO progress bar/timings
	RomReader.on_load_rom_dialog_file_selected(GameData.external_data_paths["ROM_PATH"])
	
	RomReader.export_data(GameData.external_data_paths["EXPORT_PATH"])
	push_warning("data export complete: " + GameData.external_data_paths["EXPORT_PATH"])
