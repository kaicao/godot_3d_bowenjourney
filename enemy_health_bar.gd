extends Node3D

@onready var bar: MeshInstance3D = $Bar
@onready var background: MeshInstance3D = $Background

var max_health: float = 100.0
var current_health: float = 100.0

func _ready():
	update_health_bar()

func update_health(health: float, max_hp: float):
	current_health = health
	max_health = max_hp
	update_health_bar()

func update_health_bar():
	if not bar or not background:
		return
	
	var health_ratio = current_health / max_health if max_health > 0 else 0.0
	
	# Scale the bar width based on health
	var original_scale = Vector3(1.0, 0.1, 0.1)
	bar.scale = Vector3(max(0.05, health_ratio), original_scale.y, original_scale.z)
	
	# Change color based on health percentage
	var material = StandardMaterial3D.new()
	
	if health_ratio > 0.6:
		material.albedo_color = Color(0.0, 1.0, 0.0)  # Green
	elif health_ratio > 0.3:
		material.albedo_color = Color(1.0, 1.0, 0.0)  # Yellow
	else:
		material.albedo_color = Color(1.0, 0.0, 0.0)  # Red
	
	bar.set_surface_override_material(0, material)
