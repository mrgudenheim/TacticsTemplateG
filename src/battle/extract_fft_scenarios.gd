extends Control

const SAVE_DIR: String = "res://src/_content/scenarios/"

@export var load_rom_button: LoadRomButton
@export var rom_path_label: Label
@export var auto_load_checkbox: CheckBox
@export var clear_path_button: Button
@export var extract_button: Button
@export var status_label: Label
@export var close_button: Button

var _current_rom_path: String = ""


func _ready() -> void:
	load_rom_button.file_selected.connect(_on_rom_file_selected)
	auto_load_checkbox.toggled.connect(_on_auto_load_toggled)
	clear_path_button.pressed.connect(_on_clear_path_pressed)
	extract_button.pressed.connect(_on_extract_pressed)
	close_button.pressed.connect(func() -> void: get_tree().quit())

	if RomReader.is_ready:
		_on_rom_loaded()
	else:
		RomReader.rom_loaded.connect(_on_rom_loaded)

	_update_path_display()


func _update_path_display() -> void:
	var saved_path: String = _get_saved_rom_path()
	if saved_path.is_empty():
		rom_path_label.text = "No ROM path saved"
		auto_load_checkbox.button_pressed = false
	else:
		rom_path_label.text = saved_path
		auto_load_checkbox.button_pressed = true


func _on_rom_file_selected(path: String) -> void:
	_current_rom_path = path
	status_label.text = "Loading ROM..."
	RomReader.on_load_rom_dialog_file_selected(path)
	if auto_load_checkbox.button_pressed:
		RomReader._save_rom_path(path)
		_update_path_display()


func _on_rom_loaded() -> void:
	extract_button.disabled = false
	status_label.text = "ROM loaded — ready to extract"


func _on_auto_load_toggled(enabled: bool) -> void:
	if enabled:
		if not _current_rom_path.is_empty():
			RomReader._save_rom_path(_current_rom_path)
		elif not _get_saved_rom_path().is_empty():
			pass # already saved, keep it
		else:
			# no ROM loaded yet, uncheck — nothing to save
			auto_load_checkbox.button_pressed = false
			return
	else:
		_delete_rom_path_config()
	_update_path_display()


func _on_clear_path_pressed() -> void:
	_delete_rom_path_config()
	auto_load_checkbox.button_pressed = false
	_update_path_display()
	status_label.text = "Saved path cleared"


func _on_extract_pressed() -> void:
	extract_button.disabled = true
	status_label.text = "Extracting scenarios..."

	var count: int = 0
	for scenario_name: String in RomReader.scenarios.keys():
		var scenario: Scenario = RomReader.scenarios[scenario_name]
		if not scenario.is_fft_scenario:
			continue

		var safe_name: String = scenario.unique_name.replace('"', '').replace("'", "")
		var file_path: String = SAVE_DIR + safe_name + ".scenario.json"
		var json_file: FileAccess = FileAccess.open(file_path, FileAccess.WRITE)
		if json_file == null:
			push_error("Failed to write scenario: " + file_path + " error: " + str(FileAccess.get_open_error()))
			continue
		json_file.store_line(scenario.to_json())
		json_file.close()
		count += 1

	status_label.text = "Extracted %d scenarios to %s" % [count, SAVE_DIR]
	extract_button.disabled = false


func _get_saved_rom_path() -> String:
	if not FileAccess.file_exists(RomReader.ROM_PATH_CONFIG):
		return ""
	var file: FileAccess = FileAccess.open(RomReader.ROM_PATH_CONFIG, FileAccess.READ)
	return file.get_line().strip_edges()


func _delete_rom_path_config() -> void:
	if FileAccess.file_exists(RomReader.ROM_PATH_CONFIG):
		DirAccess.remove_absolute(RomReader.ROM_PATH_CONFIG)
