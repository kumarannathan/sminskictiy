# Shared Blender helpers for the Sminski Run art pipeline.
# Run with:  Blender --background --factory-startup --python <script>.py -- <args>
import bpy, bmesh, math, os
from mathutils import Vector, Matrix

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
GAME_ART = os.path.join(os.path.dirname(ROOT), "game", "art")
OUT_MESH = os.path.join(ROOT, "meshes")
os.makedirs(GAME_ART, exist_ok=True)
os.makedirs(OUT_MESH, exist_ok=True)

FONT_ROUNDED = "/System/Library/Fonts/Supplemental/Arial Rounded Bold.ttf"


def srgb(r, g, b, a=1.0):
    """0-255 sRGB -> linear RGBA for Blender colour sockets."""
    def lin(c):
        c = c / 255.0
        return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4
    return (lin(r), lin(g), lin(b), a)


def reset():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    prefs = bpy.context.preferences.addons["cycles"].preferences
    try:
        prefs.compute_device_type = "METAL"
        prefs.get_devices()
        for d in prefs.devices:
            d.use = True
        scene.cycles.device = "GPU"
    except Exception:
        scene.cycles.device = "CPU"
    scene.cycles.samples = 96
    scene.cycles.use_denoising = True
    scene.render.film_transparent = True
    scene.render.image_settings.file_format = "PNG"
    scene.render.image_settings.color_mode = "RGBA"
    scene.view_settings.view_transform = "Standard"
    scene.view_settings.look = "None"
    scene.cycles.max_bounces = 8
    scene.cycles.transmission_bounces = 8
    # soft purple-night ambient, like the key art
    world = bpy.data.worlds.new("World")
    scene.world = world
    world.use_nodes = True
    bg = world.node_tree.nodes["Background"]
    bg.inputs["Color"].default_value = srgb(120, 110, 170)
    bg.inputs["Strength"].default_value = 0.55
    return scene


def mat(name, color, rough=0.35, metal=0.0, emit=None, emit_strength=0.0, transmission=0.0, sss=0.0, coat=0.0, alpha=1.0):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    p = m.node_tree.nodes["Principled BSDF"]
    p.inputs["Base Color"].default_value = color
    p.inputs["Roughness"].default_value = rough
    p.inputs["Metallic"].default_value = metal
    if transmission:
        p.inputs["Transmission Weight"].default_value = transmission
    if sss:
        p.inputs["Subsurface Weight"].default_value = sss
        p.inputs["Subsurface Radius"].default_value = (0.6, 0.9, 0.5)
        p.inputs["Subsurface Scale"].default_value = 0.35
    if coat:
        p.inputs["Coat Weight"].default_value = coat
        p.inputs["Coat Roughness"].default_value = 0.06
    if emit:
        p.inputs["Emission Color"].default_value = emit
        p.inputs["Emission Strength"].default_value = emit_strength
    if alpha < 1:
        p.inputs["Alpha"].default_value = alpha
    return m


def gradient_mat(name, top, bottom, rough=0.3, coat=0.6, axis="Z", lo=-1.0, hi=1.0, emit_strength=0.0):
    """Vertical colour ramp in object space (bubbly logo letters)."""
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    p = nt.nodes["Principled BSDF"]
    tc = nt.nodes.new("ShaderNodeTexCoord")
    sep = nt.nodes.new("ShaderNodeSeparateXYZ")
    mr = nt.nodes.new("ShaderNodeMapRange")
    mr.inputs["From Min"].default_value = lo
    mr.inputs["From Max"].default_value = hi
    ramp = nt.nodes.new("ShaderNodeValToRGB")
    ramp.color_ramp.elements[0].color = bottom
    ramp.color_ramp.elements[1].color = top
    nt.links.new(tc.outputs["Object"], sep.inputs["Vector"])
    nt.links.new(sep.outputs[axis], mr.inputs["Value"])
    nt.links.new(mr.outputs["Result"], ramp.inputs["Fac"])
    nt.links.new(ramp.outputs["Color"], p.inputs["Base Color"])
    p.inputs["Roughness"].default_value = rough
    p.inputs["Coat Weight"].default_value = coat
    p.inputs["Coat Roughness"].default_value = 0.05
    if emit_strength:
        nt.links.new(ramp.outputs["Color"], p.inputs["Emission Color"])
        p.inputs["Emission Strength"].default_value = emit_strength
    return m


def assign(obj, m):
    obj.data.materials.clear()
    obj.data.materials.append(m)


def smooth(obj, level=2, auto=True):
    for poly in obj.data.polygons:
        poly.use_smooth = True
    if level:
        sd = obj.modifiers.new("Subsurf", "SUBSURF")
        sd.levels = level
        sd.render_levels = level
    return obj


def area_light(name, loc, target, energy, color=(1, 1, 1), size=4.0):
    ld = bpy.data.lights.new(name, "AREA")
    ld.energy = energy
    ld.color = color
    ld.size = size
    lo = bpy.data.objects.new(name, ld)
    bpy.context.scene.collection.objects.link(lo)
    lo.location = loc
    look_at(lo, target)
    return lo


def look_at(obj, target):
    d = Vector(target) - obj.location
    obj.rotation_euler = d.to_track_quat("-Z", "Y").to_euler()


def studio_lights(scale=1.0, warm=True):
    """Key (warm lamp), fill (cool purple), rim (mint) - the key-art mood."""
    s = scale
    area_light("Key", (4 * s, -5 * s, 6 * s), (0, 0, 0), 900 * s * s, (1.0, 0.86, 0.66) if warm else (1, 1, 1), 5 * s)
    area_light("Fill", (-6 * s, -3 * s, 2 * s), (0, 0, 0), 350 * s * s, (0.72, 0.68, 1.0), 6 * s)
    area_light("Rim", (-1 * s, 6 * s, 5 * s), (0, 0, 0), 700 * s * s, (0.75, 1.0, 0.8), 4 * s)


def camera(loc, target, ortho=None, lens=85):
    cd = bpy.data.cameras.new("Cam")
    if ortho:
        cd.type = "ORTHO"
        cd.ortho_scale = ortho
    else:
        cd.lens = lens
    co = bpy.data.objects.new("Cam", cd)
    bpy.context.scene.collection.objects.link(co)
    co.location = loc
    look_at(co, target)
    bpy.context.scene.camera = co
    return co


def render(path, w, h, samples=None):
    sc = bpy.context.scene
    sc.render.resolution_x = w
    sc.render.resolution_y = h
    sc.render.resolution_percentage = 100
    if samples:
        sc.cycles.samples = samples
    sc.render.filepath = path
    bpy.ops.render.render(write_still=True)


def new_obj(name, mesh):
    o = bpy.data.objects.new(name, mesh)
    bpy.context.scene.collection.objects.link(o)
    return o


def lathe(name, profile, steps=64):
    """Spin an (r, z) profile around Z into a closed, smooth solid."""
    bm = bmesh.new()
    rings = []
    for i in range(steps):
        a = i / steps * math.tau
        ring = [bm.verts.new((r * math.cos(a), r * math.sin(a), z)) for r, z in profile]
        rings.append(ring)
    for i in range(steps):
        a, b = rings[i], rings[(i + 1) % steps]
        for j in range(len(profile) - 1):
            bm.faces.new((a[j], b[j], b[j + 1], a[j + 1]))
    # caps
    top = bm.verts.new((0, 0, profile[-1][1]))
    bot = bm.verts.new((0, 0, profile[0][1]))
    for i in range(steps):
        a, b = rings[i], rings[(i + 1) % steps]
        bm.faces.new((a[-1], b[-1], top))
        bm.faces.new((b[0], a[0], bot))
    me = bpy.data.meshes.new(name)
    bm.normal_update()
    bm.to_mesh(me)
    bm.free()
    o = new_obj(name, me)
    for p in me.polygons:
        p.use_smooth = True
    return o


def star_prism(name, r_out, r_in, depth, points=5, round_tips=0.0):
    """Extruded 5-point star (flat faces along Z)."""
    bm = bmesh.new()
    top, bot = [], []
    for i in range(points * 2):
        a = math.pi / 2 + i * math.pi / points
        r = r_out if i % 2 == 0 else r_in
        x, y = r * math.cos(a), r * math.sin(a)
        top.append(bm.verts.new((x, y, depth / 2)))
        bot.append(bm.verts.new((x, y, -depth / 2)))
    bm.faces.new(top)
    bm.faces.new(list(reversed(bot)))
    n = len(top)
    for i in range(n):
        bm.faces.new((bot[i], bot[(i + 1) % n], top[(i + 1) % n], top[i]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    return new_obj(name, me)


def apply_mods(obj):
    bpy.context.view_layer.objects.active = obj
    for o in bpy.context.selected_objects:
        o.select_set(False)
    obj.select_set(True)
    for m in list(obj.modifiers):
        bpy.ops.object.modifier_apply(modifier=m.name)
