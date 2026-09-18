class_name HapticManager
extends Node

## Signals
signal haptic_payload_ready(byte_data: PackedByteArray)

## Node References
@export_group("Dependencies")
@export var ble_manager: Node

## Config
@export_group("Communication Settings")
@export var update_frequency_hz: float = 60.0 ## Cap transmission rate to BLE bandwidth limits
@export var min_force_threshold: float = 0.05  ## Noise gate to prevent micro-actuations

## Internal State
var _time_since_last_send: float = 0.0
var _send_interval: float = 0.0
var _last_tension_state: Array[float] = [0.0, 0.0, 0.0, 0.0, 0.0]
var _last_vibration_state: Array[float] = [0.0, 0.0, 0.0, 0.0, 0.0]

func _ready() -> void:
	_send_interval = 1.0 / update_frequency_hz
	
	if ble_manager and ble_manager.has_signal("ble_connected"):
		ble_manager.connect("ble_connected", _on_ble_connected)

func _process(delta: float) -> void:
	_time_since_last_send += delta

## Primary entry point called by HandController every physics tick
func send_haptic_frame(tension_values: Array[float], vibration_values: Array[float]) -> void:
	# Clamp input arrays to 5 channels (Thumb to Pinky)
	var tension: Array[float] = _sanitize_channel_array(tension_values)
	var vibration: Array[float] = _sanitize_channel_array(vibration_values)
	
	# Rate-limit transmission to prevent clogging the BLE buffer
	if _time_since_last_send < _send_interval:
		# Store state; will sync on next available slot if significant
		_last_tension_state = tension
		_last_vibration_state = vibration
		return

	# Only send if state changed meaningfully from last frame
	if _has_state_changed(tension, vibration):
		_last_tension_state = tension
		_last_vibration_state = vibration
		_transmit_payload(tension, vibration)
		_time_since_last_send = 0.0

## Triggers a short haptic pulse on specific fingers (e.g., rigid object contact)
func trigger_impact(finger_indices: Array[int], intensity: float = 1.0, duration_ms: int = 50) -> void:
	var temp_vibe: Array[float] = [0.0, 0.0, 0.0, 0.0, 0.0]
	for idx in finger_indices:
		if idx >= 0 and idx < 5:
			temp_vibe[idx] = clamp(intensity, 0.0, 1.0)
			
	_transmit_payload(_last_tension_state, temp_vibe)
	
	# Schedule decay reset
	var timer := get_tree().create_timer(float(duration_ms) / 1000.0)
	timer.timeout.connect(func(): _transmit_payload(_last_tension_state, [0.0, 0.0, 0.0, 0.0, 0.0]))

## Packs normalized float values into a raw byte frame for BLE transmission
func _transmit_payload(tension: Array[float], vibration: Array[float]) -> void:
	var packet := PackedByteArray()
	
	# Frame Header (e.g., 0xAA 0x55 for packet synchronization)
	packet.append(0xAA)
	packet.append(0x55)
	
	# Command Byte (0x01 = Haptic Update)
	packet.append(0x01)
	
	# Encode Brake/Tension values (5 Bytes: 0-255 scale)
	for i in range(5):
		var val: int = int(round(clamp(tension[i], 0.0, 1.0) * 255.0))
		packet.append(val)
		
	# Encode Vibration Motor values (5 Bytes: 0-255 scale PWM)
	for i in range(5):
		var val: int = int(round(clamp(vibration[i], 0.0, 1.0) * 255.0))
		packet.append(val)
		
	# Checksum (Simple XOR sum for data integrity)
	var checksum: int = 0
	for byte_idx in range(2, packet.size()):
		checksum ^= packet[byte_idx]
	packet.append(checksum)

	# Emit local signal & push to BLE driver if attached
	emit_signal("haptic_payload_ready", packet)
	
	if ble_manager and ble_manager.has_method("send_bytes"):
		ble_manager.call("send_bytes", packet)

## Enforces exact 5-channel length and applies noise floor filtering
func _sanitize_channel_array(raw_values: Array[float]) -> Array[float]:
	var result: Array[float] = [0.0, 0.0, 0.0, 0.0, 0.0]
	for i in range(mini(raw_values.size(), 5)):
		var val: float = clamp(raw_values[i], 0.0, 1.0)
		result[i] = val if val >= min_force_threshold else 0.0
	return result

## Checks delta against threshold to eliminate redundant packets
func _has_state_changed(new_t: Array[float], new_v: Array[float]) -> bool:
	const EPSILON: float = 0.02
	for i in range(5):
		if abs(new_t[i] - _last_tension_state[i]) > EPSILON:
			return true
		if abs(new_v[i] - _last_vibration_state[i]) > EPSILON:
			return true
	return false

func _on_ble_connected() -> void:
	# Force clean state on initial hardware connection
	_transmit_payload([0.0, 0.0, 0.0, 0.0, 0.0], [0.0, 0.0, 0.0, 0.0, 0.0])
