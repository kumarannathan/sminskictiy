import sys, os, json
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import bpy, kit
from rigkit import rb, P, PT
from mathutils import Vector, Matrix
kit.reset()
parts = json.load(open(os.path.join(kit.OUT_MESH, "room_parts.json")))
cols = json.load(open(os.path.join(kit.OUT_MESH, "room_colors.json")))
bpy.ops.import_scene.fbx(filepath=os.path.join(kit.OUT_MESH, "SminskiRoom.fbx"))
src = {o.name.split(".")[0]: o for o in bpy.data.objects if o.type == "MESH"}
props = sorted({k.split("__")[0] for k in parts})
# normalise every prop to ~10 studs tall, lay them out in a grid
bbox = {}
for k, v in parts.items():
    p = k.split("__")[0]
    o, s = Vector(v["offset"]), Vector(v["size"])
    lo, hi = o - s / 2, o + s / 2
    if p in bbox:
        bbox[p] = (Vector(map(min, bbox[p][0], lo)), Vector(map(max, bbox[p][1], hi)))
    else:
        bbox[p] = (lo, hi)
for i, p in enumerate(props):
    lo, hi = bbox[p]
    k = 10 / max(hi - lo)
    origin = Vector(((i % 7) * 14 - 42, 0, -(i // 7) * 16))
    for name, v in parts.items():
        if not name.startswith(p + "__"):
            continue
        o = src[name].copy(); o.data = src[name].data
        bpy.context.scene.collection.objects.link(o)
        c = cols[name]
        m = kit.mat(name, kit.srgb(*c["color"]), rough=0.3 if c["material"] != "Metal" else 0.25, metal=1.0 if c["material"] == "Metal" else 0.0, coat=0.4,
                    emit=kit.srgb(*c["color"]) if c["material"] == "Neon" else None, emit_strength=3 if c["material"] == "Neon" else 0)
        o.data.materials.clear(); o.data.materials.append(m)
        pos = origin + (Vector(v["offset"]) - Vector((0, lo.y, 0))) * k
        o.matrix_world = Matrix.Translation(rb(pos)) @ Matrix.Scale(k, 4)
for ob in list(src.values()):
    bpy.data.objects.remove(ob)
kit.studio_lights(9)
kit.camera(rb((0, 44, 74)), rb((0, 4, -14)), lens=40)
kit.render(os.path.join(kit.ROOT, "preview", "room_preview.png"), 1280, 800, samples=48)
print("PP_OK")
