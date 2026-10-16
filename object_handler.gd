extends Node3D


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	# Connect Signals from menu to this script
	SignalBus.object_filepath_chosen.connect(load_object_model)
	SignalBus.object_clear_all.connect(remove_all_objects)

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(_delta: float) -> void:
	pass

func load_object_model(path: String):
	var file_type = path.get_extension().to_lower() # find the actual filetype
	var document_load # the document before converted to a node
	var root_node # the document after assmbly to a mesh
	match file_type:
		"fbx":
			document_load = FBXDocument.new()
			var state_load = FBXState.new()
			var error = document_load.append_from_file(path, state_load) # Check file validity
			if error == OK:
				root_node = document_load.generate_scene(state_load)
				add_child(root_node) # Add the generated mesh as a child
			else:
				printerr("Couldn't load glTF scene (error code: %s)." % error_string(error))
		"obj":
			document_load = ObjParse.from_path(path) # Get the byte data from the obj
			root_node = MeshInstance3D.new()
			root_node.mesh = document_load # Load the byte data to a mesh
			add_child(root_node) # Add the object as a child
			
	var spawned_object = get_child(get_child_count() - 1) 
	if spawned_object is Node3D:
		spawned_object.global_position = Vector3(0, 0, 0) 
	spawned_object.scale = Vector3(1, 1, 1)

func remove_all_objects():
	for child in get_children():
		remove_child(child)
		child.queue_free()
