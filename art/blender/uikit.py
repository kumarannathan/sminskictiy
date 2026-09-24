# Tintable glossy UI surfaces (white, meant for ImageColor3 tint + 9-slice).
import sys, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import bpy, math, kit
from icons import puffy2d, rounded_rect_pts, candy

def shot(name, build, w, h, ortho):
    kit.reset()
    build()
    kit.area_light("Key", (0, 4, 8), (0, 0, 0), 900, (1, 1, 1), 6)
    kit.area_light("Fill", (0, -6, 5), (0, 0, 0), 250, (1, 1, 1), 8)
    kit.area_light("Top", (0, 0, 9), (0, 0, 0), 300, (1, 1, 1), 10)
    kit.camera((0, 0, 12), (0, 0, 0), ortho=ortho)
    bpy.context.scene.world.node_tree.nodes["Background"].inputs["Color"].default_value = (1, 1, 1, 1)
    bpy.context.scene.world.node_tree.nodes["Background"].inputs["Strength"].default_value = 0.35
    kit.render(os.path.join(kit.GAME_ART, name + ".png"), w, h, samples=96)

def pill():
    puffy2d("Pill", rounded_rect_pts(4.6, 1.5, 0.74, 16), 0.5, 0.3, candy("W", (236, 236, 236), 0.22))

def card():
    puffy2d("Card", rounded_rect_pts(4.6, 4.6, 0.62, 16), 0.3, 0.2, candy("W", (246, 246, 246), 0.35))

def disc():
    puffy2d("Disc", [(math.cos(a / 96 * math.tau), math.sin(a / 96 * math.tau)) for a in range(96)], 0.35, 0.28, candy("W", (236, 236, 236), 0.22))

shot("ui_pill", pill, 512, 170, 5.0)
shot("ui_card", card, 512, 512, 5.0)
shot("ui_disc", disc, 256, 256, 2.3)
print("UIKIT_OK")
