extends Node3D
@export var spawn_position: Vector3 = Vector3(0, 0, 0)
@export var spawn_size: float = 1

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
	var model: Node3D
	match file_type:
		"fbx":
			var document_load = FBXDocument.new()
			var state_load = FBXState.new()
			var error = document_load.append_from_file(path, state_load) # Check file validity
			if error != OK:
				printerr("Couldn't load glTF scene (error code: %s)." % error_string(error))
				return
			model = document_load.generate_scene(state_load)
		"obj":
			var model_mesh = ObjParse.from_path(path) # Get the byte data from the obj
			model = _mesh_to_model(model_mesh)
		"stl":
			var model_mesh = STLIO.Importer.LoadFromPath(path)
			model = _mesh_to_model(model_mesh)
		_:
			return
	
	add_child(_build_model(model))
	

func _mesh_to_model(mesh: ArrayMesh) -> MeshInstance3D:
	var instance = MeshInstance3D.new()
	instance.mesh = mesh
	return instance
	
func _build_model(model: Node3D) -> Node3D:
	var holder := Node3D.new() 
	holder.add_child(model)

	var aabbs: Array[AABB] = _get_all_aabbs(model, Transform3D.IDENTITY)
	if aabbs.is_empty():
		return holder

	var combined := aabbs[0]
	for box in aabbs:
		combined = combined.merge(box)

	var largest := maxf(combined.size.x, maxf(combined.size.y, combined.size.z))
	if largest > 0.001:
		var scale_factor := spawn_size / largest
		var base := Vector3(combined.get_center().x, combined.position.y, combined.get_center().z)
		model.scale = Vector3.ONE * scale_factor
		model.position = -base * scale_factor
	return holder

	
func _get_all_aabbs(node: Node, tf: Transform3D) -> Array[AABB]:
	var output: Array[AABB] = []
	if node is Node3D and node.get_parent() != null:
		tf = tf * node.transform
	if node is MeshInstance3D and node.mesh:
		output.append(tf * node.mesh.get_aabb())
	for child in node.get_children():
		output.append_array(_get_all_aabbs(child, tf))
		
	return output
	
func remove_all_objects():
	for child in get_children():
		remove_child(child)
		child.queue_free()
