# Reusable shapes: star coin, Sminski body parts. Used for renders and mesh export.
import bpy, math
from mathutils import Vector
import kit

GOLD = kit.srgb(255, 200, 80)
GOLD_LIGHT = kit.srgb(255, 226, 130)


def coin_materials():
    return (kit.mat("CoinGold", GOLD, rough=0.3, metal=1.0, coat=0.5),
            kit.mat("CoinStar", GOLD_LIGHT, rough=0.22, metal=0.85, coat=0.7))


def build_coin(name="StarCoin", subsurf=2, apply=False):
    """Thick gold coin, raised rim, embossed star on both faces. Radius 1, facing +/-Z."""
    profile = [(0.02, -0.1), (0.62, -0.1), (0.66, -0.12), (0.70, -0.2), (0.78, -0.225), (0.93, -0.215), (0.99, -0.15),
               (1.0, 0.0), (0.99, 0.15), (0.93, 0.215), (0.78, 0.225), (0.70, 0.2), (0.66, 0.12), (0.62, 0.1), (0.02, 0.1)]
    body = kit.lathe(name, profile, steps=72)
    kit.smooth(body, subsurf)
    star = kit.star_prism(name + "Star", 0.5, 0.27, 0.3)
    bev = star.modifiers.new("Bevel", "BEVEL")
    bev.width = 0.07
    bev.segments = 5
    bev.limit_method = "NONE"
    kit.smooth(star, subsurf - 1 if subsurf > 1 else 1)
    gold, starm = coin_materials()
    kit.assign(body, gold)
    kit.assign(star, starm)
    if apply:
        kit.apply_mods(body)
        kit.apply_mods(star)
        bpy.ops.object.select_all(action="DESELECT")
        star.select_set(True)
        body.select_set(True)
        bpy.context.view_layer.objects.active = body
        bpy.ops.object.join()
    return body, star


def capsule(name, radius, length, seg=32, rings=12, squash=(1, 1, 1)):
    """Vertical capsule centred on the origin (length = straight part)."""
    prof = []
    for i in range(rings + 1):
        a = -math.pi / 2 + i / rings * math.pi / 2
        prof.append((max(0.0005, radius * math.cos(a)), -length / 2 + radius * math.sin(a)))
    for i in range(rings + 1):
        a = i / rings * math.pi / 2
        prof.append((max(0.0005, radius * math.cos(a)), length / 2 + radius * math.sin(a)))
    o = kit.lathe(name, prof, steps=seg)
    o.scale = squash
    return o
