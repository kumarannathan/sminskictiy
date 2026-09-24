import sys, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import bpy, math, kit, shapes
kit.reset()
body, star = shapes.build_coin()
for o in (body, star):
    o.rotation_euler = (math.radians(70), 0, math.radians(-18))
kit.studio_lights(0.6)
kit.camera((0, -6, 0.3), (0, 0, 0), ortho=2.5)
kit.render(os.path.join(kit.GAME_ART, "icon_coin.png"), 256, 256, samples=64)
