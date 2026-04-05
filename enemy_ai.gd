extends CharacterBody3D
class_name EnemyAI

# IQ-based parameters
@export var iq_level: int = 50  # 0-100, higher = smarter
@export var reaction_time: float = 0.5
@export var dodge_chance: float = 0.15  # Base chance, modified by IQ
@export var escape_threshold: float = 0.3
@export var vision_range: float = 10.0
@export var vision_fov: float = 105.0  # Field of view in degrees (90-120)
@export var attack_delay: float = 0.5
@export var speed: float = 2.2  # Slightly slower than player (player ~3.0)
@export var health: int = 100
@export var patrol_points: Array[Vector3]

# State commitment timers (prevent rapid state switching)
@export var min_attack_duration: float = 1.5  # Minimum time in ATTACK state
@export var min_chase_duration: float = 0.5  # Minimum time in CHASE state
@export var state_change_cooldown: float = 0.3  # Cooldown between state changes

# Anti-clumping system (DISABLED - requires CombatManager node)
# var combat_manager: CombatManager = null
# var separation_force: Vector3 = Vector3.ZERO
# var circle_tangent: Vector3 = Vector3.ZERO
# var last_attack_request_time: float = 0.0
# var attack_request_cooldown: float = 1.0

# Combat behavior
var consecutive_attacks: int = 0
var dodge_cooldown: float = 0.0  # Prevent spam dodging
var aggression_level: float = 1.0  # Increases with consecutive attacks
var awareness_level: float = 1.0  # Higher IQ = more aware
var current_health: int = 100
var max_health: int = 100
var is_defending: bool = false

# State timing
var state_enter_time: float = 0.0  # When current state started
var last_state_change_time: float = 0.0  # Cooldown tracking
var can_change_state: bool = true  # Cooldown flag

# Physics
var gravity = ProjectSettings.get_setting("physics/3d/default_gravity")

enum State { IDLE, PATROL, SEARCH, CHASE, ATTACK, DODGE, ESCAPE }
var current_state = State.IDLE
var player: CharacterBody3D = null
var last_seen_position: Vector3
var last_seen_time: float = 0.0
var attack_timer: float = 0.0
var patrol_index: int = 0

@onready var nav_agent: NavigationAgent3D = $NavigationAgent3D
@onready var vision_area: Area3D = $VisionArea
@onready var vision_ray: RayCast3D = $VisionRay
@onready var attack_timer_node: Timer = $AttackTimer

func _ready():
	# Find player
	for node in get_tree().get_nodes_in_group("player"):
		if node is CharacterBody3D:
			player = node
			break
	
	if not player:
		for node in get_tree().get_current_scene().get_children():
			if node is CharacterBody3D and "player" in node.name.to_lower():
				player = node
				break
	
	# CombatManager disabled - using solo enemy AI
	# combat_manager = get_tree().get_first_node_in_group("combat_manager")
	
	# Setup vision area
	if vision_area:
		vision_area.body_entered.connect(_on_vision_body_entered)
		vision_area.body_exited.connect(_on_vision_body_exited)
	
	# Setup attack timer
	if attack_timer_node:
		attack_timer_node.wait_time = attack_delay
		attack_timer_node.one_shot = true
	
	# Setup collision shape for vision area (sphere, but we'll filter by angle in code)
	if vision_area:
		var collision_shape = vision_area.get_node_or_null("CollisionShape3D")
		if collision_shape:
			if collision_shape.shape == null:
				collision_shape.shape = SphereShape3D.new()
			if collision_shape.shape is SphereShape3D:
				collision_shape.shape.radius = vision_range
		else:
			var new_shape = CollisionShape3D.new()
			new_shape.name = "CollisionShape3D"
			new_shape.shape = SphereShape3D.new()
			(new_shape.shape as SphereShape3D).radius = vision_range
			vision_area.add_child(new_shape)
	
	# Calculate IQ-based modifiers
	_init_iq_modifiers()
	
	# Face the player initially (use call_deferred to ensure scene is ready)
	if player:
		call_deferred("_face_player")
	
	# Start in IDLE, will transition to CHASE if player is visible
	current_state = State.IDLE
	state_enter_time = Time.get_ticks_msec() / 1000.0
	last_state_change_time = state_enter_time
	
	var iq_description = "MINDLESS"
	if iq_level >= 80:
		iq_description = "GENIUS"
	elif iq_level >= 60:
		iq_description = "SMART"
	elif iq_level >= 40:
		iq_description = "AVERAGE"
	elif iq_level >= 20:
		iq_description = "DUMB"
	
	print("[EnemyAI] ", name, " initialized - IQ: ", iq_level, " (", iq_description, ") at ", global_position)

func _physics_process(delta):
	update_perception()
	_process_state_cooldown(delta)  # Update cooldown
	update_state_machine(delta)
	
	# Apply gravity ONLY if not on floor
	if not is_on_floor():
		velocity.y -= gravity * delta
		# Debug: print if falling
		if velocity.y < -0.1:
			print("[EnemyAI] ", name, " falling, y velocity: ", velocity.y, " is_on_floor: ", is_on_floor())
	else:
		# Keep on ground - snap to floor
		velocity.y = 0
	
	move_and_slide()

func update_perception():
	if not player:
		return
	
	# Check if player is in vision area
	if vision_area:
		var overlapping = vision_area.get_overlapping_bodies()
		if overlapping.has(player):
			last_seen_position = player.global_position
			last_seen_time = Time.get_ticks_msec()

func update_state_machine(delta):
	match current_state:
		State.IDLE:
			process_idle(delta)
		State.PATROL:
			process_patrol(delta)
		State.SEARCH:
			process_search(delta)
		State.CHASE:
			process_chase(delta)
		State.ATTACK:
			process_attack(delta)
		State.DODGE:
			process_dodge(delta)
		State.ESCAPE:
			process_escape(delta)

func process_idle(_delta):
	if can_see_player():
		print("[EnemyAI] ", name, " (IQ:", iq_level, ") spotted player! CHARGING!")
		transition_to(State.CHASE)

func process_patrol(_delta):
	if not patrol_points or patrol_points.is_empty():
		# No patrol points - just idle
		return
	
	var target = patrol_points[patrol_index]
	if global_position.distance_to(target) < 0.5:
		patrol_index = (patrol_index + 1) % patrol_points.size()
		return
	
	# Direct movement toward patrol point
	var direction = (target - global_position).normalized()
	direction.y = 0
	velocity = direction * speed
	
	if can_see_player():
		transition_to(State.CHASE)

func process_search(delta):
	var time_since_seen = (Time.get_ticks_msec() - last_seen_time) / 1000.0
	
	if time_since_seen > 5.0:
		transition_to(State.PATROL if patrol_points and not patrol_points.is_empty() else State.IDLE)
		return
	
	# Direct movement toward last known position
	var direction = (last_seen_position - global_position).normalized()
	direction.y = 0
	velocity = direction * speed
	
	if global_position.distance_to(last_seen_position) < 0.5:
		rotate_y(delta)
	
	if can_see_player():
		transition_to(State.CHASE)

func process_chase(delta):
	if not player:
		transition_to(State.SEARCH)
		return
	
	# Direct movement toward player (solo AI)
	var direction = (player.global_position - global_position)
	direction.y = 0
	
	if direction.length() > 0.01:
		direction = direction.normalized()
		velocity = direction * speed
		var target_rotation = atan2(direction.x, direction.z)
		rotation.y = lerp_angle(rotation.y, target_rotation, delta * 10.0)
	else:
		velocity = Vector3.ZERO
	
	var distance = global_position.distance_to(player.global_position)
	
	if distance < 3.0 and distance > 1.5:
		if current_state != State.ATTACK:
			transition_to(State.ATTACK)
		return
	elif distance <= 1.5:
		var back_direction = -(player.global_position - global_position).normalized()
		back_direction.y = 0
		velocity = back_direction * speed * 0.3
	
	if not can_see_player():
		var time_since_seen = (Time.get_ticks_msec() - last_seen_time) / 1000.0
		if time_since_seen > 1.5:
			transition_to(State.SEARCH)

func process_attack(delta):
	# CRITICAL: Stop moving when attacking!
	velocity = Vector3.ZERO
	attack_timer += delta
	
	var time_in_attack = (Time.get_ticks_msec() / 1000.0) - state_enter_time
	
	# Log timer at key moments only (every 0.2s, not every frame)
	var timer_log_interval = 0.2
	if attack_timer < reaction_time and int(attack_timer / timer_log_interval) > int((attack_timer - delta) / timer_log_interval):
		print("[EnemyAI ⚔️ TIMER] ", name, ": ", attack_timer, "/", reaction_time)
	
	# Must stay in ATTACK state for minimum duration
	if time_in_attack < min_attack_duration:
		# CRITICAL: Check if player is still in reasonable range
		var attack_distance = global_position.distance_to(player.global_position)
		
		# If player is TOO FAR (>6 units), break attack commitment and chase
		if attack_distance > 6.0:
			print("[EnemyAI ⚔️] ", name, " player too far (", attack_distance, "), breaking attack!")
			transition_to(State.CHASE)
			return
		
		# Continue attacking if player is in range
		if attack_timer >= reaction_time:
			print("[EnemyAI ⚔️] ", name, " ⚡ ATTACK!")
			attack_timer = 0.0
			perform_attack()
			consecutive_attacks += 1
			aggression_level = min(aggression_level + 0.2, 3.0)
			dodge_cooldown = 1.5
			return
		return
	
	# After minimum duration, can check if should continue attacking
	var distance = global_position.distance_to(player.global_position)
	
	# Only exit attack if player is FAR away
	if distance > 5.0:  # Increased from 4.0 - more patient
		print("[EnemyAI ⚔️] ", name, " too far (", distance, "), returning to CHASE")
		transition_to(State.CHASE)
		return
	
	# Check if attack timer ready
	if attack_timer >= reaction_time:
		print("[EnemyAI ⚔️] ", name, " ⚡ ATTACK TRIGGERED!")
		attack_timer = 0.0
		perform_attack()
		consecutive_attacks += 1
		aggression_level = min(aggression_level + 0.2, 3.0)
		dodge_cooldown = 1.5  # Can't dodge for 1.5s after attacking
		return
	
	# NO DODGING during attack commitment - finish the attack!
	# NO ESCAPING during attack - fight to the death!

func process_dodge(_delta):
	if not player:
		transition_to(State.CHASE)
		return
	
	var dodge_direction = (global_position - player.global_position).normalized()
	velocity = dodge_direction * speed
	move_and_slide()
	
	# Dodge for a fixed duration, then return to CHASE (not ATTACK!)
	# This gives time to reposition before attacking again
	var time_in_dodge = (Time.get_ticks_msec() / 1000.0) - state_enter_time
	if time_in_dodge > 0.5:  # Dodge for 0.5s
		# Check if still in range to attack
		var distance = global_position.distance_to(player.global_position)
		if distance < 4.0:
			transition_to(State.CHASE)  # Will transition to ATTACK when in range
		else:
			transition_to(State.CHASE)

func process_escape(_delta):
	if not player:
		transition_to(State.IDLE)
		return
	
	var escape_direction = (global_position - player.global_position).normalized()
	velocity = escape_direction * speed * 1.3  # Faster than normal speed
	
	# Escape for minimum duration, then reassess
	var time_in_escape = (Time.get_ticks_msec() / 1000.0) - state_enter_time
	if time_in_escape > 3.0:  # Escape for 3 seconds minimum
		# After escaping, check if should return to fight or continue fleeing
		var health_percent = current_health / float(max_health)
		if health_percent < 0.2:  # Still very low HP
			# 50% chance to continue escaping, 50% to fight
			if randf() < 0.5:
				print("[EnemyAI] ", name, " continuing escape (HP: ", health_percent * 100, "%)")
			else:
				print("[EnemyAI] ", name, " returning to fight (HP: ", health_percent * 100, "%)")
				transition_to(State.CHASE)
		else:
			# HP recovered or regenerated - return to fight
			transition_to(State.CHASE)
	
	move_and_slide()

func can_see_player() -> bool:
	if not player:
		return false
	
	# Check if player is in vision area (range check)
	if vision_area:
		var overlapping = vision_area.get_overlapping_bodies()
		var has_player = overlapping.has(player)
		if has_player:
			# CRITICAL: Check if player is within FOV cone (90-120 degrees)
			var to_player = (player.global_position - global_position).normalized()
			
			# FIX: Skeleton model is rotated 180°, so forward is +Z instead of -Z
			var forward = transform.basis.z  # Skeleton faces POSITIVE Z (not negative!)
			forward.y = 0
			forward = forward.normalized()
			
			var angle_to_player = rad_to_deg(acos(to_player.dot(forward)))
			var half_fov = vision_fov / 2.0
			
			# Player must be within FOV cone
			if angle_to_player > half_fov:
				return false  # Player is behind or outside FOV
			
			# Higher IQ = better awareness (can detect even briefly)
			# Lower IQ = might miss player even in range
			var awareness_check = randf() < (0.5 + awareness_level * 0.25)
			return awareness_check
	
	return false

func perform_attack():
	print("[EnemyAI] ", name, " ATTACKING!")
	# Ensure we have health set
	if max_health == 100:
		current_health = health
		max_health = health
	if has_node("Skeleton_Warrior/AnimationPlayer"):
		var anim_player = $Skeleton_Warrior/AnimationPlayer
		if anim_player:
			# Pick random attack animation
			var attacks = ["1H_Melee_Attack_Chop", "1H_Melee_Attack_Stab", "1H_Melee_Attack_Slice_Diagonal"]
			var chosen_attack = attacks[randi() % attacks.size()]
			
			if anim_player.has_animation(chosen_attack):
				anim_player.play(chosen_attack)
				print("[EnemyAI] Playing attack: ", chosen_attack)
			elif anim_player.has_animation("Walking_A"):
				# Fallback to any attack animation
				anim_player.play("Walking_A")
	
	# Deal damage to player
	if player and player.has_method("take_damage"):
		player.take_damage(10)
		print("[EnemyAI] Dealt 10 damage!")

func transition_to(new_state: State):
	if new_state == current_state:
		return  # Don't transition to same state
	
	# Check state change cooldown
	var current_time = Time.get_ticks_msec() / 1000.0
	if not can_change_state:
		if current_time - last_state_change_time < state_change_cooldown:
			return  # Still on cooldown
	
	# Check minimum state duration (don't exit state too early)
	var time_in_state = current_time - state_enter_time
	if time_in_state < get_min_state_duration(current_state):
		return  # Must stay in current state longer
	
	print("[EnemyAI STATE] ", name, " ", get_state_name(current_state), " → ", get_state_name(new_state))
	
	current_state = new_state
	state_enter_time = current_time
	last_state_change_time = current_time
	can_change_state = false
	
	# Set cooldown based on state
	match new_state:
		State.ATTACK:
			# Reset timer for fresh attack
			attack_timer = 0.0
			print("[EnemyAI ⚔️] ", name, " ATTACK state entered, timer reset")
		State.CHASE:
			if nav_agent:
				nav_agent.max_speed = speed

func _on_vision_body_entered(body):
	if body == player:
		if can_see_player():
			transition_to(State.CHASE)

func _on_vision_body_exited(body):
	if body == player:
		if current_state == State.CHASE:
			transition_to(State.SEARCH)

func _face_player():
	if player:
		var direction = (player.global_position - global_position).normalized()
		direction.y = 0
		if direction.length() > 0.01:
			# Calculate angle to face player
			var angle = atan2(direction.x, direction.z)
			rotation.y = angle
			print("[EnemyAI] ", name, " now facing player, rotation.y: ", rotation_degrees.y)

func _circle_player(delta):
	"""DISABLED - Requires CombatManager"""
	pass

func _init_iq_modifiers():
	"""Initialize combat modifiers based on IQ level (0-100)"""
	# Clamp IQ between 0-100
	iq_level = clamp(iq_level, 0, 100)
	
	# IQ affects multiple combat parameters
	var iq_factor = iq_level / 100.0  # 0.0 to 1.0
	
	# Higher IQ = faster reaction, better dodging, more awareness
	reaction_time = lerp(1.0, 0.2, iq_factor)  # 1.0s (dumb) to 0.2s (smart)
	dodge_chance = lerp(0.05, 0.6, iq_factor)  # 5% (dumb) to 60% (smart)
	awareness_level = lerp(0.5, 2.0, iq_factor)  # Detection range multiplier
	aggression_level = lerp(0.7, 1.5, iq_factor)  # Smart enemies fight better
	
	# Vision range affected by IQ (smarter = spots player from farther)
	vision_range = lerp(6.0, 15.0, iq_factor)
	
	# Vision FOV affected by IQ (smarter = wider peripheral vision)
	# IQ 0 = 90°, IQ 100 = 120°
	vision_fov = lerp(90.0, 120.0, iq_factor)

func get_state_name(state: State) -> String:
	var state_names = {
		State.IDLE: "IDLE",
		State.PATROL: "PATROL",
		State.SEARCH: "SEARCH",
		State.CHASE: "CHASE",
		State.ATTACK: "ATTACK",
		State.DODGE: "DODGE",
		State.ESCAPE: "ESCAPE"
	}
	return state_names.get(state, "UNKNOWN")

func get_min_state_duration(state: State) -> float:
	match state:
		State.ATTACK: return min_attack_duration  # Must commit to attack
		State.CHASE: return min_chase_duration  # Don't give up too quickly
		State.DODGE: return 0.3  # Quick dodge, but not instant
		State.ESCAPE: return 2.0  # Once escaping, commit to it
		_: return 0.0  # No minimum for other states

func _process_state_cooldown(_delta):
	"""Update state change cooldown"""
	if not can_change_state:
		var current_time = Time.get_ticks_msec() / 1000.0
		if current_time - last_state_change_time >= state_change_cooldown:
			can_change_state = true

func _on_velocity_computed(safe_velocity: Vector3):
	velocity = safe_velocity
