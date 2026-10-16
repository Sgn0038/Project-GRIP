class_name FlexSensorHandDriver
extends Node3D

@export_category("Skeleton Setup")
@export_node_path("Skeleton3D") var skeleton_path: NodePath
@onready var skeleton: Skeleton3D = get_node_or_null(skeleton_path) as Skeleton3D

@export_category("Sensor Calibration")
# Minimum and maximum raw sensor values for each finger [Thumb, Index, Middle, Ring, Little]
@export var sensor_mins: PackedFloat32Array = [0.0, 0.0, 0.0, 0.0, 0.0]
@export var sensor_maxs: PackedFloat32Array = [1023.0, 1023.0, 1023.0, 1023.0, 1023.0]

@export_category("Collision")
@export_range(0.0, 1.0) var tracking_smoothness: float = 0.2
@export var collision_layer_grabbables: int = 2 # Physics layer for grabbable objects

@export_category("Bone Name Mapping")
@export var bone_names: Dictionary = {
	"thumb": {"mcp": "RightThumbMetacarpal", "proximal": "RightThumbProximal", "distal": "RightThumbDistal", "tip": "RightThumbTip"},
	"index": {"proximal": "RightIndexProximal", "intermediate": "RightIndexIntermediate", "distal": "RightIndexDistal", "tip": "RightIndexTip"},
	"middle": {"proximal": "RightMiddleProximal", "intermediate": "RightMiddleIntermediate", "distal": "RightMiddleDistal", "tip": "RightMiddleTip"},
	"ring": {"proximal": "RightRingProximal", "intermediate": "RightRingIntermediate", "distal": "RightRingDistal", "tip": "RightRingTip"},
	"little": {"proximal": "RightLittleProximal", "intermediate": "RightLittleIntermediate", "distal": "RightLittleDistal", "tip": "Little_Tip"}
}

# Signal to transmit tension values back to the hardware controller
signal finger_tension_calculated(finger_tensions: PackedFloat32Array)

const FINGER_KEYS = ["thumb", "index", "middle", "ring", "little"]

# Track active collisions and current limits per finger
var _finger_collision_depths: Array[float] = [0.0, 0.0, 0.0, 0.0, 0.0]
var bone_lengths: Dictionary = {}
var _bone_areas: Dictionary = {} # Stores Area3D references mapped to finger indices

func _ready() -> void:
	_initialize_collision_detectors()
	if not skeleton:
		if skeleton_path:
			skeleton = get_node(skeleton_path) as Skeleton3D
		else:
			# Fallback: look for a Skeleton3D sibling or child
			skeleton = _find_skeleton(get_parent())
			
	if skeleton:
		_cache_bone_lengths()
	else:
		push_warning("XRHandGloveDriver: No Skeleton3D found. Please assign skeleton_path.")

func _find_skeleton(node: Node) -> Skeleton3D:
	if node is Skeleton3D:
		return node
	for child in node.get_children():
		var skel = _find_skeleton(child)
		if skel:
			return skel
	return null

func _cache_bone_lengths() -> void:
	# Measure default distances between connected joints to use in analytical IK
	for finger_name in bone_names.keys():
		bone_lengths[finger_name] = {}
		var b_dict = bone_names[finger_name]
		
		if finger_name == "thumb":
			bone_lengths[finger_name]["l1"] = _get_bone_rest_length(b_dict["mcp"], b_dict["proximal"])
			bone_lengths[finger_name]["l2"] = _get_bone_rest_length(b_dict["proximal"], b_dict["distal"])
			bone_lengths[finger_name]["l3"] = _get_bone_rest_length(b_dict["distal"], b_dict["tip"])
		else:
			bone_lengths[finger_name]["l1"] = _get_bone_rest_length(b_dict["proximal"], b_dict["intermediate"])
			bone_lengths[finger_name]["l2"] = _get_bone_rest_length(b_dict["intermediate"], b_dict["distal"])
			bone_lengths[finger_name]["l3"] = _get_bone_rest_length(b_dict["distal"], b_dict["tip"])

func _get_bone_rest_length(bone_a_name: String, bone_b_name: String) -> float:
	var idx_a = skeleton.find_bone(bone_a_name)
	var idx_b = skeleton.find_bone(bone_b_name)
	if idx_a != -1 and idx_b != -1:
		var t_a = skeleton.get_bone_global_pose(idx_a)
		var t_b = skeleton.get_bone_global_pose(idx_b)
		return t_a.origin.distance_to(t_b.origin)
	return 0.03 # Default fallback length in meters (3cm)

func _initialize_collision_detectors() -> void:
	if not skeleton:
		return
		
	# Automatically setup or link Area3D collision detectors to fingertips
	for i in range(FINGER_KEYS.size()):
		var finger_name = FINGER_KEYS[i]
		var tip_bone = bone_names[finger_name]["tip"]
		var bone_idx = skeleton.find_bone(tip_bone)
		
		if bone_idx != -1:
			# Create a BoneAttachment3D node if not already present in the scene
			var attachment = BoneAttachment3D.new()
			attachment.bone_name = tip_bone
			skeleton.add_child(attachment)
			
			var area = Area3D.new()
			area.collision_mask = 1 << (collision_layer_grabbables - 1)
			
			var collision_shape = CollisionShape3D.new()
			var sphere = SphereShape3D.new()
			sphere.radius = 0.015 # 1.5cm fingertip radius
			collision_shape.shape = sphere
			
			area.add_child(collision_shape)
			attachment.add_child(area)
			
			# Connect overlap signals
			area.body_entered.connect(_on_finger_hit.bind(i))
			area.body_exited.connect(_on_finger_exit.bind(i))
			
			_bone_areas[i] = area

func process_glove_data(raw_sensors: PackedFloat32Array) -> Dictionary:
	if not skeleton or raw_sensors.size() < 5:
		return {}
		
	var fingertip_transforms: Dictionary = {}
	var fingers = ["thumb", "index", "middle", "ring", "little"]
	
	for i in range(5):
		var finger_name = fingers[i]
		# 1. Normalize sensor value between 0.0 (open) and 1.0 (fully closed)
		var s_min = sensor_mins[i]
		var s_max = sensor_maxs[i]
		var normalized_curl = clampf((raw_sensors[i] - s_min) / (s_max - s_min), 0.0, 1.0)
		
		# 2. Solve Finger Pose via Analytical IK / Forward mapping
		var tip_transform = _pose_finger(finger_name, normalized_curl)
		fingertip_transforms[finger_name] = tip_transform
		
	return fingertip_transforms

func _pose_finger(finger_name: String, curl: float) -> Transform3D:
	var b_dict = bone_names[finger_name]
	var lengths = bone_lengths.get(finger_name, {"l1": 0.03, "l2": 0.025, "l3": 0.02})
	
	# Maximum bend angles in radians
	var max_bend = 1.35 # ~77 degrees per joint segment
	var angle_total = curl * max_bend * 3.0 # Distributed across 3 joints
	
	# Distribute curl across joints proportionally (MCP/Proximal gets less, PIP/Intermediate gets more)
	var angle_1 = angle_total * 0.25
	var angle_2 = angle_total * 0.45
	var angle_3 = angle_total * 0.30
	
	if finger_name == "thumb":
		_apply_bone_rotation(b_dict["mcp"], Vector3(0, 0, -angle_1 * 0.5))
		_apply_bone_rotation(b_dict["proximal"], Vector3(angle_1, 0, 0))
		_apply_bone_rotation(b_dict["distal"], Vector3(angle_2, 0, 0))
	else:
		_apply_bone_rotation(b_dict["proximal"], Vector3(angle_1, 0, 0))
		_apply_bone_rotation(b_dict["intermediate"], Vector3(angle_2, 0, 0))
		_apply_bone_rotation(b_dict["distal"], Vector3(angle_3, 0, 0))
		
	# Return updated tip global transform
	var tip_idx = skeleton.find_bone(b_dict["tip"])
	if tip_idx != -1:
		return skeleton.get_bone_global_pose(tip_idx)
		
	return Transform3D.IDENTITY

func _apply_bone_rotation(bone_name: String, rot_angles: Vector3) -> void:
	var bone_idx = skeleton.find_bone(bone_name)
	if bone_idx == -1:
		return
		
	var pose = skeleton.get_bone_pose(bone_idx)
	# Apply local rotation relative to rest pose
	var rot_quat = Quaternion.from_euler(rot_angles)
	pose.basis = Basis(rot_quat)
	skeleton.set_bone_pose(bone_idx, pose)

func update_hand_pose(flex_values: PackedVector3Array) -> void:
	if not skeleton or flex_values.size() < 5:
		return

	var current_tensions = PackedFloat32Array()
	current_tensions.resize(5)

	for i in range(5):
		var finger_name = FINGER_KEYS[i]
		var target_curl = flex_values[i] # X: Curl, Y: Spread, Z: Twist
		
		# Limit curl if a collision is active on this finger
		var max_allowed_curl = 1.0 - _finger_collision_depths[i]
		var effective_curl = target_curl
		effective_curl.x = min(target_curl.x, max_allowed_curl)
		
		# Calculate tension based on how much the physical collision resisted the sensor's input
		var tension = clamp((target_curl.x - effective_curl.x) * 2.0, 0.0, 1.0)
		current_tensions[i] = tension
		
		_apply_finger_pose(finger_name, effective_curl, i)

	# Emit tension values to be sent to the hardware motors
	emit_signal("finger_tension_calculated", current_tensions)

func _apply_finger_pose(finger_name: String, curl: Vector3, finger_index: int) -> void:
	var bones = bone_names[finger_name]
	var joint_weights = [0.1, 0.4, 0.3, 0.2] if bones.size() == 5 else [0.3, 0.4, 0.3]
	
	for j in range(bones.size() - 1):
		var bone_name = bones[j]
		var bone_idx = skeleton.find_bone(bone_name)
		if bone_idx == -1:
			continue
			
		var current_pose = skeleton.get_bone_pose_rotation(bone_idx)
		var bend_angle = curl.x * joint_weights[j] * (-1.5)
		var spread_angle = curl.y * 0.2 if j == 0 else 0.0
		
		var target_rotation = Quaternion(Vector3.RIGHT, bend_angle) * Quaternion(Vector3.UP, spread_angle)
		var smoothed_rotation = current_pose.slerp(target_rotation, 1.0 - tracking_smoothness)
		
		skeleton.set_bone_pose_rotation(bone_idx, smoothed_rotation)

func _on_finger_hit(body: Node3D, finger_index: int) -> void:
	if body.is_in_group("grabbable") or body is RigidBody3D:
		# Set collision depth restriction factor (higher means more blocked)
		_finger_collision_depths[finger_index] = 0.4 

func _on_finger_exit(_body: Node3D, finger_index: int) -> void:
	_finger_collision_depths[finger_index] = 0.0
