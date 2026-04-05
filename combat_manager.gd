extends Node
class_name CombatManager

# Combat configuration
@export var max_attackers: int = 3
@export var slot_radius: float = 3.0  # Distance from player (in units)
@export var slot_count: int = 6
@export var separation_distance: float = 3.0  # Minimum distance between enemies (increased from 2.0)
@export var slot_rotation_speed: float = 0.1  # Rotate slots slowly for dynamic combat

# Tracking
var enemies: Array = []
var attackers: Array = []
var slot_angles: Dictionary = {}  # Track current angle for each enemy

# Threat system (optional improvement)
var threat_levels: Dictionary = {}  # Enemy -> threat value

func _ready():
	add_to_group("combat_manager")
	print("[CombatManager] Initialized with max_attackers=", max_attackers, " slot_radius=", slot_radius)

func _process(delta):
	# Rotate all slots slowly for dynamic combat
	_rotate_slots(delta)

func _rotate_slots(delta):
	# Slowly rotate all slot positions to keep combat moving
	for enemy in enemies:
		if slot_angles.has(enemy):
			slot_angles[enemy] += slot_rotation_speed * delta
			# Keep angle normalized
			if slot_angles[enemy] > TAU:
				slot_angles[enemy] -= TAU

func register_enemy(enemy):
	if not enemies.has(enemy):
		enemies.append(enemy)
		slot_angles[enemy] = randf() * TAU  # Random starting angle
		threat_levels[enemy] = 0.0
		print("[CombatManager] Registered enemy: ", enemy.name, " total: ", enemies.size())

func unregister_enemy(enemy):
	enemies.erase(enemy)
	attackers.erase(enemy)
	slot_angles.erase(enemy)
	threat_levels.erase(enemy)
	print("[CombatManager] Unregistered enemy: ", enemy.name, " remaining: ", enemies.size())

func request_attack(enemy) -> bool:
	# Check if this enemy is already attacking
	if attackers.has(enemy):
		return true
	
	# Check if we have room for more attackers
	if attackers.size() < max_attackers:
		attackers.append(enemy)
		# Increase threat (attacked recently)
		threat_levels[enemy] = min(threat_levels.get(enemy, 0.0) + 1.0, 5.0)
		return true
	
	# No slots available
	return false

func release_attack(enemy):
	attackers.erase(enemy)

func get_slot_position(enemy, player_pos: Vector3) -> Vector3:
	if not enemies.has(enemy):
		return player_pos
	
	# Calculate angle based on enemy index + rotation
	var index = enemies.find(enemy)
	var base_angle = index * (TAU / float(slot_count))
	var rotated_angle = base_angle + slot_angles.get(enemy, 0.0)
	
	# Calculate slot position
	var offset_x = cos(rotated_angle) * slot_radius
	var offset_z = sin(rotated_angle) * slot_radius
	
	return player_pos + Vector3(offset_x, 0.0, offset_z)

func get_separation_force(enemy, enemy_pos: Vector3) -> Vector3:
	var push := Vector3.ZERO
	var push_count := 0
	
	for other_enemy in enemies:
		if other_enemy != enemy and is_instance_valid(other_enemy):
			var other_pos = other_enemy.global_position
			var dir = enemy_pos - other_pos
			var dist = dir.length()
			
			# Apply repulsion if too close
			if dist < separation_distance and dist > 0.01:
				# Stronger repulsion formula
				var repulsion_strength = (separation_distance - dist) / separation_distance
				push += dir.normalized() * repulsion_strength * 2.0  # Increased multiplier
				push_count += 1
	
	# Normalize and scale the push
	if push_count > 0:
		push = push.normalized() * push_count * 1.5  # Increased from 0.5
	
	return push

func get_threat_level(enemy) -> float:
	return threat_levels.get(enemy, 0.0)

func decrease_threat(delta):
	# Gradually decrease threat for all enemies
	for enemy in threat_levels:
		threat_levels[enemy] = max(0.0, threat_levels[enemy] - delta * 0.1)

func get_attack_priority(enemy) -> float:
	# Higher priority = more likely to attack
	# Based on: low threat (hasn't attacked recently) + close to player
	var threat = threat_levels.get(enemy, 0.0)
	var distance = enemy.global_position.distance_to(get_tree().get_first_node_in_group("player").global_position) if get_tree().get_first_node_in_group("player") else 10.0
	
	# Lower threat = higher priority, closer = higher priority
	var priority = (5.0 - threat) + (10.0 - min(distance, 10.0))
	return priority
