extends SceneTree
## usage: godot --path <proj> --resolution 1920x1080 --script res://scripts/gallery/capture.gd -- <screen> <out.png>
const Gallery = preload("res://scripts/gallery/gallery.gd")


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var screen: String = args[0] if args.size() > 0 else "main"
	var out: String = args[1] if args.size() > 1 else "/tmp/%s.png" % screen
	var g := Gallery.new()
	g.screen = screen
	root.add_child(g)
	for i in 5:
		await process_frame
	var image := root.get_texture().get_image()
	image.save_png(out)
	print("saved ", out, " ", image.get_size())
	quit()
