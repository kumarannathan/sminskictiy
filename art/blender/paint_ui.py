# Tintable candy UI surfaces painted in 2D (white-ish so ImageColor3 can tint them).
from PIL import Image, ImageDraw, ImageFilter, ImageChops
import os
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "game", "art")
SS = 4  # supersample

def rrect_mask(w, h, r, inset=0):
    m = Image.new("L", (w * SS, h * SS), 0)
    ImageDraw.Draw(m).rounded_rectangle((inset * SS, inset * SS, (w - inset) * SS - 1, (h - inset) * SS - 1), r * SS, fill=255)
    return m

def vgrad(w, h, top, bottom):
    g = Image.new("L", (1, h * SS))
    for y in range(h * SS):
        k = y / (h * SS - 1)
        g.putpixel((0, y), int(top + (bottom - top) * k))
    return g.resize((w * SS, h * SS))

def surface(w, h, r, top=255, bottom=200, gloss=0.55, gloss_h=0.44, rim=0.5, name="x", inner_min=170):
    body = rrect_mask(w, h, r)
    shade = vgrad(w, h, top, bottom)
    # inner shadow toward the bottom edge + light rim on the top edge
    inner = rrect_mask(w, h, r, inset=max(3, h * 0.06)).filter(ImageFilter.GaussianBlur(h * 0.06 * SS))
    shade = ImageChops.multiply(shade, inner.point(lambda v: inner_min + v * (255 - inner_min) // 255))
    rgb = Image.merge("RGB", (shade, shade, shade))
    img = Image.new("RGBA", body.size, (0, 0, 0, 0))
    img.paste(rgb, (0, 0), body)
    # glossy highlight band across the top
    gh = int(h * gloss_h)
    gm = rrect_mask(w, h, r, inset=max(4, h * 0.08)).crop((0, 0, w * SS, (gh + int(h * 0.08)) * SS))
    gl = Image.new("L", gm.size, 0)
    fade = vgrad(w, gh + int(h * 0.08), int(255 * gloss), 0).crop((0, 0, gm.size[0], gm.size[1]))
    gl = ImageChops.multiply(gm, fade)
    img = img.resize((w, h), Image.LANCZOS)
    img.save(os.path.join(OUT, name + ".png"))
    # separate untinted gloss overlay (same size, for a second ImageLabel on top)
    glossImg = Image.new("RGBA", body.size, (255, 255, 255, 0))
    band = Image.new("L", body.size, 0)
    band.paste(gl, (0, 0))
    glossImg.putalpha(band)
    glossImg.resize((w, h), Image.LANCZOS).save(os.path.join(OUT, name + "_gloss.png"))
    return img

surface(512, 160, 80, 255, 196, 0.6, 0.46, name="ui_pill")
surface(512, 512, 64, 255, 238, 0.35, 0.16, name="ui_card", inner_min=222)
surface(256, 256, 128, 255, 190, 0.6, 0.45, name="ui_disc")
surface(512, 160, 36, 255, 200, 0.55, 0.45, name="ui_key")  # squarer "physical key" button
print("PAINT_OK")
