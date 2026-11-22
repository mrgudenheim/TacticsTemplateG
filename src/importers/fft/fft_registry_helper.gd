class_name FftRegistryHelper
extends RefCounted


static func register_unique(
	registry: Dictionary,
	resource: Resource,
	fallback_display_name: String,
	resource_label: String,
	will_overwrite: bool = false
) -> String:
	var current_unique_name: String = resource.unique_name
	if ["", "unique_name", "unique_name.triggered"].has(current_unique_name):
		if fallback_display_name.is_empty():
			push_warning("%s needs unique_name set" % resource_label)
		else:
			current_unique_name = fallback_display_name.to_snake_case()

	if registry.has(current_unique_name) and will_overwrite:
		push_warning("Overwriting existing %s: %s" % [resource_label, current_unique_name])
	elif registry.has(current_unique_name) and not will_overwrite:
		var suffix_number: int = 2
		var candidate_name: String = "%s_%02d" % [current_unique_name, suffix_number]
		while registry.has(candidate_name):
			suffix_number += 1
			candidate_name = "%s_%02d" % [current_unique_name, suffix_number]

		push_warning("%s list already contains: %s. Incrementing unique_name to: %s" % [
			resource_label,
			current_unique_name,
			candidate_name,
		])
		current_unique_name = candidate_name

	resource.unique_name = current_unique_name
	registry[current_unique_name] = resource
	return current_unique_name
