# Portraits of every Sminski (collection cards, capsule reveal) + the home hero shot.
#   Blender --background --factory-startup --python portraits.py -- [ids|hero]
import sys, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import bpy, math, kit, sminski, shapes, icons
from mathutils import Vector

argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
ONLY = set(argv[0].split(",")) if argv else None
RAW = os.path.join(kit.ROOT, "preview", "portraits_raw")
os.makedirs(RAW, exist_ok=True)

POSE = {"Glow": "wave", "Blush": "wave", "Sky": "idle", "Lemon": "cheer", "Lavender": "idle", "Mint": "wave",
        "Peach": "idle", "Ghost": "idle", "Night": "cheer", "Galaxy": "wave", "Secret": "cheer"}


def crown(root, head=(0, 0, 3.02)):
    """Little gold crown sitting on top of the head, tilted."""
    gold = icons.candy("CrownGold", (255, 205, 80), 0.2, 1.0)
    objs = []
    band = kit.lathe("CrownBand", [(0.4, 0.0), (0.44, 0.0), (0.44, 0.16), (0.4, 0.16)], 48)
    kit.assign(band, gold)
    objs.append(band)
    for i in range(5):
        a = i / 5 * math.tau
        spike = kit.lathe("Spike", [(0.001, 0.0), (0.12, 0.0), (0.001, 0.3)], 16)
        spike.location = (math.cos(a) * 0.42, math.sin(a) * 0.42, 0.14)
        kit.assign(spike, gold)
        objs.append(spike)
        bpy.ops.mesh.primitive_uv_sphere_add(radius=0.06, location=(math.cos(a) * 0.42, math.sin(a) * 0.42, 0.46))
        gem = bpy.context.active_object
        kit.assign(gem, icons.candy("Gem%d" % i, (255, 150, 190) if i % 2 else (140, 200, 255), 0.1))
        objs.append(gem)
    holder = bpy.data.objects.new("Crown", None)
    bpy.context.scene.collection.objects.link(holder)
    for o in objs:
        for p in o.data.polygons:
            p.use_smooth = True
        o.parent = holder
    holder.location = (0.08, 0.05, head[2] + 0.6)
    holder.rotation_euler = (math.radians(10), math.radians(-14), 0)
    holder.parent = root
    return holder


def headband(root, head=(0, 0, 3.02)):
    """Red ninja headband across the forehead with two tails flying back."""
    red = icons.candy("Band", (230, 70, 60), 0.35)
    band = kit.lathe("Headband", [(0.805, -0.08), (0.83, -0.06), (0.83, 0.06), (0.805, 0.08)], 64)
    band.location = (0, 0, head[2] + 0.3)
    band.rotation_euler = (math.radians(-12), 0, 0)
    kit.assign(band, red)
    band.parent = root
    for i, (dz, rot) in enumerate(((0.05, 0.35), (-0.15, 0.85))):
        tail = icons.puffy2d("Tail", icons.rounded_rect_pts(0.55, 0.16, 0.07), 0.05, 0.02, red, subsurf=1)
        tail.location = (0.25, 0.9, head[2] + 0.3 + dz)
        tail.rotation_euler = (math.pi / 2, rot, math.radians(-20))
        tail.parent = root
    return band


def portrait(cid):
    kit.reset()
    root = sminski.build(cid, POSE[cid], brows=True, mood="calm")
    root.rotation_euler.z = math.radians(-14)
    kit.studio_lights(1.1)
    kit.camera((0, -8.6, 2.5), (0, 0, 1.95), lens=62)
    kit.render(os.path.join(RAW, cid + ".png"), 512, 512, samples=110)


def hero():
    kit.reset()
    bpy.context.scene.world.node_tree.nodes["Background"].inputs["Strength"].default_value = 0.3
    sminski.CHARS["Glow"] = dict(body=(165, 235, 95), glow=(150, 255, 90))
    specs = [("Mint", Vector((-2.6, 1.4, 0)), -0.25, "crown"), ("Glow", Vector((0, 0, 0)), -0.05, None), ("Lemon", Vector((2.5, 1.2, 0)), 0.2, "band")]
    for i, (cid, loc, yaw, extra) in enumerate(specs):
        r = sminski.build(cid, "run", brows=True, mood="determined", name="S%d" % i)
        r.location = loc
        r.rotation_euler.z = yaw
        if extra == "crown":
            crown(r)
        elif extra == "band":
            headband(r)
    # coins scattered on the floor + a couple in the air
    for j, (x, y, z, rx, rz) in enumerate(((-3.5, -1.5, 0.25, 80, 20), (-1.2, -2.2, 0.25, 85, -30), (1.4, -2.0, 0.25, 82, 40),
                                             (3.6, -1.4, 0.25, 78, -10), (-0.2, -3.0, 0.25, 88, 5), (4.2, 0.6, 1.8, 30, 60), (-4.3, 0.3, 2.3, 40, -50))):
        body, star = shapes.build_coin("Coin%d" % j)
        for o in (body, star):
            o.scale = (0.55, 0.55, 0.55)
            o.location = (x, y, z)
            o.rotation_euler = (math.radians(90 - rx) if z < 1 else math.radians(rx), 0, math.radians(rz))
    kit.studio_lights(1.25)
    kit.area_light("Lamp", (7, -1, 5), (0, 0, 1.5), 450, (1.0, 0.8, 0.55), 3)
    kit.camera((0.6, -13, 3.6), (0, 0, 1.7), lens=50)
    kit.render(os.path.join(RAW, "hero.png"), 1280, 720, samples=128)


if __name__ == "__main__":
    if ONLY and "hero" in ONLY:
        hero()
        print("HERO_OK")
    else:
        for cid in sminski.CHARS:
            if ONLY and cid not in ONLY:
                continue
            portrait(cid)
            print("PORTRAIT_OK", cid)
