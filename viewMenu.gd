extends PopupMenu


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	add_check_item("Show Editor Menu")
	add_check_item("Show Hand")

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(_delta: float) -> void:
	pass
