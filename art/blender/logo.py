# Bubbly 3D logo in the key-art style: puffy lime letters, thick dark-green
# outline, glossy highlight, little bounce per letter.
#   Blender --background --factory-startup --python logo.py -- [out.png] [TEXT1] [TEXT2]
import sys, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import bpy, math, kit
from mathutils import Vector

argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
OUT = argv[0] if len(argv) > 0 else os.path.join(kit.GAME_ART, "logo.png")
LINE1 = argv[1] if len(argv) > 1 else "SMINSKI"
LINE2 = argv[2] if len(argv) > 2 else "RUN"

kit.reset()
scene = bpy.context.scene
font = bpy.data.fonts.load(kit.FONT_ROUNDED)

FILL_TOP = kit.srgb(228, 255, 168)
FILL_BOT = kit.srgb(150, 228, 70)
RUN_TOP = kit.srgb(215, 255, 120)
RUN_BOT = kit.srgb(120, 205, 40)
OUTLINE = kit.srgb(40, 92, 28)


def letter(ch, size, top, bot, outline_w):
    cu = bpy.data.curves.new("L_" + ch, "FONT")
    cu.body = ch
    cu.font = font
    cu.size = size
    cu.extrude = 0.1 * size
    cu.bevel_depth = 0.07 * size
    cu.bevel_resolution = 8
    cu.align_x = "CENTER"
    body = kit.new_obj("L_" + ch, cu)
    kit.assign(body, kit.gradient_mat("Fill", top, bot, rough=0.25, coat=1.0, axis="Y", lo=0.0, hi=0.72 * size))
    return body


def width_of(obj):
    bpy.context.view_layer.update()
    xs = [(obj.matrix_world @ Vector(c)).x for c in obj.bound_box]
    return max(xs) - min(xs)


def word(text, size, y, top, bot, outline_w, bounce, spacing):
    objs = [letter(c, size, top, bot, outline_w) for c in text]
    widths = [width_of(o) for o in objs]
    total = sum(widths) + spacing * (len(objs) - 1)
    x = -total / 2
    for i, (o, w) in enumerate(zip(objs, widths)):
        o.location = (x + w / 2, y + math.sin(i * 1.7) * bounce * size, 0)
        o.rotation_euler = (0, 0, math.radians(((i % 2) * 2 - 1) * 4))
        x += w + spacing
    return objs, total


w1 = word(LINE1, 1.0, 0.0, FILL_TOP, FILL_BOT, 0.075, 0.035, -0.02)[1]
w2 = word(LINE2, 0.8, -0.95, RUN_TOP, RUN_BOT, 0.07, 0.03, 0.0)[1]

# sparkle dashes either side of the second line, like the key art
dash = kit.mat("Dash", RUN_BOT, rough=0.3, coat=1.0)
for sx in (-1, 1):
    for j, (dx, dy, rot) in enumerate(((0.36, 0.36, 40), (0.6, 0.0, 0), (0.36, -0.36, -40))):
        bpy.ops.mesh.primitive_cylinder_add(vertices=24, radius=0.05, depth=0.16, location=(sx * (w2 / 2 + dx), -0.95 + 0.3 + dy, 0))
        d = bpy.context.active_object
        d.rotation_euler = (0, math.pi / 2, math.radians(rot * sx))
        d.scale = (1, 1, 1.2)
        bev = d.modifiers.new("B", "BEVEL")
        bev.width = 0.04
        bev.segments = 4
        kit.smooth(d, 1)
        kit.assign(d, dash)

# lights from the front-top (text faces +Z)
kit.area_light("Key", (2.5, 2.0, 6.0), (0, -0.3, 0), 900, (1.0, 0.95, 0.85), 4)
kit.area_light("Fill", (-4, -2, 4), (0, -0.3, 0), 300, (0.8, 0.85, 1.0), 6)
kit.area_light("Spec", (0, 4, 3), (0, 0, 0), 400, (1, 1, 1), 2)
cam = kit.camera((0, -0.35, 12), (0, -0.35, 0), ortho=max(w1, w2) + 1.3)
kit.render(OUT, 1024, 560, samples=128)  # outline is added in 2D by outline.py
print("LOGO_OK", w1, w2)
