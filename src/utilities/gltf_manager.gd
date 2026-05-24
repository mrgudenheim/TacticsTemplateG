class_name GltfManager


static func save_node(node_to_save: Node, save_directory: String = "user://exports/", file_name: String = "node.glb") -> void:
	DirAccess.make_dir_recursive_absolute(save_directory)
	# var file_name: String = node_to_save.name + extension
	var gltf_state: GLTFState = GLTFState.new()
	var gltf_document: GLTFDocument = GLTFDocument.new()
	
	gltf_document.append_from_scene(node_to_save, gltf_state)
	gltf_document.write_to_filesystem(gltf_state, save_directory.path_join(file_name))
	
	push_warning("Saved: " + save_directory.path_join(file_name))


static func import_gltf(import_path: String) -> Node:
	var gltf_state: GLTFState = GLTFState.new()
	var gltf_document: GLTFDocument = GLTFDocument.new()
	var error: int = gltf_document.append_from_file(import_path, gltf_state, 0, import_path.get_base_dir())
	if error != 0:
		push_warning(import_path.get_file() + " failed to import as glb: " + str(error))
		return null
	
	var node: Node = gltf_document.generate_scene(gltf_state)
	node.name = import_path.get_file().get_basename()
	
	return node
