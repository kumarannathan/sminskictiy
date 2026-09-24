# Finish a thumbnail render: bloom, vignette, logo + tagline.
#   python3 thumb_post.py <raw.png> <out.png> <logoX 0..1> <logoW 0..1> "TAGLINE" [second line] [#color]
import sys, os
from PIL import Image, ImageFilter, ImageChops, ImageDraw, ImageFont, ImageEnhance

HERE = os.path.dirname(os.path.abspath(__file__))
LOGO = os.path.join(HERE, "..", "..", "game", "art", "logo.png")
FONT = "/System/Library/Fonts/Supplemental/Arial Rounded Bold.ttf"


def bloom(img, thresh=185, radius=28, amount=0.55):
    lum = img.convert("L").point(lambda v: 0 if v < thresh else int((v - thresh) * 255 / (255 - thresh)))
    glow = Image.composite(img, Image.new("RGB", img.size), lum).filter(ImageFilter.GaussianBlur(radius))
    glow = ImageEnhance.Brightness(glow).enhance(amount * 2)
    return ImageChops.screen(img, glow)


def vignette(img, strength=0.55, tint=(40, 20, 80)):
    w, h = img.size
    m = Image.new("L", (w, h), 0)
    d = ImageDraw.Draw(m)
    d.ellipse((-w * 0.18, -h * 0.25, w * 1.18, h * 1.25), fill=255)
    m = m.filter(ImageFilter.GaussianBlur(min(w, h) * 0.18))
    dark = Image.new("RGB", (w, h), tint)
    inv = m.point(lambda v: int((255 - v) * strength))
    return Image.composite(dark, img, inv)


def outlined_text(canvas, text, center, size, fill, outline=(40, 92, 28), ow=None, shadow=True):
    f = ImageFont.truetype(FONT, size)
    ow = ow or max(3, size // 9)
    d = ImageDraw.Draw(canvas)
    bbox = d.textbbox((0, 0), text, font=f, stroke_width=ow)
    w, h = bbox[2] - bbox[0], bbox[3] - bbox[1]
    x, y = center[0] - w // 2 - bbox[0], center[1] - h // 2 - bbox[1]
    if shadow:
        sh = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
        ImageDraw.Draw(sh).text((x, y + ow), text, font=f, fill=(20, 10, 40, 150), stroke_width=ow, stroke_fill=(20, 10, 40, 150))
        canvas.alpha_composite(sh.filter(ImageFilter.GaussianBlur(3)))
    d.text((x, y), text, font=f, fill=fill, stroke_width=ow, stroke_fill=outline)
    return h


def main(raw, out, logo_x=0.62, logo_w=0.38, tag="PLAY WITH FRIENDS!", tag2=None, tagcol="#d8ff7a"):
    img = Image.open(raw).convert("RGB")
    img = bloom(img)
    img = vignette(img)
    img = ImageEnhance.Color(img).enhance(1.12)
    canvas = img.convert("RGBA")
    W, H = canvas.size
    logo = Image.open(LOGO).convert("RGBA")
    lw = int(W * logo_w)
    logo = logo.resize((lw, int(logo.height * lw / logo.width)), Image.LANCZOS)
    lx, ly = int(W * logo_x - lw / 2), int(H * 0.035)
    canvas.alpha_composite(logo, (lx, ly))
    y = ly + logo.height + int(H * 0.035)
    if tag:
        c = tuple(int(tagcol.lstrip("#")[i:i + 2], 16) for i in (0, 2, 4)) + (255,)
        h = outlined_text(canvas, tag, (int(W * logo_x), y), int(H * 0.058), c)
        y += h + int(H * 0.03)
    if tag2:
        outlined_text(canvas, tag2, (int(W * logo_x), y), int(H * 0.038), (255, 255, 255, 255), outline=(60, 40, 110))
    canvas.convert("RGB").save(out, quality=95)
    print("POST_OK", out, canvas.size)


if __name__ == "__main__":
    a = sys.argv[1:]
    main(a[0], a[1], float(a[2]) if len(a) > 2 else 0.62, float(a[3]) if len(a) > 3 else 0.38,
         a[4] if len(a) > 4 else "PLAY WITH FRIENDS!", a[5] if len(a) > 5 and a[5] else None, a[6] if len(a) > 6 else "#d8ff7a")
