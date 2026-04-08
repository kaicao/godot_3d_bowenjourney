extends CharacterBody3D
class_name EnemyAI

@export var profile: EnemyProfile
@export var patrol_points: Array[Vector3]

var current_health: int = 100
var max_health: int = 100
var is_dead: bool = false

var min_attack_duration: float = 1.5
var min_chase_duration: float = 0.5
var state_change_cooldown: float = 0.3

var consecutive_attacks: int = 0
var dodge_cooldown: float = 0.0
var aggression_level: float = 1.0
var awareness_level: float = 1.0

# Health bar
var health_bar: Node3D = null

var state_enter_time: float = 0.0
var last_state_change_time: float = 0.0
var can_change_state: bool = true

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
@onready var attack_timer_node: Timer = $AttackTimer

# Animation
var animation_player: AnimationPlayer = null
var is_moving: bool = false

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
	else:
		max_health = 100
		current_health = 100
	
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
	print("[EnemyAI 🔍] ", name, " searching for AnimationPlayer...")
	print("[EnemyAI 🔍] ", name, " children: ", get_children().map(func(c): return c.name))
	
	if has_node("AnimationPlayer"):
		animation_player = $AnimationPlayer
		print("[EnemyAI 🎬✅] ", name, " found AnimationPlayer (direct child)")
		print("[EnemyAI 🎬] ", name, " available animations: ", animation_player.get_animation_list())
	elif has_node("Rig/AnimationPlayer"):
		animation_player = $Rig/AnimationPlayer
		print("[EnemyAI 🎬✅] ", name, " found AnimationPlayer (in Rig)")
		print("[EnemyAI 🎬] ", name, " available animations: ", animation_player.get_animation_list())
	elif has_node("Skeleton_Warrior/AnimationPlayer"):
		animation_player = $Skeleton_Warrior/AnimationPlayer
		print("[EnemyAI 🎬✅] ", name, " found AnimationPlayer (in Skeleton_Warrior)")
		print("[EnemyAI 🎬] ", name, " available animations: ", animation_player.get_animation_list())
	else:
		print("[EnemyAI ❌] ", name, " NO AnimationPlayer found in any location!")
		print("[EnemyAI 🔍] ", name, " checking all children recursively...")
		for child in get_children():
			print("[EnemyAI 🔍]   - Child: ", child.name, " (", child.get_class(), ")")
			if child.get_child_count() > 0:
				for grandchild in child.get_children():
					print("[EnemyAI 🔍]     └─ Grandchild: ", grandchild.name, " (", grandchild.get_class(), ")")

# ⭐ NEW: Update movement animations with debugging
func update_movement_animation():
	if is_dead:
		return
	
	# Debug: Log state and velocity
	# print("[EnemyAI 🎬] ", name, " is_moving=", is_moving, " velocity=", velocity.length(), " state=", current_state)
	
	if is_moving:
		if animation_player:
			var target_anim = "Walking_A"
			if not animation_player.is_playing() or animation_player.current_animation != target_anim:
				if animation_player.has_animation(target_anim):
					animation_player.play(target_anim)
					print("[EnemyAI 🎬✅] ", name, " playing Walking_A (state=", current_state, ")")
				elif animation_player.has_animation("Running_A"):
					animation_player.play("Running_A")
					print("[EnemyAI 🎬✅] ", name, " playing Running_A (state=", current_state, ")")
				else:
					print("[EnemyAI ⚠️] ", name, " NO walking animation found! Available: ", animation_player.get_animation_list())
			# Debug: Check if animation is actually playing
			# if animation_player.is_playing():
			# 	print("[EnemyAI 🎬] ", name, " animation playing: ", animation_player.current_animation)
	else:
		if animation_player:
			if not animation_player.is_playing() or (animation_player.current_animation != "Idle" and animation_player.current_animation != "Idle_Combat"):
				if animation_player.has_animation("Idle"):
					animation_player.play("Idle")
					print("[EnemyAI 🎬✅] ", name, " playing Idle")
				elif animation_player.has_animation("Idle_Combat"):
					animation_player.play("Idle_Combat")
					print("[EnemyAI 🎬✅] ", name, " playing Idle_Combat")

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
			print("[EnemyAI 📊] ", name, " state: PATROL (velocity=", velocity.length(), ")")
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
			print("[EnemyAI 📊] ", name, " state: SEARCH (velocity=", velocity.length(), ")")
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
			print("[EnemyAI 📊] ", name, " state: CHASE (velocity=", velocity.length(), " is_moving=", is_moving, ")")
			# ⭐ FIX: Check if player is valid before accessing
			if player and is_instance_valid(player):
				var dir = (player.global_position - global_position)
				dir.y = 0
				if dir.length() > 0.01:
					dir = dir.normalized()
					velocity = dir * (profile.move_speed if profile else 2.2)
					rotation.y = lerp_angle(rotation.y, atan2(dir.x, dir.z), delta * 10.0)
				else:
					velocity = Vector3.ZERO
				var dist = global_position.distance_to(player.global_position)
				if dist < 3.0 and dist > 1.5:
					transition_to(State.ATTACK)
				elif dist <= 1.5:
					velocity = -(player.global_position - global_position).normalized() * (profile.move_speed if profile else 2.2) * 0.3
			else:
				# Player lost, go to search
				transition_to(State.SEARCH)
		State.ATTACK:
			print("[EnemyAI 📊] ", name, " state: ATTACK")
			velocity = Vector3.ZERO
			attack_timer += delta
			var time_in_attack = (Time.get_ticks_msec() / 1000.0) - state_enter_time
			var rt = profile.reaction_time if profile else 0.5
			if time_in_attack < (profile.min_attack_duration if profile else 1.5):
				if player and is_instance_valid(player) and global_position.distance_to(player.global_position) > 6.0:
					transition_to(State.CHASE)
				elif attack_timer >= rt:
					attack_timer = 0.0
					perform_attack()
					consecutive_attacks += 1
					aggression_level = min(aggression_level + 0.2, 3.0)
			elif player and is_instance_valid(player) and global_position.distance_to(player.global_position) > 5.0:
				transition_to(State.CHASE)
			elif attack_timer >= rt:
				attack_timer = 0.0
				perform_attack()
				consecutive_attacks += 1
		State.DODGE:
			print("[EnemyAI 📊] ", name, " state: DODGE (velocity=", velocity.length(), ")")
			if player and is_instance_valid(player):
				velocity = (global_position - player.global_position).normalized() * (profile.move_speed if profile else 2.2)
				if (Time.get_ticks_msec() / 1000.0) - state_enter_time > 0.5:
					transition_to(State.CHASE)
		State.ESCAPE:
			print("[EnemyAI 📊] ", name, " state: ESCAPE (velocity=", velocity.length(), ")")
			if player and is_instance_valid(player):
				velocity = (global_position - player.global_position).normalized() * (profile.move_speed if profile else 2.2) * 1.3
				if (Time.get_ticks_msec() / 1000.0) - state_enter_time > 3.0:
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
	if has_node("Skeleton_Warrior/AnimationPlayer"):
		var ap = $Skeleton_Warrior/AnimationPlayer
		if ap:
			var attacks = ["1H_Melee_Attack_Chop", "1H_Melee_Attack_Stab", "1H_Melee_Attack_Slice_Diagonal"]
			var chosen = attacks[randi() % attacks.size()]
			if ap.has_animation(chosen):
				ap.play(chosen)
	# ⭐ FIX: Check player is valid before calling method
	if player and is_instance_valid(player) and player.has_method("take_damage"):
		player.take_damage(profile.attack_damage if profile else 10)

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
		State.CHASE: min_dur = profile.min_chase_duration if profile else 0.5
		State.DODGE: min_dur = 0.3
		State.ESCAPE: min_dur = 2.0
	if time_in_state < min_dur:
		return
	
	current_state = new_state
	state_enter_time = current_time
	last_state_change_time = current_time
	can_change_state = false
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
	
	print("[EnemyAI 🩸] ", name, " | DMG: ", amount, " | HP: ", current_health, "/", max_health, " | ", status)
	
	_update_health_bar()
	
	if current_health <= 0:
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
	velocity = Vector3.ZERO
	
	var death_list = profile.death_animations if profile and profile.death_animations else "Death_A"
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
