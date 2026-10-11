extends PopupMenu

@onready var object_file_picker: FileDialog = $ObjectFilePicker

signal object_imported(path: String)

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	add_item("Import Object")
	add_item("Clear All Objects")
	index_pressed.connect(on_press)
	object_file_picker.file_selected.connect(alert_object_manager)

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass

func on_press(index):
	match index:
		0:
			object_file_picker.popup_centered_ratio(0.6)
			# Now the signal is connected and will run import


func alert_object_manager(path: String):
	SignalBus.object_filepath_chosen.emit(path)
