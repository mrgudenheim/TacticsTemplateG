class_name DataRegistry
extends RefCounted

var resource_type_name: String = ""
var file_suffix: String = ""

var _loader: Callable = Callable()
var _paths: Dictionary[String, String] = {}
var _cache: Dictionary[String, Resource] = {}


func _init(
	new_resource_type_name: String,
	new_file_suffix: String,
	new_loader: Callable,
) -> void:
	resource_type_name = new_resource_type_name
	file_suffix = new_file_suffix.to_lower()
	_loader = new_loader
	if not _loader.is_valid():
		push_error("DataRegistry[%s]: invalid loader callable" % resource_type_name)


func matches_file(file_path: String) -> bool:
	if file_suffix.is_empty():
		return false
	return file_path.to_lower().ends_with(file_suffix)


func index_file(file_path: String) -> bool:
	if not matches_file(file_path):
		return false
	var file_name: String = file_path.get_file()
	var unique_name: String = file_name.left(file_name.length() - file_suffix.length())
	if unique_name.is_empty():
		push_warning("DataRegistry[%s]: skipping file with empty unique_name '%s'" % [resource_type_name, file_path])
		return true
	_paths[unique_name] = file_path
	return true


func register(unique_name: String, value: Resource, file_path: String = "") -> void:
	_cache[unique_name] = value
	if not file_path.is_empty():
		_paths[unique_name] = file_path


func has(unique_name: String) -> bool:
	return _cache.has(unique_name) or _paths.has(unique_name)


func is_empty() -> bool:
	return _cache.is_empty() and _paths.is_empty()


func get_file_path(unique_name: String) -> String:
	if _paths.has(unique_name):
		return _paths[unique_name]
	push_error("DataRegistry[%s]: missing file path for '%s'" % [resource_type_name, unique_name])
	return ""


func get_all_ids() -> Array[String]:
	var all_ids: Array[String] = []
	for unique_name: String in _paths.keys():
		all_ids.append(unique_name)
	for unique_name: String in _cache.keys():
		if not _paths.has(unique_name):
			all_ids.append(unique_name)
	return all_ids


func get_or_null(unique_name: String) -> Resource:
	if _cache.has(unique_name):
		return _cache[unique_name]
	if not _paths.has(unique_name):
		push_error("DataRegistry[%s]: unknown id '%s'" % [resource_type_name, unique_name])
		return null

	if not _loader.is_valid():
		push_error("DataRegistry[%s]: cannot load '%s' without a valid loader" % [resource_type_name, unique_name])
		return null

	var file_path: String = _paths[unique_name]
	var loaded_value: Resource = _loader.call(file_path) as Resource

	if loaded_value == null:
		push_error("DataRegistry[%s]: failed to load '%s' from '%s'" % [resource_type_name, unique_name, file_path])
		return null

	_cache[unique_name] = loaded_value
	return loaded_value


func load_all() -> void:
	for unique_name: String in _paths.keys():
		get_or_null(unique_name)


func clear() -> void:
	_paths.clear()
	_cache.clear()
