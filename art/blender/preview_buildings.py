# Style check for the city kit: build a short street and render it.
#   Blender --background --factory-startup --python art/blender/preview_buildings.py
import sys, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import bpy, kit, buildings
from mathutils import Vector

kit.reset()
P = buildings.PAL
M = lambda n, c, r=0.62, **kw: kit.mat(n, kit.srgb(*c), rough=r, **kw)

WALLS = [P["cream"], P["mint"], P["sand"], P["sage"], P["white"]]
ACCENTS = [P["moss"], P["clay"], P["slate"], P["sage"]]
GLASS = M("glass", (96, 124, 134), 0.18)
STONE = M("stone", P["stone"], 0.8)
TIMBER = M("timber", P["timber"], 0.85)
METAL = M("metal", (150, 154, 156), 0.5)
LEAF = M("leaf", P["leaf"], 0.78)
LEAF2 = M("leaf2", P["leafDark"], 0.78)

x = 0.0
for i, floors in enumerate([4, 3, 5, 3, 4, 3]):
    wall = M("wall%d" % i, WALLS[i % len(WALLS)])
    acc = M("acc%d" % i, ACCENTS[i % len(ACCENTS)], 0.55)
    buildings.use({"wall": wall, "accent": acc, "glass": GLASS, "stone": STONE,
                   "door": acc, "timber": TIMBER, "metal": METAL, "leaf": LEAF, "leaf2": LEAF2})
    g = buildings.ground_storefront("g%d" % i); g.location = (x, 0, 0)
    z = 14.0
    for f in range(floors - 1):
        m = buildings.floor_module("f%d_%d" % (i, f)); m.location = (x, 0, z)
        z += buildings.FLOOR_H
    r = buildings.roof_cap("r%d" % i); r.location = (x, 0, z)
    x += buildings.UNIT_W

road = buildings._box("road", (x + 120, 44, 0.4), (x / 2 - 19, -30, 0.2), bevel=0)
kit.assign(road, M("asphalt", (78, 80, 86), 0.92))
walk = buildings._box("walk", (x + 120, 14, 0.9), (x / 2 - 19, -15, 0.45), bevel=0.1)
kit.assign(walk, STONE)

buildings.use({"wall": LEAF, "leaf": LEAF, "leaf2": LEAF2, "timber": TIMBER,
               "accent": M("bloom", (244, 178, 196), 0.7), "stone": STONE,
               "metal": METAL, "glass": GLASS, "door": METAL})
for i in range(6):
    px = 12 + i * buildings.UNIT_W
    buildings.tree("tr%d" % i).location = (px, -13, 0.9)
    buildings.lamp("lp%d" % i).location = (px + 20, -16, 0.9)
    b = buildings.bench("bn%d" % i); b.location = (px + 31, -12, 0.9); kit.assign(b, TIMBER)
    buildings.planter("pl%d" % i).location = (px + 8, -16, 0.9)

# one clear sun, a soft sky fill. No studio rig -- this is meant to look like
# daylight on a street, which is the whole point of the lighting pass.
sun = bpy.data.lights.new("Sun", "SUN")
sun.energy = 3.4
sun.angle = 0.08
so = bpy.data.objects.new("Sun", sun)
bpy.context.collection.objects.link(so)
so.rotation_euler = (1.02, 0.1, 2.35)
w = bpy.context.scene.world.node_tree.nodes["Background"]
w.inputs["Color"].default_value = kit.srgb(150, 182, 222)
w.inputs["Strength"].default_value = 1.35
bpy.context.scene.render.film_transparent = False
bpy.context.scene.view_settings.view_transform = "Standard"

kit.camera((x * 1.02, -190, 62), (x * 0.36, 4, 26), lens=40)
out = os.path.join(os.path.dirname(kit.OUT_MESH), "preview", "city_kit.png")
os.makedirs(os.path.dirname(out), exist_ok=True)
kit.render(out, 1280, 720, samples=72)
print("rendered ->", out)
