class_name AudioTestBase
extends Control
## Shared scaffold for the sound test scenes. Builds a common header (title +
## ROM-load row + status) in code, and handles getting a ROM loaded into
## RomReader (these scenes can run standalone, so they load the ISO themselves
## if the game hasn't already).
##
## Subclasses call build_scaffold() in _ready, then override _on_rom_loaded()
## to populate their content into `content_box`.

var status_label: Label
var content_box: VBoxContainer


func build_scaffold(title_text: String) -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)

	var margin: MarginContainer = MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side: String in ["left", "top", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 16)
	add_child(margin)

	var vbox: VBoxContainer = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	margin.add_child(vbox)

	var title: Label = Label.new()
	title.text = title_text
	title.add_theme_font_size_override("font_size", 22)
	vbox.add_child(title)

	var rom_row: HBoxContainer = HBoxContainer.new()
	vbox.add_child(rom_row)
	var load_button: Button = Button.new()
	load_button.text = "Load ROM…"
	load_button.pressed.connect(_on_load_rom_pressed)
	rom_row.add_child(load_button)
	status_label = Label.new()
	rom_row.add_child(status_label)

	content_box = VBoxContainer.new()
	content_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content_box.add_theme_constant_override("separation", 8)
	vbox.add_child(content_box)


## Attempts to make ROM data available: returns true if already loaded, else
## tries the ROM path saved by the external data setup panel.
func ensure_rom() -> bool:
	if not RomReader.smds.is_empty():
		return true
	var rom_path: String = GameData.external_data_paths.get("ROM_PATH", "")
	if rom_path != "" and FileAccess.file_exists(rom_path):
		RomReader.on_load_rom_dialog_file_selected(rom_path)
	return not RomReader.smds.is_empty()


func set_status(text: String) -> void:
	if status_label:
		status_label.text = text


## Override in subclasses to build their content once a ROM is available.
func _on_rom_loaded() -> void:
	pass


func _on_load_rom_pressed() -> void:
	var dialog: FileDialog = FileDialog.new()
	dialog.access = FileDialog.ACCESS_FILESYSTEM
	dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	dialog.filters = PackedStringArray(["*.bin,*.iso,*.img ; FFT ISO / disc image"])
	dialog.file_selected.connect(_load_rom_from_path.bind(dialog))
	dialog.canceled.connect(dialog.queue_free)
	add_child(dialog)
	dialog.popup_centered_ratio(0.6)


func _load_rom_from_path(path: String, dialog: FileDialog) -> void:
	dialog.queue_free()
	set_status("Loading ROM… " + path.get_file())
	RomReader.on_load_rom_dialog_file_selected(path)
	if RomReader.smds.is_empty():
		set_status("Failed to load ROM: " + path)
		return
	_on_rom_loaded()
