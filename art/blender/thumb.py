# Store thumbnails / icon for Sminski Run, in the key-art style.
#   Blender --background --factory-startup --python thumb.py -- <main|park|icon> [preview]
import sys, os, math, json
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import bpy
from mathutils import Vector, Matrix
import kit, shapes, sminski, icons, portraits
import rigpose
from rigpose import T, A, RigLib, build_kid, build_dog
from rigkit import P

argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
WHICH = argv[0] if argv else "main"
PREVIEW = len(argv) > 1 and argv[1] == "preview"
RAW = os.path.join(kit.ROOT, "preview", "thumb_raw")
os.makedirs(RAW, exist_ok=True)

kit.reset()
scene = bpy.context.scene


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
        b.width = bevel
        b.segments = 4
    kit.assign(o, mat)
    return o


def sphere(name, r, loc, mat, scale=(1, 1, 1)):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=32, ring_count=16, radius=r, location=loc)
    o = bpy.context.active_object
    o.name = name
    o.scale = scale
    for p in o.data.polygons:
        p.use_smooth = True
    kit.assign(o, mat)
    return o


def wood_floor(size=260, planks=(150, 98, 62), dark=(108, 66, 40)):
    bpy.ops.mesh.primitive_plane_add(size=size, location=(0, size / 2 - 40, 0))
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
    brick.inputs["Color2"].default_value = kit.srgb(*[int(c * 0.86) for c in planks])
    brick.inputs["Mortar"].default_value = kit.srgb(*dark)
    wave = nt.nodes.new("ShaderNodeTexWave")
    wave.inputs["Scale"].default_value = 0.5
    wave.inputs["Distortion"].default_value = 6
    mix = nt.nodes.new("ShaderNodeMix")
    mix.data_type = "RGBA"
    mix.blend_type = "MULTIPLY"
    mix.inputs["Factor"].default_value = 0.18
    nt.links.new(tc.outputs["Object"], brick.inputs["Vector"])
    nt.links.new(tc.outputs["Object"], wave.inputs["Vector"])
    nt.links.new(brick.outputs["Color"], mix.inputs["A"])
    nt.links.new(wave.outputs["Color"], mix.inputs["B"])
    nt.links.new(mix.outputs["Result"], p.inputs["Base Color"])
    p.inputs["Roughness"].default_value = 0.32
    p.inputs["Coat Weight"].default_value = 0.35
    f.data.materials.append(m)
    return f


def volume_fog(density=0.004, size=300, color=(0.8, 0.75, 1.0)):
    bpy.ops.mesh.primitive_cube_add(size=size, location=(0, size / 2 - 60, size / 2 - 1))
    v = bpy.context.active_object
    v.name = "Fog"
    m = bpy.data.materials.new("Fog")
    m.use_nodes = True
    nt = m.node_tree
    nt.nodes.remove(nt.nodes["Principled BSDF"])
    vol = nt.nodes.new("ShaderNodeVolumePrincipled")
    vol.inputs["Density"].default_value = density
    vol.inputs["Color"].default_value = (*color, 1)
    vol.inputs["Anisotropy"].default_value = 0.35
    nt.links.new(vol.outputs["Volume"], nt.nodes["Material Output"].inputs["Volume"])
    v.data.materials.append(m)
    return v


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


def plant_pot(loc, s=1.0):
    white = M("Pot", (248, 244, 236), 0.35, coat=0.6)
    pot = kit.lathe("Pot", [(0.001, 0), (1.6, 0), (1.9, 0.2), (2.1, 2.4), (2.2, 2.6), (1.9, 2.6), (0.001, 2.4)], 48)
    kit.smooth(pot, 1)
    kit.assign(pot, white)
    pot.location = loc
    pot.scale = (s, s, s)
    ink = M("PotInk", (50, 50, 55), 0.3)
    for sx in (-1, 1):
        sphere("pe", 0.16 * s, (loc[0] + sx * 0.55 * s, loc[1] - 2.02 * s, loc[2] + 1.45 * s), ink, (1, 0.5, 1.2))
        sphere("pb", 0.28 * s, (loc[0] + sx * 1.05 * s, loc[1] - 1.9 * s, loc[2] + 1.0 * s), M("PotBlush", (255, 170, 170), 0.4), (1, 0.4, 0.6))
    bpy.ops.mesh.primitive_torus_add(major_radius=0.3 * s, minor_radius=0.06 * s, location=(loc[0], loc[1] - 2.03 * s, loc[2] + 1.05 * s), rotation=(math.pi / 2, 0, 0))
    kit.assign(bpy.context.active_object, ink)
    green = M("Leaf", (110, 185, 95), 0.35, coat=0.5)
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
    sm = M("ShadeM", (255, 214, 150), 0.6, emit=3.5, emit_rgb=(255, 190, 110))
    kit.assign(shade, sm)
    shade.location = (loc[0], loc[1], loc[2] + 5.2 * s)
    shade.scale = (s, s, s)
    point("LampBulb", (loc[0], loc[1], loc[2] + 6.8 * s), 9000 * s, (1.0, 0.75, 0.45), 2.5)


def bedroom():
    wood_floor()
    wall = M("Wall", (62, 52, 118), 0.75)
    box("BackWall", (260, 2, 120), (0, 72, 60), wall, 0)
    box("SideWallL", (2, 200, 120), (-60, 20, 60), M("WallL", (54, 44, 104), 0.75), 0)
    box("Skirting", (260, 1.6, 3), (0, 70.6, 1.5), M("Skirt", (90, 78, 150), 0.5), 0.2)
    # window with night sky + moon
    box("WinFrame", (34, 1.4, 30), (-26, 70.6, 42), M("WinFrame", (240, 236, 255), 0.4), 0.4)
    box("WinGlass", (30, 1.0, 26), (-26, 70.2, 42), M("Night", (20, 26, 80), 0.3, emit=1.4, emit_rgb=(40, 55, 150)), 0)
    box("WinBarV", (1.2, 1.6, 26), (-26, 69.8, 42), M("WinFrame2", (240, 236, 255), 0.4), 0.2)
    box("WinBarH", (30, 1.6, 1.2), (-26, 69.8, 42), M("WinFrame3", (240, 236, 255), 0.4), 0.2)
    moon = sphere("Moon", 3.2, (-19, 69.4, 49), M("MoonM", (255, 250, 220), 0.3, emit=12, emit_rgb=(255, 245, 210)))
    sphere("MoonBite", 2.9, (-17.6, 69.0, 50.2), M("Night2", (20, 26, 80), 0.3, emit=1.4, emit_rgb=(40, 55, 150)))
    for i, (x, z) in enumerate(((-36, 51), (-31, 36), (-23, 33), (-35, 38), (-29, 53), (-17, 36))):
        sphere("Star%d" % i, 0.35, (x, 69.3, z), M("StarM", (255, 245, 200), 0.3, emit=20))
    # curtains
    curtain = M("Curtain", (120, 90, 190), 0.7)
    for sx in (-1, 1):
        c = sphere("Curtain", 5, (-26 + sx * 19, 68.5, 36), curtain, (0.75, 0.3, 4.4))
    box("Rod", (46, 1, 1), (-26, 69, 57.5), M("RodM", (230, 200, 140), 0.3, metal=0.5), 0.4)
    # shelf with little Sminski figures + books
    shelf_m = M("Shelf", (185, 125, 80), 0.45, coat=0.4)
    box("Shelf1", (40, 8, 1.6), (32, 67, 40), shelf_m, 0.4)
    box("Shelf2", (40, 8, 1.6), (32, 67, 26), shelf_m, 0.4)
    for i, (cid, x) in enumerate((("Mint", 20), ("Blush", 27), ("Glow", 34), ("Sky", 41))):
        r = sminski.build(cid, "idle", brows=False, name="Deco%d" % i)
        r.scale = (1.4, 1.4, 1.4)
        r.location = (x, 66, 40.8)
    for i, (x, h, col) in enumerate(((18, 7, (110, 170, 240)), (20.3, 8, (255, 125, 110)), (22.8, 6.5, (150, 205, 140)), (25, 7.5, (185, 160, 240)))):
        box("Book%d" % i, (2, 5, h), (x, 66, 26.8 + h / 2), M("BookM%d" % i, col, 0.4, coat=0.4), 0.25)
    # a toy block and a big star coin tin on the floor
    b = box("Block", (6, 6, 6), (26, 18, 3), M("BlockM", (255, 120, 105), 0.35, coat=0.5), 0.8, (0, 0, 0.35))
    box("BlockPanel", (4.6, 0.4, 4.6), (26 - 3.05 * math.sin(0.35), 18 - 3.05 * math.cos(0.35), 3), M("Panel", (255, 244, 215), 0.35), 0.4, (0, 0, 0.35))


def sky_world(color=(60, 50, 120), strength=0.5):
    bg = scene.world.node_tree.nodes["Background"]
    bg.inputs["Color"].default_value = kit.srgb(*color)
    bg.inputs["Strength"].default_value = strength


def runners(specs, mood="determined"):
    for i, (cid, loc, yaw, extra, pose) in enumerate(specs):
        r = sminski.build(cid, pose, brows=True, mood=mood, name="S%d" % i)
        r.location = loc
        r.rotation_euler.z = yaw
        if extra == "crown":
            portraits.crown(r)
        elif extra == "band":
            portraits.headband(r)
    return


def render(name, w, h, samples):
    scene.cycles.samples = samples
    scene.render.film_transparent = False
    scene.view_settings.view_transform = "Standard"
    scene.view_settings.look = "None"
    if WHICH == "main":
        scene.view_settings.exposure = 0.12
    kit.render(os.path.join(RAW, name + ".png"), w, h, samples)


def rroot(x, z, yaw=0.0):
    """Roblox-space root matrix at (x, 0, z) turned by yaw (Blender y = -z)."""
    return T(x, 0, z) @ A(0, yaw, 0)


if WHICH == "main":
    sky_world((80, 62, 150), 0.55)
    bedroom()
    lib = RigLib()
    build_kid(lib, rroot(-27, -56, 0.5), ph=0.9, run=0.9, reach=1.0, t=0.45)
    kit.area_light("KidKey", (-2, 26, 46), (-27, 56, 32), 45000, (1.0, 0.82, 0.7), 18)
    kit.area_light("KidRim", (-50, 70, 50), (-27, 56, 32), 20000, (0.6, 0.65, 1.0), 12)
    runners([("Mint", (-3.0, 1.2, 0), -0.28, "crown", "run"), ("Glow", (0.2, -0.6, 0), -0.05, None, "run"), ("Lemon", (3.2, 1.0, 0), 0.25, "band", "run")])
    for j, (x, y, z, rx, rz, s) in enumerate(((-4.6, -3.2, 0.24, 90, 20, 0.62), (-1.6, -4.4, 0.24, 90, -30, 0.62), (2.0, -4.0, 0.24, 90, 40, 0.62),
                                              (4.8, -2.4, 0.24, 90, -10, 0.62), (0.4, -6.0, 0.24, 90, 5, 0.7), (-2.6, -7.2, 0.24, 90, 25, 0.75), (3.0, -7.0, 0.24, 90, -20, 0.75), (5.4, 2.6, 2.4, 40, 60, 0.6),
                                              (-5.8, 1.8, 3.2, 50, -50, 0.6), (-8.5, -1.5, 0.24, 90, 70, 0.62), (7.5, -0.5, 0.24, 90, 15, 0.62))):
        coin((x, y, z), (math.radians(rx if z > 1 else 0), 0, math.radians(rz)), s)
    plant_pot((-9.0, -1.5, 0), 0.9)
    desk_lamp((26, 26, 0), 1.6)
    point("Moonlight", (-26, 60, 44), 30000, (0.55, 0.62, 1.0), 12)
    kit.area_light("KeyWarm", (12, -8, 9), (0, 0, 2.2), 1400, (1.0, 0.84, 0.62), 6)
    kit.area_light("Rim", (-6, 10, 8), (0, 0, 2.5), 1600, (0.7, 1.0, 0.75), 5)
    kit.area_light("FillPurple", (-14, -10, 6), (0, 0, 2), 700, (0.72, 0.62, 1.0), 10)
    volume_fog(0.0035)
    kit.camera((0.3, -12.2, 2.4), (-3.0, 20, 8.9), lens=23)
    render("main", 960 if PREVIEW else 1920, 540 if PREVIEW else 1080, 48 if PREVIEW else 110)

elif WHICH == "park":
    sky_world((140, 185, 250), 1.0)
    bpy.ops.mesh.primitive_plane_add(size=600, location=(0, 200, 0))
    grass = bpy.context.active_object
    gm = kit.mat("Grass", kit.srgb(110, 190, 90), rough=0.8)
    kit.assign(grass, gm)
    path = box("Path", (22, 400, 0.2), (0, 150, 0.05), M("PathM", (225, 210, 180), 0.8), 0)
    lib = RigLib()
    build_dog(lib, rroot(10, -62, -0.12), ph=0.4, run=1.0, reach=0.8, t=0.2)
    build_dog(lib, rroot(38, -95, -0.4), ph=2.2, run=1.0, reach=0.4, t=0.9, s=0.7, fur=(60, 55, 60), light=(150, 140, 140), dark=(40, 36, 40))
    build_kid(lib, rroot(-34, -90, 0.5), ph=2.0, run=0.6, reach=0.0, t=0.2,
              colors={"hood": (235, 110, 100), "hoodD": (200, 85, 80), "pants": (80, 110, 175), "cap": (255, 205, 70)})
    runners([("Glow", (-1.5, 0, 0), -0.1, None, "run"), ("Blush", (2.6, 2.2, 0), 0.25, None, "run"), ("Sky", (-4.8, 3.0, 0), -0.35, "crown", "run")])
    # park props: trees + a tennis ball + frisbee
    for i, (x, y, s) in enumerate(((-40, 120, 1.2), (45, 140, 1.4), (-70, 200, 1.6), (80, 220, 1.5), (10, 260, 1.8))):
        trunk = kit.lathe("Trunk", [(3, 0), (2.2, 3), (1.8, 20), (0.001, 21)], 24)
        kit.assign(trunk, M("TrunkM", (135, 95, 70), 0.7))
        trunk.location = (x, y, 0)
        trunk.scale = (s, s, s)
        for k, (dx, dz, r) in enumerate(((0, 26, 14), (-9, 20, 10), (9, 21, 10), (0, 18, 11))):
            sphere("Canopy", r * s, (x + dx * s, y, dz * s), M("Leaves", (110, 195, 95), 0.6))
    sphere("Ball", 1.5, (8.5, 6.0, 1.5), M("BallM", (215, 240, 70), 0.8))
    bpy.ops.mesh.primitive_torus_add(major_radius=1.8, minor_radius=0.25, location=(-6.5, 0.5, 0.3))
    kit.assign(bpy.context.active_object, M("Fris", (255, 125, 110), 0.3, coat=0.6))
    for j, (x, y) in enumerate(((-3.2, -3.6), (1.4, -4.6), (4.2, -2.4), (-6.5, -0.8))):
        coin((x, y, 0.24), (0, 0, math.radians(20 * j)), 0.62)
    sun = bpy.data.lights.new("Sun", "SUN")
    sun.energy = 4.5
    sun.angle = math.radians(8)
    so = bpy.data.objects.new("Sun", sun)
    scene.collection.objects.link(so)
    so.rotation_euler = (math.radians(50), math.radians(10), math.radians(-35))
    kit.area_light("Fill", (-10, -12, 8), (0, 0, 2), 900, (1, 0.95, 0.9), 10)
    kit.camera((0.5, -13.0, 2.2), (-1.0, 20, 9.5), lens=23)
    scene.view_settings.exposure = -0.35
    render("park", 960 if PREVIEW else 1920, 540 if PREVIEW else 1080, 48 if PREVIEW else 110)

elif WHICH == "icon":
    sky_world((70, 55, 130), 0.4)
    bpy.ops.mesh.primitive_plane_add(size=80, location=(0, 0, 0))
    kit.assign(bpy.context.active_object, M("Floor", (90, 70, 150), 0.6))
    sminski.CHARS["Glow"] = dict(body=(165, 235, 95), glow=(150, 255, 90))
    scene.view_settings.exposure = -0.3
    r = sminski.build("Glow", "cheer", brows=True, mood="calm", name="Hero")
    r.rotation_euler.z = math.radians(-12)
    portraits.crown(r)
    for j, (x, y, z, rx, rz) in enumerate(((-2.4, -1.4, 0.24, 0, 20), (2.3, -1.2, 0.24, 0, -30), (-2.8, 0.8, 2.6, 60, 40), (2.9, 0.5, 3.4, 50, -40))):
        coin((x, y, z), (math.radians(rx), 0, math.radians(rz)), 0.62)
    kit.area_light("Key", (4, -6, 7), (0, 0, 2.2), 1500, (1.0, 0.86, 0.66), 5)
    kit.area_light("Rim", (-3, 5, 6), (0, 0, 2.2), 1800, (0.7, 1.0, 0.75), 4)
    kit.area_light("Fill", (-6, -4, 3), (0, 0, 2), 500, (0.72, 0.62, 1.0), 8)
    kit.camera((0, -10.5, 3.0), (0, 0, 2.3), lens=50)
    render("icon", 512, 512, 40 if PREVIEW else 200)
print("THUMB_OK", WHICH)
