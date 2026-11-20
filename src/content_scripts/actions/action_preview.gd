class_name ActionPreview
extends Control

@export var label: Label
@export var unit: UnitActor
var camera: Camera3D

func _ready() -> void:
	camera = get_viewport().get_camera_3d()


func _process(_delta: float) -> void:
	if camera != null and is_instance_valid(unit) and unit.char_body != null:
		var camera_right: Vector3 = camera.basis * Vector3.RIGHT
		position = camera.unproject_position(unit.char_body.position + (Vector3.UP * 1.0) + (camera_right * 0.0))


func set_from_resolution(resolution: ActionResolution, target_unit: UnitData) -> void:
	if label == null or resolution == null or target_unit == null:
		return

	var lines: PackedStringArray = []
	var direct_result: ActionTargetResult = resolution.get_direct_target_result(target_unit)
	if direct_result != null:
		lines.append(str(direct_result.hit_chance_percentage) + "% Hit")

		var stat_lines: PackedStringArray = _format_stat_deltas(direct_result)
		lines.append_array(stat_lines)

		var status_line: String = _format_status_preview(resolution.action, direct_result)
		if not status_line.is_empty():
			lines.append(status_line)

		var sub_resolution_lines: PackedStringArray = _format_child_resolutions(direct_result.target_sub_resolutions, target_unit)
		lines.append_array(sub_resolution_lines)

	var follow_up_lines: PackedStringArray = _format_child_resolutions(resolution.secondary_resolutions, target_unit)
	lines.append_array(follow_up_lines)

	label.text = "\n".join(lines)


func _format_stat_deltas(target_result: ActionTargetResult) -> PackedStringArray:
	var stat_lines: PackedStringArray = []
	for stat_type: UnitData.StatType in target_result.stat_deltas.keys():
		var delta: int = target_result.stat_deltas[stat_type]
		if delta == 0:
			continue
		var stat_name: String = UnitData.StatType.keys()[stat_type]
		var prefix: String = "+" if delta > 0 else ""
		stat_lines.append("%s%d %s" % [prefix, delta, stat_name])
	return stat_lines


func _format_status_preview(action_data: Action, target_result: ActionTargetResult) -> String:
	if action_data == null or action_data.target_status_list.is_empty():
		return ""

	var status_chance_text: String = str(action_data.target_status_chance) + "%"
	var remove_prefix: String = "Remove " if action_data.will_remove_target_status else ""
	var group_type_text: String = ""
	if action_data.target_status_list.size() >= 2:
		group_type_text = Action.StatusListType.keys()[action_data.target_status_list_type] + " "

	var status_names: PackedStringArray = []
	for status_id: String in target_result.eligible_status_ids:
		var status_effect: StatusEffect = ActionResolver.lookup_status_effect(status_id)
		if status_effect != null and not status_effect.status_effect_name.is_empty():
			status_names.append(status_effect.status_effect_name)
		else:
			status_names.append(status_id.capitalize())

	if status_names.is_empty() and action_data.will_remove_target_status:
		status_names.append("[No status to remove]")
	elif status_names.is_empty():
		return ""

	return status_chance_text + " " + remove_prefix + group_type_text + ", ".join(status_names)


func _format_child_resolutions(child_resolutions: Array[ActionResolution], target_unit: UnitData) -> PackedStringArray:
	var child_lines: PackedStringArray = []
	if child_resolutions.is_empty():
		return child_lines

	var matching_children: Array[ActionResolution] = []
	for child_resolution: ActionResolution in child_resolutions:
		if child_resolution != null and child_resolution.get_direct_target_result(target_unit) != null:
			matching_children.append(child_resolution)

	if matching_children.is_empty():
		return child_lines

	if matching_children.size() >= 2 and matching_children[0].is_probabilistic_branch():
		child_lines.append(Action.StatusListType.keys()[matching_children[0].branch_list_type])

	for child_resolution: ActionResolution in matching_children:
		var child_result: ActionTargetResult = child_resolution.get_direct_target_result(target_unit)
		var action_name: String = child_resolution.action.display_name if child_resolution.action != null else "Secondary"
		var summary_parts: PackedStringArray = []

		if child_resolution.roll_hit_chance and (not child_resolution.is_probabilistic_branch() or child_result.hit_chance_percentage < 100):
			summary_parts.append(str(child_result.hit_chance_percentage) + "% Hit")

		summary_parts.append_array(_format_stat_deltas(child_result))

		var child_status_text: String = _format_status_preview(child_resolution.action, child_result)
		if not child_status_text.is_empty():
			summary_parts.append(child_status_text)

		var summary_text: String = ", ".join(summary_parts)
		if child_resolution.is_probabilistic_branch():
			var branch_percent: int = roundi(child_resolution.get_branch_probability() * 100.0)
			if summary_text.is_empty():
				child_lines.append("%d%% %s" % [branch_percent, action_name])
			else:
				child_lines.append("%d%% %s (%s)" % [branch_percent, action_name, summary_text])
		else:
			if summary_text.is_empty():
				child_lines.append(action_name)
			else:
				child_lines.append("%s: %s" % [action_name, summary_text])

		if not child_result.target_sub_resolutions.is_empty():
			child_lines.append_array(_format_child_resolutions(child_result.target_sub_resolutions, target_unit))

	return child_lines
