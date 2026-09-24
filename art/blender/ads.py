# Roblox ad campaign images from in-game screen grabs (art/shots/*.png).
#   python3 ads.py            -> art/ads/*.png
# Each grab is first trimmed to its top 75% (the Studio view-selector gizmo sits
# below that), then crop-fitted to each ad size around a focus point, then
# bloom + vignette + logo + tagline (+ a PLAY button on the banner formats).
import os, sys
from PIL import Image, ImageFilter, ImageChops, ImageDraw, ImageFont, ImageEnhance

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
SHOTS = os.path.join(ROOT, "shots")
OUT = os.path.join(ROOT, "ads")
LOGO = os.path.join(os.path.dirname(ROOT), "game", "art", "logo.png")
FONT = "/System/Library/Fonts/Supplemental/Arial Rounded Bold.ttf"
os.makedirs(OUT, exist_ok=True)

GREEN = (216, 255, 122)
WHITE = (255, 255, 255)
INK = (40, 92, 28)
PURPLE = (60, 40, 110)


def load(name, safe=1.0):
    im = Image.open(os.path.join(SHOTS, name + ".png")).convert("RGB")
    # paint over the Studio view-selector gizmo (fixed spot, lower left) with
    # the floor just to its right, feathered
    gx0, gy0, gx1, gy1 = 740, 1190, 930, 1360
    patch = im.crop((gx0 + 200, gy0, gx1 + 200, gy1)).filter(ImageFilter.GaussianBlur(1.5))
    mask = Image.new("L", patch.size, 0)
    ImageDraw.Draw(mask).rounded_rectangle((8, 8, patch.width - 8, patch.height - 8), radius=30, fill=255)
    mask = mask.filter(ImageFilter.GaussianBlur(8))
    im.paste(patch, (gx0, gy0), mask)
    return im.crop((0, 0, im.width, int(im.height * safe)))


def fit(im, size, focus=(0.5, 0.5), zoom=1.0):
    """Crop-fit to size (w, h) around a focus point (fractions), zoom>1 tightens."""
    W, H = size
    sw, sh = im.size
    scale = max(W / sw, H / sh) * zoom
    cw, ch = W / scale, H / scale
    cx, cy = focus[0] * sw, focus[1] * sh
    x0 = min(max(cx - cw / 2, 0), sw - cw)
    y0 = min(max(cy - ch / 2, 0), sh - ch)
    return im.crop((int(x0), int(y0), int(x0 + cw), int(y0 + ch))).resize((W, H), Image.LANCZOS)


def grade(img, bloom_amt=0.5, vig=0.45):
    lum = img.convert("L").point(lambda v: 0 if v < 190 else int((v - 190) * 255 / 65))
    glow = Image.composite(img, Image.new("RGB", img.size), lum).filter(ImageFilter.GaussianBlur(max(6, img.width // 70)))
    glow = ImageEnhance.Brightness(glow).enhance(bloom_amt * 2)
    img = ImageChops.screen(img, glow)
    img = ImageEnhance.Color(img).enhance(1.15)
    img = ImageEnhance.Contrast(img).enhance(1.06)
    w, h = img.size
    m = Image.new("L", (w, h), 0)
    ImageDraw.Draw(m).ellipse((-w * 0.2, -h * 0.3, w * 1.2, h * 1.3), fill=255)
    m = m.filter(ImageFilter.GaussianBlur(min(w, h) * 0.2))
    dark = Image.new("RGB", (w, h), (30, 15, 60))
    return Image.composite(dark, img, m.point(lambda v: int((255 - v) * vig)))


def text(canvas, s, center, size, fill, outline=INK, anchor="mm", shadow=True):
    f = ImageFont.truetype(FONT, size)
    ow = max(2, size // 9)
    d = ImageDraw.Draw(canvas)
    if shadow:
        sh = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
        ImageDraw.Draw(sh).text((center[0], center[1] + ow), s, font=f, fill=(20, 10, 40, 160), stroke_width=ow, stroke_fill=(20, 10, 40, 160), anchor=anchor)
        canvas.alpha_composite(sh.filter(ImageFilter.GaussianBlur(2)))
    d.text(center, s, font=f, fill=fill, stroke_width=ow, stroke_fill=outline, anchor=anchor)
    return d.textbbox(center, s, font=f, stroke_width=ow, anchor=anchor)


def logo(canvas, cx, cy, width):
    lg = Image.open(LOGO).convert("RGBA")
    lg = lg.resize((int(width), int(lg.height * width / lg.width)), Image.LANCZOS)
    canvas.alpha_composite(lg, (int(cx - lg.width / 2), int(cy - lg.height / 2)))
    return lg.height


def button(canvas, cx, cy, w, h, label, col=(120, 200, 110)):
    d = ImageDraw.Draw(canvas)
    d.rounded_rectangle((cx - w / 2, cy - h / 2 + h * 0.08, cx + w / 2, cy + h / 2 + h * 0.08), radius=h / 2, fill=(50, 110, 45))
    d.rounded_rectangle((cx - w / 2, cy - h / 2, cx + w / 2, cy + h / 2), radius=h / 2, fill=col)
    d.rounded_rectangle((cx - w / 2 + h * 0.15, cy - h / 2 + h * 0.1, cx + w / 2 - h * 0.15, cy - h * 0.05), radius=h / 3, fill=(170, 235, 150))
    text(canvas, label, (cx, cy + h * 0.02), int(h * 0.5), WHITE, outline=(50, 110, 45), shadow=False)


def hero(name, src, focus, tag, tag2=None, logo_side="right", zoom=1.0):
    W, H = 1920, 1080
    img = grade(fit(load(src), (W, H), focus, zoom))
    c = img.convert("RGBA")
    lx = W * (0.74 if logo_side == "right" else 0.26)
    lh = logo(c, lx, H * 0.17, W * 0.42)
    y = H * 0.17 + lh / 2 + H * 0.05
    text(c, tag, (lx, y), 62, GREEN)
    if tag2:
        text(c, tag2, (lx, y + 78), 40, WHITE, outline=PURPLE)
    c.convert("RGB").save(os.path.join(OUT, name + "_1920x1080.png"))


def square(name, src, focus, tag, tag2=None, zoom=1.0):
    W = 1080
    img = grade(fit(load(src), (W, W), focus, zoom))
    c = img.convert("RGBA")
    lh = logo(c, W / 2, W * 0.15, W * 0.7)
    text(c, tag, (W / 2, W * 0.86), 58, GREEN)
    if tag2:
        text(c, tag2, (W / 2, W * 0.93), 36, WHITE, outline=PURPLE)
    c.convert("RGB").save(os.path.join(OUT, name + "_1080x1080.png"))


def portrait(name, src, focus, tag, tag2=None, zoom=1.0):
    W, H = 1080, 1920
    img = grade(fit(load(src), (W, H), focus, zoom), vig=0.5)
    c = img.convert("RGBA")
    logo(c, W / 2, H * 0.12, W * 0.8)
    text(c, tag, (W / 2, H * 0.82), 64, GREEN)
    if tag2:
        text(c, tag2, (W / 2, H * 0.87), 40, WHITE, outline=PURPLE)
    button(c, W / 2, H * 0.94, 520, 110, "PLAY FREE")
    c.convert("RGB").save(os.path.join(OUT, name + "_1080x1920.png"))


def banner728(name, src, focus, tag, zoom=1.0):
    W, H = 728, 90
    img = grade(fit(load(src), (W, H), focus, zoom), bloom_amt=0.35, vig=0.3)
    c = img.convert("RGBA")
    # darken a band under the text for legibility
    band = Image.new("RGBA", (W, H), (20, 10, 50, 0))
    ImageDraw.Draw(band).rectangle((0, 0, W, H), fill=(20, 10, 50, 90))
    c.alpha_composite(band)
    logo(c, 100, H / 2, 170)
    text(c, tag, (372, H / 2), 26, GREEN)
    button(c, 656, H / 2, 112, 44, "PLAY")
    c.convert("RGB").save(os.path.join(OUT, name + "_728x90.png"))


def rect300(name, src, focus, tag, tag2=None, zoom=1.0):
    W, H = 300, 250
    img = grade(fit(load(src), (W, H), focus, zoom), bloom_amt=0.35)
    c = img.convert("RGBA")
    logo(c, W / 2, 48, 200)
    text(c, tag, (W / 2, 168), 24, GREEN)
    if tag2:
        text(c, tag2, (W / 2, 196), 16, WHITE, outline=PURPLE)
    button(c, W / 2, 228, 120, 34, "PLAY")
    c.convert("RGB").save(os.path.join(OUT, name + "_300x250.png"))


def sky160(name, src, focus, tag, tag2=None, zoom=1.0):
    W, H = 160, 600
    img = grade(fit(load(src), (W, H), focus, zoom), bloom_amt=0.35, vig=0.5)
    c = img.convert("RGBA")
    logo(c, W / 2, 70, 150)
    text(c, tag, (W / 2, 470), 22, GREEN)
    if tag2:
        text(c, tag2, (W / 2, 500), 15, WHITE, outline=PURPLE)
    button(c, W / 2, 555, 120, 40, "PLAY")
    c.convert("RGB").save(os.path.join(OUT, name + "_160x600.png"))


if __name__ == "__main__":
    # 16:9 heroes (Roblox thumbnails / sponsored experience creatives)
    hero("ad_lobby", "hub_row2", (0.45, 0.55), "EXPLORE THE TABLE", "a whole toy world on one side table", logo_side="left")
    hero("ad_bighouse", "run_house5", (0.45, 0.55), "RUN FROM THE KID!", "endless runner • dodge • glide • collect", logo_side="right", zoom=1.0)
    hero("ad_dollhouse", "run_dollhouse", (0.5, 0.55), "A TINY TOY IS ON THE RUN", "new maps • new Sminskis to collect", logo_side="left")
    hero("ad_dogpark", "run_dogpark2", (0.5, 0.5), "HE JUST WANTS TO PLAY", "dog park survival • 16 players • last one standing", logo_side="left")
    hero("ad_gamer", "gamer", (0.35, 0.5), "SOMEONE'S ALWAYS WATCHING", "play free on Roblox", logo_side="right")
    # squares + a story-size portrait
    square("ad_sq_dollhouse", "run_dollhouse", (0.5, 0.6), "A TINY TOY IS ON THE RUN", "play free on Roblox")
    square("ad_sq_dog", "run_dogpark2", (0.5, 0.45), "DOG PARK SURVIVAL", "16 players • last Sminski alive wins", zoom=1.1)
    square("ad_sq_lobby", "hub_row2", (0.5, 0.55), "PICK A HUT. START RUNNING.", "3 maps • endless run", zoom=1.15)
    portrait("ad_story_house", "run_house5", (0.42, 0.55), "RUN FROM THE KID!", "endless runner • play free", zoom=1.0)
    portrait("ad_story_dog", "run_dogpark2", (0.52, 0.45), "HE JUST WANTS TO PLAY", "dog park survival is live", zoom=1.0)
    # Roblox display ad sizes
    banner728("ad_banner_house", "run_house5", (0.42, 0.62), "A TINY TOY IS ON THE RUN", zoom=1.3)
    banner728("ad_banner_dog", "run_dogpark2", (0.5, 0.45), "NEW: DOG PARK SURVIVAL", zoom=1.3)
    rect300("ad_rect_dollhouse", "run_dollhouse", (0.5, 0.6), "TINY TOY. BIG RUN.", "play free", zoom=1.1)
    rect300("ad_rect_lobby", "hub_row2", (0.5, 0.55), "EXPLORE THE TABLE", "3 maps • shop • pals", zoom=1.2)
    sky160("ad_sky_house", "run_house5", (0.42, 0.4), "RUN!", "dodge the kid", zoom=1.0)
    sky160("ad_sky_dog", "run_dogpark2", (0.5, 0.45), "FETCH?", "dog park survival", zoom=1.2)
    print("ADS_OK", sorted(os.listdir(OUT)))
