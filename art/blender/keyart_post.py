# Finish the key-art renders (art/preview/keyart_raw) into store / ad images:
# bloom, colour pop, vignette, then the logo + tagline (or a custom title).
#   python3 keyart_post.py            -> art/keyart/*.png
import os, sys
from PIL import Image, ImageFilter, ImageChops, ImageDraw, ImageFont, ImageEnhance

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
RAW = os.path.join(ROOT, "preview", "keyart_raw")
OUT = os.path.join(ROOT, "keyart")
ART = os.path.join(os.path.dirname(ROOT), "game", "art")
FONT = "/System/Library/Fonts/Supplemental/Arial Rounded Bold.ttf"
os.makedirs(OUT, exist_ok=True)

GREEN = (216, 255, 122)
INK = (40, 92, 28)


def grade(img):
    lum = img.convert("L").point(lambda v: 0 if v < 175 else int((v - 175) * 255 / 80))
    glow = Image.composite(img, Image.new("RGB", img.size), lum).filter(ImageFilter.GaussianBlur(img.width // 55))
    glow = ImageEnhance.Brightness(glow).enhance(1.25)
    img = ImageChops.screen(img, glow)
    img = ImageEnhance.Color(img).enhance(1.22)
    img = ImageEnhance.Contrast(img).enhance(1.08)
    w, h = img.size
    m = Image.new("L", (w, h), 0)
    ImageDraw.Draw(m).ellipse((-w * 0.2, -h * 0.3, w * 1.2, h * 1.3), fill=255)
    m = m.filter(ImageFilter.GaussianBlur(min(w, h) * 0.2))
    dark = Image.new("RGB", (w, h), (34, 16, 70))
    return Image.composite(dark, img, m.point(lambda v: int((255 - v) * 0.5)))


def text(c, s, center, size, fill=GREEN, outline=INK, ow=None):
    f = ImageFont.truetype(FONT, size)
    ow = ow or max(3, size // 8)
    sh = Image.new("RGBA", c.size, (0, 0, 0, 0))
    ImageDraw.Draw(sh).text((center[0], center[1] + ow), s, font=f, fill=(20, 10, 40, 170), stroke_width=ow, stroke_fill=(20, 10, 40, 170), anchor="mm")
    c.alpha_composite(sh.filter(ImageFilter.GaussianBlur(4)))
    ImageDraw.Draw(c).text(center, s, font=f, fill=fill, stroke_width=ow, stroke_fill=outline, anchor="mm")


def logo(c, cx, cy, width):
    lg = Image.open(os.path.join(ART, "logo.png")).convert("RGBA")
    lg = lg.resize((int(width), int(lg.height * width / lg.width)), Image.LANCZOS)
    c.alpha_composite(lg, (int(cx - lg.width / 2), int(cy - lg.height / 2)))
    return lg.height


def heart_badge(c, cx, cy, size):
    """Glowing green heart with a + (the revive badge)."""
    s = int(size)
    layer = Image.new("RGBA", (s * 2, s * 2), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    o = s // 2

    def heart(scale, col):
        r = s * 0.27 * scale
        cx0, cy0 = s, s * 0.92
        d.ellipse((cx0 - 2 * r, cy0 - r * 1.1, cx0, cy0 + r * 0.9), fill=col)
        d.ellipse((cx0, cy0 - r * 1.1, cx0 + 2 * r, cy0 + r * 0.9), fill=col)
        d.polygon([(cx0 - 1.93 * r, cy0 + r * 0.3), (cx0 + 1.93 * r, cy0 + r * 0.3), (cx0, cy0 + r * 2.5)], fill=col)

    heart(1.22, (40, 92, 28, 255))
    heart(1.0, (150, 235, 95, 255))
    r = s * 0.27
    d.rounded_rectangle((s - r * 0.22, s * 0.92 - r * 0.75, s + r * 0.22, s * 0.92 + r * 0.95), radius=r * 0.12, fill=(240, 255, 225, 255))
    d.rounded_rectangle((s - r * 0.85, s * 0.92 - r * 0.12 + r * 0.1, s + r * 0.85, s * 0.92 + r * 0.32 + r * 0.1), radius=r * 0.12, fill=(240, 255, 225, 255))
    glow = layer.filter(ImageFilter.GaussianBlur(s * 0.08))
    c.alpha_composite(glow, (int(cx - s), int(cy - s)))
    c.alpha_composite(layer, (int(cx - s), int(cy - s)))


def make(src, out, size, logo_at=None, logo_w=0.4, tag=None, tag_at=None, tag_size=0.058, title=None, title_at=None, title_size=0.16, heart=False):
    img = Image.open(os.path.join(RAW, src)).convert("RGB").resize(size, Image.LANCZOS)
    c = grade(img).convert("RGBA")
    W, H = size
    if logo_at:
        lh = logo(c, W * logo_at[0], H * logo_at[1], W * logo_w)
        if tag and not tag_at:
            tag_at = (logo_at[0], logo_at[1] + (lh / 2 + H * 0.05) / H)
    if title:
        if heart:
            heart_badge(c, W * title_at[0], H * (title_at[1] - title_size * 0.95), H * title_size * 0.95)
        text(c, title, (W * title_at[0], H * title_at[1]), int(H * title_size), fill=(244, 255, 232), ow=int(H * title_size * 0.13))
    if tag:
        text(c, tag, (W * tag_at[0], H * tag_at[1]), int(H * tag_size))
    c.convert("RGB").save(os.path.join(OUT, out))
    print("KEYART", out)


if __name__ == "__main__":
    WIDE, SQ = (1920, 1080), (1254, 1254)
    make("hero_wide.png", "SminskiRun_KeyArt_Hero_1920x1080.png", WIDE, logo_at=(0.735, 0.2), logo_w=0.42, tag="RUN FROM THE KID!")
    make("hero_square.png", "SminskiRun_KeyArt_Hero_Square.png", SQ, logo_at=(0.63, 0.17), logo_w=0.62)
    make("friends_wide.png", "SminskiRun_KeyArt_Friends_1920x1080.png", WIDE, logo_at=(0.2, 0.2), logo_w=0.36, tag="PLAY WITH FRIENDS!")
    make("friends_square.png", "SminskiRun_KeyArt_Friends_Square.png", SQ, logo_at=(0.5, 0.15), logo_w=0.6, tag="PLAY WITH FRIENDS!", tag_size=0.05)
    make("dogpark_wide.png", "SminskiRun_KeyArt_DogPark_1920x1080.png", WIDE, logo_at=(0.74, 0.2), logo_w=0.4, tag="DOG PARK SURVIVAL")
    make("dogpark_square.png", "SminskiRun_KeyArt_DogPark_Square.png", SQ, logo_at=(0.62, 0.16), logo_w=0.6, tag="HE JUST WANTS TO PLAY", tag_size=0.046)
    make("revive_wide.png", "SminskiRun_KeyArt_Revive_1920x1080.png", WIDE, title="Revive", title_at=(0.76, 0.34), title_size=0.17, heart=True)
    make("revive_square.png", "SminskiRun_KeyArt_Revive_Square.png", SQ, title="Revive", title_at=(0.68, 0.3), title_size=0.15, heart=True)
