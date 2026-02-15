class_name StatValue
extends Resource

signal value_changed(clamped_value: StatValue)

@export var min_value: int = 0 # should not change
@export var max_value: int = 100 # should not change (except when linked to another stat, ex hp_max)
@export var base_value: int = 50 # should not change
@export var current_value: int = 50 # typically used for stats that get value_changed until end of battle: hp, mp, ct, faith, brave, exp, lvl
var modified_value: int: # typically used for stats that are modified from other things (equipment, etc): move, jump, speed, hp_max, mp_max
	get: return get_modified_value()

var modifiers: Array[Modifier] = [] # should only come from passive_effects


static func create_from_dictionary(property_dict: Dictionary) -> StatValue:
	var new_clamped_value: StatValue = StatValue.new()
	for property_name: String in property_dict.keys():
		new_clamped_value.set(property_name, property_dict[property_name])

	new_clamped_value.emit_changed()
	return new_clamped_value


func _init(new_min_value: int = 0, new_max_value: int = 100, new_current_value: int = 50) -> void:
	min_value = new_min_value
	max_value = new_max_value
	current_value = new_current_value


func to_dictionary() -> Dictionary:
	var properties_to_exclude: PackedStringArray = [
		"RefCounted",
		"Resource",
		"resource_local_to_scene",
		"resource_path",
		"resource_name",
		"resource_scene_unique_id",
		"script",
	]
	
	return Utilities.object_properties_to_dictionary(self, properties_to_exclude)


func get_unclampped_modified_value(preview_value: int = current_value) -> int:
	var temp_modified_value: int = preview_value
	for modifier: Modifier in modifiers:
		temp_modified_value = modifier.apply(temp_modified_value) # TODO sort by add, mult, set
	
	return temp_modified_value


func get_modified_value(preview_value: int = current_value) -> int:
	var temp_modified_value: int = get_unclampped_modified_value(preview_value)
	temp_modified_value = clampi(temp_modified_value, min_value, max_value)
	
	return temp_modified_value


func set_value(new_value: int) -> int:
	new_value = clampi(new_value, min_value, max_value)
	var delta_value: int = new_value - current_value
	current_value = new_value
	
	value_changed.emit(self)
	return delta_value


func get_set_delta(new_value: int) -> int:
	new_value = clampi(new_value, min_value, max_value)
	var delta_value: int = new_value - current_value
	
	return delta_value


func add_value(value: int) -> int:
	value = get_add_delta(value)
	current_value += value
	
	value_changed.emit(self)
	return value


func get_add_delta(value: int) -> int:
	# clamp delta
	if value + current_value > max_value:
		value = max_value - current_value
	elif value + current_value < min_value:
		value = min_value - current_value
	
	return value


func set_max_value(new_max_value: int) -> int:
	if new_max_value < min_value:
		push_warning("New max value (" + str(new_max_value) + ") < min value (" + str(min_value)+ ")")
	
	max_value = new_max_value
	var delta_current: int = set_value(current_value)
	
	value_changed.emit(self)
	return delta_current


func set_min_value(new_min_value: int) -> int:
	if new_min_value > max_value:
		push_warning("New min value (" + str(new_min_value) + ") > max value (" + str(max_value)+ ")")
	
	min_value = new_min_value
	var delta_current: int = set_value(current_value)
	
	value_changed.emit(self)
	return delta_current


func add_modifier(new_modifier: Modifier, emit_value_changed: bool = true) -> void:
	modifiers.append(new_modifier)
	if emit_value_changed:
		value_changed.emit(self)


func remove_modifier(modifier: Modifier) -> void:
	modifiers.erase(modifier)
	value_changed.emit(self)


func update_max_from_clamped_value(max_clamped: StatValue) -> void:
	set_max_value(max_clamped.get_modified_value())
