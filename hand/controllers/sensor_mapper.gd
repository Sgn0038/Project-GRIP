class_name SensorMapper
extends Node

# Emitted when a frame of normalized spatial targets is processed
signal pose_data_ready(palm_transform: Transform3D, fingertip_positions: Dictionary)

# Enum representing supported hardware configurations
enum SensorLayout {
	DUMMY_SYNTHETIC,    ## Generates procedural movement for testing without hardware
	FLEX_AND_IMU,       ## IMU on palm + 5 single-axis bend sensors on fingers
	DUAL_IMU_FINGERS,   ## Palm IMU + IMUs on each distal finger segment
}

@export_group("Configuration")
@export var active_layout: SensorLayout = SensorLayout.DUMMY_SYNTHETIC
@export var ble_manager: Node

@export_group("Hand Calibration (Meters)")
@export var wrist_to_palm_offset := Vector3(0.0, 0.0, -0.08)
@export var finger_offsets := {
	"Thumb": Vector3(-0.03, -0.01, -0.10),
	"Index": Vector3(-0.025, 0.0, -0.14),
	"Middle": Vector3(0.0, 0.0, -0.15),
	"Ring": Vector3(0.025, 0.0, -0.14),
	"Pinky": Vector3(0.04, -0.005, -0.12)
}

# Internal State
var _synthetic_time: float = 0.0
var _raw_curl_values := {"Thumb": 0.0, "Index": 0.0, "Middle": 0.0, "Ring": 0.0, "Pinky": 0.0}
var _current_palm_transform := Transform3D.IDENTITY

func _ready() -> void:
	if ble_manager and ble_manager.has_signal("raw_data_received"):
		ble_manager.connect("raw_data_received", _on_raw_ble_data)

func _process(delta: float) -> void:
	# If hardware isn't attached, generate procedural testing movement
	if active_layout == SensorLayout.DUMMY_SYNTHETIC:
		_synthetic_time += delta
		_generate_synthetic_pose(_synthetic_time)

# Primary receiver for BLE byte streams
func _on_raw_ble_data(payload: PackedByteArray) -> void:
	match active_layout:
		SensorLayout.FLEX_AND_IMU:
			_parse_flex_and_imu(payload)
		SensorLayout.DUAL_IMU_FINGERS:
			_parse_dual_imu(payload)
		_:
			pass

# Example Parser: 1 Palm IMU (6 Bytes Quaternion) + 5 Flex Sensors (5 Bytes)
func _parse_flex_and_imu(payload: PackedByteArray) -> void:
	# Guard clause: Check expected minimal payload size (e.g., 11 bytes)
	if payload.size() < 11:
		return

	# 1. Unpack Palm IMU Orientation (Fixed point 16-bit integers -> Quaternion)
	var qx := float(payload.decode_s16(0)) / 32767.0
	var qy := float(payload.decode_s16(2)) / 32767.0
	var qz := float(payload.decode_s16(4)) / 32767.0
	var qw := sqrt(max(0.0, 1.0 - (qx*qx + qy*qy + qz*qz))) # Reconstruct W
	
	var palm_rot := Quaternion(qx, qy, qz, qw).normalized()
	_current_palm_transform.basis = Basis(palm_rot)
	_current_palm_transform.origin = wrist_to_palm_offset

	# 2. Unpack Flex Sensor Bytes (0 to 255 -> Normalized 0.0 to 1.0)
	var keys = ["Thumb", "Index", "Middle", "Ring", "Pinky"]
	for i in range(5):
		_raw_curl_values[keys[i]] = float(payload[6 + i]) / 255.0

	_compute_and_emit_transforms()

# Example Parser: Multi-IMU Array
func _parse_dual_imu(payload: PackedByteArray) -> void:
	# Place parsing logic here when multi-IMU hardware is defined
	pass

# Calculates spatial fingertip targets based on palm transform and curl ratios
func _compute_and_emit_transforms() -> void:
	var fingertip_targets := {}

	for finger_name in finger_offsets.keys():
		var rest_offset: Vector3 = finger_offsets[finger_name]
		var curl_amount: float = _raw_curl_values[finger_name] # 0.0 = Extended, 1.0 = Curled
		
		# Estimate spatial tip movement: As finger curls, tip contracts towards palm origin
		var curl_vector := Vector3(0.0, -0.05 * curl_amount, 0.04 * curl_amount)
		var local_tip_pos := rest_offset + curl_vector
		
		# Map local tip position into global space via Palm Transform
		var global_tip_pos := _current_palm_transform * local_tip_pos
		fingertip_targets[finger_name] = global_tip_pos

	emit_signal("pose_data_ready", _current_palm_transform, fingertip_targets)

# Procedural fallback generator so the project runs immediately without hardware
func _generate_synthetic_pose(t: float) -> void:
	# Gentle hovering motion for the palm
	var palm_pos := Vector3(sin(t * 0.5) * 0.05, cos(t * 0.8) * 0.02, -0.1)
	var palm_rot := Quaternion.from_euler(Vector3(sin(t * 0.3) * 0.1, t * 0.2, 0.0))
	_current_palm_transform = Transform3D(Basis(palm_rot), palm_pos)

	# Sequential finger curling (wave motion)
	var keys = ["Thumb", "Index", "Middle", "Ring", "Pinky"]
	for i in range(5):
		var phase := t * 2.0 - (i * 0.4)
		_raw_curl_values[keys[i]] = (sin(phase) + 1.0) * 0.5

	_compute_and_emit_transforms()
