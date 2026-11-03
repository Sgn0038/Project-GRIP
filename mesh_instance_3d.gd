extends MeshInstance3D


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	for surface in mesh.get_surface_count():
		for arr in mesh.surface_get_arrays(surface):
			if arr != null:
				print(arr.size())


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass
