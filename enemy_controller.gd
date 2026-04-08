extends Node3D
class_name EnemyController

## Enemy AI Controller - Basic Chase & Attack
## Follows player and attacks when in range

@export var profile: EnemyProfile  # Profile-based configuration
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
var current_state: String = "idle"  # For animation tracking

# Navigation
var nav_agent: NavigationAgent3D = null

# Animation
var animation_player: AnimationPlayer = null
var is_moving: bool = false

# Collision
var collision_shape: CollisionShape3D = null


func _ready():
	# Setup navigation
	nav_agent = NavigationAgent3D.new()
	nav_agent.name = "NavigationAgent3D"
	add_child(nav_agent)
	nav_agent.velocity_computed.connect(_on_navigation_velocity_computed)
	
	# Get AnimationPlayer
	if has_node("AnimationPlayer"):
		animation_player = $AnimationPlayer
		print("✅ Enemy AnimationPlayer found!")
	elif has_node("Rig/AnimationPlayer"):
		animation_player = $Rig/AnimationPlayer
		print("✅ Enemy AnimationPlayer found (Rig)!")
	elif has_node("Skeleton_Warrior/AnimationPlayer"):
		animation_player = $Skeleton_Warrior/AnimationPlayer
		print("✅ Enemy AnimationPlayer found (Skeleton_Warrior)!")
	
	# Initialize from profile if available
	if profile:
		_initialize_from_profile()
	
	# Find player target
	find_player()


func _initialize_from_profile():
	if profile:
		speed = profile.move_speed
		attack_damage = profile.attack_damage
		attack_cooldown = profile.attack_cooldown
		print("📋 Loaded profile: ", profile.resource_name)


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
			is_moving = false  # Stop moving animation
			# Return to idle
			current_state = "idle"
	else:
		is_chasing = false
		is_moving = false  # Stop moving animation
		current_state = "idle"
	
	# Update movement animations
	update_movement_animation()


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
		
		# Update movement state
		is_moving = true
		current_state = "chase"
		
		print("🚶 Enemy moving: is_moving=", is_moving, " chasing=", is_chasing)
		
		# Simple movement (no physics body)
		position += direction * speed * get_process_delta_time()


func update_movement_animation():
	if is_attacking:
		# Don't play movement animations during attack
		return
	
	if is_moving:
		# Character is chasing/moving
		if animation_player:
			# Choose target animation based on profile or default
			var target_anim = "Walking_A"
			
			# Check if already playing the correct animation
			if not animation_player.is_playing() or animation_player.current_animation != target_anim:
				# Play walking animation
				if animation_player.has_animation(target_anim):
					animation_player.play(target_anim)
					print("🎬 Enemy playing: ", target_anim)
				elif animation_player.has_animation("Running_A"):
					animation_player.play("Running_A")
					print("🎬 Enemy playing: Running_A")
				else:
					print("⚠️ Enemy has no walking animation! Available: ", animation_player.get_animation_list())
	else:
		# Character is idle
		if animation_player:
			# Choose idle animation
			var target_idle = "Idle"
			
			if not animation_player.is_playing() or (animation_player.current_animation != "Idle" and animation_player.current_animation != "Idle_Combat"):
				# Play idle animation
				if animation_player.has_animation(target_idle):
					animation_player.play(target_idle)
					print("🎬 Enemy playing: Idle")
				elif animation_player.has_animation("Idle_Combat"):
					animation_player.play("Idle_Combat")
					print("🎬 Enemy playing: Idle_Combat")


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
	
	# Play attack animation from profile or default
	if animation_player:
		var attack_anim = get_random_attack_animation()
		if attack_anim and animation_player.has_animation(attack_anim):
			animation_player.play(attack_anim)
		elif animation_player.has_animation("1H_Melee_Attack_Stab"):
			animation_player.play("1H_Melee_Attack_Stab")
		elif animation_player.has_animation("2H_Melee_Attack_Chop"):
			animation_player.play("2H_Melee_Attack_Chop")
	
	# Reset attack flag after animation
	await get_tree().create_timer(0.5).timeout
	is_attacking = false
	current_state = "idle"


func get_random_attack_animation() -> String:
	if profile and not profile.attack_animations.is_empty():
		var anims = profile.attack_animations.split(",")
		if anims.size() > 0:
			return anims[randi() % anims.size()].strip_edges()
	return ""


func take_damage(amount: float):
	# Handle enemy taking damage
	print("💥 Enemy took ", amount, " damage")
	
	# Play hit reaction from profile or default
	if animation_player:
		if profile and not profile.hit_animations.is_empty():
			var hit_anims = profile.hit_animations.split(",")
			if hit_anims.size() > 0:
				var hit_anim = hit_anims[randi() % hit_anims.size()].strip_edges()
				if animation_player.has_animation(hit_anim):
					animation_player.play(hit_anim)
					return
		
		# Default hit animations
		if animation_player.has_animation("Hit_A"):
			animation_player.play("Hit_A")
		elif animation_player.has_animation("Hit_B"):
			animation_player.play("Hit_B")


func die():
	# Handle enemy death
	print("💀 Enemy defeated!")
	
	# Play death animation from profile or default
	if animation_player:
		if profile and not profile.death_animations.is_empty():
			var death_anims = profile.death_animations.split(",")
			if death_anims.size() > 0:
				var death_anim = death_anims[randi() % death_anims.size()].strip_edges()
				if animation_player.has_animation(death_anim):
					animation_player.play(death_anim)
					# Disable collision immediately
					if collision_shape:
						collision_shape.set_deferred("disabled", true)
					await get_tree().create_timer(2.0).timeout
					queue_free()
					return
		
		# Default death animations
		if animation_player.has_animation("Death_A"):
			animation_player.play("Death_A")
		elif animation_player.has_animation("Death_B"):
			animation_player.play("Death_B")
		
		# Disable collision
		if collision_shape:
			collision_shape.set_deferred("disabled", true)
		
		# Queue for deletion after animation
		await get_tree().create_timer(2.0).timeout
		queue_free()
