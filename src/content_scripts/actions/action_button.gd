class_name ActionButton
extends Button

var action_instance: ActionInstance

func _init(new_action_instance: ActionInstance = null) -> void:
	if new_action_instance == null:
		push_warning("Creating ActionButton without action instance")
		return
	
	action_instance = new_action_instance
	
	text = action_instance.action.display_name
	name = action_instance.action.display_name
	
	pressed.connect(action_instance.start_targeting)
	
	focus_entered.connect(set_active_action)
	#focus_exited.connect(hide_potential_targets)
	
	mouse_entered.connect(show_potential_targets)
	mouse_exited.connect(hide_potential_targets)


func show_potential_targets() -> void:
	if is_instance_valid(action_instance.user.active_action):
		action_instance.user.active_action.stop_targeting()
	
	action_instance.show_potential_targets()


func hide_potential_targets() -> void:
	action_instance.hide_potential_targets()
	
	if action_instance.user.active_action != null:
		if not action_instance.user.active_action.action.auto_target:
			action_instance.user.active_action.start_targeting()


func set_active_action() -> void:
	if disabled:
		return
	
	if not action_instance.action.auto_target:
		if not action_instance.potential_targets_are_set:
			await action_instance.update_potential_targets()
		action_instance.start_targeting()
	else:
		if action_instance.user.active_action != null:
			action_instance.user.active_action.stop_targeting()
		action_instance.show_potential_targets()
		action_instance.user.active_action = action_instance
