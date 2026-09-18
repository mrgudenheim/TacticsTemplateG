extends RefCounted

## Shared loader for the hand-authored / extracted JSON data assets that
## follow the "XDatabase shape" (see CONTEXT.md → Hand-authored data asset).
##
## Every `class_name` data store in `src/` used to hand-copy the same
## `_ensure_loaded()` body: open the file → null-check + push_error → parse →
## error-check + push_error → `get_data()` → unwrap a wrapper key. That
## boilerplate had already drifted (some stores swallowed errors, some used
## `push_warning`, some `JSON.parse_string()` vs `JSON.new().parse()`). This
## concentrates the open/parse/error dance in one place so a parse-handling
## fix lands once instead of ×18.
##
## This is a FREE-FUNCTION helper, not a base class the stores `extends`.
## GDScript per-subclass `static var` state does not inherit the way a shared
## cache would need, so each store keeps its own typed static cache,
## accessors, and `_loaded` flag — only the I/O body moves here.


static func load_dict(path: String, key: String = "") -> Dictionary:
	"""Open `path`, parse it as JSON, and return the root object.

	When `key` is given, return `root[key]` instead (the common "unwrap one
	wrapper key" case). A missing key returns `{}` silently, matching the
	`data.get(key, {})` idiom the stores used to inline.

	On any hard failure — missing file, parse error, a non-object root, or a
	value at `key` that is not itself an object — push_error and return `{}`.

	For values that are NOT a top-level object (an Array under a key, a nested
	path, or several sibling keys), call with the default empty `key` to get
	the root and pluck locally, e.g.:
	    JsonAsset.load_dict(path).get("groups", [])
	    var d := JsonAsset.load_dict(path); _a = d.get("x", {}); _b = d.get("y", [])
	"""
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("[JsonAsset] Failed to open %s (err %d)" % [path, FileAccess.get_open_error()])
		return {}

	var json := JSON.new()
	var err := json.parse(file.get_as_text())
	file.close()
	if err != OK:
		push_error("[JsonAsset] Failed to parse %s: %s (line %d)" % [
			path, json.get_error_message(), json.get_error_line()])
		return {}

	var data: Variant = json.get_data()
	if typeof(data) != TYPE_DICTIONARY:
		push_error("[JsonAsset] Root of %s is not a JSON object (got %s)" % [
			path, type_string(typeof(data))])
		return {}

	if key.is_empty():
		return data

	var value: Variant = data.get(key, {})
	if typeof(value) != TYPE_DICTIONARY:
		push_error("[JsonAsset] Key '%s' in %s is not a JSON object (got %s); load the root with load_dict(path) and pluck it" % [
			key, path, type_string(typeof(value))])
		return {}
	return value
