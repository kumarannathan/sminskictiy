import sys, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import bpy, math, kit, sminski
kit.reset()
root = sminski.build("Glow", "run", mood="determined")
root.rotation_euler.z = math.radians(-20)
kit.studio_lights(1.2)
kit.camera((0, -9, 2.6), (0, 0, 2.0), lens=70)
kit.render(os.path.join(kit.ROOT, "preview", "sminski_test.png"), 512, 512, samples=96)
