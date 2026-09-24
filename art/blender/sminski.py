# Smooth jelly Sminski, built to the same proportions as the in-game rig
# (Models.buildSminski): feet on z=0, torso centre z=1.5, head centre z~3.0.
import bpy, math, colorsys
from mathutils import Vector, Euler, Matrix
import kit, shapes

# character palette (mirrors Config.Characters)
CHARS = {
    "Glow": dict(body=(218, 238, 186), glow=(190, 255, 150)),
    "Blush": dict(body=(250, 214, 214), glow=(255, 180, 190)),
    "Sky": dict(body=(205, 228, 250), glow=(170, 215, 255)),
    "Lemon": dict(body=(250, 240, 180), glow=(255, 240, 150)),
    "Lavender": dict(body=(222, 208, 245), glow=(200, 170, 255)),
    "Mint": dict(body=(190, 240, 222), glow=(150, 255, 215)),
    "Peach": dict(body=(252, 220, 190), glow=(255, 200, 150)),
    "Ghost": dict(body=(238, 246, 255), glow=(190, 220, 255), ghost=True),
    "Night": dict(body=(150, 235, 205), glow=(120, 255, 220), neon=True),
    "Galaxy": dict(body=(120, 105, 190), glow=(170, 140, 255), neon=True),
    "Secret": dict(body=(245, 205, 90), glow=(255, 220, 120), metal=True),
}

FACE = kit.srgb(40, 70, 36)


def punchy(rgb, sat=1.9, val=0.96):
    """Key-art colour: the same hue, much more saturated (glowing candy jelly)."""
    h, s, v = colorsys.rgb_to_hsv(*[c / 255 for c in rgb])
    r, g, b = colorsys.hsv_to_rgb(h, min(1, s * sat), min(1, v * val))
    return (r * 255, g * 255, b * 255)


def jelly_material(cid):
    d = CHARS[cid]
    m = bpy.data.materials.new("Jelly_" + cid)
    m.use_nodes = True
    p = m.node_tree.nodes["Principled BSDF"]
    body = kit.srgb(*punchy(d["body"], 2.6 if not d.get("ghost") else 1.2, 0.97))
    glow = kit.srgb(*punchy(d["glow"], 1.6))
    # saturate the body a touch so it reads as glowing jelly, not plastic
    p.inputs["Base Color"].default_value = body
    p.inputs["Roughness"].default_value = 0.16
    p.inputs["Coat Weight"].default_value = 1.0
    p.inputs["Coat Roughness"].default_value = 0.04
    p.inputs["Emission Color"].default_value = glow
    if d.get("metal"):
        p.inputs["Metallic"].default_value = 1.0
        p.inputs["Roughness"].default_value = 0.22
        p.inputs["Emission Strength"].default_value = 0.08
        return m
    p.inputs["Subsurface Weight"].default_value = 1.0
    p.inputs["Subsurface Radius"].default_value = (0.8, 1.2, 0.5)
    p.inputs["Subsurface Scale"].default_value = 0.5
    p.inputs["Transmission Weight"].default_value = 0.35 if d.get("ghost") else 0.12
    p.inputs["Emission Strength"].default_value = 1.1 if d.get("neon") else 0.7
    if d.get("ghost"):
        p.inputs["Alpha"].default_value = 0.72
    if cid == "Galaxy":
        # starry specks glowing through the jelly
        nt = m.node_tree
        vor = nt.nodes.new("ShaderNodeTexVoronoi")
        vor.inputs["Scale"].default_value = 16
        mr = nt.nodes.new("ShaderNodeMapRange")
        mr.inputs["From Min"].default_value = 0.0
        mr.inputs["From Max"].default_value = 0.07
        mr.inputs["To Min"].default_value = 1.0
        mr.inputs["To Max"].default_value = 0.0
        mix = nt.nodes.new("ShaderNodeMix")
        mix.data_type = "RGBA"
        mix.inputs["A"].default_value = glow
        mix.inputs["B"].default_value = (1, 1, 1, 1)
        nt.links.new(vor.outputs["Distance"], mr.inputs["Value"])
        nt.links.new(mr.outputs["Result"], mix.inputs["Factor"])
        nt.links.new(mix.outputs["Result"], p.inputs["Emission Color"])
        p.inputs["Emission Strength"].default_value = 1.6
    return m


def _mesh_from(objs, name, voxel=0.028, smooth_iter=12):
    """Join overlapping primitives into one blobby surface (voxel remesh + smooth)."""
    bpy.ops.object.select_all(action="DESELECT")
    for o in objs:
        o.select_set(True)
        bpy.context.view_layer.objects.active = o
        for m in list(o.modifiers):
            bpy.ops.object.modifier_apply(modifier=m.name)
    bpy.context.view_layer.objects.active = objs[0]
    bpy.ops.object.join()
    o = bpy.context.view_layer.objects.active
    o.name = name
    rm = o.modifiers.new("Remesh", "REMESH")
    rm.mode = "VOXEL"
    rm.voxel_size = voxel
    sm = o.modifiers.new("Smooth", "CORRECTIVE_SMOOTH")
    sm.iterations = smooth_iter
    sm.use_only_smooth = True
    sm.smooth_type = "LENGTH_WEIGHTED"
    for p in o.data.polygons:
        p.use_smooth = True
    return o


def torso_parts():
    # soft column: rounded shoulders -> slight waist -> rounded hips
    prof = [(0.001, 0.62), (0.34, 0.64), (0.55, 0.74), (0.66, 0.95), (0.66, 1.2), (0.6, 1.5),
            (0.57, 1.8), (0.62, 2.02), (0.6, 2.2), (0.46, 2.36), (0.26, 2.46), (0.001, 2.5)]
    t = kit.lathe("Torso", prof, steps=48)
    t.scale = (1, 0.86, 1)
    return [t]


def arm_parts(side, swing=0.0, spread=0.12):
    """Shoulder ball + sausage arm + mitten hand, hanging from the shoulder."""
    sx = -1 if side == "L" else 1
    sh = Vector((0.62 * sx, 0.04, 2.08))
    rot = Euler((swing, -sx * spread, 0), "XYZ").to_matrix()  # rotate about the shoulder
    parts = []
    parts.append(shapes.capsule("ShoulderBall" + side, 0.23, 0.0, seg=24, rings=8))
    parts[-1].location = sh + rot @ Vector((0, 0, -0.05))
    arm = shapes.capsule("Arm" + side, 0.2, 0.72, seg=24, rings=8)
    arm.location = sh + rot @ Vector((0, 0, -0.5))
    arm.rotation_euler = rot.to_euler()
    parts.append(arm)
    hand = shapes.capsule("Hand" + side, 0.235, 0.0, seg=24, rings=8)
    hand.location = sh + rot @ Vector((0, 0.03, -1.02))
    parts.append(hand)
    return parts


def leg_parts(side, swing=0.0):
    sx = -1 if side == "L" else 1
    hip = Vector((0.3 * sx, 0, 0.82))
    rot = Euler((swing, 0, 0), "XYZ").to_matrix()
    leg = shapes.capsule("Leg" + side, 0.3, 0.3, seg=24, rings=8)
    leg.scale = (0.97, 1.03, 1)
    leg.location = hip + rot @ Vector((0, 0.02, -0.4))
    leg.rotation_euler = rot.to_euler()
    return [leg]


def head_obj():
    bpy.ops.mesh.primitive_uv_sphere_add(segments=64, ring_count=32, radius=0.8, location=(0, 0, 3.02))
    h = bpy.context.active_object
    h.name = "Head"
    for p in h.data.polygons:
        p.use_smooth = True
    return h


def face(head_center, yaw=0.0, brows=True, mood="calm"):
    """Dot eyes with a shine, little mouth, optional determined eyebrows."""
    objs = []
    fm = kit.mat("Face", FACE, rough=0.25, coat=0.8)
    shine = kit.mat("Shine", kit.srgb(255, 255, 255), rough=0.2, emit=kit.srgb(255, 255, 255), emit_strength=2.0)
    R = 0.8

    def on_head(x, z, depth=0.0):
        # point on the head sphere facing -Y (camera side), at local x/z offsets
        y = -math.sqrt(max(0.0, R * R - x * x - z * z)) - depth
        return Vector(head_center) + Vector((x, y, z))

    for sx in (-1, 1):
        bpy.ops.mesh.primitive_uv_sphere_add(segments=24, ring_count=12, radius=0.085, location=on_head(0.27 * sx, -0.02, -0.01))
        e = bpy.context.active_object
        e.scale = (1, 0.6, 1.25)
        kit.assign(e, fm)
        objs.append(e)
        bpy.ops.mesh.primitive_uv_sphere_add(segments=12, ring_count=6, radius=0.026, location=on_head(0.27 * sx + 0.03, 0.035, 0.03))
        s = bpy.context.active_object
        kit.assign(s, shine)
        objs.append(s)
        if brows:
            b = shapes.capsule("Brow", 0.028, 0.16, seg=12, rings=4)
            b.location = on_head(0.26 * sx, 0.2, 0.0)
            tilt = 0.42 if mood == "determined" else -0.12
            b.rotation_euler = (0, math.pi / 2 - sx * tilt, 0)
            kit.assign(b, fm)
            objs.append(b)
    # mouth: a small curved smile
    bpy.ops.mesh.primitive_torus_add(major_radius=0.1, minor_radius=0.022, major_segments=24, minor_segments=8,
                                     location=on_head(0.0, -0.26, -0.005))
    m = bpy.context.active_object
    m.rotation_euler = (math.pi / 2, 0, 0)
    # keep the lower half only -> a smile
    bpy.ops.object.mode_set(mode="EDIT")
    import bmesh
    bm = bmesh.from_edit_mesh(m.data)
    for v in [v for v in bm.verts if v.co.y > -0.02]:  # local y after rotation = world up
        bm.verts.remove(v)
    bmesh.update_edit_mesh(m.data)
    bpy.ops.object.mode_set(mode="OBJECT")
    if mood == "determined":
        m.scale = (0.9, 1, -0.6)
    kit.assign(m, fm)
    objs.append(m)
    for o in objs:
        o.rotation_euler.z += 0
    return objs


POSES = {
    "idle": dict(armL=(0.0, 0.12), armR=(0.0, 0.12), legL=0.0, legR=0.0, lean=0.0),
    "run": dict(armL=(0.9, 0.2), armR=(-0.9, 0.2), legL=-0.7, legR=0.65, lean=0.14),
    "cheer": dict(armL=(0.0, 2.6), armR=(0.0, 2.6), legL=0.0, legR=0.0, lean=0.0),
    "wave": dict(armL=(0.0, 0.14), armR=(0.0, 2.5), legL=0.0, legR=0.0, lean=0.0),
}


def build(cid="Glow", pose="idle", brows=True, mood="calm", name="Sminski"):
    """Full character as one blended jelly body + head + face. Returns the root empty."""
    P = POSES[pose]
    parts = torso_parts()
    parts += arm_parts("L", P["armL"][0], P["armL"][1])
    parts += arm_parts("R", P["armR"][0], P["armR"][1])
    parts += leg_parts("L", P["legL"])
    parts += leg_parts("R", P["legR"])
    body = _mesh_from(parts, name + "Body")
    head = head_obj()
    jm = jelly_material(cid)
    kit.assign(body, jm)
    kit.assign(head, jm)
    feats = face((0, 0, 3.02), brows=brows, mood=mood)
    root = bpy.data.objects.new(name, None)
    bpy.context.scene.collection.objects.link(root)
    for o in [body, head] + feats:
        o.parent = root
    root.rotation_euler = (P["lean"], 0, 0)
    # inner glow
    ld = bpy.data.lights.new(name + "Glow", "POINT")
    ld.energy = 25 if not CHARS[cid].get("metal") else 5
    ld.color = tuple(kit.srgb(*CHARS[cid]["glow"])[:3])
    ld.shadow_soft_size = 0.6
    lo = bpy.data.objects.new(name + "Glow", ld)
    bpy.context.scene.collection.objects.link(lo)
    lo.location = (0, -1.4, 2.2)
    lo.parent = root
    return root
