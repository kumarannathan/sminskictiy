# Store art: one 512px image per game pass / developer product.
# Same glossy candy look as icons.py -- and the SAME CONVENTION, which is the
# whole trick: build in the XY plane with +Z pointing at the camera, so 2D
# outlines, text curves and coin faces all face front. (Built once with a
# front camera along -Y instead: every flat shape turned edge-on and the text
# vanished into a stripe.)
#   Blender --background --factory-startup --python store_icons.py -- [name,...]
import sys, os, math
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import bpy, bmesh, kit, shapes
from mathutils import Vector

argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
ONLY = set(argv[0].split(",")) if argv and argv[0] else None
OUT = os.path.join(kit.ROOT, "store")
os.makedirs(OUT, exist_ok=True)

C = {
    "gold": (255, 200, 70), "gold2": (255, 226, 130), "bronze": (212, 152, 92),
    "coral": (255, 120, 105), "mint": (120, 220, 150), "lime": (170, 235, 90),
    "sky": (110, 180, 245), "lav": (175, 145, 245), "pink": (255, 150, 190),
    "white": (250, 248, 240), "ink": (60, 55, 80), "brown": (190, 120, 80),
    "red": (240, 80, 80), "cream": (255, 240, 205), "steel": (176, 184, 200),
    "leaf": (126, 200, 110), "orange": (255, 158, 70), "grey": (170, 170, 190),
}


def candy(name, rgb, rough=0.28, metal=0.0, emit=0.0):
    return kit.mat(name, kit.srgb(*rgb), rough=rough, metal=metal, coat=1.0,
                   emit=kit.srgb(*rgb) if emit else None, emit_strength=emit)


def puffy2d(name, pts, depth=0.3, bevel=0.12, mat=None, subsurf=2):
    """Extrude a 2D outline (XY) along Z with a fat rounded bevel."""
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
    kit.smooth(o, subsurf)
    if mat:
        kit.assign(o, mat)
    return o


def rrect(w, h, r, n=8):
    pts = []
    for cx, cy, a0 in ((w / 2 - r, h / 2 - r, 0), (-w / 2 + r, h / 2 - r, 90),
                       (-w / 2 + r, -h / 2 + r, 180), (w / 2 - r, -h / 2 + r, 270)):
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
    bpy.ops.mesh.primitive_torus_add(major_radius=R, minor_radius=r, major_segments=64, minor_segments=24,
                                     location=loc, rotation=rot)
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
    """Default axis is Z -- i.e. pointing AT the camera, which is what a clock
    face or a vault door wants. rot=(pi/2,0,0) stands it up instead."""
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


def cube(name, size, loc, mat, rot=(0, 0, 0), bevel=0.06):
    bpy.ops.mesh.primitive_cube_add(size=1, location=loc, rotation=rot)
    o = bpy.context.active_object
    o.name = name
    o.scale = size
    b = o.modifiers.new("Bevel", "BEVEL")
    b.width = bevel
    b.segments = 4
    b.limit_method = "ANGLE"
    for p in o.data.polygons:
        p.use_smooth = True
    kit.assign(o, mat)
    return o


def text3d(name, body, mat, size=1.0, loc=(0, 0, 0), extrude=0.14):
    """A FONT curve lives in XY facing +Z, so it reads straight to camera."""
    cu = bpy.data.curves.new(name, "FONT")
    cu.body = body
    cu.size = size
    cu.extrude = extrude
    cu.align_x = "CENTER"
    cu.align_y = "CENTER"
    cu.bevel_depth = 0.03
    cu.resolution_u = 3
    try:
        cu.font = bpy.data.fonts.load(kit.FONT_ROUNDED)
    except Exception:
        pass
    o = bpy.data.objects.new(name, cu)
    bpy.context.scene.collection.objects.link(o)
    o.location = loc
    kit.assign(o, mat)
    return o


# ---------------------------------------------------------------------------
# COINS. The game's own star coin, linked-duplicated -- so the thing you buy
# in the store is literally the thing you collect in the game.
# ---------------------------------------------------------------------------
def coin_fan(n, layout, scale=0.62):
    """layout(i) -> (x, y, z, tilt_deg)."""
    body, star = shapes.build_coin("Coin")
    out = []
    for i in range(n):
        x, y, z, tilt = layout(i)
        for src in (body, star):
            o = src.copy()
            o.data = src.data           # linked: one mesh, n instances
            bpy.context.scene.collection.objects.link(o)
            o.location = (x, y, z)
            o.rotation_euler = (math.radians(tilt * 0.45), math.radians(tilt), 0)
            o.scale = (scale, scale, scale)
            out.append(o)
    body.location = (0, 0, -40)         # park the originals out of frame
    star.location = (0, 0, -40)
    out += [body, star]
    return out


def heap(n, w, h, z0=0.0, scale=0.62, seed=0.0):
    """A loose, slightly overlapping fan of coins in a w x h box."""
    def layout(i):
        a = i * 2.3999 + seed
        r = (i / max(1, n - 1)) ** 0.62
        return (math.cos(a) * w * r, math.sin(a) * h * r - h * 0.1,
                z0 + (i % 3) * 0.16, ((i * 53) % 60) - 30)
    return coin_fan(n, layout, scale)


def shift(objs, dx=0.0, dy=0.0, dz=0.0):
    for o in objs:
        if o.location.z > -30:          # leave the parked originals alone
            o.location = (o.location.x + dx, o.location.y + dy, o.location.z + dz)
    return objs


# ---------------------------------------------------------------------------
# THE TWELVE
# ---------------------------------------------------------------------------
def i_coins1():
    return heap(3, 0.62, 0.5, 0.0, 0.8)


def i_coins2():
    body = candy("Purse", C["coral"])
    pouch = puffy2d("Pouch", rrect(2.0, 1.55, 0.62), 0.9, 0.28, body)
    pouch.location = (0, -0.75, 0)
    objs = [pouch]
    objs.append(cyl("Clasp", 0.98, 0.34, (0, 0.06, 0.1), candy("Cl", C["gold"], 0.2, 0.8),
                    rot=(math.pi / 2, 0, 0), bevel=0.1))
    for sx in (-1, 1):
        objs.append(sphere("Stud", 0.16, (sx * 0.74, 0.1, 0.46), candy("St", C["gold2"], 0.2, 0.7)))
    objs += shift(heap(4, 0.72, 0.4, 0.55, 0.6, 1.1), dy=0.95)
    return objs


def i_coins3():
    case = candy("Case", C["brown"])
    body = puffy2d("Case", rrect(2.5, 1.5, 0.28), 1.0, 0.22, case)
    body.location = (0, -0.85, 0)
    lid = puffy2d("Lid", rrect(2.6, 0.5, 0.2), 1.05, 0.18, candy("Lid", (150, 92, 58)))
    lid.location = (0, -0.1, 0)
    objs = [body, lid]
    objs.append(cube("Latch", (0.46, 0.3, 0.3), (0, -0.05, 0.58), candy("L", C["gold"], 0.22, 0.8)))
    objs.append(torus("Handle", 0.44, 0.11, (0, 0.34, 0), (0, 0, 0), candy("H", C["ink"]), half=True))
    objs += shift(heap(7, 0.95, 0.52, 0.6, 0.56, 0.4), dy=1.1)
    return objs


def i_coins4():
    steel = candy("Steel", C["steel"], 0.3, 0.85)
    objs = [cyl("Door", 1.6, 0.6, (0, -0.1, -0.2), steel, bevel=0.14)]
    objs.append(cyl("Plate", 1.3, 0.72, (0, -0.1, -0.15), candy("Face", C["white"], 0.34, 0.3), bevel=0.12))
    objs.append(cyl("Hub", 0.42, 0.9, (0, -0.1, -0.05), candy("Hub", C["gold"], 0.2, 0.85), bevel=0.08))
    for i in range(4):
        a = i * math.pi / 4 + math.pi / 8
        s = cube("Spoke%d" % i, (1.9, 0.17, 0.17), (0, -0.1, 0.24), steel, bevel=0.06)
        s.rotation_euler = (0, 0, a)
        objs.append(s)
    for i in range(4):
        a = i * math.pi / 2 + math.pi / 4
        objs.append(sphere("Bolt", 0.13, (math.cos(a) * 1.45, -0.1 + math.sin(a) * 1.45, 0.3),
                           candy("B", C["grey"], 0.3, 0.8)))
    objs += shift(heap(8, 0.9, 0.48, 0.9, 0.48, 2.2), dx=0.88, dy=0.92)
    return objs


def i_skipbiz():
    objs = [cyl("Face", 1.2, 0.42, (-0.35, 0.25, 0), candy("F", C["white"], 0.32), bevel=0.14)]
    objs.append(torus("Rim", 1.2, 0.16, (-0.35, 0.25, 0), (0, 0, 0), candy("R", C["lav"])))
    h1 = puffy2d("HandH", rrect(0.21, 0.86, 0.1), 0.14, 0.05, candy("Ink", C["ink"]), subsurf=1)
    h1.location = (-0.35, 0.62, 0.26)
    h2 = puffy2d("HandM", rrect(0.19, 0.66, 0.09), 0.14, 0.05, candy("Ink2", C["coral"]), subsurf=1)
    h2.location = (-0.05, 0.4, 0.28)
    h2.rotation_euler.z = math.radians(-64)
    objs += [h1, h2]
    objs.append(sphere("Pin", 0.15, (-0.35, 0.25, 0.34), candy("P", C["ink"])))
    # ticks sweeping the hands forward: this SKIPS the wait
    for i, a in enumerate((-40, -8, 24)):
        arc = puffy2d("Arc%d" % i, rrect(0.6 - i * 0.1, 0.16, 0.08), 0.12, 0.05, candy("A", C["mint"]), subsurf=1)
        arc.location = (1.15 + i * 0.06, 1.1 - i * 0.52, 0.1)
        arc.rotation_euler.z = math.radians(a)
        objs.append(arc)
    objs += shift(heap(3, 0.5, 0.34, 0.45, 0.62, 0.9), dx=0.95, dy=-1.15)
    return objs


def i_skipfarm():
    pot = puffy2d("Pot", [(-0.74, 0.28), (0.74, 0.28), (0.56, -0.92), (-0.56, -0.92)], 0.9, 0.2,
                  candy("Pot", C["bronze"]))
    pot.location = (0, -0.75, 0)
    lip = puffy2d("Lip", rrect(1.72, 0.36, 0.16), 0.98, 0.14, candy("Lip", C["coral"]))
    lip.location = (0, -0.34, 0)
    objs = [pot, lip, cyl("Stem", 0.11, 1.5, (0, 0.5, 0), candy("Stem", C["leaf"]), rot=(math.pi / 2, 0, 0), bevel=0.03)]
    for sx, ang in ((-1, 58), (1, -58)):
        lf = sphere("Leaf", 0.5, (sx * 0.42, 0.66, 0.05), candy("Lf", C["leaf"]), scale=(1.45, 0.58, 0.4))
        lf.rotation_euler = (0, 0, math.radians(ang))
        objs.append(lf)
    objs.append(sphere("Bud", 0.34, (0, 1.32, 0.05), candy("Bud", C["pink"])))
    for i, (dx, dy) in enumerate(((-1.55, 0.95), (-1.85, 0.45), (-1.55, -0.05))):
        t = puffy2d("Tick%d" % i, rrect(0.62 - abs(i - 1) * 0.16, 0.13, 0.065), 0.12, 0.05,
                    candy("Tk", C["lime"]), subsurf=1)
        t.location = (dx, dy, 0.1)
        objs.append(t)
    return objs


def badge(col, label, size=1.5, w=2.7, h=2.0):
    b = puffy2d("Badge", rrect(w, h, 0.66), 0.5, 0.2, candy("Bg", col))
    # the label sits PROUD of the badge face, not flush with it: flush reads as
    # embossed-in-the-same-colour and the number disappears at thumbnail size
    m = kit.mat("Tx", kit.srgb(*C["white"]), rough=0.42, coat=0.0)
    t = text3d("Label", label, m, size=size, loc=(0, 0, 0.55))
    return [b, t]


def i_boost2x():
    objs = badge(C["orange"], "2x")
    for o in objs:
        o.location = (o.location.x - 0.25, o.location.y + 0.45, o.location.z)
    objs += shift(heap(4, 0.68, 0.42, 0.5, 0.6, 1.7), dx=0.85, dy=-1.25)
    return objs


def i_boost2xs():
    objs = badge(C["coral"], "2x", 1.35, 2.5, 1.85)
    for o in objs:
        o.location = (o.location.x, o.location.y + 0.85, o.location.z)
    # three little Sminskis under it: the whole server gets this one
    for i, (dx, col) in enumerate(((-1.15, C["mint"]), (0, C["sky"]), (1.15, C["lav"]))):
        m = candy("Body%d" % i, col)
        objs.append(cyl("Body%d" % i, 0.34, 0.66, (dx, -1.25, 0.2), m, rot=(math.pi / 2, 0, 0), bevel=0.14))
        objs.append(sphere("Head%d" % i, 0.42, (dx, -0.82, 0.2), m))
        for sx in (-1, 1):
            objs.append(sphere("Eye", 0.055, (dx + sx * 0.13, -0.85, 0.58), candy("Ink", C["ink"])))
    return objs


def i_boost2xs30():
    objs = badge(C["red"], "2x", 1.35, 2.5, 1.85)
    for o in objs:
        o.location = (o.location.x, o.location.y + 0.7, o.location.z)
    pill = puffy2d("Pill", rrect(3.0, 1.0, 0.5), 0.42, 0.17,
                   kit.mat("Pl", kit.srgb(186, 48, 56), rough=0.5, coat=0.0))
    pill.location = (0, -1.24, 0)
    objs.append(pill)
    objs.append(text3d("Mins", "30 MIN", kit.mat("W2", kit.srgb(255, 255, 255), rough=0.45, coat=0.0),
                       size=0.46, loc=(0, -1.24, 0.56), extrude=0.06))
    return objs


def i_starter():
    b = puffy2d("Box", rrect(2.2, 1.9, 0.2), 1.1, 0.24, candy("Gift", C["sky"]))
    b.location = (0, -0.62, 0)
    lid = puffy2d("Lid", rrect(2.5, 0.6, 0.22), 1.2, 0.2, candy("Lid", C["white"]))
    lid.location = (0, 0.52, 0)
    objs = [b, lid]
    rib = candy("Rib", C["coral"])
    band = puffy2d("Band", rrect(0.44, 2.0, 0.1), 1.24, 0.1, rib, subsurf=1)
    band.location = (0, -0.62, 0)
    objs.append(band)
    objs.append(cube("BandLid", (0.46, 0.64, 1.26), (0, 0.52, 0), rib, bevel=0.08))
    for sx in (-1, 1):
        lp = sphere("Bow", 0.42, (sx * 0.42, 1.12, 0.1), rib, scale=(1.0, 0.68, 0.42))
        lp.rotation_euler = (0, 0, math.radians(sx * 28))
        objs.append(lp)
    objs.append(sphere("Knot", 0.2, (0, 0.98, 0.26), rib))
    objs += shift(heap(3, 0.42, 0.3, 0.7, 0.46, 0.6), dx=-1.3, dy=0.66)
    # a sprout for the garden plot the pack unlocks
    objs.append(cyl("Sprout", 0.07, 0.58, (1.28, 0.75, 0.5), candy("Sp", C["leaf"]),
                    rot=(math.pi / 2, 0, 0), bevel=0.02))
    for sx in (-1, 1):
        lf = sphere("SLeaf", 0.24, (1.28 + sx * 0.2, 0.98, 0.5), candy("Sl2", C["leaf"]),
                    scale=(1.4, 0.6, 0.4))
        lf.rotation_euler = (0, 0, math.radians(sx * 32))
        objs.append(lf)
    return objs


def i_auto():
    cogm = candy("Cog", C["sky"])
    objs = [cyl("Cog", 1.18, 0.5, (-0.15, -0.35, 0), cogm, bevel=0.12)]
    for i in range(8):
        a = i * math.pi / 4
        t = cube("Tooth%d" % i, (0.5, 0.46, 0.5), (-0.15 + math.cos(a) * 1.3, -0.35 + math.sin(a) * 1.3, 0),
                 cogm, bevel=0.1)
        t.rotation_euler = (0, 0, a)
        objs.append(t)
    objs.append(cyl("Bore", 0.42, 0.66, (-0.15, -0.35, 0), candy("Bo", C["white"], 0.34), bevel=0.08))
    # a coin dropping into it on its own -- that is the whole pass
    objs += shift(heap(1, 0.1, 0.1, 0.8, 0.72), dx=0.62, dy=1.42)
    for i, dy in enumerate((0.62, 0.95)):
        t = puffy2d("Fall%d" % i, rrect(0.14, 0.34 - i * 0.1, 0.07), 0.12, 0.05, candy("Fa", C["gold2"]), subsurf=1)
        t.location = (0.62, dy, 0.5)
        objs.append(t)
    return objs


def i_speed():
    sole = candy("Sole", C["white"], 0.34)
    shoe = puffy2d("Shoe", [(-1.4, -0.3), (-1.44, 0.16), (-1.3, 0.6), (-1.0, 0.86),
                            (-0.6, 0.88), (-0.48, 0.5), (-0.1, 0.36), (0.5, 0.26),
                            (1.02, 0.22), (1.34, 0.04), (1.46, -0.16), (1.48, -0.3)],
                   0.95, 0.2, candy("Shoe", C["mint"]))
    shoe.location = (-0.1, -0.3, 0)
    s = puffy2d("Sole", [(-1.5, -0.34), (1.58, -0.34), (1.62, -0.62), (1.4, -0.78),
                         (-1.44, -0.78), (-1.56, -0.62)], 1.02, 0.16, sole)
    s.location = (-0.1, -0.24, 0)
    objs = [shoe, s]
    for i, (x, y) in enumerate(((-0.42, 0.46), (-0.12, 0.36), (0.2, 0.28))):
        lc = puffy2d("Lace%d" % i, rrect(0.5, 0.13, 0.065), 1.02, 0.06, sole, subsurf=1)
        lc.location = (x - 0.1, y - 0.3, 0)
        lc.rotation_euler.z = math.radians(-22)
        objs.append(lc)
    bolt = puffy2d("Bolt", [(0.25, 1.0), (-0.65, -0.05), (-0.05, -0.05), (-0.3, -1.0), (0.65, 0.12), (0.05, 0.12)],
                   0.4, 0.12, candy("Bolt", C["gold"], 0.2))
    bolt.location = (1.15, 0.95, 0.3)
    bolt.scale = (0.78, 0.78, 0.78)
    objs.append(bolt)
    for i, (dx, dy) in enumerate(((-1.85, 0.55), (-2.1, 0.1), (-1.85, -0.35))):
        t = puffy2d("Sl%d" % i, rrect(0.78 - abs(i - 1) * 0.2, 0.14, 0.07), 0.12, 0.05,
                    candy("Sl", C["sky"]), subsurf=1)
        t.location = (dx, dy, 0.2)
        objs.append(t)
    return objs


BUILDERS = {
    "coins1": i_coins1, "coins2": i_coins2, "coins3": i_coins3, "coins4": i_coins4,
    "skipbiz": i_skipbiz, "skipfarm": i_skipfarm,
    "boost2x": i_boost2x, "boost2xs": i_boost2xs, "boost2xs30": i_boost2xs30,
    "starter": i_starter, "auto": i_auto, "speed": i_speed,
}

# A soft card behind each one. Roblox shows store images on a pale panel, so a
# transparent PNG would leave the icon floating on grey.
BACKDROP = {
    "coins1": (255, 234, 184), "coins2": (255, 222, 210), "coins3": (252, 230, 200), "coins4": (255, 224, 168),
    "skipbiz": (230, 222, 255), "skipfarm": (224, 246, 212),
    "boost2x": (255, 228, 198), "boost2xs": (255, 218, 212), "boost2xs30": (255, 212, 212),
    "starter": (214, 234, 255), "auto": (216, 234, 255), "speed": (212, 246, 234),
}
TILT = {"coins1": (-8, 20), "coins4": (-10, 16), "boost2x": (-10, 14), "boost2xs": (-10, 14),
        "boost2xs30": (-10, 14)}


def render(name):
    kit.reset()
    objs = BUILDERS[name]()
    root = bpy.data.objects.new("Root", None)
    bpy.context.scene.collection.objects.link(root)
    for o in objs:
        if o.parent is None:
            o.parent = root
    tx, ty = TILT.get(name, (-15, 20))
    root.rotation_euler = (math.radians(tx), math.radians(ty), 0)
    bpy.ops.mesh.primitive_plane_add(size=40, location=(0, 0, -7))
    kit.assign(bpy.context.active_object, kit.mat("Backdrop", kit.srgb(*BACKDROP[name]), rough=0.92))
    kit.area_light("Key", (3.5, 3.5, 8), (0, 0, 0), 820, (1.0, 0.93, 0.82), 7)
    kit.area_light("Fill", (-6, -1.5, 5), (0, 0, 0), 300, (0.78, 0.76, 1.0), 9)
    kit.area_light("Rim", (-2.5, 5.5, -1.5), (0, 0, 0), 520, (0.8, 1.0, 0.9), 5)
    bpy.context.scene.render.film_transparent = False
    kit.camera((0, 0, 13), (0, 0, 0), ortho=4.4)
    kit.render(os.path.join(OUT, name + ".png"), 512, 512, samples=110)


made = []
for n in BUILDERS:
    if ONLY and n not in ONLY:
        continue
    try:
        render(n)
        made.append(n)
        print("STORE_OK", n)
    except Exception as e:
        import traceback
        traceback.print_exc()
        print("STORE_FAIL", n, e)
print("rendered %d icons -> %s" % (len(made), OUT))
