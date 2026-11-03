class_name HandController
extends Node3D

## Signals
signal grab_started(target_object: RigidBody3D)
signal grab_released(target_object: RigidBody3D)

## Node References
@export_group("Dependencies")
@export var kinematic_solver: Node
@export var haptic_manager: Node
@export var skeleton: Skeleton3D
@export var palm_area: Area3D
@export var finger_tip_areas: Array[Area3D] = []


@export_group("Grabbing Settings")
@export_flags_3d_physics var interactable_layer: int = 1
@export var finger_grab_threshold: float = 0.6 ## Joint angle percentage (0.0 to 1.0) considered "curled"

## Internal State
var _held_object: RigidBody3D = null
var _grab_joint: Generic6DOFJoint3D = null
var _target_finger_angles: Dictionary = {} ## Bone Name -> Quaternion/Basis
var _blocked_finger_angles: Dictionary = {} ## Current physical pose constraints

func _ready() -> void:
	# Connect to KinematicSolver signals
	if kinematic_solver:
		kinematic_solver.connect("pose_updated", _on_pose_updated)
	else:
		push_warning("HandController: KinematicSolver not assigned.")
		
	# Setup palm area monitoring
	if palm_area:
		palm_area.collision_mask = interactable_layer

func _physics_process(delta: float) -> void:
	_update_skeleton_pose()
	_process_grab_logic()
	_evaluate_haptics()

## Handler for KinematicSolver output
func _on_pose_updated(wrist_transform: Transform3D, joint_rotations: Dictionary) -> void:
	# Update wrist positioning
	global_transform = wrist_transform
	
	# Store target finger poses
	_target_finger_angles = joint_rotations

## Applies solved poses to visual skeleton
func _update_skeleton_pose() -> void:
	if not skeleton:
		return
		
	for bone_name in _target_finger_angles.keys():
		var bone_idx: int = skeleton.find_bone(bone_name)
		if bone_idx != -1:
			var target_rot: Quaternion = _target_finger_angles[bone_name]
			skeleton.set_bone_pose_rotation(bone_idx, target_rot)

# Evaluates whether to initiate or release a grab action
func _process_grab_logic() -> void:
	var is_curled: bool = _check_fingers_curled()
	
	if _held_object == null:
		# Check if we should grab
		if is_curled:
			var candidate: RigidBody3D = _get_grab_candidate()
			if candidate:
				_grab_object(candidate)
	else:
		# Check if we should release
		if not is_curled:
			_release_object()

# Finds the first valid interactable RigidBody3D inside the palm detection zone
func _get_grab_candidate() -> RigidBody3D:
	if not palm_area:
		return null
		
	var bodies = palm_area.get_overlapping_bodies()
	for body in bodies:
		if body is RigidBody3D:
			return body
	return null

# Creates a physical constraint joint attaching the object to the hand
func _grab_object(target: RigidBody3D) -> void:
	_held_object = target
	
	# Create dynamic joint to anchor object to hand palm
	_grab_joint = Generic6DOFJoint3D.new()
	add_child(_grab_joint)
	
	_grab_joint.global_position = palm_area.global_position
	_grab_joint.node_a = palm_area.get_path()
	_grab_joint.node_b = target.get_path()
	
	# Lock linear and angular axes for rigid grab
	for i in range(6):
		_grab_joint.set_param_x(Generic6DOFJoint3D.PARAM_LINEAR_LOWER_LIMIT, 0)
		_grab_joint.set_param_x(Generic6DOFJoint3D.PARAM_LINEAR_UPPER_LIMIT, 0)

	emit_signal("grab_started", _held_object)

# Detaches the dynamic joint and restores full object physics
func _release_object() -> void:
	if not _held_object:
		return
		
	var released_ref = _held_object
	if _grab_joint:
		_grab_joint.queue_free()
		_grab_joint = null
		
	_held_object = null
	emit_signal("grab_released", released_ref)

# Calculates discrepancy between real glove pose and visual/physical collisions
func _evaluate_haptics() -> void:
	if not haptic_manager:
		return
		
	var tension_values: Array[float] = [0.0, 0.0, 0.0, 0.0, 0.0]
	var vibration_values: Array[float] = [0.0, 0.0, 0.0, 0.0, 0.0]
	
	# Process fingertips collision depth and torque delta
	for i in range(finger_tip_areas.size()):
		var tip_area: Area3D = finger_tip_areas[i]
		if tip_area and tip_area.has_overlapping_bodies():
			# Finger is colliding; lock tension wire to prevent movement into geometry
			tension_values[i] = 1.0 
			
			# Add subtle vibration feedback on contact
			vibration_values[i] = 0.5 if _held_object else 0.2

	# Send resistance commands down to the physical glove
	haptic_manager.send_haptic_frame(tension_values, vibration_values)

# Helper to evaluate if finger flex sensors pass the threshold for grabbing
func _check_fingers_curled() -> bool:
	if _target_finger_angles.is_empty():
		return false
		
	var total_curl: float = 0.0
	var count: int = 0
	
	for bone_name in _target_finger_angles.keys():
		var rot: Quaternion = _target_finger_angles[bone_name]
		# Approximate curl using Euler angle on local X-axis (pitch)
		total_curl += abs(rot.get_euler().x)
		count += 1
		
	if count == 0:
		return false
		
	var average_curl = total_curl / count
	return average_curl >= finger_grab_threshold
