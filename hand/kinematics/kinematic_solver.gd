extends Node
@onready var ik_solver = FingerIKSolver.new()
@export_node_path("SensorMapper") var mapper
func _ready() -> void:
	if mapper: get_node(mapper).connect("pose_data_ready", _on_pose_data_received)
	
func _on_pose_data_received(palm_transform: Transform3D, fingertip_positions: Dictionary) -> void:
	# 1. Position the palm
	%HandVis.global_transform = palm_transform
	# 2. Feed the fingertip positions directly into your FingerIKSolver
	update_hand_pose(%HandVis/Skeleton3D, palm_transform, fingertip_positions)

func update_hand_pose(skeleton: Skeleton3D, palm_transform: Transform3D, fingertip_positions: Dictionary) -> void:
	var palm_normal = -palm_transform.basis.z # Palm facing vector
	
	for finger_name in ["Index", "Middle", "Ring", "Pinky"]:
		var mcp_bone_idx = skeleton.find_bone(finger_name + "_Proximal_R")
		var mcp_global_pos = skeleton.get_bone_global_pose(mcp_bone_idx).origin
		var target_tip_pos = fingertip_positions[finger_name]
		
		# Solve IK angles
		var pose = ik_solver.solve_finger(mcp_global_pos, target_tip_pos, palm_normal)
		
		# Apply Rotations to skeleton
		skeleton.set_bone_pose_rotation(mcp_bone_idx, pose["mcp_rotation"])
		
		var pip_bone_idx = skeleton.find_bone(finger_name + "_Intermediate")
		skeleton.set_bone_pose_rotation(pip_bone_idx, pose["pip_rotation"])
		
		var dip_bone_idx = skeleton.find_bone(finger_name + "_Distal")
		skeleton.set_bone_pose_rotation(dip_bone_idx, pose["dip_rotation"])
