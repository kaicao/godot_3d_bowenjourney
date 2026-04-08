@tool
extends EditorScript

var file = "res://world.tscn"

func _run():
	scan_file("res://")
	print("Conversion finished.")

func scan_file(path):
	process_scene(file)


func process_scene(path):
	var scene = load(path)
	if scene == null:
		return

	var root = scene.instantiate()

	var changed = convert_nodes(root)

	if changed:
		var packed = PackedScene.new()
		packed.pack(root)
		ResourceSaver.save(packed, path)
		print("Fixed:", path)

func convert_nodes(node):
	var changed = false

	for child in node.get_children():
		changed = convert_nodes(child) or changed

		if child is Area3D:
			var static_body = StaticBody3D.new()

			static_body.name = child.name
			static_body.transform = child.transform

			child.replace_by(static_body)

			changed = true

	return changed
