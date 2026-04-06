@tool
extends EditorScript

func _run():
	# Create and save the large ground mesh properly
	var large_mesh = PlaneMesh.new()
	large_mesh.size = Vector2(1000, 1000)
	large_mesh.subdivide_width = 100
	large_mesh.subdivide_depth = 100
	
	# Load the floor tile to get its texture
	var floor_tile_path = "res://addons/kaykit_dungeon_remastered/Assets/gltf/floor_dirt_large.gltf.glb"
	var floor_scene = load(floor_tile_path)
	var floor_instance = floor_scene.instantiate()
	
	var floor_mesh = null
	for child in floor_instance.get_children():
		if child is MeshInstance3D:
			floor_mesh = child
			break
	
	var source_mesh = floor_mesh.mesh
	var material = source_mesh.surface_get_material(0)
	var texture = null
	if material and material is StandardMaterial3D:
		texture = material.albedo_texture
	
	floor_instance.queue_free()
	
	# Create material with texture
	var large_material = StandardMaterial3D.new()
	if texture:
		large_material.albedo_texture = texture
		large_material.uv1_scale = Vector3(250, 250, 1)
	
	# Save resources to disk
	var mesh_path = "res://large_ground_mesh.tres"
	var material_path = "res://large_ground_material.tres"
	
	var err1 = ResourceSaver.save(large_mesh, mesh_path)
	var err2 = ResourceSaver.save(large_material, material_path)
	
	print("Saved mesh: %d, material: %d" % [err1, err2])
	
	# Now update the GroundMesh node
	var world = get_editor_interface().get_edited_scene_root()
	var ground_mesh = world.get_node("Terrain/TerrainVisual/GroundMesh")
	if ground_mesh:
		ground_mesh.mesh = large_mesh
		ground_mesh.material_override = large_material
		print("GroundMesh updated successfully")
	
	# Save the scene
	var scene_path = "res://world.tscn"
	get_editor_interface().save_scene()
	print("Scene saved successfully")
