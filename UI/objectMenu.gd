extends PopupMenu

@onready var object_file_picker: FileDialog = $ObjectFilePicker

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	add_item("Import Object")
	add_item("Clear All Objects")
	index_pressed.connect(on_press) # Handles what happens to each index after press
	# Connect the file picker signal to this file, then alert object manager
	object_file_picker.file_selected.connect(alert_object_manager) 

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(_delta: float) -> void:
	pass

func on_press(index):
	match index:
		0: # Selecting "Import Object"
			object_file_picker.popup_centered_ratio(0.6)
		1: # Selecting "Clear All Objects"
			SignalBus.object_clear_all.emit()


func alert_object_manager(path: String):
	SignalBus.object_filepath_chosen.emit(path)
