extends Node3D
class_name WorldManager

## World Manager - Controls the 1000x1000 Medieval Map
## Manages terrain chunks, streaming, and world initialization

const CHUNK_SIZE := 100.0  # 100x100 units per chunk
const GRID_SIZE := 10      # 10x10 grid = 1000x1000 units
const ACTIVE_RADIUS := 2   # Load chunks within this radius of player

@export var player: Node3D
@export var chunk_parent: Node3D

var active_chunks: Dictionary = {}  # chunk_key -> Node3D
var chunk_size_world: float = CHUNK_SIZE

func _ready():
	print("🌍 World Manager initialized")
	print("Map size: ", GRID_SIZE * CHUNK_SIZE, "x", GRID_SIZE * CHUNK_SIZE, " units")
	print("Chunk size: ", CHUNK_SIZE, "x", CHUNK_SIZE, " units")
	print("Total chunks: ", GRID_SIZE * GRID_SIZE)
	
	# Initialize world
	_initialize_world()

func _process(_delta):
	if player:
		_update_active_chunks()

func _initialize_world():
	"""Initialize the world on startup"""
	print("🏗️ Initializing world...")
	
	# Get references
	if not chunk_parent:
		chunk_parent = get_node_or_null("Terrain/Chunks")
		if not chunk_parent:
			print("⚠️ Chunk parent not found, creating it")
			chunk_parent = Node3D.new()
			chunk_parent.name = "Chunks"
			add_child(chunk_parent)
	
	# Load initial chunks around center (0, 0)
	var center_chunk_x = GRID_SIZE / 2
	var center_chunk_z = GRID_SIZE / 2
	
	for dx in range(-ACTIVE_RADIUS, ACTIVE_RADIUS + 1):
		for dz in range(-ACTIVE_RADIUS, ACTIVE_RADIUS + 1):
			var chunk_x = int(center_chunk_x) + dx
			var chunk_z = int(center_chunk_z) + dz
			if _is_valid_chunk(chunk_x, chunk_z):
				_load_chunk(chunk_x, chunk_z)
	
	print("✅ World initialization complete")
	print("📦 Loaded ", active_chunks.size(), " initial chunks")

func _update_active_chunks():
	"""Update which chunks should be active based on player position"""
	if not player or not chunk_parent:
		return
	
	var player_pos = player.global_position
	var player_chunk_x = int(floor((player_pos.x + 500) / CHUNK_SIZE))
	var player_chunk_z = int(floor((player_pos.z + 500) / CHUNK_SIZE))
	
	var desired_chunks: Dictionary = {}
	
	# Calculate which chunks should be active
	for dx in range(-ACTIVE_RADIUS, ACTIVE_RADIUS + 1):
		for dz in range(-ACTIVE_RADIUS, ACTIVE_RADIUS + 1):
			var chunk_x = player_chunk_x + dx
			var chunk_z = player_chunk_z + dz
			if _is_valid_chunk(chunk_x, chunk_z):
				var key = _get_chunk_key(chunk_x, chunk_z)
				desired_chunks[key] = true
				
				# Load if not already active
				if not active_chunks.has(key):
					_load_chunk(chunk_x, chunk_z)
	
	# Unload chunks that are no longer needed
	var chunks_to_unload: Array = []
	for key in active_chunks.keys():
		if not desired_chunks.has(key):
			chunks_to_unload.append(key)
	
	for key in chunks_to_unload:
		_unload_chunk(key)

func _load_chunk(chunk_x: int, chunk_z: int):
	"""Load a terrain chunk at grid coordinates"""
	var key = _get_chunk_key(chunk_x, chunk_z)
	
	if active_chunks.has(key):
		return  # Already loaded
	
	print("📦 Loading chunk (", chunk_x, ", ", chunk_z, ")")
	
	# Create chunk node
	var chunk = Node3D.new()
	chunk.name = "Chunk_%d_%d" % [chunk_x, chunk_z]
	
	# Calculate world position
	var world_x = (chunk_x * CHUNK_SIZE) - 500 + (CHUNK_SIZE / 2)
	var world_z = (chunk_z * CHUNK_SIZE) - 500 + (CHUNK_SIZE / 2)
	chunk.position = Vector3(world_x, 0, world_z)
	
	# Add to scene
	if chunk_parent:
		chunk_parent.add_child(chunk)
	
	active_chunks[key] = chunk
	print("✅ Loaded chunk: ", key)

func _unload_chunk(chunk_key: String):
	"""Unload a terrain chunk"""
	if not active_chunks.has(chunk_key):
		return
	
	print("🗑️ Unloading chunk: ", chunk_key)
	
	var chunk = active_chunks[chunk_key]
	if is_instance_valid(chunk):
		chunk.queue_free()
	
	active_chunks.erase(chunk_key)

func _is_valid_chunk(chunk_x: int, chunk_z: int) -> bool:
	"""Check if chunk coordinates are within valid range"""
	return chunk_x >= 0 and chunk_x < GRID_SIZE and \
		   chunk_z >= 0 and chunk_z < GRID_SIZE

func _get_chunk_key(chunk_x: int, chunk_z: int) -> String:
	"""Generate a unique key for a chunk"""
	return "%d_%d" % [chunk_x, chunk_z]

# Utility functions for building
func create_floor_tile(tile_type: String, position: Vector3, rotation: Vector3 = Vector3.ZERO) -> Node3D:
	"""Create a floor tile instance"""
	var tile = Node3D.new()
	tile.name = tile_type
	tile.position = position
	tile.rotation = rotation
	
	# Load the asset
	var asset_path = "res://addons/kaykit_dungeon_remastered/Assets/gltf/floor_dirt_large.gltf.glb"
	if ResourceLoader.exists(asset_path):
		var scene = load(asset_path)
		var instance = scene.instantiate()
		tile.add_child(instance)
		print("✅ Created floor tile at ", position)
	else:
		push_error("Asset not found: " + asset_path)
	
	return tile

func create_wall_segment(wall_type: String, position: Vector3, rotation: Vector3 = Vector3.ZERO) -> Node3D:
	"""Create a wall segment instance"""
	var wall = Node3D.new()
	wall.name = wall_type
	wall.position = position
	wall.rotation = rotation
	
	# Load the asset
	var asset_path = "res://addons/kaykit_dungeon_remastered/Assets/gltf/wall_stone_a.gltf"
	if ResourceLoader.exists(asset_path):
		var scene = load(asset_path)
		var instance = scene.instantiate()
		wall.add_child(instance)
		print("✅ Created wall segment at ", position)
	else:
		push_error("Asset not found: " + asset_path)
	
	return wall
