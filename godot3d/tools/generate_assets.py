import bpy
import math
from pathlib import Path
from mathutils import Vector

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "assets" / "models" / "authored"
OUT.mkdir(parents=True, exist_ok=True)


def material(name, color, metallic=0.0, roughness=0.7, emission=None, strength=0.0):
    mat = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    mat.diffuse_color = (*color, 1.0)
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes.get("Principled BSDF")
    bsdf.inputs["Base Color"].default_value = (*color, 1.0)
    bsdf.inputs["Metallic"].default_value = metallic
    bsdf.inputs["Roughness"].default_value = roughness
    if emission:
        bsdf.inputs["Emission Color"].default_value = (*emission, 1.0)
        bsdf.inputs["Emission Strength"].default_value = strength
    return mat


OLIVE = material("Earth_Olive", (0.11, 0.20, 0.075), 0.55, 0.5)
OLIVE_LIGHT = material("Earth_Olive_Light", (0.21, 0.29, 0.13), 0.4, 0.58)
GUNMETAL = material("Gunmetal", (0.055, 0.075, 0.085), 0.8, 0.3)
CONCRETE = material("Warm_Concrete", (0.19, 0.18, 0.15), 0.05, 0.88)
CYAN = material("Cyan_Energy", (0.02, 0.42, 0.48), 0.2, 0.22, (0.03, 0.9, 1.0), 5.0)
AMBER = material("Amber_Light", (0.62, 0.31, 0.04), 0.15, 0.3, (1.0, 0.38, 0.03), 3.0)
ALIEN_DARK = material("Alien_Ceramic", (0.025, 0.018, 0.028), 0.35, 0.22)
CRIMSON = material("Alien_Crimson", (0.36, 0.018, 0.026), 0.68, 0.32)
CRIMSON_EDGE = material("Alien_Edge", (0.65, 0.03, 0.045), 0.55, 0.28)
BARK = material("Bark", (0.18, 0.105, 0.055), 0.0, 0.95)
LEAF = material("Leaves", (0.035, 0.13, 0.045), 0.0, 0.88)
ROCK = material("Rock", (0.105, 0.115, 0.105), 0.0, 0.95)


def reset():
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)


def finish(obj, mat, name, bevel=0.025):
    obj.name = name
    obj.data.materials.append(mat)
    if bevel > 0:
        mod = obj.modifiers.new("EdgeBevel", "BEVEL")
        mod.width = bevel
        mod.segments = 2
    return obj


def box(name, loc, size, mat, bevel=0.025, rot=(0, 0, 0)):
    bpy.ops.mesh.primitive_cube_add(location=loc, rotation=rot)
    obj = bpy.context.object
    obj.scale = Vector(size) * 0.5
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    return finish(obj, mat, name, bevel)


def cyl(name, loc, radius, depth, mat, vertices=12, rot=(0, 0, 0), bevel=0.018):
    bpy.ops.mesh.primitive_cylinder_add(vertices=vertices, radius=radius, depth=depth, location=loc, rotation=rot)
    return finish(bpy.context.object, mat, name, bevel)


def cone(name, loc, r1, r2, depth, mat, vertices=10, rot=(0, 0, 0)):
    bpy.ops.mesh.primitive_cone_add(vertices=vertices, radius1=r1, radius2=r2, depth=depth, location=loc, rotation=rot)
    return finish(bpy.context.object, mat, name, 0.018)


def ico(name, loc, scale, mat, subdivisions=2):
    bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=subdivisions, radius=1.0, location=loc)
    obj = bpy.context.object
    obj.scale = scale
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    return finish(obj, mat, name, 0.012)


def beam(name, a, b, radius, mat, vertices=8):
    a, b = Vector(a), Vector(b)
    direction = b - a
    obj = cyl(name, (a + b) * 0.5, radius, direction.length, mat, vertices, bevel=0.01)
    obj.rotation_mode = "QUATERNION"
    obj.rotation_quaternion = Vector((0, 0, 1)).rotation_difference(direction.normalized())
    return obj


def export(name):
    for obj in bpy.context.scene.objects:
        obj.select_set(True)
    bpy.ops.export_scene.gltf(
        filepath=str(OUT / f"{name}.glb"),
        export_format="GLB",
        use_selection=False,
        export_apply=True,
    )


def human_hq():
    box("Foundation", (0, 0, 0.07), (2.2, 1.7, 0.14), CONCRETE, 0.04)
    box("MainHull", (0, 0, 0.48), (1.62, 1.22, 0.78), OLIVE, 0.09)
    box("UpperDeck", (0, 0, 0.96), (1.12, 0.82, 0.24), GUNMETAL, 0.055)
    box("FrontRamp", (0, -0.92, 0.21), (0.8, 0.7, 0.16), CONCRETE, 0.025, (math.radians(-12), 0, 0))
    for x in (-0.58, 0.58):
        box("CyanWindow", (x, -0.616, 0.55), (0.25, 0.025, 0.18), CYAN, 0.008)
        cyl("Antenna", (x, 0.12, 1.38), 0.025, 0.72, GUNMETAL, 8)
    cyl("RadarMast", (0, 0, 1.38), 0.055, 0.68, GUNMETAL, 10)
    cyl("Beacon", (0, 0, 1.75), 0.11, 0.06, CYAN, 12)


def human_industry():
    box("Foundation", (0, 0, 0.06), (1.85, 1.55, 0.12), CONCRETE, 0.035)
    box("Plant", (-0.18, 0, 0.47), (1.18, 1.1, 0.76), OLIVE, 0.07)
    box("ServiceWing", (0.62, 0.15, 0.31), (0.48, 0.75, 0.48), GUNMETAL, 0.04)
    for x in (-0.42, 0.08):
        cyl("Stack", (x, 0.18, 1.15), 0.15, 0.7, GUNMETAL, 12)
        cyl("StackCap", (x, 0.18, 1.52), 0.19, 0.07, AMBER, 12)
    for x in (-0.55, 0, 0.55):
        box("Vent", (x, -0.56, 0.58), (0.26, 0.035, 0.14), CYAN, 0.008)


def human_barracks():
    box("Foundation", (0, 0, 0.06), (1.8, 1.45, 0.12), CONCRETE, 0.035)
    box("BarracksHull", (0, 0, 0.43), (1.45, 1.1, 0.68), OLIVE_LIGHT, 0.065)
    box("RoofArmor", (0, 0, 0.82), (1.22, 0.86, 0.14), GUNMETAL, 0.035)
    box("Door", (0, -0.56, 0.35), (0.44, 0.035, 0.46), GUNMETAL, 0.01)
    box("DoorLight", (0, -0.582, 0.66), (0.26, 0.025, 0.055), CYAN, 0.006)
    for x in (-0.55, 0.55):
        box("Cargo", (x, 0.55, 0.22), (0.3, 0.34, 0.32), CONCRETE, 0.025)


def human_tank():
    box("LeftTrack", (-0.29, 0, 0.16), (0.18, 0.9, 0.22), GUNMETAL, 0.045)
    box("RightTrack", (0.29, 0, 0.16), (0.18, 0.9, 0.22), GUNMETAL, 0.045)
    box("Chassis", (0, 0, 0.28), (0.55, 0.78, 0.24), OLIVE, 0.065)
    cyl("Turret", (0, -0.04, 0.49), 0.22, 0.18, OLIVE_LIGHT, 12)
    beam("MainGun", (0, -0.14, 0.52), (0, -0.72, 0.54), 0.045, GUNMETAL, 10)
    box("CyanOptic", (0.13, -0.23, 0.58), (0.07, 0.05, 0.07), CYAN, 0.008)


def human_infantry():
    cyl("Body", (0, 0, 0.31), 0.105, 0.36, OLIVE, 10)
    ico("Helmet", (0, 0, 0.57), (0.12, 0.105, 0.11), GUNMETAL, 2)
    for x in (-0.065, 0.065):
        beam("Leg", (x, 0, 0.2), (x * 1.25, 0, 0.02), 0.032, GUNMETAL, 7)
    beam("Rifle", (0.06, -0.03, 0.4), (0.06, -0.42, 0.34), 0.025, GUNMETAL, 8)
    box("Optic", (0.06, -0.27, 0.39), (0.045, 0.07, 0.04), CYAN, 0.005)


def human_anti_armor():
    cyl("Body", (0, 0, 0.32), 0.115, 0.4, OLIVE_LIGHT, 10)
    ico("Helmet", (0, 0, 0.61), (0.13, 0.115, 0.12), GUNMETAL, 2)
    for x in (-0.07, 0.07):
        beam("Leg", (x, 0, 0.2), (x * 1.3, 0, 0.02), 0.034, GUNMETAL, 7)
    box("Backpack", (0, 0.11, 0.43), (0.25, 0.16, 0.3), OLIVE, 0.025)
    beam("Launcher", (-0.13, -0.02, 0.56), (-0.13, -0.62, 0.62), 0.055, GUNMETAL, 10)
    cone("Warhead", (-0.13, -0.68, 0.63), 0.075, 0.02, 0.18, AMBER, 10, (math.radians(90), 0, 0))


def human_gunship():
    ico("Fuselage", (0, 0, 0.38), (0.28, 0.62, 0.22), OLIVE, 2)
    box("MainWing", (0, 0.02, 0.38), (1.2, 0.34, 0.07), OLIVE_LIGHT, 0.04)
    box("TailWing", (0, 0.48, 0.45), (0.62, 0.18, 0.05), GUNMETAL, 0.025)
    box("TailFin", (0, 0.47, 0.62), (0.07, 0.22, 0.32), GUNMETAL, 0.025)
    ico("Canopy", (0, -0.32, 0.53), (0.16, 0.24, 0.1), CYAN, 2)
    for x in (-0.43, 0.43):
        cyl("LiftFan", (x, 0.03, 0.4), 0.17, 0.06, GUNMETAL, 16)
        cyl("EngineGlow", (x, 0.2, 0.38), 0.075, 0.05, CYAN, 12, (math.radians(90), 0, 0))
    beam("NoseGun", (0, -0.38, 0.35), (0, -0.72, 0.3), 0.035, GUNMETAL, 10)


def human_capital():
    ico("CommandHull", (0, 0, 0.48), (0.5, 1.0, 0.3), OLIVE, 2)
    box("ArmoredSpine", (0, 0.08, 0.7), (0.34, 1.35, 0.16), GUNMETAL, 0.05)
    box("MainWing", (0, 0.04, 0.45), (2.0, 0.62, 0.11), OLIVE_LIGHT, 0.07)
    box("ForwardDeck", (0, -0.68, 0.52), (0.72, 0.64, 0.18), CONCRETE, 0.06)
    ico("Bridge", (0, -0.4, 0.78), (0.22, 0.3, 0.12), CYAN, 2)
    for x in (-0.68, -0.24, 0.24, 0.68):
        cyl("Drive", (x, 0.48, 0.44), 0.1, 0.18, GUNMETAL, 12, (math.radians(90), 0, 0))
        cyl("DriveGlow", (x, 0.59, 0.44), 0.075, 0.04, CYAN, 12, (math.radians(90), 0, 0))
    beam("RailLance", (0, -0.72, 0.62), (0, -1.28, 0.62), 0.055, GUNMETAL, 12)


def human_harvester():
    box("LeftTrack", (-0.34, 0, 0.16), (0.2, 0.95, 0.24), GUNMETAL, 0.05)
    box("RightTrack", (0.34, 0, 0.16), (0.2, 0.95, 0.24), GUNMETAL, 0.05)
    box("Cab", (0, -0.22, 0.4), (0.58, 0.5, 0.48), OLIVE_LIGHT, 0.07)
    box("CargoBed", (0, 0.3, 0.36), (0.66, 0.5, 0.38), OLIVE, 0.05)
    box("Windshield", (0, -0.48, 0.48), (0.38, 0.025, 0.16), CYAN, 0.01)
    for x in (-0.2, 0.2):
        beam("Collector", (x, -0.45, 0.22), (x * 1.4, -0.7, 0.08), 0.045, AMBER, 8)


def alien_core():
    cyl("Foundation", (0, 0, 0.07), 1.05, 0.14, ALIEN_DARK, 12, bevel=0.035)
    ico("CoreShell", (0, 0, 0.72), (0.58, 0.58, 0.72), CRIMSON, 2)
    ico("EnergyCore", (0, -0.28, 0.82), (0.23, 0.16, 0.28), CYAN, 2)
    for i in range(6):
        angle = i * math.tau / 6
        x, y = math.cos(angle) * 0.82, math.sin(angle) * 0.82
        cone("CoreBlade", (x, y, 0.73), 0.22, 0.035, 1.25, CRIMSON_EDGE, 8, (0, math.radians(18), -angle))
        beam("Root", (x * 0.35, y * 0.35, 0.38), (x * 1.12, y * 1.12, 0.06), 0.07, ALIEN_DARK, 8)


def alien_spire():
    cyl("Foundation", (0, 0, 0.05), 0.58, 0.1, ALIEN_DARK, 10)
    cone("Spire", (0, 0, 0.74), 0.42, 0.06, 1.4, CRIMSON, 9)
    cone("InnerBlade", (0, -0.12, 0.92), 0.19, 0.02, 1.15, ALIEN_DARK, 8, (math.radians(-8), 0, 0))
    ico("Energy", (0, -0.25, 0.8), (0.14, 0.1, 0.28), CYAN, 2)
    for side in (-1, 1):
        cone("Flank", (side * 0.37, 0.08, 0.44), 0.16, 0.025, 0.75, CRIMSON_EDGE, 7, (0, math.radians(side * 16), 0))


def alien_walker():
    ico("Body", (0, 0, 0.48), (0.34, 0.45, 0.25), CRIMSON, 2)
    ico("Carapace", (0, 0.05, 0.61), (0.27, 0.32, 0.16), ALIEN_DARK, 2)
    ico("Eye", (0, -0.4, 0.5), (0.1, 0.08, 0.09), CYAN, 2)
    for side in (-1, 1):
        for y in (-0.22, 0.18):
            beam("UpperLeg", (side * 0.24, y, 0.46), (side * 0.52, y + 0.04, 0.22), 0.045, CRIMSON_EDGE, 7)
            beam("LowerLeg", (side * 0.52, y + 0.04, 0.22), (side * 0.66, y - 0.02, 0.02), 0.035, ALIEN_DARK, 7)


def alien_drone():
    ico("DroneBody", (0, 0, 0.34), (0.18, 0.28, 0.2), CRIMSON, 2)
    ico("DroneEye", (0, -0.23, 0.36), (0.075, 0.055, 0.075), CYAN, 2)
    for side in (-1, 1):
        beam("Arm", (side * 0.1, 0, 0.3), (side * 0.28, 0.06, 0.12), 0.025, ALIEN_DARK, 7)
        beam("Leg", (side * 0.09, 0.04, 0.25), (side * 0.17, 0.05, 0.0), 0.028, CRIMSON_EDGE, 7)


def alien_anti_armor():
    ico("LancerBody", (0, 0, 0.5), (0.24, 0.3, 0.34), CRIMSON, 2)
    ico("LancerEye", (0, -0.27, 0.58), (0.09, 0.06, 0.11), CYAN, 2)
    for side in (-1, 1):
        beam("Leg", (side * 0.13, 0, 0.34), (side * 0.3, 0.04, 0.02), 0.04, ALIEN_DARK, 7)
    beam("EnergyLance", (0.16, -0.05, 0.52), (0.16, -0.82, 0.58), 0.045, CRIMSON_EDGE, 8)
    ico("LanceCore", (0.16, -0.48, 0.58), (0.08, 0.15, 0.08), CYAN, 2)


def alien_gunship():
    ico("MantaCore", (0, 0, 0.42), (0.28, 0.55, 0.2), ALIEN_DARK, 2)
    for side in (-1, 1):
        cone("ScytheWing", (side * 0.48, 0.04, 0.4), 0.34, 0.025, 1.15, CRIMSON, 8, (0, math.radians(side * 58), 0))
        ico("WingNode", (side * 0.42, 0.12, 0.4), (0.1, 0.16, 0.09), CYAN, 2)
    ico("PilotEye", (0, -0.43, 0.48), (0.13, 0.09, 0.1), CYAN, 2)
    cone("TailBlade", (0, 0.55, 0.48), 0.16, 0.02, 0.7, CRIMSON_EDGE, 8)


def alien_capital():
    ico("WorldShipCore", (0, 0, 0.56), (0.5, 0.9, 0.34), ALIEN_DARK, 2)
    ico("WorldShipEye", (0, -0.74, 0.61), (0.2, 0.13, 0.16), CYAN, 2)
    for side in (-1, 1):
        cone("WorldBlade", (side * 0.72, 0.0, 0.52), 0.5, 0.04, 1.9, CRIMSON, 9, (0, math.radians(side * 61), 0))
        cone("OuterBlade", (side * 1.0, 0.2, 0.48), 0.25, 0.025, 1.2, CRIMSON_EDGE, 8, (0, math.radians(side * 72), 0))
    for x in (-0.44, 0, 0.44):
        ico("DriveCore", (x, 0.65, 0.5), (0.1, 0.16, 0.1), CYAN, 2)


def alien_harvester():
    ico("ExtractorCore", (0, 0, 0.44), (0.34, 0.4, 0.28), CRIMSON, 2)
    ico("CargoOrgan", (0, 0.18, 0.58), (0.22, 0.25, 0.2), CYAN, 2)
    for i in range(6):
        angle = i * math.tau / 6
        x, y = math.cos(angle) * 0.26, math.sin(angle) * 0.26
        beam("UpperLeg", (x, y, 0.4), (x * 1.8, y * 1.8, 0.18), 0.035, CRIMSON_EDGE, 7)
        beam("LowerLeg", (x * 1.8, y * 1.8, 0.18), (x * 2.15, y * 2.15, 0.02), 0.028, ALIEN_DARK, 7)


def human_structure(kind):
    box("Foundation", (0, 0, 0.06), (1.85, 1.5, 0.12), CONCRETE, 0.035)
    if kind == "power":
        cyl("Reactor", (0, 0.08, 0.58), 0.46, 1.0, OLIVE, 16)
        for x in (-0.58, 0.58):
            cyl("EnergyCoil", (x, 0.02, 0.52), 0.17, 0.7, CYAN, 12)
    elif kind == "refinery":
        box("ProcessingHall", (-0.25, 0.1, 0.43), (1.15, 1.0, 0.72), OLIVE, 0.06)
        cyl("OreDrum", (0.58, 0.18, 0.46), 0.34, 0.75, AMBER, 14)
        box("Intake", (0, -0.72, 0.22), (0.9, 0.45, 0.3), GUNMETAL, 0.035)
    elif kind in ("gun_turret", "aa_turret"):
        cyl("Tower", (0, 0, 0.48), 0.3, 0.72, OLIVE_LIGHT, 12)
        if kind == "gun_turret":
            cyl("Turret", (0, -0.02, 0.88), 0.34, 0.2, GUNMETAL, 12)
            for x in (-0.11, 0.11):
                beam("Cannon", (x, -0.16, 0.91), (x, -0.78, 0.94), 0.045, GUNMETAL, 10)
        else:
            for x in (-0.19, 0.19):
                beam("MissileRail", (x, -0.08, 0.75), (x, -0.58, 1.05), 0.05, GUNMETAL, 8)
                cone("Missile", (x, -0.62, 1.08), 0.065, 0.01, 0.24, AMBER, 8, (math.radians(58), 0, 0))
    elif kind == "wall":
        box("Wall", (0, 0, 0.42), (1.7, 0.3, 0.6), OLIVE, 0.045)
        for x in (-0.72, 0, 0.72):
            box("Buttress", (x, 0, 0.46), (0.18, 0.48, 0.72), GUNMETAL, 0.025)
    elif kind == "lab":
        box("LabHull", (0, 0.12, 0.42), (1.38, 1.0, 0.68), OLIVE_LIGHT, 0.07)
        ico("QuantumDome", (0, -0.1, 0.91), (0.48, 0.42, 0.28), CYAN, 2)
    else:
        for side in (-1, 1):
            cone("ContainmentPylon", (side * 0.48, 0, 0.6), 0.24, 0.07, 1.05, GUNMETAL, 10)
            beam("ContainmentArc", (side * 0.42, 0, 0.72), (0, 0, 0.88), 0.045, CYAN, 10)
        ico("AntimatterCore", (0, 0, 0.82), (0.24, 0.24, 0.24), CYAN, 3)


def alien_structure(kind):
    cyl("Foundation", (0, 0, 0.06), 0.86, 0.12, ALIEN_DARK, 12)
    if kind == "barracks":
        ico("BroodHall", (0, 0.1, 0.48), (0.62, 0.55, 0.42), CRIMSON, 2)
        ico("Gate", (0, -0.48, 0.42), (0.25, 0.12, 0.28), CYAN, 2)
    elif kind == "power":
        ico("ReactorCore", (0, 0, 0.66), (0.3, 0.3, 0.44), CYAN, 2)
        for i in range(5):
            angle = i * math.tau / 5
            cone("ReactorBlade", (math.cos(angle) * 0.52, math.sin(angle) * 0.52, 0.54), 0.18, 0.025, 0.92, CRIMSON, 8, (0, math.radians(22), -angle))
    elif kind == "refinery":
        ico("Digestor", (0, 0.12, 0.52), (0.58, 0.5, 0.48), CRIMSON, 2)
        ico("OreMaw", (0, -0.48, 0.38), (0.35, 0.2, 0.24), AMBER, 2)
    elif kind in ("gun_turret", "aa_turret"):
        cone("Stalk", (0, 0, 0.52), 0.3, 0.1, 0.88, CRIMSON_EDGE, 9)
        ico("Tracker", (0, -0.12, 0.94), (0.18, 0.2, 0.15), CYAN, 2)
        count = 2 if kind == "gun_turret" else 3
        for i in range(count):
            angle = (i - (count - 1) / 2) * 0.34
            beam("EnergyLance", (math.sin(angle) * 0.16, -0.15, 0.94), (math.sin(angle) * 0.38, -0.78, 1.02), 0.04, CRIMSON, 8)
    elif kind == "wall":
        for x in (-0.68, -0.34, 0, 0.34, 0.68):
            cone("WallBlade", (x, 0, 0.42), 0.18, 0.035, 0.72, CRIMSON, 7)
        beam("EnergyVein", (-0.72, -0.17, 0.38), (0.72, -0.17, 0.38), 0.035, CYAN, 8)
    elif kind == "lab":
        ico("Archive", (0, 0.08, 0.56), (0.5, 0.46, 0.55), CRIMSON, 2)
        ico("KnowledgeCore", (0, -0.32, 0.7), (0.19, 0.13, 0.28), CYAN, 2)
    else:
        ico("VoidCore", (0, 0, 0.66), (0.3, 0.3, 0.3), ALIEN_DARK, 3)
        for i in range(6):
            angle = i * math.tau / 6
            x, y = math.cos(angle) * 0.55, math.sin(angle) * 0.55
            beam("CollectorArm", (x, y, 0.24), (x * 0.5, y * 0.5, 0.68), 0.065, CRIMSON_EDGE, 8)


def world_tree():
    cyl("Trunk", (0, 0, 0.36), 0.075, 0.72, BARK, 8)
    ico("CrownA", (0, 0, 0.84), (0.36, 0.34, 0.32), LEAF, 2)
    ico("CrownB", (0.18, 0.02, 0.72), (0.27, 0.25, 0.24), LEAF, 1)
    ico("CrownC", (-0.16, 0.05, 0.74), (0.24, 0.23, 0.25), LEAF, 1)


def world_rock():
    ico("RockA", (-0.16, 0, 0.14), (0.28, 0.22, 0.24), ROCK, 1)
    ico("RockB", (0.14, 0.04, 0.2), (0.24, 0.3, 0.22), ROCK, 1)
    ico("RockC", (0.02, -0.16, 0.1), (0.2, 0.16, 0.18), ROCK, 1)


ASSETS = {
    "human_hq": human_hq,
    "human_industry": human_industry,
    "human_barracks": human_barracks,
    "human_tank": human_tank,
    "human_infantry": human_infantry,
    "human_anti_armor": human_anti_armor,
    "human_gunship": human_gunship,
    "human_capital": human_capital,
    "human_harvester": human_harvester,
    "human_power": lambda: human_structure("power"),
    "human_refinery": lambda: human_structure("refinery"),
    "human_gun_turret": lambda: human_structure("gun_turret"),
    "human_aa_turret": lambda: human_structure("aa_turret"),
    "human_wall": lambda: human_structure("wall"),
    "human_lab": lambda: human_structure("lab"),
    "human_antimatter": lambda: human_structure("antimatter"),
    "alien_core": alien_core,
    "alien_spire": alien_spire,
    "alien_walker": alien_walker,
    "alien_drone": alien_drone,
    "alien_anti_armor": alien_anti_armor,
    "alien_gunship": alien_gunship,
    "alien_capital": alien_capital,
    "alien_harvester": alien_harvester,
    "alien_barracks": lambda: alien_structure("barracks"),
    "alien_power": lambda: alien_structure("power"),
    "alien_refinery": lambda: alien_structure("refinery"),
    "alien_gun_turret": lambda: alien_structure("gun_turret"),
    "alien_aa_turret": lambda: alien_structure("aa_turret"),
    "alien_wall": lambda: alien_structure("wall"),
    "alien_lab": lambda: alien_structure("lab"),
    "alien_antimatter": lambda: alien_structure("antimatter"),
    "world_tree": world_tree,
    "world_rock": world_rock,
}

for asset_name, builder in ASSETS.items():
    reset()
    builder()
    export(asset_name)
    print(f"exported {asset_name}.glb")
