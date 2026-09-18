class_name IKConstraints
extends RefCounted

# Clamps 1-DoF hinge joints (PIP/DIP/IP) around a single local rotation axis (e.g., X-axis)
static func clamp_hinge_angle(angle_rad: float, min_deg: float, max_deg: float) -> float:
	var min_rad := deg_to_rad(min_deg)
	var max_rad := deg_to_rad(max_deg)
	return clamp(angle_rad, min_rad, max_rad)

# Clamps a 2-DoF joint (MCP/CMC) using Swing-Twist decomposition
# Restricts "Swing" within an elliptical cone (Flexion/Extension & Abduction)
# and limits "Twist" around the bone's primary axis.
static func clamp_swing_twist(
	q: Quaternion,
	flexion_min_deg: float,
	flexion_max_deg: float,
	abduction_max_deg: float,
	twist_max_deg: float
) -> Quaternion:
	
	# Extract Swing (rotation off axis) and Twist (rotation around local X)
	var twist := Quaternion(q.x, 0.0, 0.0, q.w).normalized()
	var swing := q * twist.inverse()
	
	# Convert Swing to local Euler-like offsets
	var swing_vector := Vector3(swing.x, swing.y, swing.z)
	if swing_vector.length_squared() < 0.00001:
		return q # No rotation applied
		
	# Decompose swing into Flexion (Pitch / X) and Abduction (Yaw / Y)
	var flex_angle := rad_to_deg(2.0 * atan2(swing.x, swing.w))
	var abd_angle := rad_to_deg(2.0 * atan2(swing.y, swing.w))
	
	# Clamp Flexion (Pitch)
	flex_angle = clamp(flex_angle, flexion_min_deg, flexion_max_deg)
	# Clamp Abduction (Yaw)
	abd_angle = clamp(abd_angle, -abduction_max_deg, abduction_max_deg)
	
	# Reconstruct clamped Swing
	var flex_rad := deg_to_rad(flex_angle * 0.5)
	var abd_rad := deg_to_rad(abd_angle * 0.5)
	var clamped_swing := Quaternion(sin(flex_rad), sin(abd_rad), 0.0, cos(flex_rad) * cos(abd_rad)).normalized()
	
	# Clamp Twist (Roll around bone shaft)
	var twist_angle := rad_to_deg(2.0 * atan2(twist.x, twist.w))
	twist_angle = clamp(twist_angle, -twist_max_deg, twist_max_deg)
	var twist_rad := deg_to_rad(twist_angle * 0.5)
	var clamped_twist := Quaternion(sin(twist_rad), 0.0, 0.0, cos(twist_rad))
	
	# Combine clamped Swing and Twist
	return (clamped_swing * clamped_twist).normalized()
