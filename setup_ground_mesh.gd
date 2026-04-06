@tool
extends EditorScript

func _run():
	print("=== Starting Ground Mesh Setup ===")
	
	# Load the floor tile to get its texture
	var floor_tile_path = "res://addons/kaykit_dungeon_remastered/Assets/gltf/floor_dirt_large.gltf.glb"
	
	if not ResourceLoader.exists(floor_tile_path):
		print("ERROR: Floor tile not found at: " + floor_tile_path)
		return
	
	var floor_scene = load(floor_tile_path)
	var floor_instance = floor_scene.instantiate()
	
	var floor_mesh = null
	for child in floor_instance.get_children():
		if child is MeshInstance3D:
			floor_mesh = child
			break
	
	if not floor_mesh:
		print("ERROR: No MeshInstance3D found in floor tile")
		floor_instance.queue_free()
		return
	
	var source_mesh = floor_mesh.mesh
	var material = source_mesh.surface_get_material(0)
	var texture = null
	if material and material is StandardMaterial3D:
		texture = material.albedo_texture
		print("Found texture: " + str(texture.resource_path))
	
	floor_instance.queue_free()
	
	# Create the large ground mesh (1000x1000)
	var large_mesh = PlaneMesh.new()
	large_mesh.size = Vector2(1000, 1000)
	large_mesh.subdivide_width = 250
	large_mesh.subdivide_depth = 250
	
	# Create material with the floor texture
	var large_material = StandardMaterial3D.new()
	if texture:
		large_material.albedo_texture = texture
		# Tile the texture 250x250 times across the 1000x1000 mesh
		# Each tile is 4x4 units, so 1000/4 = 250 tiles
		large_material.uv1_scale = Vector3(250, 250, 1)
		large_material.uv1_offset = Vector3(0, 0, 0)
	
	# Save resources to disk
	var mesh_save_path = "res://large_ground_mesh.tres"
	var material_save_path = "res://large_ground_material.tres"
	
	var err_mesh = ResourceSaver.save(large_mesh, mesh_save_path)
	var err_mat = ResourceSaver.save(large_material, material_save_path)
	
	print("Saved mesh to: " + mesh_save_path + " (error: " + str(err_mesh) + ")")
	print("Saved material to: " + material_save_path + " (error: " + str(err_mat) + ")")
	
	if err_mesh != 0 or err_mat != 0:
		print("ERROR: Failed to save resources")
		return
	
	# Force filesystem to refresh
	get_editor_interface().get_resource_filesystem().scan()
	
	# Now load the saved resources and apply them to GroundMesh
	var world = get_editor_interface().get_edited_scene_root()
	var ground_mesh_node = world.get_node("Terrain/TerrainVisual/GroundMesh")
	
	if not ground_mesh_node:
		print("ERROR: GroundMesh node not found")
		return
	
	# Load the saved resources
	var loaded_mesh = load(mesh_save_path)
	var loaded_material = load(material_save_path)
	
	if not loaded_mesh:
		print("ERROR: Failed to load mesh from " + mesh_save_path)
		return
	
	if not loaded_material:
		print("ERROR: Failed to load material from " + material_save_path)
		return
	
	# Apply to the node
	ground_mesh_node.mesh = loaded_mesh
	ground_mesh_node.material_override = loaded_material
	
	print("Successfully applied resources to GroundMesh node")
	print("Mesh size: " + str(loaded_mesh.size))
	print("Material UV scale: " + str(loaded_material.uv1_scale))
	
	# Save the scene
	get_editor_interface().save_scene()
	print("Scene saved successfully")
	print("=== Ground Mesh Setup Complete ===")
