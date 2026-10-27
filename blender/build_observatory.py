"""Builds a simplified 3D model of the OST observatory (Universität Potsdam, Golm) from the
reference photos in docs/reference/observatory/ and exports it as glTF for Godot.

    blender --background --python blender/build_observatory.py

Units are metres, Blender Z up (glTF/Godot convert to Y up). Animated parts are separate
objects whose origin is their pivot:
  DomeRotator (dome shell, shutter, slit), turns about the vertical axis
  Shutter      , opens over the zenith (rotation about the local X axis)
  RA_Axis      , polar axis, tilted to the latitude 52.4 deg, pointing north (+Y)
  Dec_Axis     , declination axis, child of RA_Axis; OTA (CDK20) is its child
Materials only carry names and base factors; the look is finished in Godot.
"""

import math
from pathlib import Path

import bpy
import bmesh
from mathutils import Euler, Matrix, Vector, noise

REPO = Path(__file__).resolve().parents[1]
OUT = REPO / "godot/assets/models/observatory.glb"
LAT = math.radians(52.41)

DOME_R = 2.55
BASE_R = 2.5
BASE_H = 2.3
SLIT_W = 1.21


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


# Intro flight of the camera (ObservatoryScene SHOTS "street" -> "roof" through VIA, a
# quadratic Bezier, Blender axes): no tree may stand in its way.
FLIGHT = (Vector((-45.0, -55.0, -12.3)), Vector((-22.0, -20.0, 6.0)), Vector((-7.0, 1.5, 1.7)))
# Compass: +x north, -y east (the dome door), -x south (the black building), +y west (the
# road, the Stellwerk and the railway).
# Institute building (x0, x1, y0, y1): long from north to south, the dome terrace near its
# south-west corner, 9 m from the south and 8 m from the west facade.
BUILDING = (-9.0, 89.0, -31.0, 8.0)
COURTYARD = (22.0, 70.0, -20.0, -8.0)   # open inner courtyard (x0, x1, y0, y1)
ROOF_Z = -0.3       # top of the building box; gravel roof a little above, terrace at z = 0


def in_flight_path(center, radii, margin=1.4):
    a, v, b = FLIGHT
    for k in range(201):
        t = k / 200
        p = a.lerp(v, t).lerp(v.lerp(b, t), t)
        q = sum(((p[j] - center[j]) / radii[j]) ** 2 for j in range(3))
        if q < margin * margin:
            return True
    return False


def railing(name, points, material, parent, heights=(0.22, 0.48, 0.74, 1.05), z0=0.0):
    """Galvanised railing along a polyline: posts every ~1.6 m and four bars."""
    for i in range(len(points) - 1):
        a, b = Vector((*points[i], z0)), Vector((*points[i + 1], z0))
        n = max(1, int((b - a).length / 1.6))
        for k in range(n + 1):
            p = a.lerp(b, k / n)
            box(f"{name}Post{i}_{k}", (0.05, 0.05, 1.08), (p.x, p.y, z0 + 0.54), material, parent)
        for h in heights:
            rod(f"{name}Bar{i}_{h}", (a.x, a.y, z0 + h), (b.x, b.y, z0 + h), 0.022, material, parent)


def at_wall(angle_deg, depth, gap=0.05, r_wall=BASE_R - 0.06):
    """Centre (x, y) and z rotation of furniture standing at the inner base wall."""
    a = math.radians(angle_deg)
    r = r_wall - depth / 2 - gap
    return (math.cos(a) * r, math.sin(a) * r), a + math.pi / 2


def desk(name, angle, width, M, parent, top_z=0.82):
    """Desk at the wall with a drawer block on one side (white, golden handles)."""
    (x, y), rz = at_wall(angle, 0.62)
    t = Vector((math.cos(rz), math.sin(rz), 0))
    box(f"{name}Top", (width, 0.62, 0.04), (x, y, top_z), M["desk"], parent, rot=(0, 0, rz))
    dx = t * (width / 2 - 0.27)
    box(f"{name}Drawers", (0.5, 0.58, top_z - 0.04), (x + dx.x, y + dx.y, (top_z - 0.04) / 2), M["cabinet"], parent, rot=(0, 0, rz))
    for k, h in enumerate((0.62, 0.32)):
        box(f"{name}Handle{k}", (0.36, 0.64, 0.025), (x + dx.x, y + dx.y, h), M["brass"], parent, rot=(0, 0, rz))
    lx = t * -(width / 2 - 0.04)
    box(f"{name}Leg", (0.04, 0.58, top_z - 0.04), (x + lx.x, y + lx.y, (top_z - 0.04) / 2), M["galv"], parent, rot=(0, 0, rz))
    return (x, y), rz


def split_sides(o, inner_name, outer_name, horizontal):
    """Splits a shell into its inner side (faces turned towards the dome's axis or centre)
    and the rest (outer side, rims, cut edges): Godot lights them differently, the inside
    only with the red lamps, the outside only with moon and street lights."""
    parts = []
    for keep_inner, name in ((True, inner_name), (False, outer_name)):
        c = o.copy()
        c.data = o.data.copy()
        c.name = name
        bpy.context.collection.objects.link(c)
        bm = bmesh.new()
        bm.from_mesh(c.data)
        drop = []
        for f in bm.faces:
            p = f.calc_center_median()
            n = f.normal
            d = (n.x * p.x + n.y * p.y) if horizontal else n.dot(p)
            if (d < -1e-3) != keep_inner:
                drop.append(f)
        bmesh.ops.delete(bm, geom=drop, context="FACES")
        bm.to_mesh(c.data)
        bm.free()
        parts.append(c)
    bpy.data.objects.remove(o, do_unlink=True)
    return parts


def hip_roof(name, w, d, h, loc, material, parent):
    """Pyramid roof w x d (x, y) and h high, base centred at loc."""
    bpy.ops.mesh.primitive_cone_add(vertices=4, radius1=1.0, radius2=0, depth=1.0, rotation=(0, 0, math.radians(45)))
    o = bpy.context.active_object
    o.name = name
    bpy.ops.object.transform_apply(location=False, rotation=True, scale=False)
    o.scale = (w / math.sqrt(2), d / math.sqrt(2), h)
    o.location = (loc[0], loc[1], loc[2] + h / 2)
    return link(assign(o, material), parent)


def rod(name, a, b, r, material, parent=None, verts=8):
    a, b = Vector(a), Vector(b)
    d = b - a
    o = cyl(name, r, d.length, (a + b) / 2, material, verts=verts)
    o.rotation_mode = "QUATERNION"
    o.rotation_quaternion = Vector((0, 0, 1)).rotation_difference(d.normalized())
    return link(o, parent)


def foliage(name, r, loc, scale, material, seed, parts):
    """A lumpy ball of leaves: an ico sphere pushed in and out by fractal noise."""
    bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=2, radius=r, location=loc)
    o = bpy.context.active_object
    o.name = name
    o.scale = scale
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    off = Vector((seed, seed * 0.7, seed * 1.3))
    for v in o.data.vertices:
        n = noise.fractal(v.co * (1.6 / r) + off, 0.6, 2.0, 3)
        v.co += v.normal * n * r * 0.32
    bpy.ops.object.shade_smooth()
    parts.append(assign(o, material))


def tree(name, kind, base, h, rnd, seed, crown, M, parent, bark_mat=None):
    """Broad-leaved tree (several lumps of leaves), columnar tree (poplar, hornbeam) or
    Scots pine (long bare trunk, flat crown on top): all common around Golm."""
    x, y, z = base
    parts = []
    if kind == "pine":
        trunk_h, crown_mat, bark = h * 0.78, M["tree_pine"], M["bark_pine"]
    elif kind == "column":
        trunk_h, crown_mat, bark = h * 0.3, crown, M["bark"]
    elif kind == "ball":
        trunk_h, crown_mat, bark = h * 0.42, crown, M["bark"]
    elif kind == "birch":
        trunk_h, crown_mat, bark = h * 0.75, crown, M["bark_birch"]
    else:
        trunk_h, crown_mat, bark = h * 0.45, crown, M["bark"]
    bark = bark_mat or bark
    r_trunk = h * (0.03 if kind == "ball" else 0.022)
    parts.append(cyl(f"{name}_trunk", r_trunk, trunk_h, (x, y, z + trunk_h / 2), bark, verts=8, r2=r_trunk * 0.6))
    if kind == "broad":
        R = h * 0.3
        cz = z + h - R * 1.05
        for k in range(rnd.randint(5, 7)):
            a = rnd.uniform(0, math.tau)
            rr = rnd.uniform(0.2, 0.6) * R
            p = (x + math.cos(a) * rr, y + math.sin(a) * rr, cz + rnd.uniform(-0.45, 0.4) * R)
            foliage(f"{name}_c{k}", R * rnd.uniform(0.5, 0.7), p, (1, 1, rnd.uniform(0.8, 1.0)), crown_mat, seed + k, parts)
    elif kind == "ball":
        # Ball maple: one dense, slightly flattened crown on a short trunk.
        R = h * 0.36
        for k in range(3):
            p = (x + rnd.uniform(-0.15, 0.15) * R, y + rnd.uniform(-0.15, 0.15) * R, z + h - R * 0.85 + k * 0.1)
            foliage(f"{name}_c{k}", R * rnd.uniform(0.8, 0.95), p, (1, 1, 0.75), crown_mat, seed + k, parts)
    elif kind == "birch":
        # Birch: tall white trunk, loose narrow crown of small lumps.
        R = h * 0.13
        for k in range(rnd.randint(6, 8)):
            t = rnd.uniform(0.35, 0.95)
            a = rnd.uniform(0, math.tau)
            rr = rnd.uniform(0.3, 1.0) * R * (1.2 - t * 0.6)
            p = (x + math.cos(a) * rr, y + math.sin(a) * rr, z + h * t)
            foliage(f"{name}_c{k}", R * rnd.uniform(0.45, 0.7), p, (1, 1, 1.2), crown_mat, seed + k, parts)
    elif kind == "column":
        R = h * 0.15
        n = rnd.randint(3, 4)
        for k in range(n):
            t = (k + 0.5) / n
            p = (x + rnd.uniform(-0.2, 0.2) * R, y + rnd.uniform(-0.2, 0.2) * R, z + h * (0.3 + 0.62 * t))
            foliage(f"{name}_c{k}", R * (1.15 - 0.45 * abs(t - 0.4)), p, (1, 1, 1.5), crown_mat, seed + k, parts)
    else:
        R = h * 0.17
        for k in range(rnd.randint(3, 5)):
            a = rnd.uniform(0, math.tau)
            rr = rnd.uniform(0.1, 0.7) * R
            p = (x + math.cos(a) * rr, y + math.sin(a) * rr, z + h * rnd.uniform(0.8, 0.93))
            foliage(f"{name}_c{k}", R * rnd.uniform(0.55, 0.8), p, (1, 1, 0.55), crown_mat, seed + k, parts)
    # One object per tree.
    bpy.ops.object.select_all(action="DESELECT")
    for o in parts:
        o.select_set(True)
    bpy.context.view_layer.objects.active = parts[0]
    bpy.ops.object.join()
    t = bpy.context.active_object
    t.name = name
    return link(t, parent)


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
        "tree_light": mat("tree_light", (0.19, 0.31, 0.12), 0.9),
        "tree_dark": mat("tree_dark", (0.09, 0.19, 0.08), 0.9),
        "tree_pine": mat("tree_pine", (0.07, 0.15, 0.09), 0.9),
        "bark": mat("bark", (0.17, 0.15, 0.13), 0.95),
        "bark_pine": mat("bark_pine", (0.3, 0.2, 0.15), 0.9),
        "hill": mat("hill", (0.1, 0.17, 0.08), 0.95),
        "grass": mat("grass", (0.16, 0.25, 0.1), 0.95),
        "pavement": mat("pavement", (0.36, 0.37, 0.39), 0.9),
        "asphalt": mat("asphalt", (0.1, 0.1, 0.11), 0.9),
        "water": mat("water", (0.03, 0.06, 0.08), 0.05),
        "stair": mat("stair_gold", (0.62, 0.5, 0.3), 0.55, 0.6),
        "bark_birch": mat("bark_birch", (0.85, 0.84, 0.8), 0.8),
        "lamp_head": mat("lamp_head", (1.0, 0.85, 0.6), 0.5),
        "lamp": mat("lamp_red", (1.0, 0.1, 0.05), 0.5),
        "cabinet": mat("cabinet_white", (0.85, 0.86, 0.85), 0.5),
        "desk": mat("desk_top", (0.62, 0.63, 0.62), 0.6),
        "brass": mat("brass", (0.75, 0.6, 0.3), 0.35, 1.0),
        "blue": mat("box_blue", (0.08, 0.28, 0.65), 0.5),
        "gravel": mat("gravel", (0.55, 0.53, 0.5), 0.95),
        "coping": mat("coping", (0.64, 0.62, 0.56), 0.85),
        "plaster": mat("plaster_white", (0.85, 0.85, 0.83), 0.8),
        "brick": mat("brick", (0.42, 0.22, 0.16), 0.9),
        "train": mat("train_red", (0.72, 0.07, 0.06), 0.45, 0.3),
        "ballast": mat("ballast", (0.36, 0.33, 0.3), 0.95),
    }
    root = empty("Observatory")

    # Building below the roof (golden perforated facade), the gravel roof and, at its +y end,
    # the raised dome terrace (photos 2026-10: terrace with railing, the golden stair house with
    # its door towards the terrace, a ventilation box in front, lightning masts with guy wires).
    # (Panels and windows of the facade are a texture made in Godot, ObservatoryScene.)
    x0, x1, y0, y1 = BUILDING
    h = 14.0 + ROOF_Z
    building = box("Building", (x1 - x0, y1 - y0, h), ((x0 + x1) / 2, (y0 + y1) / 2, -14.0 + h / 2), M["gold"], root)
    rooftop = box("RoofTop", (x1 - x0 - 0.2, y1 - y0 - 0.2, 0.05), ((x0 + x1) / 2, (y0 + y1) / 2, ROOF_Z + 0.025), M["gravel"], root)
    # Inner courtyard: its walls show the same facade (with windows) seen from the roof.
    cx0, cx1, cy0, cy1 = COURTYARD
    for target in (building, rooftop):
        boolean(target, box("CourtCut", (cx1 - cx0, cy1 - cy0, 16), ((cx0 + cx1) / 2, (cy0 + cy1) / 2, -6.0), M["gold"]))
    box("CourtFloor", (cx1 - cx0, cy1 - cy0, 0.06), ((cx0 + cx1) / 2, (cy0 + cy1) / 2, -13.97), M["pavement"], root)
    for name, sx, sy, px, py in (("CourtCopN", cx1 - cx0 + 1, 0.5, (cx0 + cx1) / 2, cy1 + 0.25), ("CourtCopS", cx1 - cx0 + 1, 0.5, (cx0 + cx1) / 2, cy0 - 0.25),
                                 ("CourtCopW", 0.5, cy1 - cy0, cx0 - 0.25, (cy0 + cy1) / 2), ("CourtCopE", 0.5, cy1 - cy0, cx1 + 0.25, (cy0 + cy1) / 2)):
        box(name, (sx, sy, 0.6), (px, py, ROOF_Z + 0.3), M["coping"], root)
    for name, sx, sy, cx, cy in (("CopingN", x1 - x0, 0.5, (x0 + x1) / 2, y1 - 0.25), ("CopingS", x1 - x0, 0.5, (x0 + x1) / 2, y0 + 0.25),
                                 ("CopingW", 0.5, y1 - y0, x0 + 0.25, (y0 + y1) / 2), ("CopingE", 0.5, y1 - y0, x1 - 0.25, (y0 + y1) / 2)):
        box(name, (sx, sy, 0.6), (cx, cy, ROOF_Z + 0.3), M["coping"], root)
    box("Walkway", (76, 0.7, 0.04), (48, -3, ROOF_Z + 0.07), M["pavement"], root)
    # Terrace: around the dome and up to the stair house (L-shaped).
    # (Stair house 1.2 m clear of the dome: the open shutter flap reaches out about 3.7 m.)
    box("Terrace", (13.1, 16.1, -ROOF_Z), (-2.05, -0.45, ROOF_Z / 2), M["concrete"], root)
    box("TerraceB", (4.2, 8.6, -ROOF_Z), (6.6, 3.3, ROOF_Z / 2), M["concrete"], root)
    railing("Rail", [(4.5, -8.3), (-8.3, -8.3), (-8.3, 7.0), (8.5, 7.0), (8.5, -0.9)], M["galv"], root)
    # Stair house: a large block of plain golden panels, door towards the terrace.
    box("StairHouse", (4.0, 8.5, 3.7), (6.5, -5.25, ROOF_Z + 1.85), M["stair"], root)
    box("StairDoor", (0.06, 1.05, 2.15), (4.48, -2.4, 1.08), M["dark"], root)
    cyl("StairLampHousing", 0.13, 0.06, (4.45, -1.6, 2.35), M["paint"], root, rot=(0, math.pi / 2, 0), verts=16)
    box("StairAlarm", (0.04, 0.08, 0.08), (4.47, -0.9, 2.4), M["lamp"], root)
    # Ventilation box in front of the terrace, skylights and a cooling unit on the gravel.
    box("VentBox", (4.6, 1.0, 1.1), (-1.6, -9.3, ROOF_Z + 0.6), M["galv"], root)
    cyl("VentDuct", 0.48, 1.4, (-1.6, -9.3, ROOF_Z + 0.6), M["galv"], root, rot=(0, math.pi / 2, 0), verts=24)
    # Skylights: a row from north to south on the east wing, one from east to west on the
    # northern part between the courtyard and the north facade.
    lights_ns = [(x, -26.0) for x in (16, 26, 36, 46, 56)]
    lights_ew = [(78.0, y) for y in (-26, -19, -12, -5, 2)]
    for k, (x, y) in enumerate(lights_ns + lights_ew):
        box(f"SkylightBase{k}", (1.5, 1.5, 0.35), (x, y, ROOF_Z + 0.2), M["concrete"], root)
        bpy.ops.mesh.primitive_uv_sphere_add(radius=0.68, segments=16, ring_count=8, location=(x, y, ROOF_Z + 0.37))
        sky = bpy.context.active_object
        sky.name = f"Skylight{k}"
        sky.scale = (1, 1, 0.35)
        link(assign(sky, M["paint"]), root)
    box("CoolingUnit", (3.2, 1.7, 1.0), (14.0, -14.0, ROOF_Z + 1.0), M["cabinet"], root)
    for k in range(4):
        cyl(f"CoolingLeg{k}", 0.05, 0.5, (12.6 + 2.8 * (k % 2), -14.7 + 1.4 * (k // 2), ROOF_Z + 0.25), M["galv"], root, verts=6)
    # Lightning masts with guy wires on tripod feet, a weather box at the railing.
    for name, x, y in (("MastA", -5.5, 3.5), ("MastB", 5.9, 2.6), ("MastC", -7.4, -5.8)):
        rod(name, (x, y, 0), (x, y, 6.5), 0.025, M["galv"], root)
        for ang in (0, 120, 240):
            dx, dy = math.cos(math.radians(ang)) * 1.4, math.sin(math.radians(ang)) * 1.4
            rod(f"{name}_wire{ang}", (x, y, 3.2), (x + dx, y + dy, 0.0), 0.006, M["galv"], root, verts=4)
            rod(f"{name}_leg{ang}", (x, y, 0.4), (x + dx * 0.5, y + dy * 0.5, 0.02), 0.02, M["galv"], root, verts=6)
        cyl(f"{name}_foot", 0.22, 0.3, (x, y, 0.15), M["concrete"], root, verts=12)

    # Dome base (open cylinder with door, a flared foot ring) and interior floor.
    base = cyl("DomeBase", BASE_R, BASE_H, (0, 0, BASE_H / 2), M["paint"], root, verts=96)
    inner = cyl("BaseInner", BASE_R - 0.06, BASE_H + 0.2, (0, 0, BASE_H / 2), M["paint"], verts=96)
    boolean(base, inner)
    door_cut = box("DoorCut", (0.9, 0.5, 1.9), (0.0, -BASE_R, 0.95 + 0.05), M["paint"])
    boolean(base, door_cut)
    split_sides(base, "DomeWallInner", "DomeWallOuter", True)
    # Door (towards east) on a hinge at its south edge; Godot swings it open outwards.
    door = empty("DomeDoor", (-0.45, -BASE_R - 0.02, 0.0), root)
    box("Door", (0.9, 0.04, 1.9), (0.45, 0.0, 1.0), M["paint"], door)
    for k, dy in enumerate((-0.04, 0.04)):
        box(f"DoorHandle{k}", (0.14, 0.04, 0.03), (0.75, dy, 1.0), M["steel"], door)
    foot = cyl("BaseFoot", BASE_R + 0.07, 0.12, (0, 0, 0.06), M["paint"], root, verts=96)
    boolean(foot, cyl("BaseFootHole", BASE_R - 0.05, 0.3, (0, 0, 0.06), M["paint"], verts=96))
    boolean(foot, box("FootDoorCut", (0.9, 0.6, 0.4), (0.0, -BASE_R, 0.06), M["paint"]))
    cyl("Floor", BASE_R - 0.06, 0.04, (0, 0, 0.02), M["wood"], root, verts=96)
    # Inside: the ring ledge with the dome drive boxes, a rail around the wall, red lamps.
    ledge = cyl("Ledge", BASE_R - 0.02, 0.06, (0, 0, BASE_H - 0.05), M["interior"], root, verts=96)
    boolean(ledge, cyl("LedgeHole", BASE_R - 0.32, 0.2, (0, 0, BASE_H - 0.05), M["interior"], verts=96))
    for i, ang in enumerate((25, 145, 265)):
        a = math.radians(ang)
        box(f"DriveBox{i}", (0.42, 0.28, 0.3), (math.cos(a) * (BASE_R - 0.2), math.sin(a) * (BASE_R - 0.2), BASE_H + 0.12),
            M["cabinet"], root, rot=(0, 0, a + math.pi / 2))
    rail = cyl("WallRail", BASE_R - 0.07, 0.05, (0, 0, 1.75), M["interior"], root, verts=96)
    boolean(rail, cyl("WallRailHole", BASE_R - 0.12, 0.2, (0, 0, 1.75), M["interior"], verts=96))
    boolean(rail, box("RailDoorCut", (1.0, 0.6, 0.4), (0.0, -BASE_R, 1.75), M["interior"]))
    for i, ang in enumerate((40, 130, 220, 310)):
        x, y = math.cos(math.radians(ang)) * (BASE_R - 0.1), math.sin(math.radians(ang)) * (BASE_R - 0.1)
        cyl(f"RedLamp{i}", 0.06, 0.12, (x * 0.97, y * 0.97, 1.85), M["lamp"], root, verts=12)
    # Furniture (photos 2026-10), going round from the door (-y), right of it seen from inside:
    # electrical cabinet and inverter on the wall, desk with the observatory management box
    # above it, two chairs, the black tool trolley, the tall cabinet (west wall) with the
    # platform ladder in front, the desk with the white flat-field box (north side).
    # Angles: 0 = north, 90 = west, -90 = east (the door), 180 = south.
    (x, y), rz = at_wall(-114, 0.22, 0.0)
    box("ElectricCabinet", (0.55, 0.22, 0.75), (x, y, 1.3), M["cabinet"], root, rot=(0, 0, rz))
    (x, y), rz = at_wall(-128, 0.14, 0.0)
    box("Inverter", (0.3, 0.14, 0.45), (x, y, 1.35), M["blue"], root, rot=(0, 0, rz))
    desk("OmsDesk", -158, 1.2, M, root)
    (x, y), rz = at_wall(-156, 0.3, 0.0)
    box("ManagementBox", (0.7, 0.3, 0.55), (x, y, 1.25), M["steel"], root, rot=(0, 0, rz))
    for k, ang in enumerate((163, 176)):
        (x, y), rz = at_wall(ang, 0.45, 0.25)
        box(f"ChairSeat{k}", (0.45, 0.42, 0.04), (x, y, 0.45), M["steel"], root, rot=(0, 0, rz))
        o = Vector((-math.cos(math.radians(ang)), -math.sin(math.radians(ang)), 0)) * -0.2
        box(f"ChairBack{k}", (0.45, 0.03, 0.38), (x + o.x, y + o.y, 0.7), M["steel"], root, rot=(0, 0, rz))
        for j in range(4):
            jx, jy = (0.19 if j % 2 else -0.19), (0.17 if j // 2 else -0.17)
            px = x + jx * math.cos(rz) - jy * math.sin(rz)
            py = y + jx * math.sin(rz) + jy * math.cos(rz)
            rod(f"ChairLeg{k}_{j}", (px, py, 0.0), (px, py, 0.44), 0.012, M["steel"], root, verts=6)
    (x, y), rz = at_wall(146, 0.45)
    box("ToolTrolley", (0.55, 0.45, 0.95), (x, y, 0.5), M["black"], root, rot=(0, 0, rz))
    (x, y), rz = at_wall(90, 0.5, 0.02)          # west wall
    box("TallCabinet", (0.95, 0.5, 1.95), (x, y, 0.975), M["cabinet"], root, rot=(0, 0, rz))
    # Platform ladder in front of the cabinet: platform, two steps, handrails (aluminium).
    a = math.radians(72)
    out = Vector((math.cos(a), math.sin(a), 0))
    side = Vector((-out.y, out.x, 0))
    c = out * 1.5
    box("LadderPlatform", (0.55, 0.5, 0.04), (c.x, c.y, 0.8), M["galv"], root, rot=(0, 0, a + math.pi / 2))
    for k, z in enumerate((0.54, 0.27)):           # upper step next to the platform
        p = c - out * (0.37 + 0.24 * k)
        box(f"LadderStep{k}", (0.5, 0.22, 0.03), (p.x, p.y, z), M["galv"], root, rot=(0, 0, a + math.pi / 2))
    for sgn in (-1, 1):
        s0 = side * (0.27 * sgn)
        back, front = c + out * 0.25 + s0, c - out * 0.85 + s0
        rod(f"LadderStile{sgn}", (front.x, front.y, 0.0), (c.x - out.x * 0.25 + s0.x, c.y - out.y * 0.25 + s0.y, 0.8), 0.02, M["galv"], root)
        rod(f"LadderLegB{sgn}", (back.x, back.y, 0.0), (back.x, back.y, 1.75), 0.02, M["galv"], root)
        top_front = c - out * 0.2 + s0
        rod(f"LadderRailF{sgn}", (top_front.x, top_front.y, 0.8), (top_front.x, top_front.y, 1.75), 0.02, M["galv"], root)
        rod(f"LadderRailT{sgn}", (top_front.x, top_front.y, 1.75), (back.x, back.y, 1.75), 0.02, M["galv"], root)
        rod(f"LadderRailM{sgn}", (top_front.x, top_front.y, 1.3), (back.x, back.y, 1.3), 0.015, M["galv"], root)
    (x, y), rz = desk("FlatDesk", 0, 1.3, M, root)   # north side
    bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=1, radius=0.42, location=(x, y, 0.84 + 0.26))
    ff = bpy.context.active_object
    ff.name = "FlatfieldBox"
    ff.scale = (1.0, 0.8, 0.62)
    ff.rotation_euler = (0, 0, rz)
    link(assign(ff, M["cabinet"]), root)

    # Rotating dome with slit and shutter. Slit faces +Y (towards the telescope's south side
    # is handled by turning the whole DomeRotator in Godot).
    rot = empty("DomeRotator", (0, 0, BASE_H), root)
    shell = hemisphere_shell("DomeShell", DOME_R, 0.05, M["dome"])
    slit = box("SlitCut", (SLIT_W, 3.2, 3.2), (0, 1.5, 1.6 + 0.35), M["dome"])
    boolean(shell, slit)
    for part in split_sides(shell, "DomeShellInner", "DomeShellOuter", False):
        part.location = (0, 0, 0)
        part.parent = rot
    # Shutter in two parts like the Baader dome: the upper part slides over the top to the
    # back (pivot "Shutter" at the centre), the lower flap swings out at its lower edge
    # ("ShutterFlap"). The upper part ends in a hood just beyond the zenith.
    split = 1.3   # height (local z) where upper part and flap meet
    upper = hemisphere_shell("ShutterShell", DOME_R + 0.06, 0.05, M["dome"])
    boolean(upper, box("ShutterKeep", (SLIT_W + 0.24, 3.4, 3.4 - split), (0, 1.55, split + (3.4 - split) / 2), M["dome"]), "INTERSECT")
    hood = hemisphere_shell("ShutterHood", DOME_R + 0.14, 0.1, M["dome"])
    boolean(hood, box("HoodKeep", (SLIT_W + 0.34, 0.5, 0.5), (0, -0.05, DOME_R), M["dome"]), "INTERSECT")
    shutter_pivot = empty("Shutter", (0, 0, 0), rot)
    for o in (upper, hood):
        o.parent = shutter_pivot
    flap = hemisphere_shell("ShutterFlapShell", DOME_R + 0.06, 0.05, M["dome"])
    boolean(flap, box("FlapKeep", (SLIT_W + 0.24, 3.4, split - 0.3), (0, 1.55, 0.3 + (split - 0.3) / 2), M["dome"]), "INTERSECT")
    hinge = Vector((0.0, math.sqrt((DOME_R + 0.06) ** 2 - 0.3 ** 2), 0.3))
    flap.data.transform(Matrix.Translation(-hinge))
    flap_pivot = empty("ShutterFlap", tuple(hinge), rot)
    flap.parent = flap_pivot
    flap.location = (0, 0, 0)
    # Ribs on the inside of the dome (not across the slit).
    for k, ang in enumerate((20, 160, 205, 250, 295, 340)):
        a = math.radians(ang)
        rib = hemisphere_shell(f"Rib{k}", DOME_R - 0.05, 0.06, M["interior"])
        boolean(rib, box(f"RibKeep{k}", (3.0, 0.07, 2.3), (math.cos(a) * 1.6, math.sin(a) * 1.6, 1.15), M["interior"], rot=(0, 0, a)), "INTERSECT")
        rib.parent = rot
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

    # Surroundings after photos of the campus (2026-10): across the road (+y) the orange
    # "Stellwerk" with the railway behind it; to the west (-x) a lawn with birches, the corner
    # plaza with ball-shaped maples, a water basin and flag poles, and the black building; far
    # west the white office building with two chimneys; columnar hornbeams along the long
    # facades. Ground level z = -14.
    import random
    rnd = random.Random(7)
    g = -14.0
    for name, (ax0, ax1, ay0, ay1), m in (
            ("PathAround", (x0 - 6, x1 + 6, y0 - 6, y1 + 6), M["pavement"]),
            ("Plaza", (-31, x0 - 6, -19, y1 + 6), M["pavement"]),
            ("Road", (-1500, 1500, 28, 36), M["asphalt"]),
            ("Railway", (-1500, 1500, 57, 69), M["ballast"])):
        box(name, (ax1 - ax0, ay1 - ay0, 0.06), ((ax0 + ax1) / 2, (ay0 + ay1) / 2, g + 0.03), m, root)
    for t, ty in enumerate((60.5, 65.5)):
        for r, dy in enumerate((-0.72, 0.72)):
            box(f"Rail{t}_{r}", (3000, 0.08, 0.16), (0, ty + dy, g + 0.14), M["steel"], root)
    for k, mx in enumerate(range(-1500, 1500, 40)):   # railway from horizon to horizon
        for side, my in enumerate((58.0, 68.0)):
            box(f"Catenary{k}_{side}", (0.35, 0.35, 8.5), (mx, my, g + 4.25), M["galv"], root)
        rod(f"CatenaryBeam{k}", (mx, 58.0, g + 8.2), (mx, 68.0, g + 8.2), 0.06, M["galv"], root, verts=6)
    for t, ty in enumerate((60.5, 65.5)):
        rod(f"Contact{t}", (-1500, ty, g + 6.3), (1500, ty, g + 6.3), 0.015, M["black"], root, verts=4)
    # The red regional train standing at the station.
    box("Train", (64, 2.9, 3.4), (-6, 60.5, g + 2.3), M["train"], root)
    box("TrainWindows", (64.1, 2.95, 0.9), (-6, 60.5, g + 2.7), M["glass"], root)
    box("TrainRoof", (63, 2.6, 0.35), (-6, 60.5, g + 4.15), M["galv"], root)
    # The Stellwerk: orange, three storeys, red tiled hip roof, windows towards the campus.
    sx, sy = -14.0, 46.0
    box("StellwerkHouse", (22, 11, 9.5), (sx, sy, g + 4.75), M["orange"], root)
    hip_roof("StellwerkRoof", 23, 12, 4.8, (sx, sy, g + 9.5), M["roof"], root)
    for fl in range(3):
        for k in range(9):
            box(f"StellwerkWin{fl}_{k}", (1.1, 0.1, 1.4), (sx - 9.6 + k * 2.4, sy - 5.52, g + 1.9 + fl * 3.0), M["glass"], root)
    # Houses with red roofs beyond the railway.
    for k, (hx, hy, hw) in enumerate(((-50, 85, 10), (-22, 83, 9), (18, 87, 12), (45, 81, 9), (70, 89, 11))):
        box(f"House{k}", (hw, 8, 6.5), (hx, hy, g + 3.25), M["plaster"], root)
        hip_roof(f"HouseRoof{k}", hw + 1, 9, 3.6, (hx, hy, g + 6.5), M["roof"], root)
    # The black building with big framed windows, facing the plaza and our building.
    box("BlackBuilding", (26, 52, 18), (-66, -16, g + 9), M["dark"], root)
    for k, (wy, wz, ww, wh) in enumerate(((-30, 9, 12, 4), (-8, 6, 7, 3), (4, 12.5, 8, 4))):
        box(f"BlackFrame{k}", (0.5, ww + 0.6, wh + 0.6), (-52.8, wy, g + wz), M["coping"], root)
        box(f"BlackGlass{k}", (0.6, ww, wh), (-52.8, wy, g + wz), M["glass"], root)
    # The white office building far west with window bands, and two brick chimneys.
    box("OfficeBuilding", (30, 55, 17), (-115, -75, g + 8.5), M["plaster"], root)
    for k in range(4):
        box(f"OfficeBand{k}", (30.2, 55.2, 1.3), (-115, -75, g + 3.5 + k * 3.6), M["glass"], root)
    # Plaza beside the building: water basin along it, benches; street lights around.
    box("BasinRim", (4.6, 12.6, 0.45), (-23, -3, g + 0.22), M["concrete"], root)
    box("Water", (4, 12, 0.1), (-23, -3, g + 0.4), M["water"], root)
    for k, (bx, by) in enumerate(((-28, -12), (-28, 6), (-18, -12), (-18, 6))):
        cyl(f"Bench{k}", 0.25, 1.8, (bx, by, g + 0.25), M["concrete"], root, rot=(math.pi / 2, 0, 0), verts=6)
    lights = ((0, y0 - 4), (30, y0 - 4), (60, y0 - 4), (20, y1 + 5), (50, y1 + 5), (80, y1 + 5),
              (-30, -17), (-18, 12), (x1 + 4, -10), (x0 - 4, -25))
    for k, (lx, ly) in enumerate(lights):
        cyl(f"LampPole{k}", 0.07, 4.2, (lx, ly, g + 2.1), M["galv"], root, verts=8)
        cyl(f"LampHead{k}", 0.35, 0.25, (lx, ly, g + 4.3), M["lamp_head"], root, verts=16)
        empty(f"StreetLight{k}", (lx, ly, g + 4.0), root)

    crowns = [M["tree"], M["tree_light"], M["tree_dark"]]
    planted = []

    def plant(name, kind, x, y, h, crown=None, bark=None):
        if in_flight_path((x, y, g + h * 0.6), (h * 0.38, h * 0.38, h * 0.55)):
            return
        v = Vector((x, y)) - FLIGHT[0].xy                     # keep the start view open
        if v.length < 35.0 and v.angle(-FLIGHT[0].xy, 0.0) < math.radians(40):
            return
        tree(name, kind, (x, y, g), h, rnd, rnd.random() * 100.0, crown or rnd.choice(crowns), M, root, bark)
        planted.append((x, y))

    k = 0
    for x in range(int(x0) + 4, int(x1), 7):      # hornbeams along both long facades
        for y in (y0 - 3.5, y1 + 3.5):
            plant(f"Hornbeam{k}", "column", x, y + rnd.uniform(-0.3, 0.3), rnd.uniform(10.5, 13.0))
            k += 1
    for k, (bx, by) in enumerate(((-29, -15), (-29, -4), (-29, 7), (-17, -16), (-17, 12), (-23, 12))):
        plant(f"Maple{k}", "ball", bx, by, rnd.uniform(4.5, 5.5))
    for k, (bx, by) in enumerate(((14, -30), (18, -52))):    # in the courtyard
        plant(f"CourtTree{k}", "ball", bx, by, rnd.uniform(5.0, 6.0))
    for k in range(10):                             # birches on the lawn towards the black building
        plant(f"Birch{k}", "birch", rnd.uniform(-48, -34), rnd.uniform(-40, -8), rnd.uniform(12, 15), M["tree_light"], M["bark_birch"])
    for k in range(6):                              # trees along the road and by the Stellwerk
        plant(f"RoadTree{k}", "broad", rnd.uniform(-60, 60), rnd.choice((24.0, 39.5)), rnd.uniform(9, 13))

    def free(x, y, pad):
        if x0 - pad - 6 < x < x1 + pad + 6 and y0 - pad - 6 < y < y1 + pad + 6:
            return False
        for bx0, bx1, by0, by1 in ((-80, -52, -42, 10), (-130, -100, -103, -47), (-26, -2, 40, 52),
                                   (-1500, 1500, 26, 71), (-33, -13, -21, 16)):
            if bx0 - pad < x < bx1 + pad and by0 - pad < y < by1 + pad:
                return False
        return all((x - px) ** 2 + (y - py) ** 2 > 36 for px, py in planted)

    n = 0
    while n < 80:
        ang = rnd.uniform(0, math.tau)
        d = rnd.uniform(25, 150)
        x, y = math.cos(ang) * d + 10, math.sin(ang) * d - 30
        if not free(x, y, 3):
            continue
        kind = rnd.choices(["broad", "column", "pine"], weights=(6, 1, 3))[0]
        plant(f"Tree{n}", kind, x, y, rnd.uniform(10, 18))
        n += 1
    for i, (x, y, rr) in enumerate(((-170, 230, 90), (60, 230, 120), (240, -170, 100))):   # clear of the railway
        bpy.ops.mesh.primitive_uv_sphere_add(radius=rr, location=(x, y, -14 - rr * 0.82))
        hl = bpy.context.active_object
        hl.name = f"Hill{i}"
        hl.scale = (1.6, 1.0, 1.0)
        link(assign(hl, M["hill"]), root)
    box("Ground", (4000, 4000, 1), (0, 0, -14.5), M["grass"], root)
    join_static(root)


def join_static(root):
    """All parts that never move into two objects: "DomeInterior" (inner side of the dome
    base, floor, pier, furniture: red light only) and "Campus" (everything else, including
    the outer side of the base: moon and street lights); a few hundred objects cost a draw
    call each, every frame. Moving parts (dome, shutter, telescope, door) and the red lamps
    keep their own objects."""
    inside, outside = [], []
    for o in list(root.children):
        if o.type != "MESH" or o.name.startswith("RedLamp"):
            continue
        bb = [o.matrix_world @ Vector(c) for c in o.bound_box]
        far = max(max(abs(v.x), abs(v.y)) for v in bb)   # box within the dome's square
        if o.name.startswith("DomeWallOuter"):
            outside.append(o)
        elif far < 2.8 and max(v.z for v in bb) < 5.6 and min(v.z for v in bb) > -0.5 and not o.name.startswith("BaseFoot"):
            inside.append(o)
        else:
            outside.append(o)
    for name, group in (("DomeInterior", inside), ("Campus", outside)):
        bpy.ops.object.select_all(action="DESELECT")
        for o in group:
            o.select_set(True)
        bpy.context.view_layer.objects.active = group[0]
        bpy.ops.object.join()
        bpy.context.active_object.name = name


def export():
    OUT.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.export_scene.gltf(filepath=str(OUT), export_format="GLB", export_apply=True,
                              export_yup=True, export_materials="EXPORT")
    print("exported", OUT)


if __name__ == "__main__":
    reset()
    build()
    export()
