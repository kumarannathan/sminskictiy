# Smooth in-game meshes for every animated character, built in the exact
# joint space Models.lua already uses (so all poses keep working):
#   Sminski (head/torso/arm/leg), the chibi kid, the dog, plus the star coin.
# Output: art/meshes/SminskiRig.fbx + rig.json (size + offset from each joint).
import sys, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import bpy, math, kit, shapes
from rigkit import *

kit.reset()
H = math.pi / 2

# ---------------------------------------------------------------------------
# SMINSKI (head radius 0.8; body joint 1.5 above the feet)
# ---------------------------------------------------------------------------
bpy.ops.mesh.primitive_uv_sphere_add(segments=40, ring_count=20, radius=0.8)
head = bpy.context.active_object
finish(head, "SmHead", 2000, "head", uv_rect=(-0.8, 0.8, -0.8, 0.8))

prof = [(0.001, 0.62), (0.34, 0.64), (0.55, 0.74), (0.66, 0.95), (0.66, 1.2), (0.6, 1.5),
        (0.57, 1.8), (0.62, 2.02), (0.6, 2.2), (0.46, 2.36), (0.26, 2.46), (0.001, 2.5)]
torso = kit.lathe("SmTorso", [(r, z - 1.5) for r, z in prof], steps=40)
torso.scale = (1, 0.86, 1)
kit.smooth(torso, 1)
finish(torso, "SmTorso", 2200, "body")

arm = merge([ellipsoid("a", (0.46, 0.46, 0.46), (0, -0.05, 0)),
             ellipsoid("b", (0.4, 1.12, 0.42), (0, -0.5, 0)),
             ellipsoid("c", (0.46, 0.46, 0.46), (0, -1.02, 0.03))], "SmArm", 0.02, 10)
finish(arm, "SmArm", 1600, "arm")

leg = merge([ellipsoid("l", (0.58, 0.88, 0.62), (0, -0.38, 0.02))], "SmLeg", 0, 0)
finish(leg, "SmLeg", 1000, "leg")

# ---------------------------------------------------------------------------
# KID (chibi, hoodie + backwards cap)
# ---------------------------------------------------------------------------
V = 0.14  # voxel size at kid scale
finish(merge([capsule_y("t", 5.2, 0, -5.6)], "KidThigh", 0, 0), "KidThigh", 1200, "thigh")
finish(merge([capsule_y("s", 4.9, 0, -4.6)], "KidShin", 0, 0), "KidShin", 1200, "shin")
finish(merge([cyl_axis("c", 1.2, 5.3, (0, -5, 0), "Y", bevel=0.35)], "KidCuff", 0, 0), "KidCuff", 600, "shin")
upper = merge([rbox("u", (5.4, 3.0, 6.4), (0, -6, 0.6), 1.4),
               ellipsoid("toe", (5.4, 3.4, 5.4), (0, -6.2, 3.6))], "KidShoeUpper", V, 8)
finish(upper, "KidShoeUpper", 2000, "shin")
sole = merge([rbox("so", (5.8, 1.3, 8.6), (0, -7.7, 1.3), 0.6),
              cyl_axis("st", 1.3, 5.8, (0, -7.7, 4.9), "Y")], "KidSole", V * 0.8, 6)
finish(sole, "KidSole", 1600, "shin")
finish(merge([rbox("str", (5.52, 0.8, 8.72), (0, -7.1, 1.3), 0.35)], "KidStripe", 0, 0), "KidStripe", 800, "shin")
finish(merge([rbox("la", (2.2, 0.4, 2.8), (0, -4.5, 2.4), 0.18, angles(-0.35, 0, 0))], "KidLaces", 0, 0), "KidLaces", 400, "shin")

hood = merge([rbox("blk", (11.6, 8.4, 7.2), (0, 18.6, 0), 2.4),
              cyl_axis("sh", 11.6, 7.2, (0, 22.8, 0), "X"),
              ellipsoid("hd", (9, 4.2, 4.2), (0, 25.3, -2.6))], "KidHoodie", V * 1.3, 10)
finish(hood, "KidHoodie", 3000, "torso")
finish(merge([cyl_axis("hp", 11.8, 7.4, (0, 14.4, 0), "X", bevel=1.2)], "KidHips", 0, 0), "KidHips", 1400, "torso")
trim = merge([rbox("hem", (12, 1.2, 7.6), (0, 15.2, 0), 0.5), rbox("pk", (7, 3, 0.8), (0, 17.4, 3.55), 0.35)], "KidTrim", 0, 0)
finish(trim, "KidTrim", 1200, "torso")
strings = [capsule_y("s1", 0.35, 25.0, 21.9, -1.2, 3.7), capsule_y("s2", 0.35, 25.0, 21.9, 1.2, 3.7),
           ellipsoid("t1", (0.7, 0.7, 0.7), (-1.2, 21.7, 3.75)), ellipsoid("t2", (0.7, 0.7, 0.7), (1.2, 21.7, 3.75))]
finish(merge(strings, "KidStrings", 0, 0), "KidStrings", 800, "torso")

# bigger chibi head (dia 13.5, same neck), cap + hair fringe scaled to match
HK = 13.5 / 11.5
HC = 7.8  # head centre above the neck joint (bottom stays at 1.05)
def hy(y):  # old head-space y -> new
    return HC + (y - 6.8) * HK
khead = merge([cyl_axis("neck", 3, 4.4, (0, 0.6, 0), "Y"),
               ellipsoid("ball", (13.5, 13.5, 13.5), (0, HC, 0), seg=64),
               ellipsoid("earL", (2.0, 3.6, 2.7), (-6.75, hy(6.6), 0)),
               ellipsoid("earR", (2.0, 3.6, 2.7), (6.75, hy(6.6), 0))], "KidHead", 0.12, 8)
finish(khead, "KidHead", 3200, "head", uv_rect=(-6.75, 6.75, HC - 6.75, HC + 6.75))
cap = merge([ellipsoid("dome", (14.4, 7.8, 14.4), (0, hy(10.4) + 1.6, -0.2), seg=64),
             cyl_axis("band", 1.6, 14.5, (0, hy(8.6) + 1.6, -0.2), "Y"),
             ellipsoid("brim", (11, 1.0, 7.6), (0, hy(8.4) + 1.6, -9.4), angles(-0.12, 0, 0))], "KidCap", V, 8)
finish(cap, "KidCap", 2600, "head")
finish(merge([ellipsoid("btn", (1.8, 1.8, 1.8), (0, hy(13.6) + 1.8, -0.2))], "KidCapButton", 0, 0), "KidCapButton", 300, "head")
# hair: a shell just outside the head under the cap, with a swoopy fringe
hair = [ellipsoid("shell", (14.2, 6.8, 14.4), (0, hy(8.9) + 0.8, -0.4), seg=64)]
for i, x in enumerate((-4.4, -2.0, 0.4, 2.8, 4.8)):
    hair.append(ellipsoid("fr%d" % i, (3.4, 2.7, 2.4), (x, 11.35, 5.55 - abs(x) * 0.22), angles(0.7, 0, -0.35 + i * 0.12)))
hair += [ellipsoid("sideL", (3.2, 4.2, 5), (-6.3, hy(8.0), 0.8)), ellipsoid("sideR", (3.2, 4.2, 5), (6.3, hy(8.0), 0.8))]
finish(merge(hair, "KidHair", 0.13, 8), "KidHair", 2400, "head")
finish(merge([ellipsoid("hf", (14.4, 8.6, 14.6), (0, hy(9.8), -0.7), seg=64)], "KidHairFull", 0, 0), "KidHairFull", 1600, "head")
finish(merge([ellipsoid("bun", (5.2, 5.2, 5.2), (0, hy(13.6) + 0.6, -2.8))], "KidBun", 0, 0), "KidBun", 500, "head")

finish(merge([capsule_y("sl", 4.4, 0, -7.6)], "KidSleeve", 0, 0), "KidSleeve", 1200, "arm")
finish(merge([cyl_axis("cf", 1.2, 4.7, (0, -8.6, 0), "Y", bevel=0.3)], "KidSleeveCuff", 0, 0), "KidSleeveCuff", 500, "arm")
for side, tx in (("L", 1.8), ("R", -1.8)):
    hand = merge([ellipsoid("h", (4.4, 4.4, 4.4), (0, -10.8, 0.2)), ellipsoid("th", (1.6, 1.6, 1.6), (tx, -9.9, 1.2))], "KidHand" + side, 0.1, 8)
    finish(hand, "KidHand" + side, 1400, "arm")

# ---------------------------------------------------------------------------
# DOG (golden retriever proportions)
# ---------------------------------------------------------------------------
body = merge([ellipsoid("b", (15, 13, 28), (0, 0, 0), seg=64), ellipsoid("back", (12, 6, 20), (0, 5, -1))], "DogBody", 0.25, 10)
finish(body, "DogBody", 3000, "body")
finish(merge([ellipsoid("chest", (11, 10, 12), (0, -1.5, 9))], "DogChest", 0, 0), "DogChest", 1000, "body")
finish(merge([cyl_axis("col", 1.6, 11, (0, 5, 11.5), "Y", angles(0.5, 0, 0), bevel=0.5)], "DogCollar", 0, 0), "DogCollar", 800, "body")
finish(merge([ellipsoid("tag", (2.4, 2.4, 2.4), (0, 1.2, 15))], "DogTag", 0, 0), "DogTag", 300, "body")
finish(merge([ellipsoid("h", (13, 12, 12), (0, 3, 3), seg=64)], "DogHead", 0, 0), "DogHead", 2200, "head", uv_rect=(-6.5, 6.5, -3, 9))
finish(merge([ellipsoid("sn", (8, 6, 9), (0, 0, 9.5))], "DogSnout", 0, 0), "DogSnout", 1000, "head")
finish(merge([ellipsoid("no", (3.4, 2.6, 2.4), (0, 2.2, 13.8))], "DogNose", 0, 0), "DogNose", 400, "head")
finish(merge([ellipsoid("jaw", (6.5, 2.4, 7), (0, 0, 3.6))], "DogJaw", 0, 0), "DogJaw", 800, "jaw")
finish(merge([ellipsoid("tg", (3.4, 1, 5), (0, -0.6, 4.6), angles(-0.3, 0, 0))], "DogTongue", 0, 0), "DogTongue", 400, "jaw")
finish(merge([ellipsoid("ear", (3, 9, 6), (0, -3.8, 0))], "DogEar", 0, 0), "DogEar", 800, "ear")
finish(merge([cyl_axis("lg", 9, 4.6, (0, -4.5, 0), "Y"), ellipsoid("top", (4.6, 4.6, 4.6), (0, 0, 0)),
              ellipsoid("low", (4.6, 4.6, 4.6), (0, -9, 0))], "DogLeg", 0.16, 8), "DogLeg", 1200, "leg")
finish(merge([ellipsoid("paw", (5.6, 3, 6.6), (0, -9.4, 1))], "DogPaw", 0, 0), "DogPaw", 600, "leg")
finish(merge([ellipsoid("tail", (3.4, 3.4, 11), (0, 0, -5))], "DogTail", 0, 0), "DogTail", 600, "tail")

# ---------------------------------------------------------------------------
# STAR COIN (lies in the Roblox XY plane, facing +Z)
# ---------------------------------------------------------------------------
body_c, _ = shapes.build_coin("StarCoin", subsurf=2, apply=True)
body_c.rotation_euler = (H, 0, 0)  # Blender XY -> faces -Y (= Roblox +Z)
finish(body_c, "StarCoin", 3200, "")

out = os.path.join(kit.OUT_MESH, "SminskiRig.fbx")
export(out, os.path.join(kit.OUT_MESH, "rig.json"))
tot = sum(v["tris"] for v in RECORD.values())
print("RIG_OK", len(RECORD), "meshes", tot, "tris")
