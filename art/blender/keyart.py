# Key art for ads / store page, in the reference style: low wide lens, a hero
# Sminski filling the foreground, the kid lunging big behind, bokeh coins,
# a cluttered cozy night bedroom.
#   Blender --background --factory-startup --python keyart.py -- <scene> <wide|square> [preview]
#   scenes: hero, friends, revive, dogpark
import sys, os, math
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import bpy
from mathutils import Vector
import kit, shapes, sminski, portraits
from rigpose import T, A, RigLib, kid_joints, dog_joints, face_material

argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
SCENE = argv[0] if argv else "hero"
ASPECT = argv[1] if len(argv) > 1 else "wide"
PREVIEW = "preview" in argv
RAW = os.path.join(kit.ROOT, "preview", "keyart_raw")
os.makedirs(RAW, exist_ok=True)

kit.reset()
scene = bpy.context.scene
# key-art Glow: lime rather than yellow-green
sminski.CHARS["Glow"] = dict(sminski.CHARS["Glow"], body=(166, 232, 96), glow=(150, 255, 90))


def M(name, rgb, rough=0.4, metal=0.0, coat=0.3, emit=0.0, emit_rgb=None):
    return kit.mat(name, kit.srgb(*rgb), rough=rough, metal=metal, coat=coat,
                   emit=kit.srgb(*(emit_rgb or rgb)) if emit else None, emit_strength=emit)


def box(name, size, loc, mat, bevel=0.15, rot=(0, 0, 0)):
    bpy.ops.mesh.primitive_cube_add(size=1, location=loc, rotation=rot)
    o = bpy.context.active_object
    o.name = name
    o.scale = size
    bpy.ops.object.transform_apply(scale=True)
    if bevel:
        b = o.modifiers.new("B", "BEVEL")
        b.width = min(bevel, min(size) / 2.2)
        b.segments = 4
    kit.assign(o, mat)
    return o


def sphere(name, r, loc, mat, scale=(1, 1, 1), rot=(0, 0, 0)):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=32, ring_count=16, radius=r, location=loc, rotation=rot)
    o = bpy.context.active_object
    o.name = name
    o.scale = scale
    for p in o.data.polygons:
        p.use_smooth = True
    kit.assign(o, mat)
    return o


def point(name, loc, energy, color, radius=1.0):
    ld = bpy.data.lights.new(name, "POINT")
    ld.energy = energy
    ld.color = color
    ld.shadow_soft_size = radius
    o = bpy.data.objects.new(name, ld)
    scene.collection.objects.link(o)
    o.location = loc
    return o


def coin(loc, rot, s=1.0):
    body, star = shapes.build_coin("Coin")
    for o in (body, star):
        o.scale = (s, s, s)
        o.location = loc
        o.rotation_euler = rot


def wood_floor(size=300, planks=(150, 98, 64), dark=(104, 64, 40)):
    bpy.ops.mesh.primitive_plane_add(size=size, location=(0, size / 2 - 60, 0))
    f = bpy.context.active_object
    m = bpy.data.materials.new("Wood")
    m.use_nodes = True
    nt = m.node_tree
    p = nt.nodes["Principled BSDF"]
    tc = nt.nodes.new("ShaderNodeTexCoord")
    brick = nt.nodes.new("ShaderNodeTexBrick")
    brick.inputs["Scale"].default_value = 0.09
    brick.inputs["Mortar Size"].default_value = 0.012
    brick.inputs["Brick Width"].default_value = 3.2
    brick.inputs["Row Height"].default_value = 0.42
    brick.inputs["Color1"].default_value = kit.srgb(*planks)
    brick.inputs["Color2"].default_value = kit.srgb(*[int(c * 0.88) for c in planks])
    brick.inputs["Mortar"].default_value = kit.srgb(*dark)
    nt.links.new(tc.outputs["Object"], brick.inputs["Vector"])
    nt.links.new(brick.outputs["Color"], p.inputs["Base Color"])
    p.inputs["Roughness"].default_value = 0.5
    p.inputs["Coat Weight"].default_value = 0.25
    f.data.materials.append(m)
    return f


def fog(density=0.003, size=320, color=(0.8, 0.72, 1.0)):
    bpy.ops.mesh.primitive_cube_add(size=size, location=(0, size / 2 - 70, size / 2 - 1))
    v = bpy.context.active_object
    v.name = "Fog"
    m = bpy.data.materials.new("Fog")
    m.use_nodes = True
    nt = m.node_tree
    nt.nodes.remove(nt.nodes["Principled BSDF"])
    vol = nt.nodes.new("ShaderNodeVolumePrincipled")
    vol.inputs["Density"].default_value = density
    vol.inputs["Color"].default_value = (*color, 1)
    vol.inputs["Anisotropy"].default_value = 0.4
    nt.links.new(vol.outputs["Volume"], nt.nodes["Material Output"].inputs["Volume"])
    v.data.materials.append(m)


def sky(color, strength):
    bg = scene.world.node_tree.nodes["Background"]
    bg.inputs["Color"].default_value = kit.srgb(*color)
    bg.inputs["Strength"].default_value = strength


# ---------------------------------------------------------------------------
# props
# ---------------------------------------------------------------------------
def plushie(loc, col, s=1.0, yaw=0.0):
    fm = M("PlushF", (50, 46, 60), 0.3)
    body = M("Plush%d" % col[0], col, 0.7)
    sphere("pb", 1.0 * s, (loc[0], loc[1], loc[2] + 0.9 * s), body, (1, 0.9, 0.85), (0, 0, yaw))
    sphere("ph", 0.85 * s, (loc[0], loc[1], loc[2] + 2.2 * s), body, (1, 0.9, 0.9), (0, 0, yaw))
    for sx in (-1, 1):
        sphere("pe", 0.32 * s, (loc[0] + sx * 0.6 * s, loc[1] + 0.1 * s, loc[2] + 2.9 * s), body)
        sphere("py", 0.1 * s, (loc[0] + sx * 0.3 * s - math.sin(yaw) * 0.7 * s, loc[1] - math.cos(yaw) * 0.72 * s, loc[2] + 2.3 * s), fm, (1, 0.5, 1.3))
    sphere("pn", 0.11 * s, (loc[0] - math.sin(yaw) * 0.82 * s, loc[1] - math.cos(yaw) * 0.82 * s, loc[2] + 2.05 * s), fm, (1, 0.6, 0.8))


def plant_pot(loc, s=1.0, face=True):
    white = M("Pot", (250, 246, 238), 0.35, coat=0.6)
    pot = kit.lathe("Pot", [(0.001, 0), (1.6, 0), (1.9, 0.2), (2.1, 2.4), (2.2, 2.6), (1.9, 2.6), (0.001, 2.4)], 48)
    kit.smooth(pot, 1)
    kit.assign(pot, white)
    pot.location = loc
    pot.scale = (s, s, s)
    if face:
        ink = M("PotInk", (50, 50, 55), 0.3)
        for sx in (-1, 1):
            sphere("pe", 0.16 * s, (loc[0] + sx * 0.55 * s, loc[1] - 2.02 * s, loc[2] + 1.45 * s), ink, (1, 0.5, 1.2))
            sphere("pb", 0.28 * s, (loc[0] + sx * 1.05 * s, loc[1] - 1.9 * s, loc[2] + 1.0 * s), M("PotBlush", (255, 170, 170), 0.4), (1, 0.4, 0.6))
        bpy.ops.mesh.primitive_torus_add(major_radius=0.3 * s, minor_radius=0.06 * s, location=(loc[0], loc[1] - 2.03 * s, loc[2] + 1.05 * s), rotation=(math.pi / 2, 0, 0))
        kit.assign(bpy.context.active_object, ink)
    green = M("Leaf", (110, 190, 95), 0.35, coat=0.5)
    for i in range(9):
        a = i / 9 * math.tau
        tilt = 0.5 + (i % 3) * 0.2
        leaf = sphere("leaf", 0.7 * s, (loc[0] + math.cos(a) * 0.7 * s, loc[1] + math.sin(a) * 0.7 * s, loc[2] + (2.9 + (i % 3) * 0.3) * s), green, (0.55, 0.55, 1.4))
        leaf.rotation_euler = (math.cos(a) * tilt, -math.sin(a) * tilt, 0)
    sphere("leafc", 0.6 * s, (loc[0], loc[1], loc[2] + 3.6 * s), green, (0.6, 0.6, 1.3))


def desk_lamp(loc, s=1.0):
    base = kit.lathe("LampBase", [(0.001, 0), (2.4, 0), (2.4, 0.5), (0.6, 0.9), (0.001, 1)], 48)
    kit.smooth(base, 1)
    kit.assign(base, M("LampWood", (170, 110, 70), 0.4, coat=0.5))
    base.location = loc
    base.scale = (s, s, s)
    pole = kit.lathe("LampPole", [(0.35, 0), (0.35, 6), (0.001, 6.1)], 24)
    kit.assign(pole, M("LampPoleM", (200, 160, 110), 0.3, metal=0.6))
    pole.location = loc
    pole.scale = (s, s, s)
    shade = kit.lathe("Shade", [(4.6, 0), (4.7, 0.2), (3.0, 4.6), (2.8, 4.8), (2.7, 4.7), (4.5, 0.15)], 64)
    for p in shade.data.polygons:
        p.use_smooth = True
    kit.assign(shade, M("ShadeM", (255, 214, 150), 0.6, emit=3.0, emit_rgb=(255, 190, 110)))
    shade.location = (loc[0], loc[1], loc[2] + 5.2 * s)
    shade.scale = (s, s, s)
    point("LampBulb", (loc[0], loc[1], loc[2] + 6.8 * s), 2600 * s, (1.0, 0.75, 0.45), 2.5)


def bedroom(kid_side=-1):
    """Cluttered cozy night bedroom. Wall at y=70, side walls at x=±62."""
    wood_floor()
    wall = M("Wall", (66, 54, 128), 0.75)
    box("BackWall", (260, 2, 130), (0, 72, 65), wall, 0)
    box("SideWallL", (2, 220, 130), (-62, 20, 65), M("WallL", (56, 46, 110), 0.75), 0)
    box("SideWallR", (2, 220, 130), (62, 20, 65), M("WallR", (56, 46, 110), 0.75), 0)
    box("Skirting", (260, 1.6, 3), (0, 70.6, 1.5), M("Skirt", (96, 82, 160), 0.5), 0.2)
    # window with night sky + moon (behind the kid)
    wx = kid_side * 30
    box("WinFrame", (36, 1.4, 32), (wx, 70.6, 46), M("WinFrame", (244, 240, 255), 0.4), 0.4)
    box("WinGlass", (32, 1.0, 28), (wx, 70.2, 46), M("Night", (22, 30, 92), 0.3, emit=1.6, emit_rgb=(45, 62, 170)), 0)
    box("WinBarV", (1.2, 1.6, 28), (wx, 69.8, 46), M("WinFrame2", (244, 240, 255), 0.4), 0.2)
    box("WinBarH", (32, 1.6, 1.2), (wx, 69.8, 46), M("WinFrame3", (244, 240, 255), 0.4), 0.2)
    sphere("Moon", 3.4, (wx + 7, 69.4, 53), M("MoonM", (255, 250, 220), 0.3, emit=12, emit_rgb=(255, 245, 210)))
    sphere("MoonBite", 3.1, (wx + 8.6, 69.0, 54.2), M("Night2", (22, 30, 92), 0.3, emit=1.6, emit_rgb=(45, 62, 170)))
    for i, (dx, z) in enumerate(((-10, 55), (-5, 40), (3, 37), (-9, 42), (-3, 57), (9, 40), (12, 52))):
        sphere("Star%d" % i, 0.4, (wx + dx, 69.3, z), M("StarM", (255, 245, 200), 0.3, emit=20))
    curtain = M("Curtain", (128, 96, 200), 0.7)
    for sx in (-1, 1):
        sphere("Curtain", 5, (wx + sx * 20, 68.5, 40), curtain, (0.75, 0.3, 4.6))
    box("Rod", (50, 1, 1), (wx, 69, 62), M("RodM", (230, 200, 140), 0.3, metal=0.5), 0.4)
    # wall stars + a poster
    for i, (x, z, s) in enumerate(((10, 100, 2.2), (-8, 112, 1.6), (26, 118, 1.4))):
        st = kit.star_prism("WallStar", s, s * 0.45, 0.4, round_tips=0.2)
        kit.assign(st, M("WallStarM", (255, 205, 90), 0.4, coat=0.5))
        st.location = (x, 70.4, z)
        st.rotation_euler = (math.pi / 2, 0, 0.2 * i)
    # tall shelf unit opposite the kid, packed with plushies and books
    sx = -kid_side
    shelf_m = M("Shelf", (176, 118, 76), 0.45, coat=0.4)
    ux = sx * 40
    box("ShelfBack", (34, 2, 70), (ux, 69.5, 46), M("ShelfBack", (150, 98, 62), 0.5), 0.3)
    for z in (16, 34, 52, 70):
        box("ShelfPlank", (34, 9, 1.6), (ux, 66, z), shelf_m, 0.4)
    for sd in (-1, 1):
        box("ShelfSide", (1.8, 9, 70), (ux + sd * 17, 66, 46), shelf_m, 0.3)
    plush_cols = ((150, 205, 140), (255, 170, 190), (255, 205, 90), (140, 190, 240), (185, 160, 240), (255, 125, 110))
    k = 0
    for z in (16.8, 34.8, 52.8):
        for j, dx in enumerate((-11, -1, 9)):
            if (k + j) % 4 == 3:
                for b, (h, col) in enumerate(((7, (110, 170, 240)), (8, (255, 125, 110)), (6.5, (150, 205, 140)))):
                    box("Book", (2, 5, h), (ux + dx - 3 + b * 2.4, 65, z + h / 2), M("BookM%d" % b, col, 0.4, coat=0.4), 0.25)
            else:
                plushie((ux + dx, 65, z), plush_cols[(k + j) % len(plush_cols)], 1.7, yaw=(j - 1) * 0.25)
        k += 1
    for j, (cid, dx) in enumerate((("Mint", -10), ("Blush", 0), ("Sky", 10))):
        r = sminski.build(cid, "idle", brows=False, name="Deco%d" % j)
        r.scale = (1.5, 1.5, 1.5)
        r.location = (ux + dx, 64, 70.8)
    # bed on the kid's side, boxes, a toy bin, a big plant
    bx = kid_side * 44
    box("BedBase", (36, 60, 9), (bx, 40, 4.5), M("BedWood", (168, 118, 82), 0.5, coat=0.3), 0.8)
    box("Mattress", (34, 58, 6), (bx, 40, 12), M("Sheet", (238, 232, 250), 0.8), 1.8)
    box("Duvet", (36, 34, 6), (bx, 30, 15), M("Duvet", (120, 100, 205), 0.85), 2.4)
    box("Pillow", (24, 10, 5), (bx, 62, 16.5), M("PillowM", (250, 248, 255), 0.85), 2.2)
    box("Headboard", (38, 3, 26), (bx, 69, 13), M("HeadW", (168, 118, 82), 0.5), 0.6)
    box("Crate", (12, 12, 10), (bx - kid_side * 30, 60, 5), M("CrateM", (200, 150, 100), 0.6), 0.6, (0, 0, 0.3))
    # toy bin tipped over spilling coins near the kid's feet
    bin_ = kit.lathe("Bin", [(4.6, 0), (4.9, 0.3), (5.0, 9.5), (4.7, 9.8), (4.3, 9.6), (4.3, 0.4)], 48)
    kit.assign(bin_, M("BinM", (250, 242, 225), 0.5, coat=0.4))
    bin_.location = (kid_side * 20, 6, 4.6)
    bin_.rotation_euler = (math.radians(70), 0, math.radians(-kid_side * 30))
    box("BinLabel", (6, 6, 0.5), (kid_side * 20, 6, 9.4), M("BinLabel", (150, 205, 140), 0.5), 0.5, (math.radians(70), 0, math.radians(-kid_side * 30)))
    desk_lamp((-kid_side * 50, 14, 0), 1.8)
    plant_pot((-kid_side * 44, 2, 0), 1.0)
    plant_pot((kid_side * 11, -4.2, 0), 0.55)


def kid(root, ph=0.9, run=0.9, reach=1.0, t=0.45, s=1.0, colors=None, lib=None):
    lib = lib or RigLib()
    c = colors or {}
    col = lambda k, d: kit.mat("kid_" + k, kit.srgb(*c.get(k, d)), rough=0.4, coat=0.3)
    skin = col("skin", (255, 212, 180))
    hood = col("hood", (44, 48, 92))
    hoodD = col("hoodD", (32, 36, 70))
    pants = col("pants", (150, 152, 172))
    j = kid_joints(root, ph, run, reach, t, s)
    for n, m in (("KidHoodie", hood), ("KidHips", pants), ("KidTrim", hoodD), ("KidStrings", col("str", (240, 240, 245)))):
        lib.place(n, j["torso"], m, s)
    lib.place("KidHead", j["head"], face_material(c.get("skin", (255, 212, 180)), "face_kid.png"), s)
    lib.place("KidCap", j["head"], col("cap", (30, 34, 62)), s)
    lib.place("KidCapButton", j["head"], col("cap", (30, 34, 62)), s)
    lib.place("KidHair", j["head"], col("hair", (110, 70, 45)), s)
    for sd in ("L", "R"):
        lib.place("KidThigh", j["thigh" + sd], pants, s)
        for n, m in (("KidShin", pants), ("KidCuff", pants), ("KidShoeUpper", col("shoe", (252, 252, 255))), ("KidSole", col("sole", (236, 236, 242))),
                     ("KidStripe", col("stripe", (235, 85, 85))), ("KidLaces", col("lace", (230, 230, 235)))):
            lib.place(n, j["shin" + sd], m, s)
        for n, m in (("KidSleeve", hood), ("KidSleeveCuff", hoodD), ("KidHand" + sd, skin)):
            lib.place(n, j["arm" + sd], m, s)
    return lib


def dog(root, ph=0.8, run=1.0, reach=0.6, t=0.2, s=1.0, pounce=0.0, lib=None):
    lib = lib or RigLib()
    fur, light, dark = (232, 172, 92), (248, 214, 150), (196, 132, 64)
    F = kit.mat("fur", kit.srgb(*fur), rough=0.45, coat=0.2)
    L = kit.mat("furL", kit.srgb(*light), rough=0.45, coat=0.2)
    D = kit.mat("furD", kit.srgb(*dark), rough=0.45, coat=0.2)
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
    return lib


def hero_sminski(cid, loc, yaw, lean=0.32, mood="determined", brows=True, extra=None, s=1.0, pose="run"):
    r = sminski.build(cid, pose, brows=brows, mood=mood, name="Hero" + cid)
    r.location = loc
    r.scale = (s, s, s)
    r.rotation_euler = (lean, 0, yaw)
    if extra == "crown":
        portraits.crown(r)
    elif extra == "band":
        portraits.headband(r)
    return r


def coin_field(seed=3, n=16, spread=(-9, 9, -7, 6), fly=4):
    import random
    rng = random.Random(seed)
    for i in range(n):
        x = rng.uniform(spread[0], spread[1])
        y = rng.uniform(spread[2], spread[3])
        if abs(x) < 1.6 and -2 < y < 2:
            x += 3
        s = rng.uniform(0.55, 0.8)
        coin((x, y, 0.24), (0, 0, rng.uniform(0, 6.3)), s)
    for i in range(fly):
        coin((rng.uniform(-8, 8), rng.uniform(-4, 5), rng.uniform(1.8, 5.5)), (rng.uniform(0.6, 1.4), 0, rng.uniform(0, 6.3)), rng.uniform(0.5, 0.7))


def rroot(x, z, yaw=0.0):
    return T(x, 0, z) @ A(0, yaw, 0)


def camera(loc, target, lens, focus, fstop=2.4):
    cam = kit.camera(loc, target, lens=lens)
    cam.data.dof.use_dof = True
    cam.data.dof.focus_distance = (Vector(focus) - Vector(loc)).length
    cam.data.dof.aperture_fstop = fstop
    cam.data.dof.aperture_blades = 6
    return cam


def render(name, exposure=0.15):
    wide = ASPECT == "wide"
    w, h = (1920, 1080) if wide else (1400, 1400)
    if PREVIEW:
        w, h = w // 2, h // 2
    scene.render.film_transparent = False
    scene.view_settings.view_transform = "Standard"
    scene.view_settings.look = "None"
    scene.view_settings.exposure = exposure
    scene.cycles.use_denoising = True
    kit.render(os.path.join(RAW, "%s_%s.png" % (name, ASPECT)), w, h, 40 if PREVIEW else 128)


wide = ASPECT == "wide"

if SCENE == "hero":
    sky((84, 66, 160), 0.6)
    bedroom(kid_side=-1)
    # the kid: big, lunging in from the back-left, hand out
    kid(rroot(-12, -25, 0.66) @ A(0.4, 0, 0), ph=1.1, run=1.0, reach=1.0, t=0.5, s=0.6)
    kit.area_light("KidKey", (6, 6, 16), (-12, 25, 14), 5200, (1.0, 0.82, 0.68), 8)
    kit.area_light("KidRim", (-40, 60, 40), (-13, 27, 15), 18000, (0.55, 0.62, 1.0), 12)
    # the hero: running at the lens, leaning in
    hero_sminski("Glow", (0.9, -1.0, 0.1), -0.22, lean=0.36, mood="determined", brows=True, s=1.08)
    coin_field(3, 18)
    point("HeroGlow", (0.8, -2.6, 2.2), 90, (0.75, 1.0, 0.55), 1.2)
    kit.area_light("KeyWarm", (9, -7, 8), (0.9, -1, 2.2), 900, (1.0, 0.84, 0.62), 6)
    kit.area_light("Rim", (-5, 8, 7), (0.9, -1, 2.5), 2000, (0.7, 1.0, 0.78), 5)
    kit.area_light("FillPurple", (-12, -8, 5), (0, 0, 2), 700, (0.72, 0.62, 1.0), 10)
    fog(0.0028)
    if wide:
        camera((1.5, -7.6, 1.5), (-1.8, 12, 7.0), 19, (0.9, -1.0, 2.2), 1.8)
    else:
        camera((1.3, -7.6, 1.6), (-2.0, 12, 8.2), 20, (0.9, -1.0, 2.2), 1.8)
    render("hero", exposure=0.1)

elif SCENE == "friends":
    sky((84, 66, 160), 0.6)
    bedroom(kid_side=-1)
    kid(rroot(-11, -30, 0.6) @ A(0.4, 0, 0), ph=1.1, run=1.0, reach=1.0, t=0.5, s=0.6)
    kit.area_light("KidKey", (6, 8, 16), (-11, 30, 14), 5200, (1.0, 0.82, 0.68), 8)
    kit.area_light("KidRim", (-40, 60, 40), (-12, 40, 16), 16000, (0.55, 0.62, 1.0), 12)
    hero_sminski("Glow", (0.2, -0.4, 0.1), -0.08, lean=0.3, mood="determined", s=1.05)
    hero_sminski("Mint", (-3.4, 1.4, 0.1), -0.3, lean=0.3, mood="determined", extra="crown")
    hero_sminski("Lemon", (3.4, 1.2, 0.1), 0.22, lean=0.3, mood="determined", extra="band")
    coin_field(7, 16, fly=5)
    kit.area_light("KeyWarm", (9, -7, 8), (0, 0, 2.2), 900, (1.0, 0.84, 0.62), 6)
    kit.area_light("Rim", (-5, 8, 7), (0, 0, 2.5), 2000, (0.7, 1.0, 0.78), 5)
    kit.area_light("FillPurple", (-12, -8, 5), (0, 0, 2), 700, (0.72, 0.62, 1.0), 10)
    fog(0.0028)
    if wide:
        camera((0.6, -9.6, 1.6), (-1.0, 12, 7.0), 20, (0, -0.4, 2.2), 2.2)
    else:
        camera((0.4, -9.6, 1.8), (-1.2, 12, 8.6), 21, (0, -0.4, 2.2), 2.2)
    render("friends", exposure=0.1)

elif SCENE == "revive":
    sky((84, 66, 160), 0.6)
    bedroom(kid_side=-1)
    # the kid crouches in close, reaching for the fallen Sminski
    kid(rroot(-7, -17, 0.7) @ A(0.2, 0, 0) @ T(0, -5, 0), ph=0.2, run=0.0, reach=1.0, t=0.2, s=0.5)
    kit.area_light("KidKey", (6, 2, 14), (-7, 17, 11), 4200, (1.0, 0.84, 0.7), 8)
    kit.area_light("KidRim", (-36, 50, 36), (-9, 22, 12), 14000, (0.55, 0.62, 1.0), 12)
    # fallen Sminski on its back, glowing revive ring around it
    r = sminski.build("Glow", "idle", brows=False, mood="calm", name="Fallen")
    r.scale = (1.45, 1.45, 1.45)
    r.location = (-2.2, 0.4, 1.2)
    r.rotation_euler = (math.radians(8), math.radians(82), math.radians(-14))
    ring = M("RingM", (120, 240, 70), 0.3, emit=3.2, emit_rgb=(90, 235, 50))
    for i, (mr, z, tilt) in enumerate(((3.0, 0.7, 0.12), (3.8, 1.6, 0.2))):
        bpy.ops.mesh.primitive_torus_add(major_radius=mr, minor_radius=0.14, location=(1.4, -0.4, z), rotation=(tilt, 0.1 * i, 0.3))
        kit.assign(bpy.context.active_object, ring)
    plus = M("PlusM", (150, 245, 90), 0.3, emit=4, emit_rgb=(110, 240, 60))
    for i, (x, y, z, s) in enumerate(((-2.6, -1.8, 2.4, 0.5), (4.6, 0.5, 3.2, 0.6), (3.8, -2.6, 1.4, 0.4), (-1.2, 1.9, 4.1, 0.5), (1.0, -3.2, 3.6, 0.35))):
        box("Plus", (s, 0.2, s * 0.3), (x, y, z), plus, 0.05, (0, 0, 0.3 * i))
        box("Plus", (s * 0.3, 0.2, s), (x, y, z), plus, 0.05, (0, 0, 0.3 * i))
    point("ReviveGlow", (1.4, -1.5, 2.4), 420, (0.6, 1.0, 0.4), 2.0)
    coin_field(11, 8, fly=0)
    kit.area_light("KeyWarm", (9, -7, 8), (1.4, -0.4, 1.5), 800, (1.0, 0.84, 0.62), 6)
    kit.area_light("FillPurple", (-12, -8, 5), (0, 0, 2), 700, (0.72, 0.62, 1.0), 10)
    fog(0.0028)
    if wide:
        camera((2.6, -7.6, 3.4), (-0.4, 10, 4.2), 22, (1.6, -0.6, 1.4), 2.4)
    else:
        camera((2.4, -7.6, 3.6), (-0.6, 10, 5.4), 23, (1.6, -0.6, 1.4), 2.4)
    render("revive", exposure=0.1)

elif SCENE == "dogpark":
    sky((150, 195, 255), 1.0)
    bpy.ops.mesh.primitive_plane_add(size=600, location=(0, 200, 0))
    kit.assign(bpy.context.active_object, kit.mat("Grass", kit.srgb(112, 196, 92), rough=0.8))
    box("Path", (24, 400, 0.2), (0, 150, 0.05), M("PathM", (176, 150, 110), 0.9), 0)
    # fence
    fm = M("Fence", (250, 248, 240), 0.5)
    for i in range(-8, 9):
        box("Post", (1.2, 1.2, 9), (i * 7, 60, 4.5), fm, 0.2)
    box("Rail", (120, 0.8, 1.4), (0, 60, 6.5), fm, 0.2)
    box("Rail2", (120, 0.8, 1.4), (0, 60, 3.0), fm, 0.2)
    for i, (x, y, s) in enumerate(((-48, 100, 1.2), (44, 120, 1.4), (-70, 180, 1.6), (80, 200, 1.5), (10, 250, 1.9), (-20, 150, 1.3))):
        trunk = kit.lathe("Trunk", [(3, 0), (2.2, 3), (1.8, 20), (0.001, 21)], 24)
        kit.assign(trunk, M("TrunkM", (135, 95, 70), 0.7))
        trunk.location = (x, y, 0)
        trunk.scale = (s, s, s)
        for dx, dz, r in ((0, 26, 14), (-9, 20, 10), (9, 21, 10), (0, 18, 11)):
            sphere("Canopy", r * s, (x + dx * s, y, dz * s), M("Leaves", (110, 200, 95), 0.6))
    # the dog pouncing in from behind, tongue out
    dog(rroot(-9, -22, 0.5) @ A(0.12, 0, 0), ph=0.6, run=1.0, reach=0.9, t=0.3, s=0.55, pounce=0.55)
    hero_sminski("Glow", (2.4, -0.8, 0.1), -0.3, lean=0.36, mood="determined", brows=True, s=1.08)
    sphere("Ball", 1.1, (8.5, 9.0, 1.1), M("BallM", (215, 240, 70), 0.8))
    bpy.ops.mesh.primitive_torus_add(major_radius=1.8, minor_radius=0.25, location=(-6.5, 1.5, 0.3))
    kit.assign(bpy.context.active_object, M("Fris", (255, 125, 110), 0.3, coat=0.6))
    coin_field(5, 14, fly=3)
    sun = bpy.data.lights.new("Sun", "SUN")
    sun.energy = 3.0
    sun.angle = math.radians(8)
    so = bpy.data.objects.new("Sun", sun)
    scene.collection.objects.link(so)
    so.rotation_euler = (math.radians(50), math.radians(10), math.radians(-35))
    kit.area_light("Fill", (-10, -12, 8), (0, 0, 2), 900, (1, 0.95, 0.9), 10)
    point("HeroGlow", (0.8, -2.6, 2.2), 200, (0.75, 1.0, 0.55), 1.2)
    if wide:
        camera((1.8, -7.6, 1.5), (-1.8, 12, 6.4), 19, (2.4, -0.8, 2.2), 1.8)
    else:
        camera((1.8, -7.6, 1.6), (-1.6, 12, 7.6), 20, (2.4, -0.8, 2.2), 1.8)
    render("dogpark", exposure=-0.3)

elif SCENE.startswith("pass_"):
    # game-pass icons: one hero prop group on a glowing colour backdrop
    kind = SCENE[5:]
    theme = {
        "vip": ((96, 62, 190), (255, 205, 90)),
        "double": ((235, 130, 40), (255, 225, 120)),
        "maps": ((46, 150, 120), (190, 255, 170)),
        "revive": ((225, 90, 130), (190, 255, 150)),
    }[kind]
    bgc, glowc = theme
    sky(bgc, 0.9)
    bpy.ops.mesh.primitive_plane_add(size=200, location=(0, 40, 0))
    kit.assign(bpy.context.active_object, M("PassFloor", bgc, 0.45, coat=0.4))
    box("PassWall", (200, 2, 120), (0, 30, 60), M("PassWall", bgc, 0.8), 0)
    # sunburst of soft rays behind the subject
    ray = M("Ray", tuple(min(255, int(c * 1.25) + 20) for c in bgc), 0.8, emit=0.6)
    for i in range(12):
        a = i / 12 * math.tau
        b = box("RayBar", (2.6, 0.3, 46), (math.cos(a) * 1.0, 28.5, 3.4 + math.sin(a) * 1.0), ray, 0)
        b.rotation_euler = (0, a, 0)
    point("BackGlow", (0, 18, 5), 3200, tuple(c / 255 for c in glowc), 6)
    kit.area_light("Key", (5, -7, 8), (0, 0, 2.4), 1500, (1.0, 0.9, 0.75), 6)
    kit.area_light("Rim", (-4, 6, 7), (0, 0, 2.6), 2200, tuple(c / 255 for c in glowc), 5)
    kit.area_light("Fill", (-7, -5, 3), (0, 0, 2), 500, (0.8, 0.75, 1.0), 8)
    if kind == "vip":
        hero_sminski("Glow", (0, 0, 0.05), -0.12, lean=0.0, mood="calm", brows=False, extra="crown", s=1.25, pose="cheer")
        for i, (x, y, z, rx, rz, sc) in enumerate(((-3.4, 0.6, 3.6, 70, 30, 0.7), (3.5, 0.2, 4.4, 60, -40, 0.7), (-2.6, -1.4, 0.24, 0, 10, 0.7), (2.8, -1.2, 0.24, 0, 50, 0.7), (3.9, 1.5, 1.4, 80, 20, 0.55), (-4.2, 1.8, 1.6, 75, -20, 0.55))):
            coin((x, y, z), (math.radians(rx), 0, math.radians(rz)), sc)
        for i, (x, z, r) in enumerate(((-2.4, 5.6, 0.5), (2.6, 6.2, 0.4), (0, 7.0, 0.35), (-3.6, 2.4, 0.3), (3.8, 2.8, 0.3))):
            st = kit.star_prism("Spark", r, r * 0.42, 0.25, round_tips=0.1)
            kit.assign(st, M("SparkM", (255, 235, 150), 0.3, emit=6, emit_rgb=(255, 225, 120)))
            st.location = (x, 1.5, z)
            st.rotation_euler = (math.pi / 2, 0, 0.3 * i)
    elif kind == "double":
        hero_sminski("Glow", (0, -1.6, 0.05), 0.0, lean=0.0, mood="calm", brows=False, s=1.15, pose="cheer")
        coin((-3.0, 1.6, 2.9), (math.radians(84), 0, math.radians(24)), 2.2)
        coin((3.0, 1.8, 2.7), (math.radians(84), 0, math.radians(-26)), 2.0)
        import random
        rng = random.Random(4)
        for i in range(16):
            coin((rng.uniform(-5, 5), rng.uniform(-3.4, 2.5), 0.24 + (0.3 if i % 3 == 0 else 0)), (0, 0, rng.uniform(0, 6.3)), rng.uniform(0.6, 0.85))
        for i in range(5):
            coin((rng.uniform(-5, 5), rng.uniform(0, 3), rng.uniform(4.5, 7)), (rng.uniform(0.8, 1.5), 0, rng.uniform(0, 6.3)), 0.6)
    elif kind == "maps":
        # the three Endless Run huts: dog park (red), dollhouse (green), big house (purple)
        for i, (x, y, wall, roofc, yaw) in enumerate(((-4.4, 3.0, (170, 215, 255), (235, 100, 90), 0.28), (0, 4.6, (190, 240, 190), (110, 200, 100), 0.0), (4.4, 3.0, (110, 96, 190), (130, 100, 215), -0.28))):
            box("Hut", (3.6, 3.0, 3.0), (x, y, 1.5), M("HutWall%d" % i, wall, 0.5), 0.2, (0, 0, yaw))
            bpy.ops.mesh.primitive_cone_add(vertices=4, radius1=3.3, depth=2.2, location=(x, y, 4.1), rotation=(0, 0, yaw + math.pi / 4))
            rf = bpy.context.active_object
            kit.assign(rf, M("HutRoof%d" % i, roofc, 0.45, coat=0.4))
            box("Door", (1.0, 0.2, 1.7), (x + math.sin(yaw) * 1.55, y - math.cos(yaw) * 1.55, 0.85), M("DoorM%d" % i, (255, 214, 140), 0.4, emit=3, emit_rgb=(255, 200, 120)), 0.15, (0, 0, yaw))
            for sx in (-1, 1):
                box("Win", (0.7, 0.2, 0.7), (x + math.cos(yaw) * sx * 1.1 + math.sin(yaw) * 1.55, y + math.sin(yaw) * sx * 1.1 - math.cos(yaw) * 1.55, 2.1), M("WinM%d" % i, (255, 235, 170), 0.4, emit=4, emit_rgb=(255, 225, 150)), 0.1, (0, 0, yaw))
        hero_sminski("Glow", (0, -1.2, 0.05), 0.0, lean=0.0, mood="calm", brows=False, s=1.0, pose="wave")
        for x, y in ((-2.4, -2.2), (2.6, -2.0), (-4.6, -0.6), (4.8, -0.4)):
            coin((x, y, 0.24), (0, 0, x), 0.6)
    elif kind == "revive":
        hero_sminski("Glow", (0, 0, 0.05), 0.0, lean=0.0, mood="calm", brows=False, s=1.2, pose="cheer")
        ringm = M("RingM", (150, 250, 100), 0.3, emit=3.5, emit_rgb=(120, 245, 70))
        for mr, z, tilt in ((3.0, 0.8, 0.1), (3.6, 2.6, -0.16), (2.6, 4.6, 0.2)):
            bpy.ops.mesh.primitive_torus_add(major_radius=mr, minor_radius=0.13, location=(0, 0, z), rotation=(tilt, 0.1, 0))
            kit.assign(bpy.context.active_object, ringm)
        plus = M("PlusM", (200, 255, 160), 0.3, emit=5, emit_rgb=(150, 250, 90))
        for i, (x, y, z, sc) in enumerate(((-3.4, -0.5, 4.8, 0.7), (3.6, 0.2, 5.4, 0.8), (3.0, -1.8, 1.6, 0.5), (-3.0, -1.4, 2.0, 0.55), (0.4, 1.0, 7.0, 0.5))):
            box("Plus", (sc, 0.22, sc * 0.3), (x, y, z), plus, 0.05)
            box("Plus", (sc * 0.3, 0.22, sc), (x, y, z), plus, 0.05)
    cam = kit.camera((0, -10.6, 3.3), (0, 0, 3.0), lens=40)
    cam.data.dof.use_dof = True
    cam.data.dof.focus_distance = 10.6
    cam.data.dof.aperture_fstop = 4.0
    ASPECT = "square"
    scene.render.film_transparent = False
    scene.view_settings.view_transform = "Standard"
    scene.view_settings.exposure = -0.2
    kit.render(os.path.join(RAW, "%s.png" % SCENE), 512 if PREVIEW else 1024, 512 if PREVIEW else 1024, 40 if PREVIEW else 128)

print("KEYART_OK", SCENE, ASPECT)
