extends CharacterBody3D
class_name EnemyAI

@export var profile: EnemyProfile
@export var patrol_points: Array[Vector3]

var current_health: int = 500
var max_health: int = 500
var is_dead: bool = false

var min_attack_duration: float = 1.5
var min_chase_duration: float = 0.5
var state_change_cooldown: float = 0.3

var consecutive_attacks: int = 0
var dodge_cooldown: float = 0.0
var defend_cooldown: float = 0.0
var defend_duration: float = 0.0
var is_defending: bool = false
var dodge_cooldown_time: float = 2.0  # Configurable from profile
var aggression_level: float = 1.0
var awareness_level: float = 1.0

# Health bars
var health_bar: Node3D = null

var state_enter_time: float = 0.0
var last_state_change_time: float = 0.0
var can_change_state: bool = true

var gravity = ProjectSettings.get_setting("physics/3d/default_gravity")

enum State { IDLE, PATROL, SEARCH, CHASE, ATTACK, DODGE, DEFEND, ESCAPE }
var current_state = State.IDLE
var player: CharacterBody3D = null
var last_seen_position: Vector3
var last_seen_time: float = 0.0
var attack_timer: float = 0.0
var patrol_index: int = 0
var escape_target_position: Vector3 = Vector3.ZERO  # Fixed escape destination
var escape_start_position: Vector3 = Vector3.ZERO    # Where escape started (for distance tracking)
var has_escaped: bool = false                        # ⭐ NEW: Track if enemy has ever escaped (ONCE per lifetime)
var escape_target_reached_printed: bool = false      # ⭐ NEW: Prevent log spam

@onready var nav_agent: NavigationAgent3D = $NavigationAgent3D
@onready var vision_area: Area3D = $VisionArea
@onready var attack_timer_node: Timer = $AttackTimer

# Animation
var animation_player: AnimationPlayer = null
var is_moving: bool = false
var is_attacking: bool = false  # Track if attack animation is playing
var is_dodging: bool = false    # Track if dodge animation is playing
var is_dying: bool = false      # Track if death animation is playing

# ⭐ NEW: Search for player periodically
var player_search_timer: float = 0.0
var player_search_interval: float = 2.0  # Search every 2 seconds

func _ready():
	print("[EnemyAI 🟢] ", name, " _ready() started")
	
	if profile:
		max_health = profile.max_health
		current_health = profile.max_health
		min_attack_duration = profile.min_attack_duration
		min_chase_duration = profile.min_chase_duration
		state_change_cooldown = profile.state_change_cooldown
		dodge_cooldown_time = profile.dodge_cooldown_time  # Use profile value
	else:
		max_health = 100
		current_health = 100
		dodge_cooldown_time = 2.0  # Default
	
	# ⭐ FIX: Search for player, but don't rely on it being found yet
	_find_player()
	
	if vision_area:
		vision_area.body_entered.connect(_on_vision_body_entered)
		vision_area.body_exited.connect(_on_vision_body_exited)
		var cs = vision_area.get_node_or_null("CollisionShape3D")
		if cs and cs.shape is SphereShape3D:
			cs.shape.radius = profile.vision_range if profile else 10.0
	
	if attack_timer_node:
		attack_timer_node.wait_time = profile.attack_delay if profile else 0.5
	
	# ⭐ FIX: Don't call _face_player if player is null
	if player:
		call_deferred("_face_player")
		print("[EnemyAI ✅] ", name, " found player: ", player.name)
	else:
		print("[EnemyAI ⚠️] ", name, " player NOT found in _ready(), will search periodically")
	
	_create_health_bar()
	
	# ⭐ NEW: Get AnimationPlayer
	_find_animation_player()
	
	current_state = State.IDLE
	state_enter_time = Time.get_ticks_msec() / 1000.0
	last_state_change_time = state_enter_time
	dodge_cooldown = 0.0  # Start with dodge ready

# ⭐ NEW: Helper function to find player
func _find_player() -> bool:
	# Method 1: Group lookup (best)
	for node in get_tree().get_nodes_in_group("player"):
		if node is CharacterBody3D:
			player = node
			return true
	
	# Method 2: Name search (fallback)
	for node in get_tree().get_current_scene().get_children():
		if node is CharacterBody3D and "player" in node.name.to_lower():
			player = node
			return true
	
	return false

# ⭐ NEW: Helper function to find AnimationPlayer with verbose logging
func _find_animation_player():
	# Only log on first find, not every enemy
	if has_node("AnimationPlayer"):
		animation_player = $AnimationPlayer
		# print("[EnemyAI 🎬✅] ", name, " found AnimationPlayer (direct child)")
	elif has_node("Rig/AnimationPlayer"):
		animation_player = $Rig/AnimationPlayer
		# print("[EnemyAI 🎬✅] ", name, " found AnimationPlayer (in Rig)")
	elif has_node("Skeleton_Warrior/AnimationPlayer"):
		animation_player = $Skeleton_Warrior/AnimationPlayer
		# print("[EnemyAI 🎬✅] ", name, " found AnimationPlayer (in Skeleton_Warrior)")
	else:
		print("[EnemyAI ❌] ", name, " NO AnimationPlayer found!")

# ⭐ NEW: Update movement animations with debugging
var last_idle_state: State = State.IDLE  # Track last state to avoid spam

func update_movement_animation():
	if is_dead or is_dying:
		return
	
	# Don't interrupt special animations (attack, dodge, defend, death)
	if is_attacking or is_dodging or is_defending:
		return
	
	# Debug: Log state and velocity
	# print("[EnemyAI 🎬] ", name, " is_moving=", is_moving, " velocity=", velocity.length(), " state=", current_state)
	
	if is_moving:
		if animation_player:
			var target_anim = "Walking_A"
			if not animation_player.is_playing() or animation_player.current_animation != target_anim:
				if animation_player.has_animation(target_anim):
					animation_player.play(target_anim)
					print("[EnemyAI 🚶] ", name, " Walking_A (state=", current_state, ")")
				elif animation_player.has_animation("Running_A"):
					animation_player.play("Running_A")
					print("[EnemyAI 🏃] ", name, " Running_A (state=", current_state, ")")
				else:
					print("[EnemyAI ⚠️] ", name, " NO walking animation found! Available: ", animation_player.get_animation_list())
			# Debug: Check if animation is actually playing
			# if animation_player.is_playing():
			# 	print("[EnemyAI 🎬] ", name, " animation playing: ", animation_player.current_animation)
	else:
		if animation_player:
			if not animation_player.is_playing() or (animation_player.current_animation != "Idle" and animation_player.current_animation != "Idle_Combat"):
				# Only log idle when state changes to reduce spam
				if current_state != last_idle_state:
					if animation_player.has_animation("Idle"):
						animation_player.play("Idle")
						# print("[EnemyAI 😴] ", name, " Idle (state=", current_state, ")")
					elif animation_player.has_animation("Idle_Combat"):
						animation_player.play("Idle_Combat")
						# print("[EnemyAI 😴] ", name, " Idle_Combat (state=", current_state, ")")
					last_idle_state = current_state
				else:
					# Just play without logging
					if animation_player.has_animation("Idle"):
						animation_player.play("Idle")
					elif animation_player.has_animation("Idle_Combat"):
						animation_player.play("Idle_Combat")

func _physics_process(delta):
	if is_dead:
		return
	
	# ⭐ NEW: Periodically search for player if we don't have one
	if not player or not is_instance_valid(player):
		player_search_timer += delta
		if player_search_timer >= player_search_interval:
			player_search_timer = 0.0
			if _find_player():
				print("[EnemyAI 🔍] ", name, " found player via periodic search!")
	
	# Track player position if visible
	var overlapping = vision_area.get_overlapping_bodies() if vision_area else []
	if player and overlapping.has(player):
		last_seen_position = player.global_position
		last_seen_time = Time.get_ticks_msec()
	
	var current_time = Time.get_ticks_msec() / 1000.0
	if not can_change_state:
		if current_time - last_state_change_time >= state_change_cooldown:
			can_change_state = true
	
	match current_state:
		State.IDLE:
			# print("[EnemyAI 📊] ", name, " state: IDLE")
			if can_see_player():
				transition_to(State.CHASE)
		State.PATROL:
			if patrol_points and not patrol_points.is_empty():
				var target = patrol_points[patrol_index]
				if global_position.distance_to(target) < 0.5:
					patrol_index = (patrol_index + 1) % patrol_points.size()
				else:
					var dir = (target - global_position).normalized()
					dir.y = 0
					velocity = dir * (profile.move_speed if profile else 2.2)
			if can_see_player():
				transition_to(State.CHASE)
		State.SEARCH:
			var ts = (Time.get_ticks_msec() - last_seen_time) / 1000.0
			if ts > 5.0:
				transition_to(State.PATROL if patrol_points and not patrol_points.is_empty() else State.IDLE)
			else:
				var dir = (last_seen_position - global_position).normalized()
				dir.y = 0
				velocity = dir * (profile.move_speed if profile else 2.2)
				if global_position.distance_to(last_seen_position) < 0.5:
					rotation.y += delta
			if can_see_player():
				transition_to(State.CHASE)
		State.CHASE:
			# ⭐ FIX: Use NavigationAgent for pathfinding with fallback
			if player and is_instance_valid(player):
				var dist = global_position.distance_to(player.global_position)
				var has_moved = false
				
				# ⭐ NEW: Check dodge/escape EVERY frame while chasing
				if profile:
					var health_percent = current_health / float(max_health)
					
					# Update dodge cooldown
					if dodge_cooldown > 0:
						dodge_cooldown -= delta
					
					# Escape if low health and hasn't escaped yet (ONCE per lifetime)
					if health_percent < profile.escape_threshold and not has_escaped:
						print("[COMBAT 🏃] ", name, " FLEEING at ", health_percent * 100, "% health! (ONCE per lifetime)")
						transition_to(State.ESCAPE)  # Will log in transition_to
						return
					
					# ⭐ FIX: Only dodge/defend when player is actually attacking
					# Update cooldowns
					if dodge_cooldown > 0:
						dodge_cooldown -= delta
					if defend_cooldown > 0:
						defend_cooldown -= delta
					
					# Check if player is attacking and in range
					if dist <= 3.5 and dist >= 1.5:
						var player_is_attacking = false
						if player.has_method("get_is_attacking"):
							player_is_attacking = player.get_is_attacking()
						elif "is_attacking" in player:
							player_is_attacking = player.is_attacking
						
						# Only consider dodge/defend if player is attacking
						if player_is_attacking:
							# Decide between dodge and defend
							var defend_roll = randf()
							var dodge_roll = randf()
							
							# Try to defend first (if chance met and cooldown ready)
							if profile.defend_chance > 0 and defend_cooldown <= 0 and defend_roll < profile.defend_chance:
								defend_cooldown = dodge_cooldown_time * 1.5  # Longer cooldown for defend
								defend_duration = 1.0  # Defend for 1 second
								transition_to(State.DEFEND)  # Will log in transition_to
								return
							
							# Try to dodge (if chance met and cooldown ready)
							elif profile.dodge_chance > 0 and dodge_cooldown <= 0 and dodge_roll < profile.dodge_chance:
								dodge_cooldown = dodge_cooldown_time
								transition_to(State.DODGE)  # Will log in transition_to
								return
				
				# Use NavigationAgent for pathfinding
				if nav_agent:
					nav_agent.target_position = player.global_position
					
					if not nav_agent.is_navigation_finished():
						var next_position = nav_agent.get_next_path_position()
						var dir = (next_position - global_position)
						dir.y = 0
						if dir.length() > 0.01:
							dir = dir.normalized()
							velocity = dir * (profile.move_speed if profile else 2.2)
							rotation.y = lerp_angle(rotation.y, atan2(dir.x, dir.z), delta * 10.0)
							has_moved = true
				
				# Fallback to direct movement if navigation failed
				if not has_moved:
					var dir = (player.global_position - global_position)
					dir.y = 0
					if dir.length() > 0.01:
						dir = dir.normalized()
						velocity = dir * (profile.move_speed if profile else 2.2)
						rotation.y = lerp_angle(rotation.y, atan2(dir.x, dir.z), delta * 10.0)
						has_moved = true
					else:
						velocity = Vector3.ZERO
				
				# Check attack range - should attack when close enough
				# print("[EnemyAI 📏] ", name, " distance to player: ", dist)
				if dist <= 3.0:
					# print("[EnemyAI ⚔️] ", name, " CLOSE ENOUGH TO ATTACK! dist=", dist)
					transition_to(State.ATTACK)
			else:
				# Player lost, go to search
				transition_to(State.SEARCH)
		State.ATTACK:
			velocity = Vector3.ZERO
			attack_timer += delta
			var time_in_attack = (Time.get_ticks_msec() / 1000.0) - state_enter_time
			var rt = profile.reaction_time if profile else 0.5
			var min_attack_dur = profile.min_attack_duration if profile else 1.5
			
			# ⭐ FIX: Check escape even in ATTACK state (low health priority!)
			if profile:
				var health_percent = current_health / float(max_health)
				if health_percent < profile.escape_threshold and not has_escaped:
					print("[COMBAT 🏃] ", name, " FLEEING at ", health_percent * 100, "% health! (ONCE per lifetime)")
					print("[EnemyAI 🏃] ", name, " ESCAPE TRIGGERED from ATTACK! Health: ", health_percent * 100, "%")
					transition_to(State.ESCAPE)
					return
			
			# Check if player is still in range
			if not player or not is_instance_valid(player) or global_position.distance_to(player.global_position) > 6.0:
				transition_to(State.CHASE)
				return
			
			# Perform attack after minimum duration
			if time_in_attack >= min_attack_dur:
				if attack_timer >= rt:
					attack_timer = 0.0
					perform_attack()
					consecutive_attacks += 1
					aggression_level = min(aggression_level + 0.2, 3.0)
					# Stay in attack state longer to show animation
					state_enter_time = Time.get_ticks_msec() / 1000.0  # Reset timer
					min_attack_dur = 0.8  # Shorter duration for subsequent attacks
		State.DODGE:
			if player and is_instance_valid(player):
				# Dodge away from player
				var dodge_dir = (global_position - player.global_position).normalized()
				dodge_dir.y = 0
				
				# Play dodge animation if not already playing
				if not is_dodging and animation_player:
					var dodge_anims = ["Hit_A", "Hit_B"]  # Use hit animations as dodge
					for anim in dodge_anims:
						if animation_player.has_animation(anim):
							animation_player.play(anim)
							is_dodging = true
							print("[EnemyAI 🎬] ", name, " playing dodge: ", anim)
							# Wait for dodge animation
							await animation_player.animation_finished
							is_dodging = false
							print("[EnemyAI 🎬✅] ", name, " dodge animation finished")
							break
				
				# Use navigation if available
				if nav_agent and not nav_agent.is_navigation_finished():
					var dodge_target = global_position + dodge_dir * 5.0
					nav_agent.target_position = dodge_target
					var next_pos = nav_agent.get_next_path_position()
					velocity = (next_pos - global_position).normalized() * (profile.move_speed if profile else 2.2)
				else:
					velocity = dodge_dir * (profile.move_speed if profile else 2.2)
				
				if (Time.get_ticks_msec() / 1000.0) - state_enter_time > 0.5:
					transition_to(State.CHASE)
			else:
				transition_to(State.CHASE)
		State.DEFEND:
			# Defend in place - block incoming attacks
			is_defending = true
			defend_duration -= delta
			
			# Play defend animation (use idle combat as defend stance)
			if animation_player and not animation_player.is_playing():
				if animation_player.has_animation("Idle_Combat"):
					animation_player.play("Idle_Combat")
					print("[EnemyAI 🎬] ", name, " playing defend: Idle_Combat")
			
			# Defend for duration, then return to chase
			if defend_duration <= 0:
				is_defending = false
				print("[EnemyAI 🛡️✅] ", name, " defend finished")
				transition_to(State.CHASE)
		State.ESCAPE:
			# ⭐ FINAL FIX: Track distance traveled from START position
			var escape_dir = (escape_target_position - global_position)
			escape_dir.y = 0
			var dist_to_target = escape_dir.length()
			
			# Calculate distance traveled from escape start
			var dist_traveled = global_position.distance_to(escape_target_position)
			var escape_distance = escape_target_position.distance_to(escape_start_position)
			
			# Debug: Print ONLY ONCE when reaching target
			if dist_to_target <= 0.5 and not escape_target_reached_printed:
				print("[EnemyAI 🏃✅] ", name, " REACHED TARGET! Traveled: ", escape_distance, "m")
				escape_target_reached_printed = true  # ⭐ Prevent spam
			
			# Move towards target
			if dist_to_target > 0.5:
				escape_dir = escape_dir.normalized()
				
				# ⭐ Use profile escape speed multiplier
				var escape_speed = profile.move_speed * profile.escape_speed_multiplier if profile else 2.2 * 1.3
				velocity.x = escape_dir.x * escape_speed
				velocity.z = escape_dir.z * escape_speed
				
				# Rotate to face direction
				rotation.y = lerp_angle(rotation.y, atan2(escape_dir.x, escape_dir.z), delta * 10.0)
				
				# Play running animation
				if animation_player and not animation_player.is_playing():
					if animation_player.has_animation("Running_A"):
						animation_player.play("Running_A")
			else:
				# Reached target - stop
				velocity = Vector3.ZERO
			
			# ⭐ FIX: Check if should return to chase
			var time_in_escape = (Time.get_ticks_msec() / 1000.0) - state_enter_time
			
			# Return conditions (check every frame, no blocking):
			var should_return = false
			
			if dist_to_target <= 0.5 and time_in_escape > 0.5:
				# Reached target + waited 0.5s - ALWAYS return to chase
				should_return = true
				if not escape_target_reached_printed:
					print("[EnemyAI 🎯] ", name, " escape complete! Returning to CHASE.")
			elif time_in_escape > 3.0:
				# Timeout after 3 seconds - force return
				should_return = true
				if not escape_target_reached_printed:
					print("[EnemyAI ⏱️] ", name, " escape timeout! Returning to CHASE.")
			
			# Actually transition if conditions met
			if should_return and current_health > 0:
				has_escaped = true  # ⭐ Mark as escaped ONLY when successfully completing escape
				print("[EnemyAI 🎯✅] ", name, " escape COMPLETE! Has escaped flag set to TRUE. HP=", current_health, "/", max_health)
				print("[EnemyAI 🔄] ", name, " CHASING again! HP=", current_health, "/", max_health)
				transition_to(State.CHASE)
	
	if not is_on_floor():
		velocity.y -= gravity * delta
	else:
		velocity.y = 0
	
	move_and_slide()
	
	# Update is_moving based on velocity
	is_moving = velocity.length() > 0.1
	
	# Update movement animations
	update_movement_animation()

func can_see_player() -> bool:
	# ⭐ FIX: Find player if we don't have one
	if not player or not is_instance_valid(player):
		_find_player()
		if not player:
			return false
	
	if not vision_area:
		return false
	
	var overlapping = vision_area.get_overlapping_bodies()
	if not overlapping.has(player):
		return false
	
	var to_player = (player.global_position - global_position).normalized()
	var forward = transform.basis.z
	forward.y = 0
	forward = forward.normalized()
	var angle = rad_to_deg(acos(to_player.dot(forward)))
	var half_fov = (profile.vision_fov if profile else 105.0) / 2.0
	if angle > half_fov:
		return false
	return randf() < (0.5 + awareness_level * 0.25)

func perform_attack():
	print("[EnemyAI ⚔️] ", name, " PERFORMING ATTACK!")
	
	# Use the animation_player we already found
	if animation_player:
		var attacks = ["1H_Melee_Attack_Chop", "1H_Melee_Attack_Stab", "1H_Melee_Attack_Slice_Diagonal"]
		var chosen = attacks[randi() % attacks.size()]
		if animation_player.has_animation(chosen):
			animation_player.play(chosen)
			is_attacking = true  # Mark that we're attacking
			print("[EnemyAI 🎬] ", name, " playing attack: ", chosen, " (duration: ", animation_player.get_animation(chosen).length, "s)")
			
			# Wait for attack animation to finish
			await animation_player.animation_finished
			is_attacking = false
			print("[EnemyAI 🎬✅] ", name, " attack animation finished")
		else:
			# Try any attack animation
			for anim in attacks:
				if animation_player.has_animation(anim):
					animation_player.play(anim)
					is_attacking = true
					print("[EnemyAI 🎬] ", name, " playing fallback attack: ", anim)
					await animation_player.animation_finished
					is_attacking = false
					break
	else:
		print("[EnemyAI ⚠️] ", name, " NO animation_player for attack!")
	
	# Deal damage to player AFTER animation delay (so it hits when animation plays)
	await get_tree().create_timer(0.3).timeout  # Wait for animation to start
	
	if player and is_instance_valid(player):
		if player.has_method("take_damage"):
			var damage = profile.attack_damage if profile else 10
			player.take_damage(damage)
			print("[COMBAT ⚔️] ", name, " hit PLAYER for ", damage, " damage!")
		else:
			print("[EnemyAI ⚠️] ", name, " player has no take_damage method")

func transition_to(new_state: State):
	if new_state == current_state:
		return
	var current_time = Time.get_ticks_msec() / 1000.0
	if not can_change_state or current_time - last_state_change_time < state_change_cooldown:
		return
	var time_in_state = current_time - state_enter_time
	var min_dur = 0.0
	match current_state:
		State.ATTACK: min_dur = profile.min_attack_duration if profile else 1.5
		State.CHASE: 
			# ⭐ Allow immediate escape from CHASE if health critical
			if new_state == State.ESCAPE:
				min_dur = 0.0  # Can escape immediately
			else:
				min_dur = profile.min_chase_duration if profile else 0.5
		State.DODGE: min_dur = 0.3
		State.DEFEND: min_dur = 0.5
		State.ESCAPE: 
			# ⭐ Allow ESCAPE to end immediately when conditions met
			min_dur = 0.0
	if time_in_state < min_dur:
		return
	
	# ✅ Log state change ONLY when it actually happens
	var state_names = ["IDLE", "PATROL", "SEARCH", "CHASE", "ATTACK", "DODGE", "DEFEND", "ESCAPE"]
	print("[EnemyAI 🔄] ", name, " state: ", state_names[current_state], " → ", state_names[new_state])
	
	current_state = new_state
	state_enter_time = current_time
	last_state_change_time = current_time
	can_change_state = false
	
	# Set escape target when entering ESCAPE state
	if new_state == State.ESCAPE and player and is_instance_valid(player):
		# ⭐ FIX: Reset print flag and set START position
		escape_target_reached_printed = false  # Reset for this escape
		escape_start_position = global_position
		
		var escape_dir = (global_position - player.global_position).normalized()
		escape_dir.y = 0
		
		# ⭐ Use profile settings for escape distance
		var escape_distance = 15.0
		if profile:
			escape_distance = randf_range(profile.escape_distance_min, profile.escape_distance_max)
		
		escape_target_position = global_position + escape_dir * escape_distance
		escape_target_position.y = global_position.y  # Keep same Y level
		
		print("[EnemyAI 🏃START] ", name, " position=", global_position, " → target=", escape_target_position, " (", escape_distance, "u)")
		
		# Reset nav agent (not used for movement, just for show)
		if nav_agent:
			nav_agent.target_position = escape_target_position
	
	if new_state == State.ATTACK:
		attack_timer = 0.0

# ⭐ FIX: Check if body is in "player" group, not just if body == player
func _on_vision_body_entered(body):
	if body.is_in_group("player"):
		player = body  # Update player reference
		print("[EnemyAI 👁️] ", name, " vision detected player: ", body.name)
		if can_see_player():
			transition_to(State.CHASE)

func _on_vision_body_exited(body):
	if body == player and current_state == State.CHASE:
		transition_to(State.SEARCH)

func _face_player():
	if player:
		var dir = (player.global_position - global_position).normalized()
		dir.y = 0
		if dir.length() > 0.01:
			rotation.y = atan2(dir.x, dir.z)

func take_damage(amount: int):
	if is_dead:
		return
	
	var old_health = current_health
	current_health = max(0, current_health - amount)
	var health_percent = (current_health / float(max_health)) * 100.0
	
	var status = ""
	if health_percent > 80:
		status = "Healthy"
	elif health_percent > 60:
		status = "Wounded"
	elif health_percent > 40:
		status = "Injured"
	elif health_percent > 20:
		status = "Critical"
	else:
		status = "Dying"
	
	# ⭐ COMBAT LOG
	var damage_percent = (amount / float(max_health)) * 100.0
	print("[COMBAT ⚔️] ", name, " hit! DMG=", amount, " (", damage_percent, "%) | HP=", old_health, "→", current_health, "/", max_health, " (", health_percent, "%) | ", status)
	
	# ⭐ FIX: Only escape ONCE per lifetime, and only if profile allows
	if profile and profile.can_escape:
		if health_percent < profile.escape_health_threshold and not has_escaped and current_state != State.ESCAPE and current_state != State.DODGE:
			print("[COMBAT 🏃] ", name, " FLEEING at ", health_percent, "% health! (ONLY ONCE)")
			transition_to(State.ESCAPE)
			has_escaped = true  # ⭐ Never escape again!
		elif health_percent < profile.escape_health_threshold and has_escaped:
			print("[COMBAT 🚫] ", name, " already escaped! Fighting to death...")
	else:
		# Enemy type cannot escape (e.g., bosses, berserkers)
		if health_percent < 20.0:
			print("[COMBAT 💪] ", name, " too tough to flee! Fighting to death...")
	
	_update_health_bar()
	
	if current_health <= 0:
		print("[COMBAT 💀] ", name, " DEFEATED! Final HP=0/", max_health)
		die()

func _get_animation_player() -> AnimationPlayer:
	if not profile:
		return null
	
	var model = profile.model_path if profile.model_path else "Skeleton_Warrior"
	var anim_path = profile.animation_player_path if profile.animation_player_path else "AnimationPlayer"
	var full_path = model + "/" + anim_path
	
	if has_node(full_path):
		return get_node(full_path)
	return null

func _play_random_animation(anim_list_str: String, state_name: String = ""):
	var anim_player = _get_animation_player()
	print("[EnemyAI 🎬] ", name, " _play_random_animation: ", state_name, " | AP: ", anim_player != null, " | List: ", anim_list_str)
	
	if not anim_player or not anim_list_str:
		print("[EnemyAI 🎬] ", name, " FAILED: No anim player or empty list")
		return
	
	var anim_list = anim_list_str.split(",")
	if anim_list.size() > 0:
		var chosen = anim_list[randi() % anim_list.size()].strip_edges()
		print("[EnemyAI 🎬] ", name, " chosen: ", chosen, " | Has it: ", anim_player.has_animation(chosen))
		if anim_player.has_animation(chosen):
			anim_player.play(chosen)
			if state_name:
				print("[EnemyAI] ", name, " playing ", state_name, " animation: ", chosen)
		else:
			print("[EnemyAI] ", name, " animation not found: ", chosen)

func _create_health_bar():
	var health_bar_scene = load("res://enemy_health_bar.tscn")
	if health_bar_scene:
		health_bar = health_bar_scene.instantiate()
		add_child(health_bar)
		_update_health_bar()

func _update_health_bar():
	if health_bar and health_bar.has_method("update_health"):
		health_bar.update_health(current_health, max_health)

func die():
	is_dead = true
	is_dying = true
	velocity = Vector3.ZERO
	
	var death_list = profile.death_animations if profile and profile.death_animations else "Death_A"
	
	# Play death animation and wait for it to finish
	if animation_player:
		var anim_list = death_list.split(",")
		if anim_list.size() > 0:
			var chosen = anim_list[randi() % anim_list.size()].strip_edges()
			if animation_player.has_animation(chosen):
				animation_player.play(chosen)
				print("[EnemyAI 🎬] ", name, " playing death: ", chosen)
				# Wait for death animation to finish
				await animation_player.animation_finished
				print("[EnemyAI 🎬✅] ", name, " death animation finished")
	else:
		_play_random_animation(death_list, "death")
		await get_tree().create_timer(0.5).timeout
	
	var collision_shape = get_node_or_null("CollisionShape3D")
	if collision_shape:
		collision_shape.set_deferred("disabled", true)
	
	if attack_timer_node:
		attack_timer_node.stop()
	
	if health_bar:
		health_bar.queue_free()
	
	print("[EnemyAI 💀] ", name, " has been defeated - collision disabled")
