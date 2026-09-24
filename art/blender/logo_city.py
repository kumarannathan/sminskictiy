# The SMINSKI CITY wordmark: cream bubble letters, a Smiski head with a
# sprout sitting on top, and a wooden plank reading CITY.
#
# Built rather than lifted. A logo is a hero asset (pipeline.md), so it has
# to come from code that can be re-run and corrected -- a keyed crop out of a
# concept image cannot be re-rendered at a different size, has no alpha worth
# trusting and drags whatever was behind it along for the ride.
#
# The outline is added in 2D afterwards by outline.py, same as the RUN logo.
#   Blender --background --factory-startup --python logo_city.py -- [out.png]
import sys, os, math
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import bpy, kit
from mathutils import Vector

argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
OUT = argv[0] if len(argv) > 0 else os.path.join(kit.ROOT, "preview", "logo_city_raw.png")
WORD = argv[1] if len(argv) > 1 else "Sminski"
PLANK = argv[2] if len(argv) > 2 else "CITY"

kit.reset()
font = bpy.data.fonts.load(kit.FONT_ROUNDED)

CREAM_TOP = kit.srgb(255, 253, 244)
CREAM_BOT = kit.srgb(244, 236, 200)
BODY = kit.srgb(214, 236, 206)      # the little head
BODY_D = kit.srgb(186, 216, 180)
LEAF = kit.srgb(150, 206, 122)
WOOD_T = kit.srgb(186, 138, 92)
WOOD_B = kit.srgb(150, 106, 68)
INK = kit.srgb(46, 44, 52)


def letter(ch, size):
    cu = bpy.data.curves.new("L_" + ch, "FONT")
    cu.body = ch
    cu.font = font
    cu.size = size
    cu.extrude = 0.10 * size
    cu.bevel_depth = 0.075 * size
    cu.bevel_resolution = 8
    cu.align_x = "CENTER"
    o = kit.new_obj("L_" + ch, cu)
    kit.assign(o, kit.gradient_mat("Cream", CREAM_TOP, CREAM_BOT, rough=0.26, coat=1.0,
                                   axis="Y", lo=-0.1 * size, hi=0.78 * size))
    return o


def width_of(o):
    bpy.context.view_layer.update()
    xs = [(o.matrix_world @ Vector(c)).x for c in o.bound_box]
    return max(xs) - min(xs)


# THE WORD. Mixed case with a tall capital, gently bouncing -- the reference
# is hand-lettered, so a dead-straight baseline reads as the wrong thing.
objs = [letter(c, 1.0) for c in WORD]
widths = [width_of(o) for o in objs]
total = sum(widths) + 0.035 * (len(objs) - 1)
x = -total / 2
for i, (o, w) in enumerate(zip(objs, widths)):
    o.location = (x + w / 2, math.sin(i * 1.35) * 0.028, 0)
    o.rotation_euler = (0, 0, math.radians(((i % 2) * 2 - 1) * 3.2))
    x += w + 0.035

# THE HEAD, sitting on the word about a third in, like the reference
hx = -total / 2 + total * 0.30
bpy.ops.mesh.primitive_uv_sphere_add(radius=0.42, segments=64, ring_count=32, location=(hx, 1.02, 0.12))
head = bpy.context.active_object
head.scale = (1.0, 0.94, 0.82)
kit.smooth(head, 0)
kit.assign(head, kit.gradient_mat("Head", BODY, BODY_D, rough=0.3, coat=0.9, axis="Y", lo=0.55, hi=1.35))
for sx in (-1, 1):
    bpy.ops.mesh.primitive_uv_sphere_add(radius=0.055, segments=24, ring_count=12,
                                         location=(hx + sx * 0.145, 1.03, 0.46))
    e = bpy.context.active_object
    e.scale = (1, 1.25, 0.6)
    kit.smooth(e, 0)
    kit.assign(e, kit.mat("Ink", INK, rough=0.35))
bpy.ops.mesh.primitive_torus_add(major_radius=0.075, minor_radius=0.016, major_segments=40, minor_segments=10,
                                 location=(hx, 0.955, 0.45), rotation=(math.pi / 2, 0, 0))
m = bpy.context.active_object
kit.smooth(m, 0)
kit.assign(m, kit.mat("Ink2", INK, rough=0.35))

# THE SPROUT, just right of the head
sx0 = hx + 0.62
bpy.ops.mesh.primitive_cylinder_add(vertices=20, radius=0.026, depth=0.26, location=(sx0, 0.95, 0.05))
st = bpy.context.active_object
kit.smooth(st, 0)
kit.assign(st, kit.mat("Stem", LEAF, rough=0.35))
for sgn, ang in ((-1, 32), (1, -32)):
    bpy.ops.mesh.primitive_uv_sphere_add(radius=0.19, segments=40, ring_count=20,
                                         location=(sx0 + sgn * 0.17, 1.11, 0.05))
    lf = bpy.context.active_object
    lf.scale = (1.35, 0.72, 0.30)
    lf.rotation_euler = (0, 0, math.radians(ang))
    kit.smooth(lf, 0)
    kit.assign(lf, kit.gradient_mat("Leaf", kit.srgb(176, 222, 146), LEAF, rough=0.32, coat=0.7,
                                    axis="Y", lo=0.9, hi=1.2))

# THE PLANK. A slab with softened, slightly irregular ends so it reads as a
# board rather than a rounded rectangle.
pw = total * 0.60
bpy.ops.mesh.primitive_cube_add(size=1, location=(0, -0.80, 0))
plank = bpy.context.active_object
plank.scale = (pw, 0.48, 0.30)
b = plank.modifiers.new("B", "BEVEL")
b.width = 0.085
b.segments = 6
b.limit_method = "ANGLE"
kit.smooth(plank, 1)
plank.rotation_euler = (0, 0, math.radians(-1.4))
kit.assign(plank, kit.gradient_mat("Wood", WOOD_T, WOOD_B, rough=0.55, coat=0.25,
                                   axis="Y", lo=-1.06, hi=-0.52))

pcu = bpy.data.curves.new("Plank", "FONT")
pcu.body = PLANK
pcu.font = font
pcu.size = 0.44
pcu.extrude = 0.05
pcu.bevel_depth = 0.032
pcu.bevel_resolution = 6
pcu.align_x = "CENTER"
pcu.space_character = 1.5
pt = kit.new_obj("PlankText", pcu)
pt.location = (0, -0.955, 0.33)
pt.rotation_euler = (0, 0, math.radians(-1.4))
kit.assign(pt, kit.mat("PlankInk", kit.srgb(255, 252, 245), rough=0.3, coat=1.0))

# cream has to stay cream: an over-lit bubble letter clips to flat white and
# loses the whole shape it was extruded for
kit.area_light("Key", (2.6, 2.2, 6.0), (0, -0.2, 0), 560, (1.0, 0.96, 0.88), 5)
kit.area_light("Fill", (-4.2, -2.0, 4.0), (0, -0.2, 0), 210, (0.82, 0.88, 1.0), 6)
kit.area_light("Spec", (0, 3.8, 3.2), (0, 0.2, 0), 260, (1, 1, 1), 2.5)
kit.camera((0, 0.02, 12), (0, 0.02, 0), ortho=total + 1.5)
kit.render(OUT, 1200, 720, samples=140)
print("LOGO_CITY_OK width", total)
