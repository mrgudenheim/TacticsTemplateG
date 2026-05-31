extends AudioTestBase
## Test scene: lists every effect (E###.BIN) that has a FEDS sound section and
## auditions the selected effect's sound pair through the one always-on
## EffectSfxEngine (the same continuous SFX SPU the game uses). Click an effect
## to play pair 0; use the Pair spinner to audition other pairs; toggle the
## voice mode to A/B legacy (FFT-faithful) vs unlimited (scaling) playback.
##   Godot --path . res://src/audio/feds_test_scene.tscn

var _effect_list: ItemList
var _pair_spin: SpinBox
var _now_playing: Label
var _mode_option: OptionButton

var _effects: Array[VisualEffectData] = []
var _sfx_token: int = 0
var _suppress_pair_signal: bool = false


func _ready() -> void:
	build_scaffold("FEDS Effect-Sound Player")

	_effect_list = ItemList.new()
	_effect_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_effect_list.item_clicked.connect(_on_effect_clicked)
	content_box.add_child(_effect_list)

	var controls: HBoxContainer = HBoxContainer.new()
	content_box.add_child(controls)
	var pair_label: Label = Label.new()
	pair_label.text = "Pair:"
	controls.add_child(pair_label)
	_pair_spin = SpinBox.new()
	_pair_spin.min_value = 0
	_pair_spin.value_changed.connect(_on_pair_changed)
	controls.add_child(_pair_spin)
	var mode_label: Label = Label.new()
	mode_label.text = "Voices:"
	controls.add_child(mode_label)
	_mode_option = OptionButton.new()
	_mode_option.add_item("Unlimited (scaling)", EffectSfxEngine.VoiceMode.UNLOCKED)
	_mode_option.add_item("Legacy (FFT-faithful)", EffectSfxEngine.VoiceMode.FAITHFUL)
	_mode_option.item_selected.connect(_on_mode_selected)
	controls.add_child(_mode_option)
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
	_populate()
	set_status("ROM loaded — %d effects with a FEDS section" % _effects.size())


func _populate() -> void:
	_effect_list.clear()
	_effects.clear()
	for vfx_data: VisualEffectData in RomReader.vfx:
		var feds_bank: FedsBankData = RomReader.get_feds_bank(vfx_data)
		if feds_bank == null:
			continue
		_effects.append(vfx_data)
		_effect_list.add_item("%s   (%d pairs)" % [vfx_data.unique_name, feds_bank.sounds.size()])
	if _effects.is_empty():
		_effect_list.add_item("(no effects with a FEDS section found)")


func _on_effect_clicked(index: int, _at_position: Vector2, mouse_button_index: int) -> void:
	if mouse_button_index != MOUSE_BUTTON_LEFT:
		return
	if index < 0 or index >= _effects.size():
		return
	_effect_list.select(index)
	var pair_count: int = _pair_count_for(_effects[index])
	_suppress_pair_signal = true
	_pair_spin.max_value = maxi(0, pair_count - 1)
	_pair_spin.value = clampi(int(_pair_spin.value), 0, int(_pair_spin.max_value))
	_suppress_pair_signal = false
	_play(index, int(_pair_spin.value))


func _on_pair_changed(value: float) -> void:
	if _suppress_pair_signal:
		return
	var selected: PackedInt32Array = _effect_list.get_selected_items()
	if selected.is_empty():
		return
	_play(selected[0], int(value))


func _on_mode_selected(_item_index: int) -> void:
	EffectSfxEngine.set_voice_mode(_mode_option.get_selected_id())


func _on_stop() -> void:
	EffectSfxEngine.end_effect(_sfx_token)  # ring-out; tail decays on the SPU clock
	_sfx_token = 0
	_set_now_playing("Stopped")


func _play(index: int, pair_idx: int) -> void:
	EffectSfxEngine.end_effect(_sfx_token)  # end the previous audition first
	_sfx_token = 0
	var vfx_data: VisualEffectData = _effects[index]
	var feds_bytes: PackedByteArray = RomReader.get_feds_bytes(vfx_data)
	_sfx_token = EffectSfxEngine.audition_feds_bytes(feds_bytes, pair_idx)
	if _sfx_token != 0:
		_set_now_playing("%s — pair %d" % [vfx_data.unique_name, pair_idx])
	else:
		_set_now_playing("FAILED: %s pair %d" % [vfx_data.unique_name, pair_idx])


func _pair_count_for(vfx_data: VisualEffectData) -> int:
	var feds_bank: FedsBankData = RomReader.get_feds_bank(vfx_data)
	return feds_bank.sounds.size() if feds_bank != null else 0


func _set_now_playing(text: String) -> void:
	if _now_playing:
		_now_playing.text = text
