extends Node3D
class_name EnemyController

## Enemy AI Controller - Basic Chase & Attack
## Follows player and attacks when in range

@export var speed: float = 3.0
@export var attack_range: float = 2.5
@export var attack_damage: float = 10.0
@export var attack_cooldown: float = 1.0
@export var chase_distance: float = 15.0

# State tracking
var is_chasing: bool = false
var is_attacking: bool = false
var attack_timer: float = 0.0
var current_target: Node3D = null

# Navigation
var nav_agent: NavigationAgent3D = null

# Animation
var animation_player: AnimationPlayer = null

# Collision
var collision_shape: CollisionShape3D = null


func _ready():
	# Setup navigation
	nav_agent = NavigationAgent3D.new()
	nav_agent.name = "NavigationAgent3D"
	add_child(nav_agent)
	nav_agent.velocity_computed = _on_navigation_velocity_computed
	
	# Get AnimationPlayer
	if has_node("Skeleton_Warrior/AnimationPlayer"):
		animation_player = $Skeleton_Warrior/AnimationPlayer
		print("✅ Enemy AnimationPlayer found!")
	
	# Find player target
	find_player()


func _physics_process(delta):
	# Update attack cooldown
	if attack_timer > 0:
		attack_timer -= delta
	
	# Check if player is in range
	if current_target:
		var distance_to_player = global_position.distance_to(current_target.global_position)
		
		# Chase if player is within chase distance
		if distance_to_player <= chase_distance:
			is_chasing = true
			update_navigation_target(current_target.global_position)
			
			# Attack if in range
			if distance_to_player <= attack_range and can_attack():
				perform_attack()
		else:
			is_chasing = false
			# Play idle animation
			if animation_player and animation_player.has_animation("Idle"):
				animation_player.play("Idle")


func find_player():
	# Look for player node
	var player = get_tree().get_first_node_in_group("player")
	if not player:
		# Try to find by name
		player = get_node_or_null("../../Player")
	
	if player:
		current_target = player
		print("🎯 Target acquired: ", player.name)
	else:
		print("⚠️ No player found to target")


func update_navigation_target(target_position: Vector3):
	if nav_agent:
		nav_agent.target_position = target_position


func _on_navigation_velocity_computed(safe_velocity: Vector3):
	if is_chasing and current_target:
		# Move toward player
		var direction = (current_target.global_position - global_position).normalized()
		
		# Look at player
		look_at(current_target.global_position)
		
		# Apply movement
		if animation_player and animation_player.has_animation("Walk"):
			animation_player.play("Walk")
		
		# Simple movement (no physics body)
		position += direction * speed * get_process_delta_time()


func can_attack() -> bool:
	return attack_timer <= 0 and not is_attacking


func perform_attack():
	is_attacking = true
	attack_timer = attack_cooldown
	
	print("⚔️ Enemy attacking!")
	
	# Check if player is in range
	if current_target:
		var distance = global_position.distance_to(current_target.global_position)
		if distance <= attack_range:
			# Deal damage to player
			if current_target.has_method("take_damage"):
				current_target.take_damage(attack_damage)
				print("💥 Hit player for ", attack_damage, " damage!")
	
	# Play attack animation
	if animation_player:
		if animation_player.has_animation("1H_Melee_Attack_Stab"):
			animation_player.play("1H_Melee_Attack_Stab")
		elif animation_player.has_animation("2H_Melee_Attack_Chop"):
			animation_player.play("2H_Melee_Attack_Chop")
	
	# Reset attack flag after animation
	await get_tree().create_timer(0.5).timeout
	is_attacking = false


func take_damage(amount: float):
	# Handle enemy taking damage
	print("💥 Enemy took ", amount, " damage")
	
	# Play hit reaction
	if animation_player and animation_player.has_animation("Hit_React"):
		animation_player.play("Hit_React")


func die():
	# Handle enemy death
	print("💀 Enemy defeated!")
	
	if animation_player and animation_player.has_animation("Death"):
		animation_player.play("Death")
	
	# Disable collision
	if collision_shape:
		collision_shape.set_deferred("disabled", true)
	
	# Queue for deletion after animation
	await get_tree().create_timer(2.0).timeout
	queue_free()
