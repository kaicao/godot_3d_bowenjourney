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

func _ready():
	if profile:
		max_health = profile.max_health
		current_health = profile.max_health
		min_attack_duration = profile.min_attack_duration
		min_chase_duration = profile.min_chase_duration
		state_change_cooldown = profile.state_change_cooldown
	else:
		max_health = 100
		current_health = 100
	
	for node in get_tree().get_nodes_in_group("player"):
		if node is CharacterBody3D:
			player = node
			break
	
	if not player:
		for node in get_tree().get_current_scene().get_children():
			if node is CharacterBody3D and "player" in node.name.to_lower():
				player = node
				break
	
	if vision_area:
		vision_area.body_entered.connect(_on_vision_body_entered)
		vision_area.body_exited.connect(_on_vision_body_exited)
		var cs = vision_area.get_node_or_null("CollisionShape3D")
		if cs and cs.shape is SphereShape3D:
			cs.shape.radius = profile.vision_range if profile else 10.0
	
	if attack_timer_node:
		attack_timer_node.wait_time = profile.attack_delay if profile else 0.5
	
	if player:
		call_deferred("_face_player")
	
	_create_health_bar()
	
	current_state = State.IDLE
	state_enter_time = Time.get_ticks_msec() / 1000.0
	last_state_change_time = state_enter_time

func _physics_process(delta):
	if is_dead:
		return
	
	var overlapping = vision_area.get_overlapping_bodies() if vision_area else []
	if overlapping.has(player):
		last_seen_position = player.global_position
		last_seen_time = Time.get_ticks_msec()
	
	var current_time = Time.get_ticks_msec() / 1000.0
	if not can_change_state:
		if current_time - last_state_change_time >= state_change_cooldown:
			can_change_state = true
	
	match current_state:
		State.IDLE:
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
			if player:
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
		State.ATTACK:
			velocity = Vector3.ZERO
			attack_timer += delta
			var time_in_attack = (Time.get_ticks_msec() / 1000.0) - state_enter_time
			var rt = profile.reaction_time if profile else 0.5
			if time_in_attack < (profile.min_attack_duration if profile else 1.5):
				if global_position.distance_to(player.global_position) > 6.0:
					transition_to(State.CHASE)
				elif attack_timer >= rt:
					attack_timer = 0.0
					perform_attack()
					consecutive_attacks += 1
					aggression_level = min(aggression_level + 0.2, 3.0)
			elif global_position.distance_to(player.global_position) > 5.0:
				transition_to(State.CHASE)
			elif attack_timer >= rt:
				attack_timer = 0.0
				perform_attack()
				consecutive_attacks += 1
		State.DODGE:
			if player:
				velocity = (global_position - player.global_position).normalized() * (profile.move_speed if profile else 2.2)
				if (Time.get_ticks_msec() / 1000.0) - state_enter_time > 0.5:
					transition_to(State.CHASE)
		State.ESCAPE:
			if player:
				velocity = (global_position - player.global_position).normalized() * (profile.move_speed if profile else 2.2) * 1.3
				if (Time.get_ticks_msec() / 1000.0) - state_enter_time > 3.0:
					transition_to(State.CHASE)
	
	if not is_on_floor():
		velocity.y -= gravity * delta
	else:
		velocity.y = 0
	
	move_and_slide()

func can_see_player() -> bool:
	if not player or not vision_area:
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
	if player and player.has_method("take_damage"):
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

func _on_vision_body_entered(body):
	if body == player and can_see_player():
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
	
	# Log health status with emoji
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
	
	# Play random death animation from profile
	var death_list = profile.death_animations if profile and profile.death_animations else "Death_A"
	_play_random_animation(death_list, "death")
	
	# Disable collision after animation starts
	await get_tree().create_timer(0.5).timeout
	var collision_shape = get_node_or_null("CollisionShape3D")
	if collision_shape:
		collision_shape.set_deferred("disabled", true)
	
	# Stop AI
	if attack_timer_node:
		attack_timer_node.stop()
	
	# Remove health bar
	if health_bar:
		health_bar.queue_free()
	
	print("[EnemyAI 💀] ", name, " has been defeated - collision disabled")
