# Face decals (transparent PNG) front-projected onto the head meshes.
# Coordinates are head/joint space in studs; rect = the UV projection rect from rig_meshes.py.
from PIL import Image, ImageDraw, ImageFilter
import os, math
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "game", "art")
SS = 3

class Face:
    def __init__(self, size, rect):
        self.size = size
        self.rect = rect
        self.img = Image.new("RGBA", (size * SS, size * SS), (0, 0, 0, 0))
        self.d = ImageDraw.Draw(self.img)
    def px(self, x, y):
        x0, x1, y0, y1 = self.rect
        return ((x - x0) / (x1 - x0) * self.size * SS, (1 - (y - y0) / (y1 - y0)) * self.size * SS)
    def k(self):
        return self.size * SS / (self.rect[1] - self.rect[0])
    def ellipse(self, cx, cy, rx, ry, col):
        a = self.px(cx - rx, cy + ry); b = self.px(cx + rx, cy - ry)
        self.d.ellipse((a[0], a[1], b[0], b[1]), fill=col)
    def line(self, pts, w, col):
        pp = [self.px(x, y) for x, y in pts]
        self.d.line(pp, fill=col, width=max(1, int(w * self.k())), joint="curve")
        r = w * self.k() / 2
        for p in (pp[0], pp[-1]):
            self.d.ellipse((p[0] - r, p[1] - r, p[0] + r, p[1] + r), fill=col)
    def arc(self, cx, cy, rx, ry, a0, a1, w, col, n=24):
        pts = [(cx + rx * math.cos(math.radians(a0 + (a1 - a0) * i / n)), cy + ry * math.sin(math.radians(a0 + (a1 - a0) * i / n))) for i in range(n + 1)]
        self.line(pts, w, col)
    def save(self, name, soften=0):
        im = self.img
        if soften:
            im = im.filter(ImageFilter.GaussianBlur(soften))
        im.resize((self.size, self.size), Image.LANCZOS).save(os.path.join(OUT, name))

# SMINSKI: shiny oval eyes, soft brows, little smile (reads on every body colour)
f = Face(512, (-0.8, 0.8, -0.8, 0.8))
INK = (38, 52, 34, 255)
for sx in (-1, 1):
    f.ellipse(0.27 * sx, -0.03, 0.078, 0.105, INK)
    f.ellipse(0.27 * sx + 0.026, 0.012, 0.03, 0.034, (255, 255, 255, 255))
    f.ellipse(0.27 * sx - 0.022, -0.075, 0.013, 0.013, (255, 255, 255, 230))
    f.line([(0.37 * sx, 0.2), (0.27 * sx, 0.215), (0.17 * sx, 0.185)], 0.042, INK)
    f.ellipse(0.43 * sx, -0.19, 0.085, 0.045, (255, 150, 150, 70))  # faint blush
f.arc(0.02, -0.21, 0.085, 0.07, 200, 340, 0.036, INK)
f.save("face_sminski.png")

# KID: big glossy eyes, cross brows, open yelling mouth, blush (head dia 13.5, centre y 7.8)
HC, K = 7.8, 13.5 / 11.5
f = Face(1024, (-6.75, 6.75, HC - 6.75, HC + 6.75))
def P(x, y): return (x * K, HC + y * K)
EYE = (35, 30, 45, 255)
for sx in (-1, 1):
    x, y = P(2.3 * sx, 0.15)
    f.ellipse(x, y, 0.95 * K, 1.3 * K, EYE)
    f.ellipse(x + 0.35 * K, y + 0.55 * K, 0.38 * K, 0.42 * K, (255, 255, 255, 255))
    f.ellipse(x - 0.35 * K, y - 0.6 * K, 0.18 * K, 0.18 * K, (255, 255, 255, 235))
    a, b = P(3.35 * sx, 1.72), P(1.35 * sx, 1.28)
    f.line([a, b], 0.62 * K, (95, 60, 40, 255))
    bx, by = P(3.95 * sx, -1.5)
    f.ellipse(bx, by, 1.05 * K, 0.55 * K, (255, 150, 150, 150))
mx, my = P(0, -2.5)
f.ellipse(mx, my, 1.55 * K, 1.15 * K, (140, 45, 60, 255))
f.ellipse(mx, my - 0.55 * K, 0.95 * K, 0.45 * K, (245, 120, 130, 255))
tx, ty = P(0, -1.75)
f.ellipse(tx, ty, 1.0 * K, 0.28 * K, (255, 255, 255, 255))
f.save("face_kid.png")

# KID (calm): the gamer at his desk. Relaxed half-lidded eyes, soft brows, a
# small focused smile, headphone-light glow catch in the eyes.
f = Face(1024, (-6.75, 6.75, HC - 6.75, HC + 6.75))
for sx in (-1, 1):
    x, y = P(2.3 * sx, 0.15)
    f.ellipse(x, y, 0.95 * K, 1.05 * K, EYE)
    # upper lid: skin-coloured cap makes the eye look relaxed
    f.ellipse(x, y + 0.75 * K, 1.05 * K, 0.55 * K, (245, 214, 190, 255))
    f.ellipse(x + 0.3 * K, y + 0.25 * K, 0.34 * K, 0.34 * K, (255, 255, 255, 255))
    f.ellipse(x - 0.3 * K, y - 0.45 * K, 0.15 * K, 0.15 * K, (180, 240, 255, 235))
    a, b = P(3.3 * sx, 1.55), P(1.35 * sx, 1.6)
    f.line([a, b], 0.5 * K, (95, 60, 40, 255))
    bx, by = P(3.9 * sx, -1.4)
    f.ellipse(bx, by, 1.0 * K, 0.5 * K, (255, 150, 150, 110))
f.arc(0.3 * K, HC - 2.2 * K, 0.9 * K, 0.5 * K, 15, 165, 0.32 * K, (140, 45, 60, 255))
f.save("face_kid_calm.png")

# DOG: soft puppy eyes with shine + little brow tufts (head space; head centre (0,3,3))
f = Face(512, (-6.5, 6.5, -3, 9))
for sx in (-1, 1):
    f.ellipse(3.1 * sx, 5.4, 1.15, 1.45, (35, 28, 30, 255))
    f.ellipse(3.1 * sx + 0.4, 5.95, 0.45, 0.5, (255, 255, 255, 255))
    f.ellipse(3.1 * sx - 0.35, 4.85, 0.2, 0.2, (255, 255, 255, 220))
    f.ellipse(3.0 * sx, 7.55, 1.1, 0.42, (196, 132, 64, 255))
f.save("face_dog.png")
print("FACES_OK")
