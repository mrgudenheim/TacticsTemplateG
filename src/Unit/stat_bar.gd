class_name StatBar
extends TextureProgressBar

const STAT_BAR_TSCN: PackedScene = preload("res://src/Unit/stat_bar.tscn")

@export var name_label: Label
@export var value_label: Label
@export var visual_max: float = 0.0:
	set(new_value):
		visual_max = new_value
		max_value = visual_max

@export var show_name: bool = false:
	set(new_value):
		show_name = new_value
		name_label.visible = new_value

@export var show_value: bool = false:
	set(new_value):
		show_value = new_value
		value_label.visible = new_value

@export var fill_color: Color = Color.WHITE:
	set(new_value):
		fill_color = new_value
		tint_progress = new_value


static func instantiate() -> StatBar:
	return STAT_BAR_TSCN.instantiate()


func set_stat(stat_name: String, stat: StatValue) -> void:
	name_label.text = stat_name
	update_stat(stat)
	
	if not stat.value_changed.is_connected(update_stat):
		stat.value_changed.connect(update_stat)


func update_stat(stat: StatValue) -> void:
	min_value = stat.min_value
	
	if visual_max == 0.0:
		max_value = stat.max_value
	
	value = stat.get_modified_value()
	
	value_label.text = str(roundi(value)) + "/" + str(roundi(max_value))
