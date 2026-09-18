class_name FingerIKSolver
extends Node

# Segment lengths for the target finger (in meters)
@export var l1_proximal: float = 0.045     # MCP -> PIP
@export var l2_intermediate: float = 0.025 # PIP -> DIP
@export var l3_distal: float = 0.020       # DIP -> Tip

# Solves local rotations for MCP, PIP, and DIP joints
func solve_finger(mcp: Vector3, tip_target: Vector3, palm_normal: Vector3) -> Dictionary:
	
	var target_vec: Vector3 = tip_target - mcp
	var R: float = target_vec.length()
	
	# Clamp total distance within physical reach limits
	var max_reach: float = l1_proximal + l2_intermediate + l3_distal - 0.001
	var min_reach: float = abs(l1_proximal - (l2_intermediate + l3_distal)) + 0.005
	R = clamp(R, min_reach, max_reach)
	
	# Determine Plane of Flexion using Palm Normal
	var flex_normal: Vector3 = target_vec.cross(palm_normal).normalized()
	var flex_dir: Vector3 = flex_normal.cross(target_vec).normalized()
	
	# Numerically solve PIP flexion (Theta) matching distance R
	var theta_pip: float = _solve_pip_angle(R)
	var theta_dip: float = theta_pip * 0.66
	
	# Compute interior angle at MCP using Law of Cosines
	var l_eff: float = _get_effective_distal_length(theta_pip)
	var cos_mcp: float = (pow(l1_proximal, 2) + pow(R, 2) - pow(l_eff, 2)) / (2.0 * l1_proximal * R)
	var alpha_mcp: float = acos(clamp(cos_mcp, -1.0, 1.0))
	
	# Construct Basis orientations
	# MCP Basis: Aligned toward target, rotated by interior angle alpha_mcp
	var mcp_dir: Vector3 = target_vec.normalized().rotated(flex_normal, alpha_mcp)
	var mcp_basis := Basis()
	mcp_basis.z = flex_normal
	mcp_basis.y = flex_dir
	mcp_basis.x = mcp_dir
	mcp_basis = mcp_basis.orthonormalized()
	
	# Local rotations relative to parent joints
	var mcp_quat := mcp_basis.get_rotation_quaternion()
	var pip_quat := Quaternion(Vector3.RIGHT, theta_pip)
	var dip_quat := Quaternion(Vector3.RIGHT, theta_dip)
	
	return {
		"mcp_rotation": mcp_quat,
		"pip_rotation": pip_quat,
		"dip_rotation": dip_quat
	}

# Solves Law of Cosines iteratively for PIP angle given target distance R
func _solve_pip_angle(R: float) -> float:
	var low: float = 0.0
	var high: float = PI * 0.55 # Max ~100 deg flexion
	
	for i in range(8): # Binary search convergence
		var mid: float = (low + high) * 0.5
		var l_eff: float = _get_effective_distal_length(mid)
		
		# Law of Cosines target equation test
		var max_r: float = l1_proximal + l_eff
		var cos_val: float = (pow(l1_proximal, 2) + pow(l_eff, 2) - pow(R, 2)) / (2.0 * l1_proximal * l_eff)
		
		if cos_val < -1.0 or cos_val > 1.0:
			low = mid
		else:
			high = mid
			
	return (low + high) * 0.5

# Calculates effective distance from PIP to Tip given joint flexion
func _get_effective_distal_length(theta_pip: float) -> float:
	var theta_dip: float = theta_pip * 0.66
	var gamma: float = PI - theta_dip
	return sqrt(pow(l2_intermediate, 2) + pow(l3_distal, 2) - (2.0 * l2_intermediate * l3_distal * cos(gamma)))

# Solves local rotations for MCP, PIP, and DIP joints with constraints
func solve_finger_constrained(
	mcp_global_pos: Vector3, 
	tip_target_pos: Vector3, 
	palm_normal: Vector3
) -> Dictionary:
	
	var target_vec: Vector3 = tip_target_pos - mcp_global_pos
	var R: float = target_vec.length()
	
	# Clamp target vector reach within anatomical bounds
	var max_reach: float = l1_proximal + l2_intermediate + l3_distal - 0.001
	var min_reach: float = abs(l1_proximal - (l2_intermediate + l3_distal)) + 0.005
	R = clamp(R, min_reach, max_reach)
	
	# Plane of Flexion
	var flex_normal: Vector3 = target_vec.cross(palm_normal).normalized()
	var flex_dir: Vector3 = flex_normal.cross(target_vec).normalized()
	
	# Raw Angle Calculations
	var raw_theta_pip: float = _solve_pip_angle(R)
	var raw_theta_dip: float = raw_theta_pip * 0.66
	
	# PIP: 0 deg (flat) to 100 deg (fully bent)
	var clamped_theta_pip: float = IKConstraints.clamp_hinge_angle(raw_theta_pip, 0.0, 100.0)
	# DIP: 0 deg (flat) to 80 deg (fully bent)
	var clamped_theta_dip: float = IKConstraints.clamp_hinge_angle(raw_theta_dip, 0.0, 80.0)
	
	# Re-calculate MCP interior angle based on constrained PIP/DIP reach
	var l_eff: float = _get_effective_distal_length(clamped_theta_pip)
	var cos_mcp: float = (pow(l1_proximal, 2) + pow(R, 2) - pow(l_eff, 2)) / (2.0 * l1_proximal * R)
	var alpha_mcp: float = acos(clamp(cos_mcp, -1.0, 1.0))
	
	# Construct candidate MCP Basis
	var mcp_dir: Vector3 = target_vec.normalized().rotated(flex_normal, alpha_mcp)
	var mcp_basis := Basis()
	mcp_basis.z = flex_normal
	mcp_basis.y = flex_dir
	mcp_basis.x = mcp_dir
	mcp_basis = mcp_basis.orthonormalized()
	
	var raw_mcp_quat := mcp_basis.get_rotation_quaternion()
	
	# Allow -10 to 90 deg Flexion/Extension, +/-20 deg Abduction, +/-5 deg Twist
	var clamped_mcp_quat := IKConstraints.clamp_swing_twist(
		raw_mcp_quat,
		-10.0, # Extension limit
		90.0,  # Flexion limit
		20.0,  # Abduction limit (spread)
		5.0    # Twist limit
	)
	
	return {
		"mcp_rotation": clamped_mcp_quat,
		"pip_rotation": Quaternion(Vector3.RIGHT, clamped_theta_pip),
		"dip_rotation": Quaternion(Vector3.RIGHT, clamped_theta_dip)
	}
