"""Builds a simplified 3D model of the OST observatory (Universität Potsdam, Golm) from the
reference photos in docs/reference/observatory/ and exports it as glTF for Godot.

    blender --background --python blender/build_observatory.py

Units are metres, Blender Z up (glTF/Godot convert to Y up). Animated parts are separate
objects whose origin is their pivot:
  DomeRotator (dome shell, shutter, slit) – turns about the vertical axis
  Shutter       – opens over the zenith (rotation about the local X axis)
  RA_Axis       – polar axis, tilted to the latitude 52.4 deg, pointing north (+Y)
  Dec_Axis      – declination axis, child of RA_Axis; OTA (CDK20) is its child
Materials only carry names and base factors; the look is finished in Godot.
"""

import math
from pathlib import Path

import bpy
import bmesh
from mathutils import Euler, Matrix, Vector

REPO = Path(__file__).resolve().parents[1]
OUT = REPO / "godot/assets/models/observatory.glb"
LAT = math.radians(52.41)

DOME_R = 2.55
BASE_R = 2.5
BASE_H = 2.3
SLIT_W = 1.1


# --- helpers ----------------------------------------------------------------------------

def reset():
    bpy.ops.wm.read_factory_settings(use_empty=True)


_materials = {}


def mat(name, color, rough=0.6, metal=0.0):
    if name in _materials:
        return _materials[name]
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    bsdf = m.node_tree.nodes["Principled BSDF"]
    bsdf.inputs["Base Color"].default_value = (*color, 1.0)
    bsdf.inputs["Roughness"].default_value = rough
    bsdf.inputs["Metallic"].default_value = metal
    _materials[name] = m
    return m


def assign(obj, material):
    obj.data.materials.clear()
    obj.data.materials.append(material)
    return obj


def link(obj, parent=None):
    if parent is not None:
        obj.parent = parent
    return obj


def box(name, size, loc, material, parent=None, rot=(0, 0, 0)):
    bpy.ops.mesh.primitive_cube_add(size=1, location=loc, rotation=rot)
    o = bpy.context.active_object
    o.name = name
    o.scale = size
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    return link(assign(o, material), parent)


def cyl(name, r, h, loc, material, parent=None, rot=(0, 0, 0), verts=32, r2=None):
    if r2 is None:
        bpy.ops.mesh.primitive_cylinder_add(radius=r, depth=h, location=loc, rotation=rot, vertices=verts)
    else:
        bpy.ops.mesh.primitive_cone_add(radius1=r, radius2=r2, depth=h, location=loc, rotation=rot, vertices=verts)
    o = bpy.context.active_object
    o.name = name
    return link(assign(o, material), parent)


def empty(name, loc=(0, 0, 0), parent=None, rot=(0, 0, 0)):
    o = bpy.data.objects.new(name, None)
    bpy.context.collection.objects.link(o)
    o.location = loc
    o.rotation_euler = rot
    return link(o, parent)


def boolean(target, cutter, op="DIFFERENCE"):
    mod = target.modifiers.new("bool", "BOOLEAN")
    mod.operation = op
    mod.object = cutter
    mod.solver = "EXACT"
    bpy.context.view_layer.objects.active = target
    bpy.ops.object.modifier_apply(modifier=mod.name)
    bpy.data.objects.remove(cutter, do_unlink=True)


def hemisphere_shell(name, r, thickness, material):
    bpy.ops.mesh.primitive_uv_sphere_add(radius=r, segments=96, ring_count=48, location=(0, 0, 0))
    o = bpy.context.active_object
    o.name = name
    bm = bmesh.new()
    bm.from_mesh(o.data)
    bmesh.ops.delete(bm, geom=[v for v in bm.verts if v.co.z < -1e-4], context="VERTS")
    bm.to_mesh(o.data)
    bm.free()
    sol = o.modifiers.new("solid", "SOLIDIFY")
    sol.thickness = thickness
    sol.offset = -1.0
    bpy.context.view_layer.objects.active = o
    bpy.ops.object.modifier_apply(modifier=sol.name)
    bpy.ops.object.shade_smooth()
    return assign(o, material)


def rod(name, a, b, r, material, parent=None, verts=8):
    a, b = Vector(a), Vector(b)
    d = b - a
    o = cyl(name, r, d.length, (a + b) / 2, material, verts=verts)
    o.rotation_mode = "QUATERNION"
    o.rotation_quaternion = Vector((0, 0, 1)).rotation_difference(d.normalized())
    return link(o, parent)


# --- the model ----------------------------------------------------------------------------

def build():
    M = {
        "dome": mat("dome_white", (0.92, 0.92, 0.89), 0.35),
        "paint": mat("paint_white", (0.88, 0.88, 0.86), 0.45),
        "interior": mat("panel_grey", (0.72, 0.73, 0.72), 0.6),
        "concrete": mat("concrete", (0.42, 0.42, 0.41), 0.92),
        "wood": mat("wood_floor", (0.43, 0.29, 0.18), 0.7),
        "galv": mat("metal_galv", (0.66, 0.67, 0.68), 0.45, 1.0),
        "black": mat("anodized_black", (0.03, 0.03, 0.035), 0.4, 0.6),
        "steel": mat("steel", (0.8, 0.8, 0.82), 0.22, 1.0),
        "shroud": mat("shroud_black", (0.02, 0.02, 0.03), 0.95),
        "gold": mat("facade_gold", (0.62, 0.5, 0.3), 0.55, 0.6),
        "dark": mat("facade_dark", (0.07, 0.07, 0.08), 0.3, 0.2),
        "glass": mat("glass_dark", (0.05, 0.07, 0.1), 0.1, 0.0),
        "orange": mat("plaster_orange", (0.85, 0.48, 0.22), 0.85),
        "roof": mat("roof_red", (0.55, 0.16, 0.1), 0.7),
        "tree": mat("tree", (0.13, 0.25, 0.1), 0.9),
        "hill": mat("hill", (0.1, 0.17, 0.08), 0.95),
        "lamp": mat("lamp_red", (1.0, 0.1, 0.05), 0.5),
        "cabinet": mat("cabinet_white", (0.85, 0.86, 0.85), 0.5),
    }
    root = empty("Observatory")

    # Building below the roof (golden perforated facade) and the roof terrace.
    box("Building", (46, 18, 14), (-8, 2, -7.05), M["gold"], root)
    for z in (-3.0, -8.0):
        box(f"WindowBand{z}", (46.2, 18.2, 1.0), (-8, 2, z), M["glass"], root)
    box("RoofSlab", (16, 12, 0.3), (0, 0, -0.15), M["concrete"], root)
    box("Parapet", (16.4, 12.4, 0.35), (0, 0, 0.0), M["concrete"], root)
    box("ParapetInner", (15.6, 11.6, 0.6), (0, 0, 0.05), M["concrete"], root)  # removed below
    parapet = bpy.data.objects["Parapet"]
    boolean(parapet, bpy.data.objects["ParapetInner"])
    # Railing: posts and two rails around the terrace.
    rail_h = (0.5, 1.05)
    corners = [(-7.6, -5.6), (7.6, -5.6), (7.6, 5.6), (-7.6, 5.6)]
    for i in range(4):
        a, b = Vector((*corners[i], 0)), Vector((*corners[(i + 1) % 4], 0))
        n = int((b - a).length / 1.6)
        for k in range(n + 1):
            p = a.lerp(b, k / n)
            cyl(f"Post{i}_{k}", 0.025, 1.05, (p.x, p.y, 0.53), M["galv"], root, verts=8)
        for h in rail_h:
            rod(f"Rail{i}_{h}", (a.x, a.y, h), (b.x, b.y, h), 0.025, M["galv"], root)
    # Antenna masts with guy wires, stair house, small boxes.
    for name, x, y in (("MastA", -5.5, 3.5), ("MastB", 5.8, -3.8)):
        rod(name, (x, y, 0), (x, y, 6.5), 0.025, M["galv"], root)
        for ang in (0, 120, 240):
            dx, dy = math.cos(math.radians(ang)) * 1.6, math.sin(math.radians(ang)) * 1.6
            rod(f"{name}_wire{ang}", (x, y, 4.0), (x + dx, y + dy, 0.0), 0.006, M["galv"], root, verts=4)
            cyl(f"{name}_foot{ang}", 0.18, 0.2, (x + dx, y + dy, 0.1), M["concrete"], root, verts=12)
    box("StairHouse", (3.2, 2.6, 2.7), (5.6, 4.3, 1.35), M["gold"], root)
    box("StairDoor", (1.0, 0.05, 2.1), (5.0, 2.98, 1.05), M["dark"], root)
    box("WeatherBox", (0.4, 0.3, 0.5), (-7.3, -2.0, 1.4), M["paint"], root)

    # Dome base (open cylinder with door) and interior floor.
    base = cyl("DomeBase", BASE_R, BASE_H, (0, 0, BASE_H / 2), M["paint"], root, verts=96)
    inner = cyl("BaseInner", BASE_R - 0.06, BASE_H + 0.2, (0, 0, BASE_H / 2), M["paint"], verts=96)
    boolean(base, inner)
    door_cut = box("DoorCut", (0.9, 0.5, 1.9), (0.0, -BASE_R, 0.95 + 0.05), M["paint"])
    boolean(base, door_cut)
    box("Door", (0.9, 0.04, 1.9), (0.0, -BASE_R - 0.02, 1.0), M["paint"], root)
    cyl("Floor", BASE_R - 0.06, 0.04, (0, 0, 0.02), M["wood"], root, verts=96)
    ledge = cyl("Ledge", BASE_R - 0.02, 0.06, (0, 0, BASE_H - 0.05), M["interior"], root, verts=96)
    boolean(ledge, cyl("LedgeHole", BASE_R - 0.32, 0.2, (0, 0, BASE_H - 0.05), M["interior"], verts=96))
    for i, ang in enumerate((40, 130, 220, 310)):
        x, y = math.cos(math.radians(ang)) * (BASE_R - 0.1), math.sin(math.radians(ang)) * (BASE_R - 0.1)
        cyl(f"RedLamp{i}", 0.06, 0.12, (x * 0.97, y * 0.97, 1.85), M["lamp"], root, verts=12)
    box("Cabinet", (1.2, 0.6, 0.9), (-1.3, 1.6, 0.45), M["cabinet"], root, rot=(0, 0, math.radians(-35)))
    box("FlatfieldBox", (0.9, 0.6, 0.6), (1.4, 1.5, 1.2), M["cabinet"], root, rot=(0, 0, math.radians(30)))
    box("ToolTrolley", (0.6, 0.45, 1.0), (1.8, -1.0, 0.5), M["dark"], root, rot=(0, 0, math.radians(60)))
    box("ControlCabinet", (0.6, 0.3, 0.8), (-1.9, -0.9, 1.3), M["galv"], root, rot=(0, 0, math.radians(110)))

    # Rotating dome with slit and shutter. Slit faces +Y (towards the telescope's south side
    # is handled by turning the whole DomeRotator in Godot).
    rot = empty("DomeRotator", (0, 0, BASE_H), root)
    shell = hemisphere_shell("DomeShell", DOME_R, 0.05, M["dome"])
    slit = box("SlitCut", (SLIT_W, 3.2, 3.2), (0, 1.5, 1.6 + 0.35), M["dome"])
    boolean(shell, slit)
    shell.location = (0, 0, 0)
    shell.parent = rot
    # Shutter: a strip of a slightly larger shell, covering the slit when closed.
    shutter = hemisphere_shell("ShutterShell", DOME_R + 0.06, 0.05, M["dome"])
    keep = box("ShutterKeep", (SLIT_W + 0.24, 3.4, 3.4), (0, 1.55, 1.7 + 0.3), M["dome"])
    boolean(shutter, keep, "INTERSECT")
    shutter_pivot = empty("Shutter", (0, 0, 0), rot)
    shutter.parent = shutter_pivot
    # Slit side frames (the white arches visible on the photos).
    for sx in (-1, 1):
        arch = hemisphere_shell(f"SlitFrame{sx}", DOME_R + 0.02, 0.08, M["paint"])
        cut = box("FrameKeep", (0.12, 3.4, 3.4), (sx * (SLIT_W / 2 + 0.06), 1.4, 1.7 + 0.3), M["paint"])
        boolean(arch, cut, "INTERSECT")
        arch.parent = rot

    # Pier, mount and telescope.
    cyl("Pier", 0.36, 1.45, (0, 0, 0.725), M["paint"], root, verts=8, r2=0.28)
    cyl("PierRing", 0.33, 0.08, (0, 0, 1.49), M["galv"], root, verts=32)
    for i in range(6):
        a = math.radians(i * 60)
        cyl(f"PierStud{i}", 0.03, 0.22, (math.cos(a) * 0.24, math.sin(a) * 0.24, 1.64), M["paint"], root, verts=8)
    cyl("PierTop", 0.3, 0.06, (0, 0, 1.78), M["galv"], root, verts=32)
    box("MountBase", (0.36, 0.42, 0.24), (0, 0, 1.93), M["black"], root)
    # Polar axis: tilted by the latitude, pointing north (+Y) and up.
    ra = empty("RA_Axis", (0, 0.05, 2.1), root, rot=(-(math.pi / 2 - LAT), 0, 0))
    cyl("RA_Housing", 0.17, 0.55, (0, 0, 0.0), M["black"], ra, verts=32)
    dec = empty("Dec_Axis", (0, 0, 0.33), ra)
    cyl("Dec_Housing", 0.15, 0.7, (0, 0, 0), M["black"], dec, rot=(0, math.pi / 2, 0), verts=32)
    rod("CW_Shaft", (-0.3, 0, 0), (-1.15, 0, 0), 0.045, M["steel"], dec, verts=16)
    for i in range(3):
        cyl(f"CW_{i}", 0.19, 0.1, (-0.75 - i * 0.11, 0, 0), M["steel"], dec, rot=(0, math.pi / 2, 0), verts=32)
    # CDK20 optical tube (truss with black shroud), along the local Z axis.
    ota = empty("OTA", (0.48, 0, 0), dec)
    cyl("OTA_Saddle", 0.08, 0.5, (0, 0, 0), M["black"], ota, rot=(0, math.pi / 2, 0), verts=16)
    cyl("OTA_Back", 0.33, 0.22, (0.4, 0, -0.35), M["black"], ota, verts=48)
    cyl("OTA_Front", 0.34, 0.12, (0.4, 0, 0.75), M["black"], ota, verts=48)
    cyl("OTA_Shroud", 0.315, 0.98, (0.4, 0, 0.21), M["shroud"], ota, verts=48)
    cyl("OTA_Secondary", 0.09, 0.1, (0.4, 0, 0.72), M["black"], ota, verts=24)
    for i in range(4):
        a = math.radians(45 + 90 * i)
        rod(f"OTA_Spider{i}", (0.4, 0, 0.74), (0.4 + math.cos(a) * 0.32, math.sin(a) * 0.32, 0.74), 0.006, M["black"], ota, verts=4)
    cyl("FilterWheel", 0.26, 0.08, (0.4, 0, -0.52), M["black"], ota, verts=48)
    box("Camera_QHY600", (0.16, 0.16, 0.14), (0.4, 0, -0.63), M["black"], ota)
    cyl("Guidescope", 0.04, 0.38, (0.75, 0, 0.1), M["paint"], ota, verts=16)

    # Surroundings (very simplified, for the intro shot).
    box("DarkBuilding", (22, 14, 15), (-34, -22, -6.5), M["dark"], root)
    box("StellwerkHouse", (16, 8, 8), (24, 22, -10), M["orange"], root)
    bpy.ops.mesh.primitive_cone_add(vertices=4, radius1=11.5, radius2=0, depth=4, location=(24, 22, -4), rotation=(0, 0, math.radians(45)))
    r = bpy.context.active_object
    r.name = "StellwerkRoof"
    r.scale = (1.0, 0.5, 1.0)
    link(assign(r, M["roof"]), root)
    import random
    rnd = random.Random(7)
    for i in range(40):
        ang = rnd.uniform(0, math.tau)
        d = rnd.uniform(28, 70)
        x, y = math.cos(ang) * d, math.sin(ang) * d
        h = rnd.uniform(9, 16)
        bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=2, radius=h * 0.38, location=(x, y, -14 + h * 0.75))
        t = bpy.context.active_object
        t.name = f"Tree{i}"
        t.scale = (1, 1, 1.35)
        link(assign(t, M["tree"]), root)
    for i, (x, y, rr) in enumerate(((-140, 160, 90), (60, 220, 120), (220, 40, 100))):
        bpy.ops.mesh.primitive_uv_sphere_add(radius=rr, location=(x, y, -14 - rr * 0.82))
        hl = bpy.context.active_object
        hl.name = f"Hill{i}"
        hl.scale = (1.6, 1.0, 1.0)
        link(assign(hl, M["hill"]), root)
    box("Ground", (600, 600, 1), (0, 0, -14.5), M["hill"], root)


def export():
    OUT.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.export_scene.gltf(filepath=str(OUT), export_format="GLB", export_apply=True,
                              export_yup=True, export_materials="EXPORT")
    print("exported", OUT)


if __name__ == "__main__":
    reset()
    build()
    export()
