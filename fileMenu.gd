extends PopupMenu


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	add_item("New Scene")
	add_item("Save Scene")
	add_item("Load Scene")
	index_pressed.connect(onPress)


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(_delta: float) -> void:
	pass

func onPress(index) -> void:
	match index:
		0:
			print("New Scene Loading")
		1:
			print("Saved scene!")
		2:
			print("Loaded Scene!")
			
