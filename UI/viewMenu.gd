extends PopupMenu

@export var hand_toggled: bool  = true

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	add_check_item("Show Editor Menu")
	add_check_item("Show Hand")
	set_item_checked(1, hand_toggled) 
	index_pressed.connect(on_press)
	
# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(_delta: float) -> void:
	pass
	

func on_press(index: int):
	match index:
		0: # Selecting Show Editor Menu
			return
		1: # Selecting Show Hand
			hand_toggled = is_item_checked(1)
			hand_toggled = !hand_toggled
			set_item_checked(1, hand_toggled)
			SignalBus.view_hand_toggle.emit(hand_toggled)				
