extends Node3D


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	SignalBus.object_filepath_chosen.connect(load_object_model)

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass

func load_object_model(path: String):
	var file_type = path.get_extension().to_lower()
	var document_load
	var root_node
	match file_type:
		"fbx":
			document_load = FBXDocument.new()
			var state_load = FBXState.new()
			var error = document_load.append_from_file(path, state_load)
			if error == OK:
				root_node = document_load.generate_scene(state_load)
				add_child(root_node)
			else:
				printerr("Couldn't load glTF scene (error code: %s)." % error_string(error))
		"obj":
			document_load = ObjParse.from_path(path)
			root_node = MeshInstance3D.new()
			root_node.mesh = document_load
			add_child(root_node)
			
	var spawned_object = get_child(get_child_count() - 1)
	if spawned_object is Node3D:
		spawned_object.global_position = Vector3(0, 0, 0) 
	spawned_object.scale = Vector3(1, 1, 1)
