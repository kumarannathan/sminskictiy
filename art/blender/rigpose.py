# Python port of Rigs.lua joint maths + helpers to drop the exported rig meshes
# (art/meshes/SminskiRig.fbx) into a Blender scene in any pose.
import os, json, math
import bpy
from mathutils import Matrix, Vector
import kit
from rigkit import P

P4 = P.to_4x4()
P4T = P.transposed().to_4x4()


def T(x, y, z):
    return Matrix.Translation((x, y, z))


def A(rx=0.0, ry=0.0, rz=0.0):
    return (Matrix.Rotation(rx, 4, "X") @ Matrix.Rotation(ry, 4, "Y") @ Matrix.Rotation(rz, 4, "Z"))


def kid_joints(root, ph, run, reach, t, s=1.0, throw=0.0):
    sw = math.sin(ph) * 0.6 * run
    bob = abs(math.cos(ph)) * 1.2 * run * s
    lean = 0.12 + 0.26 * reach
    torso = root @ T(0, bob, 0) @ A(lean, 0, math.sin(ph) * 0.04 * run)
    grab = math.sin(t * 9) * 0.3 * reach
    arm_idle = -0.15 + math.sin(t * 1.7) * 0.05
    kneeL = max(0, math.sin(ph + 0.9)) * 1.3 * run + 0.08
    kneeR = max(0, math.sin(ph + 0.9 + math.pi)) * 1.3 * run + 0.08
    thighL = torso @ T(-3 * s, 14 * s, 0) @ A(-lean - sw - 0.1 * run, 0, 0)
    thighR = torso @ T(3 * s, 14 * s, 0) @ A(-lean + sw - 0.1 * run, 0, 0)
    armRx = -sw * 0.9 * (1 - reach) + arm_idle * (1 - reach) + (-1.55 - grab) * reach
    armRx = armRx + (-2.6 - armRx) * throw
    return {
        "torso": torso, "thighL": thighL, "thighR": thighR,
        "shinL": thighL @ T(0, -5.6 * s, 0) @ A(kneeL, 0, 0),
        "shinR": thighR @ T(0, -5.6 * s, 0) @ A(kneeR, 0, 0),
        "head": torso @ T(0, 25.6 * s, 0) @ A(-lean * 0.7 + math.sin(t * 3) * 0.04, math.sin(t * 1.3) * 0.08, 0),
        "armL": torso @ T(-7.2 * s, 22.8 * s, 0) @ A(sw * 0.9 * (1 - reach) + arm_idle * (1 - reach) + (-1.55 + grab) * reach, 0, -0.14 + 0.36 * reach),
        "armR": torso @ T(7.2 * s, 22.8 * s, 0) @ A(armRx, 0, 0.14 - 0.36 * reach),
    }


def dog_joints(root, ph, run, reach, t, s=1.0, pounce=0.0):
    sn = math.sin(ph) * run
    bob = abs(math.cos(ph)) * 1.8 * run * s
    pitch = math.sin(ph) * 0.08 * run - reach * 0.08
    lift, legF, legB, headDip = 0, 0, 0, 0
    if pounce > 0:
        k = pounce
        lift = math.sin(math.pi * min(k, 1)) * 7 * s - k * k * 3.2 * s
        pitch = -0.35 + 0.95 * k
        legF, legB, headDip = -0.9 - 0.4 * k, 0.9, 0.35 * k
        sn, bob = 0, 0
    body = root @ T(0, 13.4 * s + bob + lift, 0) @ A(pitch, 0, 0)
    mouth_open = 0.15 + reach * 0.35 + max(0, math.sin(t * 5)) * 0.15
    head = body @ T(0, 7 * s, 12 * s) @ A(-0.1 + reach * 0.35 + headDip + math.sin(ph * 0.5) * 0.05, math.sin(t * 1.5) * 0.12 * (1 - run), 0)
    cp = 0 if pounce > 0 else pitch
    return {
        "body": body, "head": head,
        "jaw": head @ T(0, -2.6 * s, 6 * s) @ A(mouth_open, 0, 0),
        "earL": head @ T(-6.2 * s, 6 * s, 1.5 * s) @ A(math.sin(ph) * 0.25 * run - 0.2, 0, -0.35),
        "earR": head @ T(6.2 * s, 6 * s, 1.5 * s) @ A(math.sin(ph + 0.6) * 0.25 * run - 0.2, 0, 0.35),
        "FL": body @ T(-4.6 * s, -2.5 * s, 9 * s) @ A(-sn * 0.8 + legF - cp, 0, 0),
        "FR": body @ T(4.6 * s, -2.5 * s, 9 * s) @ A(-sn * 0.65 + legF - cp, 0, 0),
        "BL": body @ T(-4.6 * s, -2.5 * s, -9 * s) @ A(sn * 0.8 + legB - cp, 0, 0),
        "BR": body @ T(4.6 * s, -2.5 * s, -9 * s) @ A(sn * 0.65 + legB - cp, 0, 0),
        "tail": body @ T(0, 4 * s, -13.5 * s) @ A(0.7, math.sin(t * 14) * 0.6, 0),
    }


class RigLib:
    """Loads SminskiRig.fbx once; place(name, jointMatrix, material, scale)."""

    def __init__(self):
        self.rig = json.load(open(os.path.join(kit.OUT_MESH, "rig.json")))
        before = set(bpy.data.objects)
        bpy.ops.import_scene.fbx(filepath=os.path.join(kit.OUT_MESH, "SminskiRig.fbx"))
        self.src = {}
        for o in set(bpy.data.objects) - before:
            if o.type == "MESH":
                self.src[o.name.split(".")[0]] = o
                o.hide_render = True
                o.hide_viewport = True

    def place(self, name, joint, material, s=1.0, grow=1.0):
        src = self.src[name]
        o = src.copy()
        o.data = src.data
        o.hide_render = False
        o.hide_viewport = False
        bpy.context.scene.collection.objects.link(o)
        off = Vector(self.rig[name]["offset"]) * s
        m = joint @ T(*off) @ Matrix.Scale(s * grow, 4)
        o.matrix_world = P4 @ m @ P4T
        o.data = src.data.copy()
        o.data.materials.clear()
        o.data.materials.append(material)
        return o


def face_material(base_rgb, image, rough=0.35, emit=0.0):
    m = kit.mat("face_" + image, kit.srgb(*base_rgb), rough=rough, coat=0.4)
    nt = m.node_tree
    pr = nt.nodes["Principled BSDF"]
    tex = nt.nodes.new("ShaderNodeTexImage")
    tex.image = bpy.data.images.load(os.path.join(kit.GAME_ART, image))
    mix = nt.nodes.new("ShaderNodeMix")
    mix.data_type = "RGBA"
    mix.inputs["A"].default_value = kit.srgb(*base_rgb)
    nt.links.new(tex.outputs["Color"], mix.inputs["B"])
    nt.links.new(tex.outputs["Alpha"], mix.inputs["Factor"])
    nt.links.new(mix.outputs["Result"], pr.inputs["Base Color"])
    if emit:
        pr.inputs["Emission Color"].default_value = kit.srgb(*base_rgb)
        pr.inputs["Emission Strength"].default_value = emit
    return m


def build_kid(lib, root, ph=0.6, run=0.8, reach=1.0, t=0.4, colors=None):
    c = colors or {}
    col = lambda k, d: kit.mat("kid_" + k, kit.srgb(*c.get(k, d)), rough=0.4, coat=0.3)
    skin = col("skin", (255, 212, 180))
    hood = col("hood", (52, 60, 112))
    hoodD = col("hoodD", (40, 46, 88))
    pants = col("pants", (150, 152, 170))
    j = kid_joints(root, ph, run, reach, t)
    for n, m in (("KidHoodie", hood), ("KidHips", pants), ("KidTrim", hoodD), ("KidStrings", col("str", (240, 240, 245)))):
        lib.place(n, j["torso"], m)
    lib.place("KidHead", j["head"], face_material(c.get("skin", (255, 212, 180)), "face_kid.png"))
    lib.place("KidCap", j["head"], col("cap", (34, 38, 70)))
    lib.place("KidCapButton", j["head"], col("cap", (34, 38, 70)))
    lib.place("KidHair", j["head"], col("hair", (110, 70, 45)))
    for sd in ("L", "R"):
        lib.place("KidThigh", j["thigh" + sd], pants)
        for n, m in (("KidShin", pants), ("KidCuff", pants), ("KidShoeUpper", col("shoe", (252, 252, 255))), ("KidSole", col("sole", (236, 236, 242))),
                     ("KidStripe", col("stripe", (235, 85, 85))), ("KidLaces", col("lace", (230, 230, 235)))):
            lib.place(n, j["shin" + sd], m)
        for n, m in (("KidSleeve", hood), ("KidSleeveCuff", hoodD), ("KidHand" + sd, skin)):
            lib.place(n, j["arm" + sd], m)


def build_dog(lib, root, ph=0.8, run=1.0, reach=0.6, t=0.2, s=1.0, pounce=0.0, fur=(232, 172, 92), light=(248, 214, 150), dark=(196, 132, 64)):
    F = kit.mat("fur%d" % fur[0], kit.srgb(*fur), rough=0.45, coat=0.2)
    L = kit.mat("furL%d" % light[0], kit.srgb(*light), rough=0.45, coat=0.2)
    D = kit.mat("furD%d" % dark[0], kit.srgb(*dark), rough=0.45, coat=0.2)
    j = dog_joints(root, ph, run, reach, t, s, pounce)
    lib.place("DogBody", j["body"], F, s)
    lib.place("DogChest", j["body"], L, s)
    lib.place("DogCollar", j["body"], kit.mat("collar", kit.srgb(220, 70, 80), rough=0.3, coat=0.5), s)
    lib.place("DogTag", j["body"], kit.mat("tag", kit.srgb(255, 210, 80), rough=0.2, metal=1.0), s)
    lib.place("DogHead", j["head"], face_material(fur, "face_dog.png", 0.45), s)
    lib.place("DogSnout", j["head"], L, s)
    lib.place("DogNose", j["head"], kit.mat("nose", kit.srgb(40, 30, 30), rough=0.15, coat=1.0), s)
    lib.place("DogJaw", j["jaw"], L, s)
    lib.place("DogTongue", j["jaw"], kit.mat("tongue", kit.srgb(245, 120, 140), rough=0.3), s)
    lib.place("DogEar", j["earL"], D, s)
    lib.place("DogEar", j["earR"], D, s)
    for leg in ("FL", "FR", "BL", "BR"):
        lib.place("DogLeg", j[leg], F, s)
        lib.place("DogPaw", j[leg], L, s)
    lib.place("DogTail", j["tail"], L, s)
