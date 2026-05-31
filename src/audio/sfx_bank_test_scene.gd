extends AudioTestBase
## Test scene: auditions every sound in FFT's global SFX banks (SYSTEM.SED /
## ENV.SED) through the SFX path. These are the battle/system effects NOT tied
## to a visual effect — the unit death cry (SYSTEM id 0x45), melee/physical hit
## noises, menu blips, etc. Pick a bank, click a sound id to play it.
##   Godot --path . res://src/audio/sfx_bank_test_scene.tscn

var _bank_option: OptionButton
var _sound_list: ItemList
var _now_playing: Label
var _mode_option: OptionButton

var _sfx_token: int = 0
var _current_sounds: Array = []  # FedsBankData.FedsSound for the selected bank


func _ready() -> void:
	build_scaffold("SFX Bank Player (SYSTEM / ENV)")

	var controls: HBoxContainer = HBoxContainer.new()
	content_box.add_child(controls)
	var bank_label: Label = Label.new()
	bank_label.text = "Bank:"
	controls.add_child(bank_label)
	_bank_option = OptionButton.new()
	_bank_option.item_selected.connect(_on_bank_selected)
	controls.add_child(_bank_option)
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

	_sound_list = ItemList.new()
	_sound_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_sound_list.item_clicked.connect(_on_sound_clicked)
	content_box.add_child(_sound_list)

	_now_playing = Label.new()
	content_box.add_child(_now_playing)

	if ensure_rom():
		_on_rom_loaded()
	else:
		set_status("No ROM loaded — click 'Load ROM…' to pick an FFT ISO.")
	_set_now_playing("Stopped")


func _on_rom_loaded() -> void:
	_bank_option.clear()
	for bank_index: int in RomReader.sfx_banks_array.size():
		var sfx_bank: FedsBankData = RomReader.sfx_banks_array[bank_index]
		sfx_bank.init_from_file()
		_bank_option.add_item("%s  (%d sounds)" % [sfx_bank.unique_name, sfx_bank.sounds.size()], bank_index)
	set_status("ROM loaded — %d SFX banks" % RomReader.sfx_banks_array.size())
	if RomReader.sfx_banks_array.size() > 0:
		_bank_option.select(0)
		_on_bank_selected(0)


func _on_bank_selected(item_index: int) -> void:
	_sound_list.clear()
	_current_sounds.clear()
	if item_index < 0 or item_index >= RomReader.sfx_banks_array.size():
		return
	var sfx_bank: FedsBankData = RomReader.sfx_banks_array[item_index]
	sfx_bank.init_from_file()
	for sound: FedsBankData.FedsSound in sfx_bank.sounds:
		_current_sounds.append(sound)
		_sound_list.add_item("0x%02X (%d)    gain %d" % [sound.index, sound.index, sound.gain_byte])
	if _current_sounds.is_empty():
		_sound_list.add_item("(no sounds in bank)")


func _on_sound_clicked(index: int, _at_position: Vector2, mouse_button_index: int) -> void:
	if mouse_button_index != MOUSE_BUTTON_LEFT:
		return
	if index < 0 or index >= _current_sounds.size():
		return
	_sound_list.select(index)
	_play(index)


func _on_mode_selected(_item_index: int) -> void:
	EffectSfxEngine.set_voice_mode(_mode_option.get_selected_id())


func _on_stop() -> void:
	EffectSfxEngine.end_effect(_sfx_token)  # ring-out on the continuous SPU
	_sfx_token = 0
	_set_now_playing("Stopped")


func _play(index: int) -> void:
	EffectSfxEngine.end_effect(_sfx_token)  # end the previous audition first
	_sfx_token = 0
	var bank_index: int = _bank_option.get_selected_id()
	if bank_index < 0 or bank_index >= RomReader.sfx_banks_array.size():
		return
	var sfx_bank: FedsBankData = RomReader.sfx_banks_array[bank_index]
	var sound: FedsBankData.FedsSound = _current_sounds[index]
	var bank_bytes: PackedByteArray = RomReader.get_file_data(sfx_bank.file_name)
	_sfx_token = EffectSfxEngine.audition_bank_bytes(bank_bytes, sound.index)
	if _sfx_token != 0:
		_set_now_playing("%s — id 0x%02X (%d)" % [sfx_bank.unique_name, sound.index, sound.index])
	else:
		_set_now_playing("FAILED: %s id 0x%02X" % [sfx_bank.unique_name, sound.index])


func _set_now_playing(text: String) -> void:
	if _now_playing:
		_now_playing.text = text
