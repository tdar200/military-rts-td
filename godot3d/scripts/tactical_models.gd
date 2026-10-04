extends RefCounted
## Compact military silhouettes in the same world scale as simulation tiles.

func infantry(game, root: Node3D, anti_armour: bool) -> Node3D:
	var visual := Node3D.new()
	visual.name = "UnitVisual"
	root.add_child(visual)
	for offset in [Vector3(-0.12, 0, 0.07), Vector3(0.12, 0, 0.07), Vector3(0, 0, -0.13)]:
		var soldier := Node3D.new()
		soldier.position = offset
		visual.add_child(soldier)
		var uniform = game.materials.uniform
		var steel = game.materials.steel
		# Separate legs, armoured torso, pack and helmet read as a squad at RTS scale.
		for side in [-1.0, 1.0]:
			game._box(soldier, Vector3(0.034, 0.10, 0.038), Vector3(side * 0.028, 0.065, 0), steel)
			game._box(soldier, Vector3(0.04, 0.025, 0.064), Vector3(side * 0.028, 0.025, -0.015), steel)
			game._box(soldier, Vector3(0.035, 0.09, 0.04), Vector3(side * 0.063, 0.155, -0.012), uniform)
		game._box(soldier, Vector3(0.10, 0.105, 0.065), Vector3(0, 0.157, 0), uniform)
		game._box(soldier, Vector3(0.07, 0.075, 0.025), Vector3(0, 0.155, 0.045), game.materials.canvas)
		game._cylinder(soldier, 0.035, 0.045, Vector3(0, 0.232, 0), game.materials.skin, 10)
		var helmet := SphereMesh.new()
		helmet.radius = 0.046
		helmet.height = 0.066
		helmet.radial_segments = 12
		helmet.rings = 6
		game._mesh(helmet, uniform, Vector3(0, 0.257, 0.005), soldier)
		game._box(soldier, Vector3(0.057, 0.013, 0.008), Vector3(0, 0.237, -0.036), steel)
		game._box(soldier, Vector3(0.018, 0.022, 0.17), Vector3(0.045, 0.16, -0.09), steel)
		if anti_armour:
			var launcher = game._cylinder(soldier, 0.025, 0.23, Vector3(-0.05, 0.21, -0.03), game.materials.canvas, 10)
			launcher.rotation_degrees.x = 90.0
	return visual

func building(game, root: Node3D, kind: String) -> Node3D:
	var visual := Node3D.new()
	visual.name = "Visual"
	visual.set_meta("authored_scale", Vector3.ONE)
	root.add_child(visual)
	var steel = game.materials.steel
	var wall = game.materials.industrial
	var roof = game.materials.uniform
	var paint = game.materials.marking
	game._box(visual, Vector3(0.62, 0.025, 0.58), Vector3(0, 0.012, 0), game.materials.foundation)
	match kind:
		"CommandCenter", "ResearchLab":
			game._box(visual, Vector3(0.48, 0.18, 0.40), Vector3(0, 0.12, 0), wall)
			game._box(visual, Vector3(0.51, 0.025, 0.43), Vector3(0, 0.225, 0), roof)
			game._box(visual, Vector3(0.28, 0.09, 0.23), Vector3(0.04, 0.28, 0.025), steel)
			for x in [-0.15, -0.05, 0.05, 0.15]:
				game._box(visual, Vector3(0.06, 0.045, 0.008), Vector3(x, 0.155, -0.205), game.materials.window)
			game._cylinder(visual, 0.009, 0.31, Vector3(-0.17, 0.36, 0.13), steel, 8)
			var dish = game._cylinder(visual, 0.08, 0.016, Vector3(-0.17, 0.49, 0.13), wall, 16)
			dish.rotation_degrees.z = 30.0
		"Barracks", "VehicleFactory", "Airfield":
			game._box(visual, Vector3(0.49, 0.22, 0.42), Vector3(0, 0.135, 0.025), wall)
			game._box(visual, Vector3(0.53, 0.035, 0.46), Vector3(0, 0.262, 0.025), roof)
			for x in [-0.21, -0.07, 0.07, 0.21]:
				game._box(visual, Vector3(0.012, 0.22, 0.44), Vector3(x, 0.135, 0.025), steel)
			var door_width := 0.29 if kind != "Barracks" else 0.085
			game._box(visual, Vector3(door_width, 0.16, 0.01), Vector3(0, 0.105, -0.19), steel)
			for z in [-0.08, 0.08]:
				game._box(visual, Vector3(0.11, 0.034, 0.08), Vector3(0.10, 0.296, z), wall)
			if kind == "Airfield":
				game._box(visual, Vector3(0.46, 0.01, 0.23), Vector3(0, 0.285, 0), steel)
				for x in [-0.06, 0.06]:
					game._box(visual, Vector3(0.012, 0.01, 0.15), Vector3(x, 0.294, 0), paint)
				game._box(visual, Vector3(0.12, 0.01, 0.012), Vector3(0, 0.294, 0), paint)
		"PowerPlant", "Battery":
			for x in [-0.15, 0.15]:
				game._box(visual, Vector3(0.20, 0.19, 0.37), Vector3(x, 0.12, 0), roof)
				for z in [-0.12, -0.04, 0.04, 0.12]:
					game._box(visual, Vector3(0.18, 0.02, 0.024), Vector3(x, 0.224, z), steel)
				if kind == "PowerPlant":
					game._cylinder(visual, 0.022, 0.26, Vector3(x, 0.31, 0.12), steel, 10)
		"Refinery":
			game._box(visual, Vector3(0.26, 0.18, 0.35), Vector3(-0.1, 0.12, 0), wall)
			for z in [-0.12, 0.12]:
				game._cylinder(visual, 0.072, 0.39, Vector3(0.17, 0.225, z), wall, 16)
				game._cylinder(visual, 0.08, 0.025, Vector3(0.17, 0.34, z), steel, 16)
			game._box(visual, Vector3(0.25, 0.045, 0.10), Vector3(-0.15, 0.065, -0.19), steel)
		"SupplyDepot":
			for z in [-0.13, 0.13]:
				game._box(visual, Vector3(0.46, 0.17, 0.20), Vector3(0, 0.11, z), roof)
				for x in [-0.19, -0.09, 0.01, 0.11, 0.21]:
					game._box(visual, Vector3(0.015, 0.18, 0.205), Vector3(x, 0.11, z), steel)
	# Small identification stripe, not an emissive faction-wide colour overlay.
	game._box(visual, Vector3(0.12, 0.007, 0.025), Vector3(-0.17, 0.031, -0.26), paint)
	return visual
