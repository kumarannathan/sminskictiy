# Smooth toy-style props (key-art look) replacing ReplicatedStorage.SminskiAssets.
# Each prop is several single-colour meshes named "<Prop>__<Part>"; props.json
# records every part's size, offset from the prop origin, colour and material.
# In Studio they are assembled into Models (see the assemble step in chat/tools).
import sys, os, json
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import bpy, bmesh, math, kit, shapes
import rigkit
from rigkit import ellipsoid, rbox, capsule_y, cyl_axis, merge, finish, angles, place, rb

kit.reset()
COLORS = {}
font = bpy.data.fonts.load(kit.FONT_ROUNDED)


def part(prop, name, obj, color, material="SmoothPlastic", tris=1500, voxel=0, smooth_iter=0):
    o = merge(obj if isinstance(obj, list) else [obj], prop + "__" + name, voxel, smooth_iter)
    finish(o, prop + "__" + name, tris, prop)
    COLORS[prop + "__" + name] = {"color": color, "material": material}


def text_mesh(ch, size, depth, center, rot=None):
    cu = bpy.data.curves.new("t", "FONT")
    cu.body = ch
    cu.font = font
    cu.size = size
    cu.extrude = depth / 2
    cu.bevel_depth = depth * 0.25
    cu.bevel_resolution = 3
    cu.align_x = "CENTER"
    cu.align_y = "CENTER"
    o = kit.new_obj("t", cu)
    bpy.context.view_layer.objects.active = o
    o.select_set(True)
    bpy.ops.object.convert(target="MESH")
    o = bpy.context.active_object
    # text lies flat facing Roblox +Y; stand it up to face +Z
    base = angles(math.pi / 2, 0, 0) if rot is None else rot @ angles(math.pi / 2, 0, 0)
    return place(o, center, base)


def lathe_y(name, prof, steps=48, center=(0, 0, 0), rot=None):
    o = kit.lathe(name, prof, steps)
    return place(o, center, rot)


# ---------------------------------------------------------------------------
# TOY BLOCK (ABC block, 4.2 cube)
# ---------------------------------------------------------------------------
part("ToyBlock", "Body", rbox("b", (4.2, 4.2, 4.2), (0, 0, 0), 0.55), [255, 120, 105], tris=1200)
panels = []
for ax, rot in (("z", None), ("-z", angles(0, math.pi, 0)), ("x", angles(0, math.pi / 2, 0)), ("-x", angles(0, -math.pi / 2, 0))):
    panels.append(rbox("p", (3.1, 3.1, 0.3), (0, 0, 2.02), 0.35) if rot is None else rbox("p", (3.1, 3.1, 0.3), tuple(rot @ rigkit.Vector((0, 0, 2.02))), 0.35, rot))
panels.append(rbox("pt", (3.1, 0.3, 3.1), (0, 2.02, 0), 0.35))
part("ToyBlock", "Panels", panels, [255, 244, 215], tris=1600)
letters = []
for ch, rot in (("A", None), ("B", angles(0, math.pi, 0)), ("★", angles(0, math.pi / 2, 0)), ("C", angles(0, -math.pi / 2, 0))):
    if ch == "★":
        st = kit.star_prism("s", 1.05, 0.48, 0.3)
        letters.append(place(st, tuple((rot) @ rigkit.Vector((0, 0, 2.2))), rot @ angles(math.pi / 2, 0, 0)))
    else:
        letters.append(text_mesh(ch, 2.5, 0.3, tuple((rot or angles()) @ rigkit.Vector((0, -0.05, 2.2))), rot))
part("ToyBlock", "Letters", letters, [255, 120, 105], tris=2400)
COLORS["ToyBlock__Letters"]["tint"] = "Body"

# ---------------------------------------------------------------------------
# BOOK STACK (5.5 x 8.8 x 5)
# ---------------------------------------------------------------------------
books = [((5.2, 2.0, 4.4), 0.0, 0.06, [110, 170, 240]), ((4.8, 2.2, 4.0), 2.1, -0.1, [255, 125, 110]),
         ((5.0, 1.8, 4.2), 4.1, 0.14, [150, 205, 140]), ((4.4, 2.3, 3.6), 6.2, -0.05, [185, 160, 240])]
pages = []
for i, (sz, y, yaw, col) in enumerate(books):
    rot = angles(0, yaw, 0)
    cover = rbox("c", sz, (0, y + sz[1] / 2, 0), 0.35, rot)
    part("BookStack", "Cover%d" % (i + 1), cover, col, tris=600)
    pg = rbox("pg", (sz[0] - 0.35, sz[1] - 0.45, sz[2] - 0.1), (0.2, y + sz[1] / 2, 0), 0.12, rot)
    pages.append(pg)
part("BookStack", "Pages", pages, [252, 246, 228], tris=1200)

# ---------------------------------------------------------------------------
# PENCIL (lies along X, like the lane-crossing bar it dresses)
# ---------------------------------------------------------------------------
L = 12.0
part("Pencil", "Body", cyl_axis("b", L * 0.62, 1.6, (-0.4, 0, 0), "X", angles(math.pi / 6, 0, 0), seg=6, bevel=0.18), [255, 205, 70], tris=600)
part("Pencil", "Band", cyl_axis("bd", 0.9, 1.66, (-4.55, 0, 0), "X", bevel=0.12), [200, 205, 215], "Metal", tris=600)
part("Pencil", "Eraser", merge([cyl_axis("e", 1.2, 1.55, (-5.5, 0, 0), "X", bevel=0.4)], "er", 0, 0), [255, 150, 170], tris=600)
wood = lathe_y("w", [(0.8, 0.0), (0.12, 2.2), (0.001, 2.25)], 32, (2.95, 0, 0), angles(0, 0, -math.pi / 2))
part("Pencil", "Wood", wood, [240, 205, 160], tris=500)
lead = lathe_y("l", [(0.25, 0.0), (0.001, 0.75)], 24, (4.6, 0, 0), angles(0, 0, -math.pi / 2))
part("Pencil", "Lead", lead, [60, 60, 70], tris=200)

# ---------------------------------------------------------------------------
# TOY TRAIN CAR (5.5 x 6 x 8.9, along Z, tiles for long trains)
# ---------------------------------------------------------------------------
part("ToyTrain", "Body", [rbox("b", (5.0, 3.0, 8.6), (0, 2.6, 0), 0.8), cyl_axis("boiler", 4.2, 3.6, (0, 3.9, 1.6), "Z", bevel=0.4)], [235, 85, 85], tris=2200, voxel=0.09, smooth_iter=6)
part("ToyTrain", "Cabin", rbox("c", (4.8, 3.2, 3.2), (0, 5.3, -2.5), 0.6), [110, 170, 240], tris=800)
part("ToyTrain", "Roof", rbox("r", (5.4, 0.6, 3.8), (0, 7.05, -2.5), 0.28), [255, 205, 70], tris=500)
part("ToyTrain", "Chimney", [cyl_axis("ch", 1.6, 1.1, (0, 6.4, 2.4), "Y", bevel=0.2), cyl_axis("ct", 0.5, 1.6, (0, 7.3, 2.4), "Y", bevel=0.2)], [60, 55, 70], tris=600)
wheels = []
for x in (-2.55, 2.55):
    for z in (-2.8, 0.0, 2.8):
        wheels.append(cyl_axis("wh", 0.7, 2.2, (x, 1.1, z), "X", bevel=0.2))
part("ToyTrain", "Wheels", wheels, [55, 50, 65], tris=2000)
hubs = []
for x in (-2.95, 2.95):
    for z in (-2.8, 0.0, 2.8):
        hubs.append(ellipsoid("hb", (0.3, 0.9, 0.9), (x, 1.1, z)))
part("ToyTrain", "Hubs", hubs, [255, 205, 70], "Metal", tris=900)
part("ToyTrain", "Bumper", rbox("bp", (5.2, 0.9, 0.6), (0, 1.5, 4.45), 0.3), [255, 205, 70], tris=300)

# ---------------------------------------------------------------------------
# RUBBER DUCK (faces +Z)
# ---------------------------------------------------------------------------
duck = merge([ellipsoid("bd", (5.4, 3.6, 6.2), (0, 1.8, -0.4)), ellipsoid("tail", (2.4, 2.2, 2.4), (0, 2.8, -3.2)),
              ellipsoid("hd", (3.6, 3.4, 3.4), (0, 4.4, 1.4))], "duck", 0.08, 8)
part("RubberDuck", "Body", duck, [255, 215, 60], tris=2400)
part("RubberDuck", "Beak", ellipsoid("bk", (1.9, 0.8, 1.7), (0, 4.0, 3.1)), [255, 140, 60], tris=400)
part("RubberDuck", "Eyes", [ellipsoid("e1", (0.45, 0.6, 0.3), (-0.8, 4.8, 2.85)), ellipsoid("e2", (0.45, 0.6, 0.3), (0.8, 4.8, 2.85))], [40, 35, 45], tris=300)

# ---------------------------------------------------------------------------
# SNEAKER (giant stomping shoe, along Z, same style as the kid's)
# ---------------------------------------------------------------------------
part("Sneaker", "Upper", [rbox("u", (5.4, 3.0, 7.6), (0, 2.9, -0.6), 1.3), ellipsoid("toe", (5.4, 3.6, 5.4), (0, 2.6, 3.2)),
                          capsule_y("collar", 3.4, 5.0, 4.6, 0, -2.2)], [252, 252, 255], tris=2400, voxel=0.12, smooth_iter=8)
part("Sneaker", "Sole", [rbox("so", (5.8, 1.3, 11.4), (0, 0.65, 0.2), 0.6)], [236, 236, 242], tris=800)
part("Sneaker", "Stripe", rbox("st", (5.5, 0.8, 9.6), (0, 1.55, 0.1), 0.35), [235, 85, 85], tris=500)
part("Sneaker", "Laces", [rbox("la%d" % i, (2.4, 0.4, 0.6), (0, 4.4 - i * 0.35, 1.2 + i * 0.9), 0.18, angles(-0.35, 0, 0)) for i in range(3)], [240, 240, 245], tris=500)

# ---------------------------------------------------------------------------
# DOG BOWL
# ---------------------------------------------------------------------------
part("DogBowl", "Bowl", lathe_y("bw", [(2.2, 0.0), (2.7, 0.15), (2.75, 2.6), (2.5, 3.0), (2.25, 2.7), (1.9, 0.7), (0.001, 0.6)], 64, (0, -1.5, 0)), [235, 90, 90], tris=1600)
kib = [ellipsoid("k%d" % i, (0.75, 0.55, 0.75), (math.cos(i * 2.4) * (0.4 + (i % 4) * 0.35), 0.1 + (i % 3) * 0.12, math.sin(i * 2.4) * (0.4 + (i % 4) * 0.35))) for i in range(16)]
part("DogBowl", "Kibble", kib, [170, 110, 60], tris=1500)

# ---------------------------------------------------------------------------
# PARK BIN
# ---------------------------------------------------------------------------
part("ParkBin", "Can", lathe_y("cn", [(2.7, 0.0), (3.0, 0.3), (3.1, 8.2), (2.9, 8.4), (0.001, 8.3)], 56, (0, -5.25, 0)), [90, 160, 110], tris=1400)
part("ParkBin", "Lid", lathe_y("ld", [(3.25, 0.0), (3.3, 0.35), (2.6, 1.3), (1.0, 1.9), (0.001, 2.0)], 56, (0, 3.1, 0)), [60, 120, 80], tris=1200)
part("ParkBin", "Bands", [cyl_axis("b1", 0.5, 6.3, (0, -2.5, 0), "Y", bevel=0.15), cyl_axis("b2", 0.5, 6.3, (0, 0.8, 0), "Y", bevel=0.15)], [60, 120, 80], tris=800)

# ---------------------------------------------------------------------------
# PARK BENCH (along X, seat facing +Z)
# ---------------------------------------------------------------------------
planks = [rbox("s%d" % i, (15.6, 0.45, 1.25), (0, 3.5, -1.4 + i * 1.4), 0.18) for i in range(3)]
planks += [rbox("bk%d" % i, (15.6, 1.2, 0.45), (0, 5.2 + i * 1.4, -2.7), 0.18, angles(0.18, 0, 0)) for i in range(2)]
part("ParkBench", "Planks", planks, [200, 140, 85], tris=2000)
legs = []
for x in (-6.4, 6.4):
    legs += [rbox("lg", (0.6, 3.5, 0.6), (x, 1.75, 1.3), 0.2), rbox("lg2", (0.6, 6.8, 0.6), (x, 3.4, -2.6), 0.2),
             rbox("arm", (0.6, 0.5, 4.8), (x, 4.9, -0.3), 0.22)]
part("ParkBench", "Frame", legs, [60, 60, 75], "Metal", tris=1600)

# ---------------------------------------------------------------------------
# PARK TREE (fluffy toy-like canopy)
# ---------------------------------------------------------------------------
trunk = merge([lathe_y("tr", [(4.2, 0.0), (3.2, 1.5), (2.4, 5.0), (2.0, 16.0), (1.6, 24.0), (0.001, 25.0)], 32, (0, -23.6, 0)),
               capsule_y("br1", 1.4, -6, 2, 3.5, 0.5, rot=angles(0, 0, -0.7)), capsule_y("br2", 1.2, -5, 3, -3.2, -0.8, rot=angles(0, 0, 0.8))], "trunk", 0.3, 6)
part("ParkTree", "Trunk", trunk, [135, 95, 70], tris=1600)
blobs = [ellipsoid("c0", (26, 22, 26), (0, 8, 0)), ellipsoid("c1", (20, 18, 20), (-10, 4, 5)), ellipsoid("c2", (20, 17, 20), (10, 5, -4)),
         ellipsoid("c3", (18, 16, 18), (3, 3, 11)), ellipsoid("c4", (18, 16, 18), (-4, 5, -11)), ellipsoid("c5", (16, 14, 16), (4, 16, 3))]
part("ParkTree", "Canopy", blobs, [120, 200, 100], tris=3800, voxel=0.7, smooth_iter=12)

# ---------------------------------------------------------------------------
# FLOOR LAMP (warm glowing shade)
# ---------------------------------------------------------------------------
part("FloorLamp", "Base", lathe_y("bs", [(7.5, 0.0), (7.8, 0.6), (7.0, 1.8), (1.2, 2.4), (0.001, 2.5)], 48, (0, -28.3, 0)), [70, 60, 80], "Metal", tris=900)
part("FloorLamp", "Pole", cyl_axis("pl", 40, 1.1, (0, -6.5, 0), "Y", bevel=0.3), [200, 190, 170], "Metal", tris=300)
part("FloorLamp", "Shade", lathe_y("sh", [(8.9, 0.0), (9.0, 0.4), (6.2, 14.0), (6.0, 14.4), (5.6, 14.3), (8.5, 0.5), (8.4, 0.1)], 64, (0, 13.8, 0)), [255, 230, 190], "SmoothPlastic", tris=1400)
part("FloorLamp", "Bulb", ellipsoid("bl", (4.2, 5.0, 4.2), (0, 17.5, 0)), [255, 220, 160], "Neon", tris=400)

# ---------------------------------------------------------------------------
# SOFA (long along Z, seat facing +X)
# ---------------------------------------------------------------------------
sofa = merge([rbox("seat", (5.4, 2.2, 15.6), (0.3, -0.4, 0), 1.0), rbox("back", (1.8, 4.6, 15.8), (-2.3, 1.2, 0), 0.85),
              rbox("armL", (6.0, 3.4, 1.8), (0, 0.4, 7.2), 0.85), rbox("armR", (6.0, 3.4, 1.8), (0, 0.4, -7.2), 0.85)], "sofa", 0.12, 8)
part("Sofa", "Frame", sofa, [150, 120, 205], tris=3000)
part("Sofa", "Cushions", [rbox("c%d" % i, (4.6, 1.2, 4.8), (0.6, 1.1, -5 + i * 5), 0.55) for i in range(3)], [185, 160, 240], tris=1800)
part("Sofa", "Legs", [cyl_axis("lg", 1.0, 0.9, (x, -1.9, z), "Y", bevel=0.2) for x in (-2.2, 2.4) for z in (-7, 7)], [90, 70, 60], tris=400)

rigkit.export(os.path.join(kit.OUT_MESH, "SminskiProps.fbx"), os.path.join(kit.OUT_MESH, "props_parts.json"))
json.dump(COLORS, open(os.path.join(kit.OUT_MESH, "props_colors.json"), "w"), indent=1)
print("PROPS_OK", len(rigkit.RECORD), sum(v["tris"] for v in rigkit.RECORD.values()))
