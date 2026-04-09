extends CharacterBody3D

@export var profile: PlayerProfile  # Profile-based configuration
@export var speed: float = 5.0
@export var mouse_sensitivity: float = 0.1

var input_direction: Vector2 = Vector2.ZERO
var camera_pitch: float = 0.0

# Jump system
var is_grounded: bool = true
var is_jumping: bool = false
var jump_velocity: float = 0.0
var jump_released: bool = false
var jump_start_time: float = 0.0
@export var jump_strength: float = 5.0

# Attack system
var is_attacking: bool = false
var attack_cooldown: float = 0.0
var attack_start_time: float = 0.0
var is_heavy_attack: bool = false
@export var light_attack_cooldown: float = 0.3
@export var heavy_attack_cooldown: float = 0.8
@export var attack_charge_time: float = 0.2

# Defend system
var is_defending: bool = false
var defend_active: bool = false
var defend_start_time: float = 0.0
@export var defend_activation_delay: float = 0.15

# Animation
var animation_player: AnimationPlayer = null
var is_moving: bool = false
var current_move_animation: String = ""

# Health system
var current_health: int = 1000
var max_health: int = 1000
var is_dead: bool = false

# ⭐ NEW: Getter for enemy AI to check attack state
func get_is_attacking() -> bool:
	return is_attacking


func _ready():
	
	add_to_group("player")
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	
	# Initialize from profile if available
	if profile:
		speed = profile.move_speed
		mouse_sensitivity = profile.mouse_sensitivity
		max_health = profile.max_health
		current_health = max_health
		jump_strength = profile.jump_strength
		print("📋 Loaded player profile: max_health=", max_health, " speed=", speed)
	else:
		# Default values
		max_health = 1000
		current_health = max_health
	
	if has_node("Knight/AnimationPlayer"):
		animation_player = $Knight/AnimationPlayer
		print("✅ AnimationPlayer found!")
	else:
		print("⚠️ No AnimationPlayer found")


func _input(event):
	# Mouse look
	if event is InputEventMouseMotion and Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
		var mouse_delta = event.relative
		rotation.y -= mouse_delta.x * mouse_sensitivity * 0.01
		camera_pitch -= mouse_delta.y * mouse_sensitivity * 0.01
		camera_pitch = clamp(camera_pitch, -deg_to_rad(90), deg_to_rad(90))
		$Camera3D.rotation.x = camera_pitch
	
	# ESC toggle
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		if Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
			Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
			print("Mouse released")
		else:
			Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
			print("Mouse captured")
	
	# JUMP: Space press
	if event is InputEventKey and event.keycode == KEY_SPACE and event.pressed:
		if is_grounded and not is_jumping and not is_attacking and not is_defending:
			start_jump()
	
	# JUMP: Space release
	if event is InputEventKey and event.keycode == KEY_SPACE and not event.pressed:
		if is_jumping:
			release_jump()
	
	# ATTACK: LMB press
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		if can_attack():
			start_attack()
	
	# ATTACK: LMB release
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		if is_attacking:
			determine_attack_type()
	
	# DEFEND: RMB press
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
		if can_defend():
			start_defend()
	
	# DEFEND: RMB release
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and not event.pressed:
		if is_defending:
			stop_defend()


func _physics_process(delta):
	input_direction = Vector2.ZERO
	
	if Input.is_key_pressed(KEY_W):
		input_direction.y -= 1
	if Input.is_key_pressed(KEY_S):
		input_direction.y += 1
	if Input.is_key_pressed(KEY_A):
		input_direction.x -= 1
	if Input.is_key_pressed(KEY_D):
		input_direction.x += 1
	
	if input_direction.length() > 0:
		input_direction = input_direction.normalized()
		var forward = -global_transform.basis.z
		var right = global_transform.basis.x
		var move_direction = (forward * -input_direction.y) + (right * input_direction.x)
		velocity.x = move_direction.x * speed
		velocity.z = move_direction.z * speed
	else:
		velocity.x = 0
		velocity.z = 0
	
	velocity.y -= 9.8 * delta
	move_and_slide()
	is_grounded = is_on_floor()
	
	if is_jumping:
		handle_jump_physics(delta)
	
	if is_defending:
		handle_defend_timer(delta)
	
	if attack_cooldown > 0:
		attack_cooldown -= delta
	
	# Lock movement during attack
	if is_attacking:
		velocity.x = 0
		velocity.z = 0
	
	# Update movement animations
	update_movement_animation()


# ==================== JUMP SYSTEM ====================

func start_jump():
	is_jumping = true
	is_grounded = false
	jump_start_time = Time.get_ticks_msec() / 1000.0
	jump_released = false
	jump_velocity = jump_strength
	velocity.y = jump_velocity
	print("🦘 Jump started!")
	
	if animation_player and animation_player.has_animation("Jump_Start"):
		animation_player.play("Jump_Start")

func handle_jump_physics(_delta):
	if jump_released and velocity.y > 0:
		velocity.y *= 0.5
		jump_released = false
	
	if is_on_floor():
		is_jumping = false
		velocity.y = 0
		print("✅ Landed!")
		
		if animation_player and animation_player.has_animation("Jump_Land"):
			animation_player.play("Jump_Land")

func release_jump():
	jump_released = true
	var current_time = Time.get_ticks_msec() / 1000.0
	var hold_duration = current_time - jump_start_time
	print("Jump held for ", hold_duration, "s")
	
	if velocity.y > 0:
		velocity.y *= 0.5


# ==================== ATTACK SYSTEM ====================

func can_attack() -> bool:
	if is_attacking: return false
	if attack_cooldown > 0: return false
	if is_defending: return false
	if is_jumping or not is_grounded: return false
	return true

func start_attack():
	is_attacking = true
	attack_start_time = Time.get_ticks_msec() / 1000.0
	attack_cooldown = 0.0
	print("⚔️ Attack started!")
	
	if animation_player and animation_player.has_animation("1H_Melee_Attack_Stab"):
		animation_player.play("1H_Melee_Attack_Stab")

func determine_attack_type():
	var current_time = Time.get_ticks_msec() / 1000.0
	var hold_duration = current_time - attack_start_time
	print("Attack held for ", hold_duration, "s")
	
	if hold_duration >= attack_charge_time:
		is_heavy_attack = true
		execute_heavy_attack()
	else:
		is_heavy_attack = false
		execute_light_attack()

func execute_light_attack():
	print("LIGHT attack!")
	perform_attack_hit()
	attack_cooldown = light_attack_cooldown
	
	if animation_player and animation_player.has_animation("1H_Melee_Attack_Slice_Horizontal"):
		animation_player.play("1H_Melee_Attack_Slice_Horizontal")
	
	await get_tree().create_timer(0.4).timeout
	is_attacking = false

func execute_heavy_attack():
	print("HEAVY attack!")
	perform_attack_hit()
	attack_cooldown = heavy_attack_cooldown
	
	if animation_player and animation_player.has_animation("2H_Melee_Attack_Chop"):
		animation_player.play("2H_Melee_Attack_Chop")
	
	await get_tree().create_timer(0.8).timeout
	is_attacking = false

func perform_attack_hit():
	var space_state = get_world_3d().direct_space_state
	var query = PhysicsRayQueryParameters3D.new()
	var from_pos = global_position + Vector3(0, 1.0, 0)
	var forward = -global_transform.basis.z
	var to_pos = from_pos + forward * 2.0
	
	query.from = from_pos
	query.to = to_pos
	query.exclude = [self]
	
	var result = space_state.intersect_ray(query)
	
	if result:
		var target = result.collider
		print("⚔️ Hit: ", target.name)
		
		# Calculate damage based on attack type
		var damage = 20 if not is_heavy_attack else 40
		
		# Call take_damage if the target has the method
		if target.has_method("take_damage"):
			target.take_damage(damage)
			print("💥 Dealt ", damage, " damage to ", target.name)
		else:
			print("⚠️ Target cannot take damage")
	else:
		print("⚔️ Missed")


# ==================== DEFEND SYSTEM ====================

func can_defend() -> bool:
	if is_defending: return false
	if is_attacking: return false
	if is_jumping or not is_grounded: return false
	return true

func start_defend():
	is_defending = true
	defend_active = false
	defend_start_time = Time.get_ticks_msec() / 1000.0
	print("🛡️ Defend started!")
	
	if animation_player and animation_player.has_animation("Block"):
		animation_player.play("Block")

func handle_defend_timer(_delta):
	var current_time = Time.get_ticks_msec() / 1000.0
	var defend_duration = current_time - defend_start_time
	
	if not defend_active and defend_duration >= defend_activation_delay:
		defend_active = true
		print("🛡️ Defend ACTIVE!")
		
		if animation_player and animation_player.has_animation("Blocking"):
			animation_player.play("Blocking")

func stop_defend():
	is_defending = false
	defend_active = false
	print("Defend stopped")
	
	if animation_player:
		animation_player.stop()


# ==================== DAMAGE SYSTEM ====================

@export var defend_damage_reduction: float = 0.9  # 90% damage reduction when defending

func take_damage(amount: float):
	if is_dead:
		return
	
	var old_health = current_health
	var final_damage = amount
	
	# ⭐ Check if defending
	var is_defending_now = is_defending and defend_active
	
	if is_defending_now:
		# Apply damage reduction
		final_damage = amount * (1.0 - defend_damage_reduction)
		current_health = max(0, current_health - final_damage)
		
		var damage_percent = (amount / float(max_health)) * 100.0
		var reduced_percent = final_damage / amount * 100.0
		
		if final_damage <= 0:
			print("[COMBAT ️] PLAYER PERFECT BLOCK! DMG=", amount, " (", damage_percent, "%) → 0 | HP=", old_health, "→", current_health, "/", max_health)
		else:
			print("[COMBAT ️] PLAYER DEFENDING! DMG=", amount, " → ", final_damage, " (-", 100.0 - reduced_percent, "%) | HP=", old_health, "→", current_health, "/", max_health)
	else:
		current_health = max(0, current_health - amount)
		var damage_percent = (amount / float(max_health)) * 100.0
		print("[COMBAT ️] PLAYER HIT! DMG=", amount, " (", damage_percent, "%) | HP=", old_health, "→", current_health, "/", max_health)
	
	# ⭐ Play hit animation if NOT defending
	if not is_defending_now:
		if animation_player and animation_player.has_animation("Hit_A"):
			animation_player.play("Hit_A")
	else:
		# Keep defending
		if animation_player and animation_player.has_animation("Blocking"):
			animation_player.play("Blocking")
	
	# Check death
	if current_health <= 0:
		print("[COMBAT 💀] PLAYER DEFEATED! Game Over.")
		is_dead = true
		die()


func die():
	print("💀 PLAYER DIED!")
	is_dead = true
	velocity = Vector3.ZERO
	
	# Play death animation if available
	if animation_player and animation_player.has_animation("Death_A"):
		animation_player.play("Death_A")
	
	# Disable collision
	var collision = get_node_or_null("CollisionShape3D")
	if collision:
		collision.set_deferred("disabled", true)
	
	# Game over logic here - FIXED: Store scene path BEFORE waiting
	var scene_path = scene_file_path  # Store path now while still valid
	print("💀 Game Over - reloading scene: ", scene_path)
	
	await get_tree().create_timer(2.0).timeout
	
	# Use stored path to reload
	if scene_path and not scene_path.is_empty():
		get_tree().change_scene_to_file(scene_path)
	else:
		# Ultimate fallback: quit to project menu
		get_tree().quit()


# ==================== MOVEMENT ANIMATIONS ====================

func update_movement_animation():
	if is_attacking or is_defending or is_jumping:
		# Don't play movement animations during combat actions
		return
	
	var current_speed = velocity.length()
	
	if current_speed > 0.1:
		# Character is moving
		is_moving = true
		# Choose animation based on speed
		var target_anim = ""
		if current_speed > speed * 0.8:
			target_anim = "Running_A"
		else:
			target_anim = "Walking_A"
		
		# Play animation if not already playing the correct one
		if animation_player:
			if not animation_player.is_playing() or animation_player.current_animation != target_anim:
				if animation_player.has_animation(target_anim):
					animation_player.play(target_anim)
					current_move_animation = target_anim
	else:
		# Character is idle
		if is_moving:
			is_moving = false
			# Play idle animation
			if animation_player and animation_player.has_animation("Idle"):
				animation_player.play("Idle")
			current_move_animation = ""
