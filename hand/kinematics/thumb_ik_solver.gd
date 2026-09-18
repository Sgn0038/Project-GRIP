class_name ThumbIKSolver
extends Node

## Segment lengths for the thumb (in meters)
@export var l1_metacarpal: float = 0.045 # CMC -> MCP
@export var l2_proximal: float = 0.030   # MCP -> IP
@export var l3_distal: float = 0.025     # IP -> Tip

## Home rest vectors relative to palm transform
@export var cmc_rest_axis: Vector3 = Vector3(0.5, -0.5, -0.71).normalized() # Diagonal offset

func solve_thumb(cmc: Vector3, tip_target: Vector3, palm: Transform3D) -> Dictionary:
	
	var target_vec: Vector3 = tip_target - cmc
	var R: float = target_vec.length()
	
	# Clamp target reach within physical limits
	var max_reach: float = l1_metacarpal + l2_proximal + l3_distal - 0.001
	var min_reach: float = abs(l1_metacarpal - (l2_proximal + l3_distal)) + 0.005
	R = clamp(R, min_reach, max_reach)

	# Calculate global opposition plane using Palm's Abduction (X) and Flexion (Y) axes
	var palm_right: Vector3 = palm.basis.x
	var palm_up: Vector3 = palm.basis.y
	
	# Project target vector onto palm plane to find Abduction / Flexion angles
	var target_dir: Vector3 = target_vec.normalized()
	
	# Construct a Basis orienting the CMC joint toward target
	var flex_axis: Vector3 = target_dir.cross(palm_up).normalized()
	if flex_axis.length_squared() < 0.001:
		flex_axis = palm_right
		
	var cmc_basis := Basis()
	cmc_basis.z = flex_axis
	cmc_basis.x = target_dir
	cmc_basis.y = flex_axis.cross(target_dir).normalized()
	cmc_basis = cmc_basis.orthonormalized()

	# Calculate total effective distal segment (l2 + l3) using simplified coupling
	var theta_mcp: float = _solve_mcp_angle(R)
	var theta_ip: float = theta_mcp * 0.5 # Thumb IP coupling factor

	var cmc_quat := cmc_basis.get_rotation_quaternion()
	var mcp_quat := Quaternion(Vector3.RIGHT, theta_mcp)
	var ip_quat := Quaternion(Vector3.RIGHT, theta_ip)

	return {
		"cmc_rotation": cmc_quat,
		"mcp_rotation": mcp_quat,
		"ip_rotation": ip_quat
	}

## Calculates MCP flexion using Law of Cosines
func _solve_mcp_angle(R: float) -> float:
	var l_distal_combined: float = l2_proximal + l3_distal
	var cos_val: float = (pow(l1_metacarpal, 2) + pow(l_distal_combined, 2) - pow(R, 2)) / (2.0 * l1_metacarpal * l_distal_combined)
	return acos(clamp(cos_val, -1.0, 1.0))
