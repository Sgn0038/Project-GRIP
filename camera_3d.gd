extends Camera3D

@export_category("Camera Settings")
@export var move_speed: float = 10.0
@export var look_sensitivity: float = 0.003
@export var zoom_speed: float = 2.0

var initial_transform: Transform3D

func _ready() -> void:
	# Save the starting position and rotation
	initial_transform = transform

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			translate(Vector3(0, 0, -zoom_speed))
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			translate(Vector3(0, 0, zoom_speed))

	# Reset view with control+M (Later also assigned through menu signal)
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_M and event.ctrl_pressed:
			transform = initial_transform

	if event is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
		rotate_y(-event.relative.x * look_sensitivity)

func _process(delta: float) -> void:
	var input_dir = Vector3.ZERO

	if Input.is_key_pressed(KEY_W):
		input_dir.z -= 1.0
	if Input.is_key_pressed(KEY_S):
		input_dir.z += 1.0
	if Input.is_key_pressed(KEY_A):
		input_dir.x -= 1.0
	if Input.is_key_pressed(KEY_D):
		input_dir.x += 1.0

	input_dir = input_dir.normalized()

	# Calculate movement vector based on camera's current rotation
	var move_vector = (transform.basis * input_dir) * move_speed * delta

	var vertical_dir = 0.0
	if Input.is_key_pressed(KEY_SPACE):
		vertical_dir += 1.0
	if Input.is_key_pressed(KEY_SHIFT):
		vertical_dir -= 1.0

	move_vector += Vector3(0, vertical_dir, 0) * move_speed * delta

	# Apply translation
	global_translate(move_vector)
