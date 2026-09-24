# 2D post-process for rendered UI art: rounded outline + darker "depth" layer
# underneath + soft drop shadow, then trim to content.
#   python3 outline.py in.png out.png [radius] [hexOutline] [hexDepth] [depthPx]
import sys
from PIL import Image, ImageFilter, ImageChops

def disk_dilate(alpha, r):
    # repeated small max-filters approximate a round dilation without squaring corners
    a = alpha
    steps = max(1, int(r // 2))
    for i in range(steps):
        a = a.filter(ImageFilter.MaxFilter(5 if i % 2 == 0 else 3))
    return a.filter(ImageFilter.GaussianBlur(1.2)).point(lambda v: 255 if v > 110 else int(v * 2.3))

def hexrgb(h):
    h = h.lstrip('#')
    return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))

def process(src, dst, r=16, outline="285c1c", depth="1b4212", depth_px=7, shadow=True, pad=None):
    img = Image.open(src).convert("RGBA")
    pad = pad or r + depth_px + 16
    W, H = img.size
    canvas = Image.new("RGBA", (W + pad * 2, H + pad * 2), (0, 0, 0, 0))
    base = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    base.paste(img, (pad, pad))
    alpha = base.split()[3]
    grown = disk_dilate(alpha, r)
    if shadow:
        sh = grown.filter(ImageFilter.GaussianBlur(8)).point(lambda v: int(v * 0.35))
        shadow_layer = Image.new("RGBA", canvas.size, (20, 10, 40, 0))
        shadow_layer.putalpha(ImageChops.offset(sh, 0, depth_px + 6))
        canvas = Image.alpha_composite(canvas, shadow_layer)
    dl = Image.new("RGBA", canvas.size, hexrgb(depth) + (0,))
    dl.putalpha(ImageChops.offset(grown, 0, depth_px))
    canvas = Image.alpha_composite(canvas, dl)
    ol = Image.new("RGBA", canvas.size, hexrgb(outline) + (0,))
    ol.putalpha(grown)
    canvas = Image.alpha_composite(canvas, ol)
    canvas = Image.alpha_composite(canvas, base)
    bbox = canvas.getbbox()
    if bbox:
        canvas = canvas.crop((max(0, bbox[0] - 4), max(0, bbox[1] - 4), min(canvas.width, bbox[2] + 4), min(canvas.height, bbox[3] + 4)))
    canvas.save(dst)
    return canvas.size

if __name__ == "__main__":
    a = sys.argv[1:]
    size = process(a[0], a[1], int(a[2]) if len(a) > 2 else 16, a[3] if len(a) > 3 else "285c1c", a[4] if len(a) > 4 else "1b4212", int(a[5]) if len(a) > 5 else 7)
    print("OUTLINED", size)
