class_name ContentValidator
extends RefCounted

const SPECIAL_TRIGGERED_ACTION_NAMES: PackedStringArray = ["ATTACK", "COPY"]
const IGNORED_PLACEHOLDER_NAMES: PackedStringArray = [
	"",
	"unique_name",
	"[skillset unique name]",
]


static func validate_rom_reader_exports(rom_reader: RomReader) -> Array[String]:
	var skillsets_by_name: Dictionary[String, Skillset] = {}
	for skillset_item: Skillset in rom_reader.scus_data.skillsets_data:
		if skillset_item != null and not IGNORED_PLACEHOLDER_NAMES.has(skillset_item.unique_name):
			skillsets_by_name[skillset_item.unique_name] = skillset_item

	var valid_vfx_names: Dictionary[String, bool] = {}
	for vfx_item: VisualEffectData in rom_reader.vfx:
		if vfx_item != null and vfx_item.is_initialized and not vfx_item.unique_name.is_empty():
			valid_vfx_names[vfx_item.unique_name] = true

	var warnings: Array[String] = _validate_collections(
		rom_reader.status_effects,
		rom_reader.passive_effects,
		rom_reader.actions,
		rom_reader.triggered_actions,
		rom_reader.abilities,
		rom_reader.items,
		rom_reader.jobs_data,
		skillsets_by_name,
		valid_vfx_names
	)
	_report_warnings("RomReader export", warnings)
	return warnings


static func validate_game_data() -> Array[String]:
	var status_effects_by_name: Dictionary[String, StatusEffect] = {}
	for status_name: String in GameData.status_effect_paths.keys():
		status_effects_by_name[status_name] = GameData.get_status_effect(status_name)
	for status_name: String in GameData.status_effects.keys():
		status_effects_by_name[status_name] = GameData.status_effects[status_name]

	var passive_effects_by_name: Dictionary[String, PassiveEffect] = {}
	for passive_name: String in GameData.passive_effect_paths.keys():
		passive_effects_by_name[passive_name] = GameData.get_passive_effect(passive_name)
	for passive_name: String in GameData.passive_effects.keys():
		passive_effects_by_name[passive_name] = GameData.passive_effects[passive_name]

	var actions_by_name: Dictionary[String, Action] = {}
	for action_name: String in GameData.action_paths.keys():
		actions_by_name[action_name] = GameData.get_action(action_name)
	for action_name: String in GameData.actions.keys():
		actions_by_name[action_name] = GameData.actions[action_name]

	var triggered_actions_by_name: Dictionary[String, TriggeredAction] = {}
	for triggered_name: String in GameData.triggered_action_paths.keys():
		triggered_actions_by_name[triggered_name] = GameData.get_triggered_action(triggered_name)
	for triggered_name: String in GameData.triggered_actions.keys():
		triggered_actions_by_name[triggered_name] = GameData.triggered_actions[triggered_name]

	var abilities_by_name: Dictionary[String, Ability] = {}
	for ability_name: String in GameData.ability_paths.keys():
		abilities_by_name[ability_name] = GameData.get_ability(ability_name)
	for ability_name: String in GameData.abilities.keys():
		abilities_by_name[ability_name] = GameData.abilities[ability_name]

	var items_by_name: Dictionary[String, ItemData] = {}
	for item_name: String in GameData.item_paths.keys():
		items_by_name[item_name] = GameData.get_item(item_name)
	for item_name: String in GameData.items.keys():
		items_by_name[item_name] = GameData.items[item_name]

	var jobs_by_name: Dictionary[String, JobData] = {}
	for job_name: String in GameData.job_paths.keys():
		jobs_by_name[job_name] = GameData.get_job(job_name)
	for job_name: String in GameData.jobs_data.keys():
		jobs_by_name[job_name] = GameData.jobs_data[job_name]

	var skillsets_by_name: Dictionary[String, Skillset] = {}
	for skillset_name: String in GameData.skillset_paths.keys():
		skillsets_by_name[skillset_name] = GameData.get_skillset(skillset_name)
	for skillset_name: String in GameData.skillsets.keys():
		skillsets_by_name[skillset_name] = GameData.skillsets[skillset_name]

	var valid_vfx_names: Dictionary[String, bool] = {}
	for vfx_name: String in GameData.vfx_data_paths.keys():
		valid_vfx_names[vfx_name] = true
	for vfx_name: String in GameData.vfx.keys():
		valid_vfx_names[vfx_name] = true

	var warnings: Array[String] = _validate_collections(
		status_effects_by_name,
		passive_effects_by_name,
		actions_by_name,
		triggered_actions_by_name,
		abilities_by_name,
		items_by_name,
		jobs_by_name,
		skillsets_by_name,
		valid_vfx_names
	)
	_report_warnings("GameData", warnings)
	return warnings


static func _validate_collections(
	status_effects_by_name: Dictionary[String, StatusEffect],
	passive_effects_by_name: Dictionary[String, PassiveEffect],
	actions_by_name: Dictionary[String, Action],
	triggered_actions_by_name: Dictionary[String, TriggeredAction],
	abilities_by_name: Dictionary[String, Ability],
	items_by_name: Dictionary[String, ItemData],
	jobs_by_name: Dictionary[String, JobData],
	skillsets_by_name: Dictionary[String, Skillset],
	valid_vfx_names: Dictionary[String, bool]
) -> Array[String]:
	var warnings: Array[String] = []

	for status_key: String in status_effects_by_name.keys():
		var status_effect: StatusEffect = status_effects_by_name[status_key]
		if status_effect == null:
			continue
		_check_single_reference(warnings, "StatusEffect", status_key, "action_on_apply", status_effect.action_on_apply, actions_by_name, "Action")
		_check_single_reference(warnings, "StatusEffect", status_key, "action_on_turn_start", status_effect.action_on_turn_start, actions_by_name, "Action")
		_check_single_reference(warnings, "StatusEffect", status_key, "action_on_turn_end", status_effect.action_on_turn_end, actions_by_name, "Action")
		_check_single_reference(warnings, "StatusEffect", status_key, "action_on_x_ticks", status_effect.action_on_x_ticks, actions_by_name, "Action")
		_check_single_reference(warnings, "StatusEffect", status_key, "action_on_complete", status_effect.action_on_complete, actions_by_name, "Action")
		_check_single_reference(warnings, "StatusEffect", status_key, "passive_effect_name", status_effect.passive_effect_name, passive_effects_by_name, "PassiveEffect")
		_check_packed_reference_list(warnings, "StatusEffect", status_key, "status_cancels", status_effect.status_cancels, status_effects_by_name, "StatusEffect")
		_check_packed_reference_list(warnings, "StatusEffect", status_key, "status_cant_stack", status_effect.status_cant_stack, status_effects_by_name, "StatusEffect")

	for passive_key: String in passive_effects_by_name.keys():
		var passive_effect: PassiveEffect = passive_effects_by_name[passive_key]
		if passive_effect == null:
			continue
		_check_packed_reference_list(warnings, "PassiveEffect", passive_key, "added_actions_names", passive_effect.added_actions_names, actions_by_name, "Action")
		_check_packed_reference_list(warnings, "PassiveEffect", passive_key, "added_triggered_actions_names", passive_effect.added_triggered_actions_names, triggered_actions_by_name, "TriggeredAction")
		_check_packed_reference_list(warnings, "PassiveEffect", passive_key, "add_applicable_target_jobs", passive_effect.add_applicable_target_jobs, jobs_by_name, "JobData")
		_check_packed_reference_list(warnings, "PassiveEffect", passive_key, "add_applicable_target_statuses", passive_effect.add_applicable_target_statuses, status_effects_by_name, "StatusEffect")
		_check_packed_reference_list(warnings, "PassiveEffect", passive_key, "status_always", passive_effect.status_always, status_effects_by_name, "StatusEffect")
		_check_packed_reference_list(warnings, "PassiveEffect", passive_key, "status_immune", passive_effect.status_immune, status_effects_by_name, "StatusEffect")
		_check_packed_reference_list(warnings, "PassiveEffect", passive_key, "status_start", passive_effect.status_start, status_effects_by_name, "StatusEffect")

	for action_key: String in actions_by_name.keys():
		var action_data: Action = actions_by_name[action_key]
		if action_data == null:
			continue
		_check_packed_reference_list(warnings, "Action", action_key, "target_status_list", action_data.target_status_list, status_effects_by_name, "StatusEffect")
		_check_packed_reference_list(warnings, "Action", action_key, "user_status_list", action_data.user_status_list, status_effects_by_name, "StatusEffect")
		for preventing_status: String in action_data.status_prevents_use_any:
			_check_single_reference(warnings, "Action", action_key, "status_prevents_use_any", preventing_status, status_effects_by_name, "StatusEffect")
		_check_packed_reference_list(warnings, "Action", action_key, "ignores_statuses", action_data.ignores_statuses, status_effects_by_name, "StatusEffect")
		_check_packed_reference_list(warnings, "Action", action_key, "required_target_status_uname", action_data.required_target_status_uname, status_effects_by_name, "StatusEffect")
		_check_packed_reference_list(warnings, "Action", action_key, "required_target_job_uname", action_data.required_target_job_uname, jobs_by_name, "JobData")
		_check_packed_reference_list(warnings, "Action", action_key, "required_equipment_unique_name", action_data.required_equipment_unique_name, items_by_name, "ItemData")
		_check_packed_reference_list(warnings, "Action", action_key, "ignore_passives", action_data.ignore_passives, passive_effects_by_name, "PassiveEffect")
		for secondary_action: SecondaryAction in action_data.secondary_actions2:
			if secondary_action != null:
				_check_single_reference(warnings, "Action", action_key, "secondary_actions2.action_unique_name", secondary_action.action_unique_name, actions_by_name, "Action")
		if not valid_vfx_names.is_empty():
			_check_single_reference(warnings, "Action", action_key, "vfx_name", action_data.vfx_name, valid_vfx_names, "VisualEffectData")

	for triggered_key: String in triggered_actions_by_name.keys():
		var triggered_action: TriggeredAction = triggered_actions_by_name[triggered_key]
		if triggered_action == null:
			continue
		_check_single_reference(
			warnings,
			"TriggeredAction",
			triggered_key,
			"action_unique_name",
			triggered_action.action_unique_name,
			actions_by_name,
			"Action",
			SPECIAL_TRIGGERED_ACTION_NAMES
		)
		_check_packed_reference_list(warnings, "TriggeredAction", triggered_key, "required_status_id", triggered_action.required_status_id, status_effects_by_name, "StatusEffect")

	for ability_key: String in abilities_by_name.keys():
		var ability_data: Ability = abilities_by_name[ability_key]
		if ability_data == null:
			continue
		_check_single_reference(warnings, "Ability", ability_key, "passive_effect_name", ability_data.passive_effect_name, passive_effects_by_name, "PassiveEffect")
		_check_packed_reference_list(warnings, "Ability", ability_key, "triggered_actions_names", ability_data.triggered_actions_names, triggered_actions_by_name, "TriggeredAction")

	for item_key: String in items_by_name.keys():
		var item_data: ItemData = items_by_name[item_key]
		if item_data == null:
			continue
		_check_single_reference(warnings, "ItemData", item_key, "weapon_attack_action_name", item_data.weapon_attack_action_name, actions_by_name, "Action")
		_check_packed_reference_list(warnings, "ItemData", item_key, "equipped_action_names", item_data.equipped_action_names, actions_by_name, "Action")
		_check_single_reference(warnings, "ItemData", item_key, "passive_effect_name", item_data.passive_effect_name, passive_effects_by_name, "PassiveEffect")

	for job_key: String in jobs_by_name.keys():
		var job_data: JobData = jobs_by_name[job_key]
		if job_data == null:
			continue
		if not skillsets_by_name.is_empty():
			_check_single_reference(warnings, "JobData", job_key, "skillset_unique_name", job_data.skillset_unique_name, skillsets_by_name, "Skillset")
		_check_packed_reference_list(warnings, "JobData", job_key, "innate_ability_names", job_data.innate_ability_names, abilities_by_name, "Ability")
		_check_packed_reference_list(warnings, "JobData", job_key, "passive_effect_names", job_data.passive_effect_names, passive_effects_by_name, "PassiveEffect")

	for skillset_key: String in skillsets_by_name.keys():
		var skillset_data: Skillset = skillsets_by_name[skillset_key]
		if skillset_data == null:
			continue
		_check_packed_reference_list(warnings, "Skillset", skillset_key, "ability_names", skillset_data.ability_names, abilities_by_name, "Ability")

	return warnings


static func _check_packed_reference_list(
	warnings: Array[String],
	source_type: String,
	source_name: String,
	field_name: String,
	target_names: PackedStringArray,
	target_registry: Dictionary,
	target_type: String,
	allowed_special_names: PackedStringArray = []
) -> void:
	for target_name: String in target_names:
		_check_single_reference(
			warnings,
			source_type,
			source_name,
			field_name,
			target_name,
			target_registry,
			target_type,
			allowed_special_names
		)


static func _check_single_reference(
	warnings: Array[String],
	source_type: String,
	source_name: String,
	field_name: String,
	target_name: String,
	target_registry: Dictionary,
	target_type: String,
	allowed_special_names: PackedStringArray = []
) -> void:
	if IGNORED_PLACEHOLDER_NAMES.has(target_name):
		return
	if allowed_special_names.has(target_name):
		return
	if not target_registry.has(target_name):
		warnings.append(
			"[ContentValidator] %s '%s'.%s references missing %s '%s'" % [
				source_type,
				source_name,
				field_name,
				target_type,
				target_name,
			]
		)


static func _report_warnings(context_label: String, warnings: Array[String]) -> void:
	if warnings.is_empty():
		print("[ContentValidator] %s validation passed with 0 broken references." % context_label)
		return

	for warning_text: String in warnings:
		push_warning(warning_text)
	push_warning("[ContentValidator] %s validation found %d broken reference(s)." % [context_label, warnings.size()])
