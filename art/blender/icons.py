# Glossy candy 3D icons for the UI (256px, transparent). Outlines are added in 2D.
#   Blender --background --factory-startup --python icons.py -- [name,name,...]
import sys, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import bpy, bmesh, math, kit, shapes
from mathutils import Vector

argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
ONLY = set(argv[0].split(",")) if argv else None
OUT_DIR = os.path.join(kit.ROOT, "preview", "icons_raw")
os.makedirs(OUT_DIR, exist_ok=True)

C = {
    "gold": (255, 200, 70), "gold2": (255, 226, 130), "coral": (255, 120, 105), "mint": (120, 220, 150),
    "lime": (170, 235, 90), "sky": (110, 180, 245), "lav": (175, 145, 245), "pink": (255, 150, 190),
    "white": (250, 248, 240), "ink": (60, 55, 80), "brown": (190, 120, 80), "grey": (170, 170, 190),
    "red": (240, 80, 80), "cream": (255, 240, 205),
}


def candy(name, rgb, rough=0.28, metal=0.0, emit=0.0):
    return kit.mat(name, kit.srgb(*rgb), rough=rough, metal=metal, coat=1.0,
                   emit=kit.srgb(*rgb) if emit else None, emit_strength=emit)


def puffy2d(name, pts, depth=0.3, bevel=0.12, mat=None, subsurf=2):
    """Extrude a 2D outline (XY) along Z with a fat rounded bevel -> soft 'toy' shape."""
    bm = bmesh.new()
    vs = [bm.verts.new((x, y, -depth / 2)) for x, y in pts]
    f = bm.faces.new(vs)
    ext = bmesh.ops.extrude_face_region(bm, geom=[f])
    for v in [e for e in ext["geom"] if isinstance(e, bmesh.types.BMVert)]:
        v.co.z += depth
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    o = kit.new_obj(name, me)
    b = o.modifiers.new("Bevel", "BEVEL")
    b.width = bevel
    b.segments = 6
    b.limit_method = "ANGLE"
    b.angle_limit = math.radians(35)
    b.harden_normals = False
    kit.smooth(o, subsurf)
    if mat:
        kit.assign(o, mat)
    return o


def ring_pts(n, rfn, start=math.pi / 2):
    return [(rfn(i) * math.cos(start + i / n * math.tau), rfn(i) * math.sin(start + i / n * math.tau)) for i in range(n)]


def rounded_rect_pts(w, h, r, n=8):
    pts = []
    for cx, cy, a0 in ((w / 2 - r, h / 2 - r, 0), (-w / 2 + r, h / 2 - r, 90), (-w / 2 + r, -h / 2 + r, 180), (w / 2 - r, -h / 2 + r, 270)):
        for i in range(n + 1):
            a = math.radians(a0 + i * 90 / n)
            pts.append((cx + r * math.cos(a), cy + r * math.sin(a)))
    return pts


def sphere(name, r, loc, mat, seg=48, scale=(1, 1, 1)):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=seg, ring_count=seg // 2, radius=r, location=loc)
    o = bpy.context.active_object
    o.name = name
    o.scale = scale
    for p in o.data.polygons:
        p.use_smooth = True
    kit.assign(o, mat)
    return o


def torus(name, R, r, loc, rot, mat, half=False):
    bpy.ops.mesh.primitive_torus_add(major_radius=R, minor_radius=r, major_segments=64, minor_segments=24, location=loc, rotation=rot)
    o = bpy.context.active_object
    o.name = name
    if half:
        bpy.ops.object.mode_set(mode="EDIT")
        bm = bmesh.from_edit_mesh(o.data)
        for v in [v for v in bm.verts if v.co.y < -0.01]:
            bm.verts.remove(v)
        bmesh.update_edit_mesh(o.data)
        bpy.ops.object.mode_set(mode="OBJECT")
    for p in o.data.polygons:
        p.use_smooth = True
    kit.assign(o, mat)
    return o


def cyl(name, r, depth, loc, mat, rot=(0, 0, 0), bevel=0.06, verts=64):
    bpy.ops.mesh.primitive_cylinder_add(vertices=verts, radius=r, depth=depth, location=loc, rotation=rot)
    o = bpy.context.active_object
    o.name = name
    b = o.modifiers.new("Bevel", "BEVEL")
    b.width = bevel
    b.segments = 5
    b.limit_method = "ANGLE"
    for p in o.data.polygons:
        p.use_smooth = True
    kit.assign(o, mat)
    return o


# ---------------------------------------------------------------------------
# ICON BUILDERS (each builds around the origin, ~2 units tall, facing +Z)
# ---------------------------------------------------------------------------
def i_coin():
    body, star = shapes.build_coin()
    return [body, star]


def i_star():
    pts = ring_pts(10, lambda i: 1.0 if i % 2 == 0 else 0.52)
    return [puffy2d("Star", pts, 0.42, 0.22, candy("Star", C["gold"], 0.25, 0.3))]


def i_trophy():
    gold = candy("Gold", C["gold"], 0.22, 1.0)
    cup = kit.lathe("Cup", [(0.001, -0.05), (0.3, 0.0), (0.62, 0.35), (0.72, 0.8), (0.74, 1.05), (0.66, 1.08), (0.6, 0.85), (0.001, 0.6)], 64)
    kit.smooth(cup, 2)
    kit.assign(cup, gold)
    stem = kit.lathe("Stem", [(0.001, -0.75), (0.5, -0.75), (0.52, -0.62), (0.2, -0.55), (0.14, -0.2), (0.3, 0.02), (0.001, 0.02)], 64)
    kit.smooth(stem, 2)
    kit.assign(stem, gold)
    objs = [cup, stem]
    for sx in (-1, 1):
        objs.append(torus("Handle", 0.3, 0.07, (sx * 0.72, 0, 0.6), (math.pi / 2, 0, 0), gold))
    star = kit.star_prism("TStar", 0.22, 0.1, 0.1)
    star.location = (0, -0.7, 0.62)
    star.rotation_euler = (math.pi / 2, 0, 0)
    kit.smooth(star, 1)
    kit.assign(star, candy("W", C["white"]))
    objs.append(star)
    for o in objs:
        o.rotation_euler.x -= math.pi / 2
        o.location = Vector((o.location.x, o.location.z, -o.location.y))
    return objs


def i_bag():
    body = puffy2d("Bag", [(-0.78, 0.55), (0.78, 0.55), (0.9, -0.95), (-0.9, -0.95)], 0.7, 0.2, candy("Bag", C["coral"]))
    body.location.y = -0.1
    objs = [body]
    for sx in (-1, 1):
        h = torus("Handle", 0.26, 0.07, (sx * 0.34, 0.5, 0.18), (0, 0, 0), candy("H", C["cream"]), half=True)
        objs.append(h)
    star = puffy2d("BagStar", ring_pts(10, lambda i: 0.36 if i % 2 == 0 else 0.18), 0.12, 0.05, candy("W", C["white"]), subsurf=1)
    star.location = (0, -0.3, 0.38)
    objs.append(star)
    return objs


def i_capsule():
    top = candy("Glass", (220, 240, 255), 0.05)
    top.node_tree.nodes["Principled BSDF"].inputs["Transmission Weight"].default_value = 0.9
    bot = candy("CapPink", C["pink"])
    a = sphere("Top", 1.0, (0, 0, 0), top)
    b = sphere("Bottom", 1.01, (0, 0, 0), bot)
    for o, keep_top in ((a, True), (b, False)):
        bpy.context.view_layer.objects.active = o
        bpy.ops.object.mode_set(mode="EDIT")
        bm = bmesh.from_edit_mesh(o.data)
        for v in [v for v in bm.verts if (v.co.y < -0.02) == keep_top]:
            bm.verts.remove(v)
        bmesh.update_edit_mesh(o.data)
        bpy.ops.object.mode_set(mode="OBJECT")
    band = cyl("Band", 1.04, 0.12, (0, 0, 0), candy("Band", C["white"]), rot=(math.pi / 2, 0, 0), bevel=0.04)
    little = sphere("Mini", 0.42, (0, 0.35, 0.1), candy("MiniGlow", C["lime"], emit=0.5))
    return [a, b, band, little]


def i_gear():
    pts = ring_pts(64, lambda i: 1.0 if (i // 4) % 2 == 0 else 0.78)
    g = puffy2d("Gear", pts, 0.45, 0.1, candy("Gear", C["lav"]))
    hole = cyl("Hub", 0.36, 0.6, (0, 0, 0), candy("Hub", C["white"]), bevel=0.1)
    return [g, hole]


def i_chart():
    objs = []
    for i, (h, col) in enumerate(((0.8, C["sky"]), (1.4, C["mint"]), (2.0, C["lav"]))):
        b = puffy2d("Bar", rounded_rect_pts(0.5, h, 0.22), 0.45, 0.14, candy("B%d" % i, col))
        b.location = (-0.68 + i * 0.68, -1.0 + h / 2, 0)
        objs.append(b)
    return objs


def i_paw():
    m = candy("Paw", C["brown"])
    pad = sphere("Pad", 0.6, (0, -0.35, 0), m, scale=(1.15, 0.95, 0.55))
    objs = [pad]
    for x, y, r in ((-0.72, 0.35, 0.28), (-0.28, 0.72, 0.3), (0.28, 0.72, 0.3), (0.72, 0.35, 0.28)):
        objs.append(sphere("Toe", r, (x, y, 0), m, scale=(1, 1.15, 0.6)))
    return objs


def i_house():
    wall = puffy2d("Wall", rounded_rect_pts(1.5, 1.2, 0.2), 0.9, 0.16, candy("Wall", C["cream"]))
    wall.location.y = -0.45
    roof = puffy2d("Roof", [(-1.1, 0.0), (1.1, 0.0), (0, 0.95)], 1.0, 0.2, candy("Roof", C["coral"]))
    roof.location.y = 0.1
    door = puffy2d("Door", rounded_rect_pts(0.42, 0.6, 0.18), 0.2, 0.08, candy("Door", C["lav"]))
    door.location = (0, -0.75, 0.46)
    win = sphere("Win", 0.16, (0.45, -0.3, 0.45), candy("Win", (255, 220, 120), emit=1.5), scale=(1, 1, 0.4))
    return [wall, roof, door, win]


def i_friends():
    objs = []
    for x, col, s in ((-0.62, C["pink"], 0.72), (0.42, C["lime"], 0.92)):
        h = sphere("Head", s, (x, 0.08 if x > 0 else -0.08, -0.35 if x < 0 else 0.1), candy("F", col, emit=0.3))
        objs.append(h)
        for ex in (-0.26, 0.26):
            objs.append(sphere("Eye", 0.11 * s / 0.8, (x + ex * s - (0.12 if x < 0 else 0), h.location.y - 0.12 * s, h.location.z + s * 0.9), candy("E", C["ink"]), seg=16))
    return objs


def i_crown():
    gold = candy("Gold", C["gold"], 0.2, 1.0)
    pts = []
    n = 5
    for i in range(n * 2 + 1):
        x = -1 + i / (n * 2) * 2
        y = 0.75 if i % 2 == 0 else 0.15
        pts.append((x, y))
    pts += [(1.0, -0.55), (-1.0, -0.55)]
    c = puffy2d("Crown", pts, 0.45, 0.12, gold)
    objs = [c]
    for i in range(n + 1):
        x = -1 + i / n * 2
        objs.append(sphere("Ball", 0.13, (x, 0.8, 0), candy("Gem", C["pink"] if i % 2 else C["sky"], 0.1)))
    return objs


def heart_pts(n=64):
    pts = []
    for i in range(n):
        t = i / n * math.tau
        x = 16 * math.sin(t) ** 3
        y = 13 * math.cos(t) - 5 * math.cos(2 * t) - 2 * math.cos(3 * t) - math.cos(4 * t)
        pts.append((x / 17, y / 17 + 0.1))
    return pts


def i_heart():
    return [puffy2d("Heart", heart_pts(), 0.55, 0.25, candy("Heart", C["coral"], 0.22))]


def i_lock():
    body = puffy2d("Lock", rounded_rect_pts(1.5, 1.2, 0.28), 0.6, 0.18, candy("Lock", C["gold"], 0.25, 0.8))
    body.location.y = -0.4
    sh = torus("Shackle", 0.48, 0.13, (0, 0.2, 0), (0, 0, 0), candy("Steel", C["grey"], 0.2, 1.0), half=True)
    key = sphere("Hole", 0.14, (0, -0.35, 0.32), candy("Ink", C["ink"]), scale=(1, 1, 0.4))
    return [body, sh, key]


def i_play():
    return [puffy2d("Play", [(-0.7, 0.9), (-0.7, -0.9), (0.95, 0.0)], 0.5, 0.26, candy("Play", C["mint"]))]


def i_shirt():
    pts = [(-0.45, 0.9), (-1.05, 0.55), (-0.8, 0.05), (-0.55, 0.2), (-0.55, -0.95), (0.55, -0.95), (0.55, 0.2),
           (0.8, 0.05), (1.05, 0.55), (0.45, 0.9), (0.2, 0.7), (0, 0.66), (-0.2, 0.7)]
    return [puffy2d("Shirt", pts, 0.4, 0.14, candy("Shirt", C["sky"]))]


def i_pin():
    m = candy("Pin", C["coral"])
    head = sphere("PinHead", 0.72, (0, 0.35, 0), m)
    tip = kit.lathe("Tip", [(0.001, -1.05), (0.2, -0.6), (0.5, -0.05), (0.001, 0.2)], 48)
    tip.rotation_euler.x = math.pi / 2
    tip.rotation_euler.x = 0
    tip.location = (0, 0, 0)
    kit.smooth(tip, 1)
    # lathe builds along Z: lay it into the XY plane (point down)
    tip.rotation_euler = (-math.pi / 2, 0, 0)
    tip.location = (0, 0.0, 0)
    kit.assign(tip, m)
    dot = sphere("PinDot", 0.26, (0, 0.38, 0.62), candy("W", C["white"]))
    return [head, tip, dot]


def i_clock():
    face = cyl("Face", 1.0, 0.35, (0, 0, 0), candy("Face", C["white"]), bevel=0.12)
    rim = torus("Rim", 1.0, 0.13, (0, 0, 0), (0, 0, 0), candy("Rim", C["sky"]))
    h1 = puffy2d("Hand", rounded_rect_pts(0.12, 0.62, 0.05), 0.08, 0.02, candy("Ink", C["ink"]), subsurf=1)
    h1.location = (0, 0.28, 0.2)
    h2 = puffy2d("Hand2", rounded_rect_pts(0.12, 0.45, 0.05), 0.08, 0.02, candy("Ink2", C["coral"]), subsurf=1)
    h2.location = (0.2, -0.05, 0.22)
    h2.rotation_euler.z = math.radians(-65)
    return [face, rim, h1, h2]


def i_bolt():
    pts = [(0.25, 1.0), (-0.65, -0.05), (-0.05, -0.05), (-0.3, -1.0), (0.65, 0.12), (0.05, 0.12)]
    return [puffy2d("Bolt", pts, 0.4, 0.12, candy("Bolt", C["gold"], 0.2))]


def i_magnet():
    red = candy("Red", C["red"])
    u = torus("U", 0.62, 0.3, (0, 0.1, 0), (0, 0, math.pi), red, half=True)
    objs = [u]
    for sx in (-1, 1):
        leg = cyl("Leg", 0.3, 0.5, (sx * 0.62, 0.35, 0), red, rot=(math.pi / 2, 0, 0), bevel=0.02)
        tipc = cyl("Tip", 0.31, 0.3, (sx * 0.62, 0.72, 0), candy("Steel", C["white"], 0.2, 0.6), rot=(math.pi / 2, 0, 0), bevel=0.06)
        objs += [leg, tipc]
    return objs


def i_shield():
    pts = [(0, 1.0), (0.9, 0.7), (0.85, -0.1), (0.5, -0.65), (0, -1.0), (-0.5, -0.65), (-0.85, -0.1), (-0.9, 0.7)]
    s = puffy2d("Shield", pts, 0.5, 0.2, candy("Shield", C["sky"]))
    inner = puffy2d("Inner", [(x * 0.55, y * 0.55 + 0.02) for x, y in pts], 0.2, 0.1, candy("W", C["white"]))
    inner.location.z = 0.2
    return [s, inner]


def i_hourglass():
    glass = candy("Glass", (230, 235, 255), 0.05)
    glass.node_tree.nodes["Principled BSDF"].inputs["Transmission Weight"].default_value = 0.85
    g = kit.lathe("Glass", [(0.001, -0.85), (0.6, -0.85), (0.62, -0.5), (0.12, 0.0), (0.62, 0.5), (0.6, 0.85), (0.001, 0.85)], 48)
    kit.smooth(g, 2)
    kit.assign(g, glass)
    g.rotation_euler.x = -math.pi / 2
    sand = kit.lathe("Sand", [(0.001, -0.82), (0.5, -0.82), (0.36, -0.45), (0.001, -0.3)], 48)
    kit.smooth(sand, 1)
    kit.assign(sand, candy("Sand", C["lav"], emit=0.3))
    sand.rotation_euler.x = -math.pi / 2
    objs = [g, sand]
    for y in (-0.95, 0.95):
        objs.append(cyl("Cap", 0.78, 0.18, (0, y, 0), candy("Wood", C["brown"]), rot=(math.pi / 2, 0, 0), bevel=0.06))
    return objs


def i_x2():
    body, star = shapes.build_coin()
    star.hide_render = True
    font = bpy.data.fonts.load(kit.FONT_ROUNDED)
    cu = bpy.data.curves.new("x2", "FONT")
    cu.body = "x2"
    cu.font = font
    cu.size = 0.95
    cu.extrude = 0.08
    cu.bevel_depth = 0.04
    cu.bevel_resolution = 4
    cu.align_x = "CENTER"
    cu.align_y = "CENTER"
    t = kit.new_obj("x2", cu)
    t.location.z = 0.2
    kit.assign(t, candy("W", C["white"]))
    return [body, t]


def i_dog():
    fur = candy("Fur", (232, 172, 92))
    light = candy("FurL", (248, 214, 150))
    head = sphere("Head", 0.85, (0, 0, 0), fur, scale=(1, 0.95, 0.9))
    snout = sphere("Snout", 0.45, (0, -0.35, 0.55), light, scale=(1.1, 0.8, 0.8))
    nose = sphere("Nose", 0.16, (0, -0.2, 0.95), candy("Nose", (40, 30, 30), 0.15))
    objs = [head, snout, nose]
    for sx in (-1, 1):
        objs.append(sphere("Ear", 0.35, (sx * 0.8, 0.1, 0.1), candy("Ear", (196, 132, 64)), scale=(0.6, 1.4, 0.5)))
        objs.append(sphere("Eye", 0.1, (sx * 0.32, 0.22, 0.75), candy("Ink", C["ink"], 0.15), seg=16))
    return objs


BUILDERS = {
    "coin": i_coin, "star": i_star, "trophy": i_trophy, "bag": i_bag, "capsule": i_capsule, "gear": i_gear,
    "chart": i_chart, "paw": i_paw, "house": i_house, "friends": i_friends, "crown": i_crown, "heart": i_heart,
    "lock": i_lock, "play": i_play, "shirt": i_shirt, "pin": i_pin, "clock": i_clock, "bolt": i_bolt,
    "magnet": i_magnet, "shield": i_shield, "hourglass": i_hourglass, "x2": i_x2, "dog": i_dog,
}


def render_icon(name):
    kit.reset()
    objs = BUILDERS[name]()
    root = bpy.data.objects.new("Root", None)
    bpy.context.scene.collection.objects.link(root)
    for o in objs:
        if o.parent is None:
            o.parent = root
    # a playful 3/4 tilt so the depth + bevels read
    root.rotation_euler = (math.radians(-18), math.radians(22), 0) if name not in ("coin", "x2") else (math.radians(-8), math.radians(24), 0)
    kit.area_light("Key", (3, 3, 7), (0, 0, 0), 700, (1.0, 0.93, 0.82), 4)
    kit.area_light("Fill", (-5, -1, 4), (0, 0, 0), 260, (0.78, 0.76, 1.0), 6)
    kit.area_light("Rim", (-2, 5, -2), (0, 0, 0), 500, (0.8, 1.0, 0.9), 3)
    kit.camera((0, 0, 12), (0, 0, 0), ortho=2.7)
    kit.render(os.path.join(OUT_DIR, name + ".png"), 256, 256, samples=80)


for n in BUILDERS:
    if ONLY and n not in ONLY:
        continue
    try:
        render_icon(n)
        print("ICON_OK", n)
    except Exception as e:
        import traceback
        traceback.print_exc()
        print("ICON_FAIL", n, e)
