class_name PhysicsHandPID
extends RigidBody3D

# Visual target node (VisualHand or Skeleton tracking node)
@export var target_node: Node3D

@export_group("Linear PID Controls")
@export var kp_linear: float = 800.0   ## Proportional gain (responsiveness)
@export var ki_linear: float = 0.0     ## Integral gain (eliminates static offset)
@export var kd_linear: float = 60.0    ## Derivative gain (prevents overshoot/oscillation)
@export var max_linear_force: float = 1500.0

@export_group("Angular PID Controls")
@export var kp_angular: float = 120.0
@export var ki_angular: float = 0.0
@export var kd_angular: float = 15.0
@export var max_angular_torque: float = 300.0

# PID Integral Accumulators
var _integral_linear_error: Vector3 = Vector3.ZERO
var _integral_angular_error: Vector3 = Vector3.ZERO

func _ready() -> void:
	# Ensure physics body is configured for continuous dynamic forces
	can_sleep = false
	max_contacts_reported = 4
	contact_monitor = true

func _physics_process(delta: float) -> void:
	if not is_instance_valid(target_node):
		return

	_apply_linear_pid(delta)
	_apply_angular_pid(delta)

## Applies linear force to drive position
func _apply_linear_pid(delta: float) -> void:
	var current_pos: Vector3 = global_position
	var target_pos: Vector3 = target_node.global_position
	
	# Error = Target - Current
	var position_error: Vector3 = target_pos - current_pos
	
	# Accumulate integral error
	_integral_linear_error += position_error * delta
	_integral_linear_error = _integral_linear_error.clamp(
		Vector3(-10, -10, -10), Vector3(10, 10, 10)
	) # Anti-windup
	
	# Derivative = Current Velocity
	var velocity_error: Vector3 = linear_velocity
	
	# PID Formula: F = (Kp * error) + (Ki * integral) - (Kd * velocity)
	var force: Vector3 = (position_error * kp_linear) + (_integral_linear_error * ki_linear) - (velocity_error * kd_linear)
	
	# Limit maximum force to avoid physics engine explosions on deep clipping
	if force.length() > max_linear_force: force = force.normalized() * max_linear_force
	
	apply_central_force(force)

# Applies torque to drive rotation/orientation
func _apply_angular_pid(delta: float) -> void:
	var current_quat: Quaternion = global_transform.basis.get_rotation_quaternion()
	var target_quat: Quaternion = target_node.global_transform.basis.get_rotation_quaternion()
	
	# Shortest path orientation error
	if current_quat.dot(target_quat) < 0.0:
		target_quat = -target_quat
		
	var error_quat: Quaternion = target_quat * current_quat.inverse()
	
	# Convert error quaternion to rotation vector (axis * angle)
	var axis: Vector3 = Vector3(error_quat.x, error_quat.y, error_quat.z)
	var angle: float = 2.0 * acos(clamp(error_quat.w, -1.0, 1.0))
	
	var rotation_error := Vector3.ZERO
	if axis.length_squared() > 0.0001:
		rotation_error = axis.normalized() * angle
		
	# Accumulate integral error
	_integral_angular_error += rotation_error * delta
	_integral_angular_error = _integral_angular_error.clamp(Vector3(-5, -5, -5), Vector3(5, 5, 5)) # Anti-windup
	
	# Derivative = Angular Velocity
	var angular_velocity_error: Vector3 = angular_velocity
	
	# PID Formula: T = (Kp * error) + (Ki * integral) - (Kd * angular_velocity)
	var torque: Vector3 = (rotation_error * kp_angular) + (_integral_angular_error * ki_angular) - (angular_velocity_error * kd_angular)
	
	# Limit max torque
	if torque.length() > max_angular_torque:
		torque = torque.normalized() * max_angular_torque
		
	apply_torque(torque)
