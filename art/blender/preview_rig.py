# Re-import the exported FBX and assemble the kid, dog and a Sminski at rest,
# using rig.json offsets exactly the way Models.lua will.
import sys, os, json
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import bpy, math, kit
from rigkit import rb, P, PT, angles
from mathutils import Vector, Matrix

kit.reset()
rig = json.load(open(os.path.join(kit.OUT_MESH, "rig.json")))
bpy.ops.import_scene.fbx(filepath=os.path.join(kit.OUT_MESH, "SminskiRig.fbx"))
src = {o.name.split(".")[0]: o for o in bpy.data.objects if o.type == "MESH"}

def col(rgb, rough=0.35, metal=0.0):
    return kit.mat("m%d_%d_%d" % rgb, kit.srgb(*rgb), rough=rough, metal=metal, coat=0.4)

def put(name, jointCF, color, origin):
    o = src[name].copy()
    o.data = src[name].data
    bpy.context.scene.collection.objects.link(o)
    off = Vector(rig[name]["offset"])
    # jointCF: (Matrix3 rot, Vector pos) in Roblox space
    rot, pos = jointCF
    w = pos + rot @ off + Vector(origin)
    mb = P @ rot @ PT
    o.matrix_world = Matrix.Translation(rb(w)) @ mb.to_4x4()
    o.data.materials.clear()
    o.data.materials.append(color)

def facemat(base, img, rough=0.35, emit=0.0):
    m = kit.mat("face_" + img, base, rough=rough, coat=0.4)
    nt = m.node_tree
    pr = nt.nodes["Principled BSDF"]
    tex = nt.nodes.new("ShaderNodeTexImage")
    tex.image = bpy.data.images.load(os.path.join(kit.GAME_ART, img))
    mix = nt.nodes.new("ShaderNodeMix")
    mix.data_type = "RGBA"
    mix.inputs["A"].default_value = base
    nt.links.new(tex.outputs["Color"], mix.inputs["B"])
    nt.links.new(tex.outputs["Alpha"], mix.inputs["Factor"])
    nt.links.new(mix.outputs["Result"], pr.inputs["Base Color"])
    if emit:
        pr.inputs["Emission Color"].default_value = base
        pr.inputs["Emission Strength"].default_value = emit
    return m

I3 = Matrix.Identity(3)
def J(pos, rot=None): return (rot or I3, Vector(pos))

# --- kid at x = -30
skin, hood, hoodD, pants, hair, capc = col((255, 212, 180)), col((52, 60, 112)), col((40, 46, 88)), col((150, 152, 170)), col((110, 70, 45)), col((34, 38, 70))
white, grey, red = col((250, 250, 252)), col((225, 225, 230)), col((235, 85, 85))
K = (-30, 0, 0)
for n, c in (("KidHoodie", hood), ("KidHips", pants), ("KidTrim", hoodD), ("KidStrings", white)):
    put(n, J((0, 0, 0)), c, K)
put("KidHead", J((0, 25.6, 0)), facemat(kit.srgb(255, 212, 180), "face_kid.png"), K)
for n, c in (("KidCap", capc), ("KidCapButton", capc), ("KidHair", hair)):
    put(n, J((0, 25.6, 0)), c, K)
for sx, s in ((-1, "L"), (1, "R")):
    th = J((3 * sx, 14, 0))
    put("KidThigh", th, pants, K)
    sh = J((3 * sx, 8.4, 0))
    for n, c in (("KidShin", pants), ("KidCuff", pants), ("KidShoeUpper", white), ("KidSole", grey), ("KidStripe", red), ("KidLaces", white)):
        put(n, sh, c, K)
    arm = J((7.2 * sx, 22.8, 0), angles(-0.1, 0, 0.14 * sx))
    for n, c in (("KidSleeve", hood), ("KidSleeveCuff", hoodD), ("KidHand" + s, skin)):
        put(n, arm, c, K)

# --- dog at x = +30 (body 13.4 up)
fur, furL, furD = col((232, 172, 92)), col((248, 214, 150)), col((196, 132, 64))
D = (32, 0, 0)
body = J((0, 13.4, 0))
for n, c in (("DogBody", fur), ("DogChest", furL), ("DogCollar", col((220, 70, 80))), ("DogTag", col((255, 215, 80), 0.2, 1.0))):
    put(n, body, c, D)
head = J((0, 20.4, 12), angles(-0.1, 0, 0))
put("DogHead", head, facemat(kit.srgb(232, 172, 92), "face_dog.png"), D)
for n, c in (("DogSnout", furL), ("DogNose", col((40, 30, 30), 0.15))):
    put(n, head, c, D)
jaw = J((0, 20.4 - 2.6, 18.0), angles(0.2, 0, 0))
put("DogJaw", jaw, furL, D)
put("DogTongue", jaw, col((245, 120, 140)), D)
for sx in (-1, 1):
    put("DogEar", J((6.2 * sx, 26.4, 13.5), angles(-0.2, 0, -0.35 * sx)), furD, D)
for x, z in ((-4.6, 9), (4.6, 9), (-4.6, -9), (4.6, -9)):
    put("DogLeg", J((x, 10.9, z)), fur, D)
    put("DogPaw", J((x, 10.9, z)), furL, D)
put("DogTail", J((0, 17.4, -13.5), angles(0.7, 0, 0)), furL, D)

# --- sminski at x = 0, scaled x4 so it reads next to the giants
S = 4
jelly = kit.mat("jelly", kit.srgb(170, 240, 110), rough=0.15, coat=1, emit=kit.srgb(150, 255, 90), emit_strength=0.4)
def putS(name, pos, rot=None):
    o = src[name].copy(); o.data = src[name].data
    bpy.context.scene.collection.objects.link(o)
    off = Vector(rig[name]["offset"])
    r = rot or I3
    w = (Vector(pos) + r @ off) * S
    o.matrix_world = Matrix.Translation(rb(w)) @ (P @ r @ PT).to_4x4() @ Matrix.Scale(S, 4)
    o.data.materials.clear(); o.data.materials.append(jelly)
putS("SmTorso", (0, 1.5, 0)); putS("SmHead", (0, 3.02, 0))
jelly_face = facemat(kit.srgb(170, 240, 110), "face_sminski.png", 0.15, 0.4)
[o for o in bpy.data.objects if o.name.startswith("SmHead") and o.users_collection][-1].data.materials[0] = jelly_face
for sx in (-1, 1):
    putS("SmArm", (0.62 * sx, 2.08, 0.04), angles(-0.1, 0, 0.1 * sx)); putS("SmLeg", (0.3 * sx, 0.82, 0))
# coin
o = src["StarCoin"].copy(); o.data = src["StarCoin"].data; bpy.context.scene.collection.objects.link(o)
o.matrix_world = Matrix.Translation(rb((0, 3, 12))) @ Matrix.Scale(3, 4)
o.data.materials.clear(); o.data.materials.append(col((255, 200, 80), 0.3, 1.0))

for ob in list(src.values()):
    bpy.data.objects.remove(ob)
kit.studio_lights(8)
kit.camera(rb((10, 24, 120)), rb((0, 16, 0)), lens=45)
kit.render(os.path.join(kit.ROOT, "preview", "rig_preview.png"), 1280, 720, samples=64)
print("PREVIEW_OK")
