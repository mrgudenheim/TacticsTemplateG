class_name BattleDebugOverlay
extends CanvasLayer
## Debug overlay for the battle scene. Toggle with F3.
## Add tabs for tuning visual parameters at runtime.

var _panel: PanelContainer
var _tabs: TabContainer
var _visible: bool = false

# Tile highlight references
var _tile_highlights: Dictionary[Color, Material] = {}
var _opacity_slider: HSlider
var _opacity_label: Label
var _bias_slider: HSlider
var _bias_label: Label


func _ready() -> void:
	layer = 100
	_build_ui()
	visible = false
	var battle_manager: Node = get_parent()
	if battle_manager and "tile_highlights" in battle_manager:
		set_tile_highlights(battle_manager.tile_highlights)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_F3:
		_visible = not _visible
		visible = _visible
		get_viewport().set_input_as_handled()


func set_tile_highlights(highlights: Dictionary[Color, Material]) -> void:
	_tile_highlights = highlights
	if _opacity_slider and not _tile_highlights.is_empty():
		var first_mat: ShaderMaterial = _tile_highlights.values()[0] as ShaderMaterial
		if first_mat:
			_opacity_slider.value = first_mat.get_shader_parameter("overlay_opacity")


func _build_ui() -> void:
	_panel = PanelContainer.new()
	_panel.anchor_right = 0.0
	_panel.anchor_bottom = 0.0
	_panel.offset_right = 300
	_panel.offset_bottom = 400
	_panel.offset_left = 10
	_panel.offset_top = 10
	add_child(_panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 8)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_right", 8)
	margin.add_theme_constant_override("margin_bottom", 8)
	_panel.add_child(margin)

	var vbox := VBoxContainer.new()
	margin.add_child(vbox)

	var title := Label.new()
	title.text = "Debug (F3)"
	vbox.add_child(title)

	_tabs = TabContainer.new()
	_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(_tabs)

	_build_tiles_tab()


func _build_tiles_tab() -> void:
	var tab := VBoxContainer.new()
	tab.name = "Tiles"
	_tabs.add_child(tab)

	# Opacity
	var opacity_row := HBoxContainer.new()
	tab.add_child(opacity_row)
	var opacity_title := Label.new()
	opacity_title.text = "Opacity:"
	opacity_row.add_child(opacity_title)
	_opacity_slider = HSlider.new()
	_opacity_slider.min_value = 0.0
	_opacity_slider.max_value = 1.0
	_opacity_slider.step = 0.05
	_opacity_slider.value = 0.4
	_opacity_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_opacity_slider.value_changed.connect(_on_opacity_changed)
	opacity_row.add_child(_opacity_slider)
	_opacity_label = Label.new()
	_opacity_label.text = "0.40"
	_opacity_label.custom_minimum_size.x = 35
	opacity_row.add_child(_opacity_label)

	# Depth mode
	var depth_row := HBoxContainer.new()
	tab.add_child(depth_row)
	var depth_title := Label.new()
	depth_title.text = "Depth Mode:"
	depth_row.add_child(depth_title)
	var depth_option := OptionButton.new()
	depth_option.add_item("Standard", 0)
	depth_option.add_item("Pull Forward 8", 1)
	depth_option.add_item("Fixed Front", 2)
	depth_option.add_item("Fixed Back", 3)
	depth_option.add_item("Fixed 16", 4)
	depth_option.add_item("Pull Forward 16", 5)
	depth_option.add_item("Unit", 6)
	depth_option.add_item("Tile Overlay", 7)
	depth_option.select(7)
	depth_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	depth_option.item_selected.connect(_on_depth_mode_changed)
	depth_row.add_child(depth_option)

	# Tile overlay depth bias
	var bias_row := HBoxContainer.new()
	tab.add_child(bias_row)
	var bias_title := Label.new()
	bias_title.text = "Depth Bias:"
	bias_row.add_child(bias_title)
	_bias_slider = HSlider.new()
	_bias_slider.min_value = 0.0
	_bias_slider.max_value = 1.0
	_bias_slider.step = 0.01
	_bias_slider.value = VfxConstants.DEPTH_BIAS_TILE_OVERLAY
	_bias_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_bias_slider.value_changed.connect(_on_bias_changed)
	bias_row.add_child(_bias_slider)
	_bias_label = Label.new()
	_bias_label.text = "%.2f" % VfxConstants.DEPTH_BIAS_TILE_OVERLAY
	_bias_label.custom_minimum_size.x = 35
	bias_row.add_child(_bias_label)


func _on_opacity_changed(value: float) -> void:
	_opacity_label.text = "%.2f" % value
	for mat: Material in _tile_highlights.values():
		var shader_mat: ShaderMaterial = mat as ShaderMaterial
		if shader_mat:
			shader_mat.set_shader_parameter("overlay_opacity", value)


func _on_depth_mode_changed(index: int) -> void:
	for mat: Material in _tile_highlights.values():
		var shader_mat: ShaderMaterial = mat as ShaderMaterial
		if shader_mat:
			shader_mat.set_shader_parameter("depth_mode", index)


func _on_bias_changed(value: float) -> void:
	_bias_label.text = "%.2f" % value
	for mat: Material in _tile_highlights.values():
		var shader_mat: ShaderMaterial = mat as ShaderMaterial
		if shader_mat:
			shader_mat.set_shader_parameter("bias_tile_overlay", value)
