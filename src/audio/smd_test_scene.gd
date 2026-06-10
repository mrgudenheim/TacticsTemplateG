extends AudioTestBase
## Test scene: lists every MUSIC_##.SMD in the loaded ROM and plays the one you
## click, through the MusicPlayer autoload.
##   Godot --path . res://src/audio/smd_test_scene.tscn

var _song_list: ItemList
var _now_playing: Label
var _smds: Array[SmdData] = []


func _ready() -> void:
	build_scaffold("SMD Music Player")

	_song_list = ItemList.new()
	_song_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_song_list.item_clicked.connect(_on_song_clicked)
	content_box.add_child(_song_list)

	var controls: HBoxContainer = HBoxContainer.new()
	content_box.add_child(controls)
	var stop_button: Button = Button.new()
	stop_button.text = "Stop"
	stop_button.pressed.connect(_on_stop)
	controls.add_child(stop_button)

	_now_playing = Label.new()
	content_box.add_child(_now_playing)

	if ensure_rom():
		_on_rom_loaded()
	else:
		set_status("No ROM loaded — click 'Load ROM…' to pick an FFT ISO.")
	_set_now_playing("Stopped")


func _on_rom_loaded() -> void:
	set_status("ROM loaded — %d songs" % RomReader.smds_array.size())
	_populate()


func _populate() -> void:
	_song_list.clear()
	_smds.clear()
	for smd: SmdData in RomReader.smds_array:
		smd.init_from_file()
		_smds.append(smd)
		var title: String = smd.song_title.strip_edges()
		var label: String = smd.file_name
		if title != "":
			label += "  —  " + title
		_song_list.add_item(label)
	if _smds.is_empty():
		_song_list.add_item("(no SMD music found in ROM)")


func _on_song_clicked(index: int, _at_position: Vector2, mouse_button_index: int) -> void:
	if mouse_button_index != MOUSE_BUTTON_LEFT:
		return
	if index < 0 or index >= _smds.size():
		return
	var smd: SmdData = _smds[index]
	if MusicPlayer.play_file(smd.file_name):
		_set_now_playing("Now playing: " + smd.file_name)
	else:
		_set_now_playing("FAILED to play: " + smd.file_name)


func _on_stop() -> void:
	MusicPlayer.stop()
	_set_now_playing("Stopped")


func _set_now_playing(text: String) -> void:
	if _now_playing:
		_now_playing.text = text
