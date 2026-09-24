# High-detail bedroom furniture for the lobby (Hub.lua buildBedroom), built in
# Roblox studs at the exact sizes Hub.lua places them.  Same pipeline as
# props.py: every prop is a few single-colour meshes "<Prop>__<Part>";
# room_parts.json / room_colors.json feed _G.SR_assemble in Studio.
# Props face Roblox +Z; y = 0 is the floor / surface they stand on.
import sys, os, json, math
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import bpy, bmesh, kit
import rigkit
from rigkit import ellipsoid, rbox, capsule_y, cyl_axis, merge, finish, angles, place, rb, Vector, Matrix

kit.reset()
COLORS = {}


def part(prop, name, obj, color, material="SmoothPlastic", tris=1500, voxel=0, smooth_iter=0, transparency=None):
    o = merge(obj if isinstance(obj, list) else [obj], prop + "__" + name, voxel, smooth_iter)
    finish(o, prop + "__" + name, tris, prop)
    d = {"color": color, "material": material}
    if transparency is not None:
        d["transparency"] = transparency
    COLORS[prop + "__" + name] = d


def lathe_y(name, prof, steps=48, center=(0, 0, 0), rot=None):
    return place(kit.lathe(name, prof, steps), center, rot)


def torus_axis(name, major, minor, center, axis="Y", rot=None):
    bpy.ops.mesh.primitive_torus_add(major_radius=major, minor_radius=minor, major_segments=48, minor_segments=16)
    o = bpy.context.active_object  # ring in Blender XY, axis Z == Roblox Y
    o.name = name
    base = {"Y": Matrix.Identity(3), "X": angles(0, 0, math.pi / 2), "Z": angles(math.pi / 2, 0, 0)}[axis]
    return place(o, center, base if rot is None else rot @ base)


def wavy_sheet(name, w, h, depth, waves, thick, center, rot=None):
    """Curtain: a vertical sheet (w wide along X, h tall) with sine folds along Z."""
    bm = bmesh.new()
    nx, ny = 64, 12
    grid = []
    for j in range(ny + 1):
        row = []
        for i in range(nx + 1):
            x = -w / 2 + w * i / nx
            y = h * j / ny
            k = 1.0 - 0.35 * (j / ny)  # folds tighter near the rod
            z = math.sin(i / nx * math.tau * waves) * depth * k
            row.append(bm.verts.new((x, -z, y)))  # Blender: X, -front(Z), up(Y)
        grid.append(row)
    for j in range(ny):
        for i in range(nx):
            bm.faces.new((grid[j][i], grid[j][i + 1], grid[j + 1][i + 1], grid[j + 1][i]))
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    o = kit.new_obj(name, me)
    s = o.modifiers.new("Sol", "SOLIDIFY")
    s.thickness = thick
    s.offset = 0
    for p in me.polygons:
        p.use_smooth = True
    return place(o, center, rot)


WOOD = [165, 118, 82]
DARK = [40, 40, 50]
CREAM = [245, 240, 235]
PLUSH = [90, 105, 140]

# ---------------------------------------------------------------------------
# BED  170 x 100 x 211   (headboard at +Z)
# ---------------------------------------------------------------------------
part("Bed", "Frame", [rbox("f", (160, 26, 205), (0, 13, -3), 2.5), rbox("hb", (170, 92, 10), (0, 46, 100.5), 4.5),
                      rbox("rail", (170, 6, 6), (0, 90, 96), 2.5)], WOOD, "Wood", tris=2400)
part("Bed", "Mattress", rbox("m", (154, 18, 200), (0, 35, -1), 6), [252, 248, 244], "Fabric", tris=1600)
folds = [rbox("d", (162, 15, 138), (0, 51, -36), 7)]
rng = __import__("random").Random(3)
for i in range(9):
    folds.append(ellipsoid("fd%d" % i, (rng.uniform(30, 70), rng.uniform(6, 10), rng.uniform(30, 60)),
                           (rng.uniform(-60, 60), 57, rng.uniform(-90, 20)), angles(0, rng.uniform(0, 3), 0)))
part("Bed", "Duvet", folds, [220, 190, 210], "Fabric", tris=3600, voxel=1.4, smooth_iter=10)
part("Bed", "DuvetFold", rbox("df", (162, 9, 26), (0, 60, 34), 4.2), [240, 215, 230], "Fabric", tris=900)
part("Bed", "Pillows", [rbox("p1", (62, 20, 36), (-38, 54, 78), 9, angles(-0.25, 0, 0.05)),
                        rbox("p2", (62, 20, 36), (38, 54, 78), 9, angles(-0.25, 0, -0.05))], [255, 250, 250], "Fabric", tris=2000)

# ---------------------------------------------------------------------------
# CAT PLUSH  104 x 190 x 84  (sits on the bed, faces +Z)
# ---------------------------------------------------------------------------
body = [ellipsoid("b", (100, 92, 78), (0, 46, 0)), ellipsoid("h", (78, 64, 66), (0, 112, 6)),
        ellipsoid("ch", (60, 40, 40), (0, 80, 18))]
for sx in (-1, 1):
    body.append(lathe_y("ear", [(12, 0), (11, 4), (5, 20), (0.001, 26)], 24, (sx * 27, 138, 4), angles(0.1, 0, -sx * 0.35)))
    body.append(ellipsoid("paw", (26, 20, 30), (sx * 34, 12, 30)))
    body.append(ellipsoid("arm", (22, 40, 22), (sx * 44, 60, 14), angles(0, 0, sx * 0.5)))
for i in range(7):
    a = i / 6 * 1.8
    body.append(ellipsoid("t%d" % i, (16 - i * 1.2, 14 - i, 16 - i * 1.2), (48 + math.sin(a) * 26, 12 + i * 4, -8 - math.cos(a) * 14 + 18)))
part("CatPlush", "Body", body, PLUSH, "Fabric", tris=5000, voxel=1.6, smooth_iter=12)
part("CatPlush", "Belly", [ellipsoid("bl", (56, 52, 26), (0, 44, 34)), ellipsoid("mz", (40, 22, 22), (0, 100, 34)),
                           ellipsoid("ie1", (8, 12, 6), (-27, 136, 6)), ellipsoid("ie2", (8, 12, 6), (27, 136, 6))], [235, 225, 205], "Fabric", tris=1600)
face = []
for sx in (-1, 1):
    for k in range(5):
        a = -0.9 + k * 0.45
        face.append(rbox("e", (5.2, 2.2, 2), (sx * 15 + math.sin(a) * 5, 112 + math.cos(a) * 5 - 3, 38.5), 0.9, angles(0, 0, -a)))
face.append(rbox("m1", (7, 1.8, 2), (-3.2, 104, 44), 0.8, angles(0, 0, 0.5)))
face.append(rbox("m2", (7, 1.8, 2), (3.2, 104, 44), 0.8, angles(0, 0, -0.5)))
part("CatPlush", "Face", face, [35, 30, 45], "SmoothPlastic", tris=900)
part("CatPlush", "Nose", ellipsoid("n", (8, 5, 5), (0, 107, 45)), [240, 150, 170], "SmoothPlastic", tris=200)

# ---------------------------------------------------------------------------
# PLUSHIE  (bear, 26 x 40 x 22)
# ---------------------------------------------------------------------------
pb = [ellipsoid("b", (26, 24, 20), (0, 12, 0)), ellipsoid("h", (21, 19, 19), (0, 30, 1)),
      ellipsoid("e1", (8, 8, 6), (-8, 39, 0)), ellipsoid("e2", (8, 8, 6), (8, 39, 0)),
      ellipsoid("a1", (8, 14, 8), (-13, 14, 4), angles(0, 0, 0.5)), ellipsoid("a2", (8, 14, 8), (13, 14, 4), angles(0, 0, -0.5)),
      ellipsoid("l1", (10, 8, 12), (-7, 4, 6)), ellipsoid("l2", (10, 8, 12), (7, 4, 6))]
part("Plushie", "Body", pb, [255, 205, 80], "Fabric", tris=2200, voxel=0.45, smooth_iter=10)
part("Plushie", "Muzzle", [ellipsoid("mz", (10, 7, 7), (0, 28, 9)), ellipsoid("tm", (12, 10, 6), (0, 11, 9))], [255, 240, 215], "Fabric", tris=500)
part("Plushie", "Face", [ellipsoid("ey", (2.4, 2.4, 2), (-4, 32, 9.6)), ellipsoid("ey2", (2.4, 2.4, 2), (4, 32, 9.6)), ellipsoid("no", (3, 2.2, 2), (0, 29.5, 12.5))], [35, 30, 45], "SmoothPlastic", tris=300)

# ---------------------------------------------------------------------------
# GAMING CHAIR  56 x 96 x 56  (seat top at y=22, back at -Z, person faces +Z)
# ---------------------------------------------------------------------------
base = [cyl_axis("hub", 6, 10, (0, 3, 0), "Y", bevel=0.8), cyl_axis("pole", 13, 4, (0, 11, 0), "Y", bevel=0.4),
        cyl_axis("pl2", 4, 9, (0, 16, 0), "Y", bevel=0.6)]
wheels = []
for i in range(5):
    a = i / 5 * math.tau
    base.append(rbox("spoke", (24, 3, 5), (math.cos(a) * 11, 2.5, math.sin(a) * 11), 1.4, angles(0, -a, 0)))
    wheels.append(ellipsoid("wh", (5, 5, 5), (math.cos(a) * 22, 2.5, math.sin(a) * 22)))
part("GamingChair", "Base", base, [55, 55, 68], "Metal", tris=2000)
part("GamingChair", "Wheels", wheels, [30, 30, 38], "SmoothPlastic", tris=800)
part("GamingChair", "Seat", [rbox("s", (44, 8, 42), (0, 21, 1), 3.5), rbox("bk", (44, 54, 9), (0, 48, -20), 4, angles(-0.12, 0, 0)),
                             rbox("w1", (7, 34, 12), (-22, 44, -17), 3, angles(-0.12, 0, 0.1)), rbox("w2", (7, 34, 12), (22, 44, -17), 3, angles(-0.12, 0, -0.1))],
     [150, 125, 220], "Fabric", tris=3000)
part("GamingChair", "Trim", [rbox("t1", (30, 24, 2), (0, 40, -14.6), 1.2, angles(-0.12, 0, 0)), rbox("t2", (30, 12, 2), (0, 60, -17.1), 1.2, angles(-0.12, 0, 0)),
                             rbox("t3", (30, 3, 34), (0, 25.2, 3), 1)], [70, 60, 110], "Fabric", tris=1200)
part("GamingChair", "Headrest", rbox("hr", (26, 12, 8), (0, 68, -15), 3.5, angles(-0.12, 0, 0)), [70, 60, 110], "Fabric", tris=600)
part("GamingChair", "Arms", [rbox("a", (6, 3, 24), (sx * 25, 34, 0), 1.4) for sx in (-1, 1)] + [rbox("ap", (3, 12, 4), (sx * 25, 27, -4), 1) for sx in (-1, 1)], DARK, "SmoothPlastic", tris=800)

# ---------------------------------------------------------------------------
# GAMING DESK  230 x 48 x 72  (top surface at y=48)
# ---------------------------------------------------------------------------
part("GamingDesk", "Top", rbox("t", (230, 4, 72), (0, 46, 0), 1.6), [248, 248, 252], "SmoothPlastic", tris=800)
part("GamingDesk", "Legs", [rbox("l", (6, 44, 64), (sx * 108, 22, 0), 1.5) for sx in (-1, 1)] + [rbox("bar", (210, 6, 3), (0, 6, -30), 1.2), rbox("tray", (120, 5, 14), (0, 41, -26), 1.5)],
     [235, 235, 242], "SmoothPlastic", tris=1600)
part("GamingDesk", "Mat", rbox("m", (90, 1.4, 56), (0, 48.7, 6), 0.7), [60, 50, 90], "Fabric", tris=400)

# ---------------------------------------------------------------------------
# MONITOR  66 x 54 x 20  (screen faces +Z; "Screen" carries the SurfaceGui)
# ---------------------------------------------------------------------------
part("Monitor", "Bezel", [rbox("bz", (66, 38, 3), (0, 36, 0), 1.3), rbox("neck", (6, 16, 4), (0, 12, -3), 1.2),
                          rbox("foot", (30, 2, 16), (0, 1, -2), 1)], [30, 30, 38], "SmoothPlastic", tris=1400)
part("Monitor", "Screen", rbox("sc", (62, 34, 0.8), (0, 36, 1.7), 0.35), [80, 90, 200], "Neon", tris=300)
part("Monitor", "Led", rbox("led", (3, 0.8, 0.6), (0, 17.6, 1.6), 0.25), [120, 230, 255], "Neon", tris=100)

# ---------------------------------------------------------------------------
# PC TOWER  26 x 56 x 52  (glass on +X)
# ---------------------------------------------------------------------------
part("PCTower", "Case", [rbox("c", (24, 56, 52), (-1, 28, 0), 1.6), rbox("ft", (2, 4, 4), (12, 28, 0), 0.5)], [25, 25, 32], "SmoothPlastic", tris=1400)
part("PCTower", "Front", [rbox("fr", (22, 52, 2), (-1, 28, 26), 0.8), rbox("pb", (3, 3, 1), (-8, 50, 27.2), 0.6)], [50, 50, 62], "SmoothPlastic", tris=600)
part("PCTower", "Glass", rbox("g", (0.8, 50, 46), (12.6, 28, 0), 0.3), [160, 100, 255], "Glass", tris=200, transparency=0.45)
part("PCTower", "Fans", [torus_axis("f%d" % k, 5.4, 1.1, (11.4, 14 + k * 14, -4), "X") for k in range(3)], [120, 230, 255], "Neon", tris=2400)
part("PCTower", "Strip", rbox("st", (0.8, 50, 1.6), (12.3, 28, 24), 0.35), [255, 120, 220], "Neon", tris=200)

# ---------------------------------------------------------------------------
# KEYBOARD 44 x 3.4 x 14   /   MOUSE 7 x 3.6 x 11
# ---------------------------------------------------------------------------
part("Keyboard", "Body", rbox("kb", (44, 2, 14), (0, 1, 0), 0.7), [30, 30, 38], "SmoothPlastic", tris=600)
keys = []
for r in range(4):
    for c in range(16):
        w = 2.2 if not (r == 3 and 5 <= c <= 9) else 2.2
        keys.append(rbox("k", (w, 1.2, 2.2), (-19.5 + c * 2.6, 2.4, -4.2 + r * 2.8), 0.4))
keys.append(rbox("sp", (12.8, 1.2, 2.2), (0, 2.4, 4.2), 0.4))
part("Keyboard", "Keys", keys, [50, 50, 62], "SmoothPlastic", tris=3200)
part("Keyboard", "Glow", rbox("gl", (42.4, 0.5, 12.4), (0, 2.05, 0), 0.2), [190, 120, 255], "Neon", tris=300, transparency=0.3)
part("Mouse", "Body", ellipsoid("mb", (7, 5.2, 11), (0, 1.6, 0)), [30, 30, 38], "SmoothPlastic", tris=700)
part("Mouse", "Wheel", cyl_axis("mw", 1.2, 1.6, (0, 3.6, 2.8), "X", bevel=0.2), [190, 120, 255], "Neon", tris=200)

# ---------------------------------------------------------------------------
# NIGHTSTAND 44 x 48 x 40
# ---------------------------------------------------------------------------
part("Nightstand", "Body", [rbox("b", (44, 40, 40), (0, 26, 0), 1.6), rbox("top", (47, 3, 43), (0, 47, 0), 1.2)] + [cyl_axis("lg", 6, 3.5, (sx * 18, 3, sz * 16), "Y", bevel=0.4) for sx in (-1, 1) for sz in (-1, 1)], WOOD, "Wood", tris=2000)
part("Nightstand", "Drawers", [rbox("d1", (36, 14, 1.6), (0, 36, 20.6), 0.8), rbox("d2", (36, 14, 1.6), (0, 18, 20.6), 0.8)], [150, 105, 72], "Wood", tris=800)
part("Nightstand", "Knobs", [ellipsoid("kn", (4, 4, 3), (0, 36, 22.5)), ellipsoid("kn2", (4, 4, 3), (0, 18, 22.5))], [200, 170, 110], "Metal", tris=400)

# ---------------------------------------------------------------------------
# MOON LAMP 24 x 30 x 24
# ---------------------------------------------------------------------------
bpy.ops.mesh.primitive_uv_sphere_add(segments=64, ring_count=32, radius=12)
moon = bpy.context.active_object
moon.name = "moon"
tex = bpy.data.textures.new("crater", "CLOUDS")
tex.noise_scale = 4.0
tex.noise_depth = 2
dsp = moon.modifiers.new("Disp", "DISPLACE")
dsp.texture = tex
dsp.strength = -1.4
dsp.mid_level = 0.35
place(moon, (0, 18, 0))
part("MoonLamp", "Bulb", moon, [255, 240, 210], "Neon", tris=2400)
part("MoonLamp", "Base", lathe_y("mb", [(9, 0), (9.5, 1), (8, 4.5), (5, 6.5), (0.001, 6.6)], 48, (0, 0, 0)), [70, 45, 32], "Wood", tris=800)

# ---------------------------------------------------------------------------
# DRESSER 114 x 72 x 36
# ---------------------------------------------------------------------------
part("Dresser", "Body", [rbox("b", (110, 62, 34), (0, 37, 0), 1.6), rbox("top", (114, 3, 37), (0, 69.5, 0), 1.2)] + [cyl_axis("lg", 6, 4.5, (sx * 50, 3, sz * 13), "Y", bevel=0.5) for sx in (-1, 1) for sz in (-1, 1)], CREAM, "SmoothPlastic", tris=2200)
part("Dresser", "Drawers", [rbox("d", (50, 17, 1.6), (-26 + c * 52, 16 + r * 20, 17.6), 0.9) for r in range(3) for c in range(2)], [235, 228, 222], "SmoothPlastic", tris=1800)
part("Dresser", "Handles", [rbox("h", (9, 1.6, 2.2), (-26 + c * 52, 16 + r * 20, 19.2), 0.7) for r in range(3) for c in range(2)], [200, 170, 110], "Metal", tris=900)

# ---------------------------------------------------------------------------
# BOOKCASE 30 x 152 x 90   (open side faces +X... it stands against the +X wall,
# shelves open toward -X; built open toward +Z and rotated in Hub)
# ---------------------------------------------------------------------------
part("Bookcase", "Frame", [rbox("s", (3, 150, 28), (sx * 43.5, 75, 0), 1) for sx in (-1, 1)] + [rbox("bk", (90, 150, 2), (0, 75, -13), 0.8), rbox("tp", (92, 3, 30), (0, 150.5, 0), 1.2), rbox("kick", (86, 6, 26), (0, 3, 0), 1)], WOOD, "Wood", tris=2000)
part("Bookcase", "Shelves", [rbox("sh", (86, 2, 26), (0, 8 + s * 29, 0), 0.7) for s in range(5)], [150, 105, 72], "Wood", tris=1200)

# ---------------------------------------------------------------------------
# BEAN BAG 62 x 42 x 62
# ---------------------------------------------------------------------------
part("BeanBag", "Body", [ellipsoid("b", (60, 34, 60), (0, 17, 0)), ellipsoid("t", (44, 22, 44), (0, 28, -4)), ellipsoid("l", (30, 18, 30), (-14, 24, 12)), ellipsoid("r", (30, 18, 30), (14, 24, 12))],
     [255, 170, 120], "Fabric", tris=3000, voxel=1.0, smooth_iter=12)
part("BeanBag", "Tag", rbox("tg", (6, 3, 0.6), (18, 30, 22), 0.5, angles(0.4, 0.3, 0)), [255, 250, 245], "Fabric", tris=200)

# ---------------------------------------------------------------------------
# LAUNDRY BASKET 42 x 54 x 42 (woven, clothes on top)
# ---------------------------------------------------------------------------
prof = [(15, 0), (17, 0.6)]
for i in range(1, 30):
    z = i / 29 * 40
    prof.append((17 + z * 0.09 + (0.9 if i % 2 else 0), z))
prof += [(21.5, 40.5), (22, 41.5), (19.5, 42.2), (16, 41), (0.001, 40)]
part("LaundryBasket", "Basket", lathe_y("lb", prof, 56), [220, 200, 170], "Fabric", tris=3600)
part("LaundryBasket", "Clothes", [ellipsoid("c1", (34, 14, 30), (0, 46, 0)), ellipsoid("c2", (20, 10, 20), (8, 51, -5)), ellipsoid("c3", (18, 9, 22), (-9, 50, 6))], [140, 190, 240], "Fabric", tris=1800, voxel=0.7, smooth_iter=8)
part("LaundryBasket", "Sock", ellipsoid("sk", (10, 5, 16), (-6, 54, 8), angles(0.2, 0.6, 0)), [255, 170, 190], "Fabric", tris=400)

# ---------------------------------------------------------------------------
# POTTED PLANT 72 x 120 x 72 (tall) and SILL PLANT 12 x 22 x 12
# ---------------------------------------------------------------------------
part("PottedPlant", "Pot", lathe_y("pt", [(11, 0), (12.5, 0.6), (14, 28), (15, 29), (15, 31.5), (13.8, 32), (13, 27), (0.001, 26)], 48), CREAM, "SmoothPlastic", tris=1400)
part("PottedPlant", "Soil", cyl_axis("so", 2, 26, (0, 27.5, 0), "Y", bevel=0.4), [70, 50, 40], "Ground", tris=300)
stems, leaves, leaves2 = [], [], []
prng = __import__("random").Random(11)
for i in range(9):
    a = i / 9 * math.tau + 0.3
    lean = 0.35 + (i % 3) * 0.12
    h = 50 + (i % 4) * 14
    tip = (math.sin(a) * h * math.sin(lean), 28 + h * math.cos(lean), math.cos(a) * h * math.sin(lean))
    stems.append(capsule_y("st", 2.2, 0, h, 0, 0, rot=angles(lean * math.cos(a), 0, -lean * math.sin(a)), seg=12))
    stems[-1].matrix_world = Matrix.Translation(rb((tip[0] / 2, (28 + tip[1]) / 2, tip[2] / 2))) @ stems[-1].matrix_world.to_3x3().to_4x4()
    lf = ellipsoid("lf", (20, 2.6, 34), (tip[0] * 1.15, tip[1] + 2, tip[2] * 1.15), angles(0.5 * math.cos(a), -a, -0.5 * math.sin(a) + 0.2))
    (leaves if i % 2 else leaves2).append(lf)
part("PottedPlant", "Stems", stems, [80, 130, 70], "SmoothPlastic", tris=1600)
part("PottedPlant", "Leaves", leaves, [100, 175, 90], "SmoothPlastic", tris=2000)
part("PottedPlant", "LeavesDark", leaves2, [70, 140, 75], "SmoothPlastic", tris=2000)
part("SillPlant", "Pot", lathe_y("sp", [(3.5, 0), (4.2, 0.3), (4.8, 8), (5.2, 8.4), (5.2, 9.5), (4.6, 9.8), (4.2, 8.6), (0.001, 8.2)], 32), [245, 240, 235], "SmoothPlastic", tris=700)
blobs = [ellipsoid("bb%d" % i, (6, 6, 6), (math.cos(i * 2.1) * 3, 12 + (i % 3) * 2.2, math.sin(i * 2.1) * 3)) for i in range(7)] + [ellipsoid("bc", (9, 8, 9), (0, 14, 0))]
part("SillPlant", "Leaves", blobs, [110, 185, 95], "Grass", tris=1400, voxel=0.35, smooth_iter=8)

# ---------------------------------------------------------------------------
# TABLE LAMP 60 x 126 x 60 (the big lamp on the Sminskis' table; shade over (-18,·,-18))
# ---------------------------------------------------------------------------
part("TableLamp", "Base", lathe_y("tb", [(10, 0), (11, 0.6), (10.5, 2.4), (3, 3.6), (1.8, 4), (0.001, 4)], 48), [240, 235, 230], "SmoothPlastic", tris=900)
arm = [cyl_axis("pole", 110, 2.4, (0, 58, 0), "Y", bevel=0.4), ellipsoid("j", (4.5, 4.5, 4.5), (0, 112, 0)),
       cyl_axis("arm", 26, 2, (-9, 112, -9), "X", angles(0, math.pi / 4, 0), bevel=0.3), ellipsoid("j2", (4.5, 4.5, 4.5), (-18, 112, -18))]
part("TableLamp", "Arm", arm, [240, 235, 230], "SmoothPlastic", tris=1400)
part("TableLamp", "Shade", lathe_y("sh", [(17.5, 0), (18, 0.4), (14.5, 8), (9, 13), (5.5, 15), (2, 16.5), (0.001, 16.8), (0.001, 15.4), (4.8, 14.6), (8.4, 12.6), (13.5, 7.4), (16.5, 0.6)], 64, (-18, 96, -18)),
     [255, 235, 200], "SmoothPlastic", tris=2000)
part("TableLamp", "Bulb", ellipsoid("bl", (8, 9, 8), (-18, 104, -18)), [255, 225, 170], "Neon", tris=400)

# ---------------------------------------------------------------------------
# CEILING LAMP 40 x 18 x 40 (hangs from y=18)
# ---------------------------------------------------------------------------
part("CeilingLamp", "Shade", [lathe_y("cs", [(20, 0), (20.5, 0.4), (16, 6), (9, 9.5), (4, 11), (0.001, 11.4), (0.001, 10.4), (3.6, 10), (8.5, 8.6), (15, 5.4), (19, 0.6)], 64, (0, 4, 0)), cyl_axis("cord", 6, 1, (0, 15, 0), "Y")], [255, 240, 215], "SmoothPlastic", tris=1600)
part("CeilingLamp", "Bulb", ellipsoid("cb", (18, 7, 18), (0, 6, 0)), [255, 235, 200], "Neon", tris=400)

# ---------------------------------------------------------------------------
# CURTAIN 20 x 150 x 10 (hangs from the rod at the top)
# ---------------------------------------------------------------------------
part("Curtain", "Cloth", wavy_sheet("ct", 20, 146, 3.2, 3.5, 0.8, (0, 0, 0)), [165, 125, 185], "Fabric", tris=2600)
part("Curtain", "Rings", [torus_axis("rg%d" % i, 1.4, 0.35, (-8 + i * 4, 147.5, 0), "Z") for i in range(5)], [200, 170, 110], "Metal", tris=1000)

# ---------------------------------------------------------------------------
# SODA CAN 7 x 12 x 7
# ---------------------------------------------------------------------------
part("SodaCan", "Can", lathe_y("cn", [(2.8, 0), (3.4, 0.5), (3.5, 10), (3.2, 11.2), (0.001, 11.2)], 40), [235, 90, 90], "SmoothPlastic", tris=800)
part("SodaCan", "Top", [lathe_y("tp", [(3.0, 11.2), (3.1, 11.9), (2.6, 12), (0.001, 11.7)], 40), rbox("tab", (1.4, 0.3, 2), (0, 12.1, -0.4), 0.15)], [205, 205, 215], "Metal", tris=600)
part("SodaCan", "Label", cyl_axis("lb", 5.5, 7.05, (0, 5.5, 0), "Y"), [250, 245, 240], "SmoothPlastic", tris=300)

rigkit.export(os.path.join(kit.OUT_MESH, "SminskiRoom.fbx"), os.path.join(kit.OUT_MESH, "room_parts.json"))
json.dump(COLORS, open(os.path.join(kit.OUT_MESH, "room_colors.json"), "w"), indent=1)
print("ROOM_OK", len(rigkit.RECORD), sum(v["tris"] for v in rigkit.RECORD.values()))
