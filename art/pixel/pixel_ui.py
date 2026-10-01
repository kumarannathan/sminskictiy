#!/usr/bin/env python3
"""Pixel UI art for Sminski City -- nine-slices and icons, drawn as PIXELS.

WHY THIS IS NOT IN art/blender/. The old icons came from `art/blender/icons.py`,
which builds bevelled 3D objects, renders them at 256px and downscales. That is
the correct way to make glossy candy icons and the WRONG way to make pixel art:
rendering geometry and shrinking it produces exactly the soft mush that
`ResampleMode = Pixelated` exists to prevent. You cannot render your way to
pixel art -- you place pixels.

So this is 2D, authored at native resolution, one pixel per pixel, no filtering
anywhere in the pipeline. It is still "built from re-runnable code" as
`.claude/rules/pipeline.md` requires; the code is just Pillow instead of bpy.

NATIVE SIZES ARE SMALL ON PURPOSE. An icon is 16x16 and a button skin is 24x24.
Roblox scales them up with nearest-neighbour, so a 1px line in here is a crisp
4px line on screen at SliceScale 4 (`UI.T.border`). Authoring at 256 and
downscaling would throw away the grid that makes it read as pixel art at all.

    python3 art/pixel/pixel_ui.py            # everything -> art/pixel/out/
    python3 art/pixel/pixel_ui.py coin star  # just those
"""
import os, sys
from PIL import Image

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "out")

# ---------------------------------------------------------------------------
# PALETTE. Matches Config.lua's C table so the art and the code agree about
# what "mint" is. Lowercase = light value, uppercase = its dark pair, which is
# the same light/dark discipline the buttons use.
# ---------------------------------------------------------------------------
P = {
    ".": None,                      # transparent
    "K": (46, 51, 40, 255),         # ink
    "k": (86, 92, 74, 255),         # ink soft
    "W": (255, 253, 244, 255),      # highlight
    "w": (253, 246, 227, 255),      # paper
    "u": (239, 228, 200, 255),      # paper2
    "U": (223, 207, 168, 255),      # paper3
    "m": (143, 208, 122, 255), "M": (79, 143, 70, 255),      # mint
    "g": (245, 196, 78, 255),  "G": (184, 134, 42, 255),     # gold
    "r": (240, 112, 94, 255),  "R": (168, 63, 48, 255),      # coral
    "s": (111, 178, 232, 255), "S": (53, 113, 159, 255),     # sky
    "l": (183, 155, 232, 255), "L": (110, 85, 166, 255),     # lavender
    "p": (242, 168, 184, 255), "P": (196, 103, 124, 255),    # rose
    "n": (170, 120, 80, 255),  "N": (120, 82, 54, 255),      # brown
    "y": (176, 176, 168, 255), "Y": (118, 120, 112, 255),    # grey
}




def grid(rows, scale=1):
    """A list of equal-length strings -> an RGBA image, one char per pixel."""
    w, h = len(rows[0]), len(rows)
    for i, r in enumerate(rows):
        assert len(r) == w, f"row {i} is {len(r)} wide, expected {w}"
    img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    px = img.load()
    for y, row in enumerate(rows):
        for x, ch in enumerate(row):
            c = P[ch]
            if c:
                px[x, y] = c
    if scale > 1:
        img = img.resize((w * scale, h * scale), Image.NEAREST)
    return img


# ---------------------------------------------------------------------------
# NINE-SLICES.
#
# Built rather than hand-typed, because a panel is a rule (1px ink frame, 1px
# inside highlight along the top, flat fill) and a rule should not be retyped
# four times with four chances to get a corner wrong.
#
# WHITE FILL, TINTED AT RUNTIME. UI.skin sets ImageColor3 from the frame's
# BackgroundColor3, so the base has to be the lightest value or every tint
# comes out dark. The ink frame stays ink because it is a separate pass.
#
# NO GLOSS LAYER. The old art shipped a second untinted overlay to fake a
# specular sheen -- a 3D idea. The 1px highlight below replaces it, and
# Art.ui entries drop `gloss` entirely (UI.skin already treats it as optional).
# ---------------------------------------------------------------------------
def panel(size, radius, fill="W", frame="K", hi=None, inner="w"):
    n = size
    rows = []
    for y in range(n):
        row = ""
        for x in range(n):
            # distance from the nearest corner centre, for a pixel-exact round
            cx = radius - 1 if x < radius else (n - radius if x >= n - radius else x)
            cy = radius - 1 if y < radius else (n - radius if y >= n - radius else y)
            in_corner = (x < radius or x >= n - radius) and (y < radius or y >= n - radius)
            if in_corner:
                dx, dy = x - cx, y - cy
                d = (dx * dx + dy * dy) ** 0.5
                if d > radius - 0.5:
                    row += "."
                    continue
                edge = d > radius - 1.5
            else:
                edge = x == 0 or y == 0 or x == n - 1 or y == n - 1
            if edge:
                row += frame
            elif hi and y == 1 and radius <= x < n - radius:
                row += hi
            else:
                row += fill if y < n // 2 else inner
        row += ""
        rows.append(row)
    return rows


SLICES = {
    # name: (size, corner radius)  -- corner in SOURCE pixels
    "key":  (24, 6),    # the standard button
    "pill":  (24, 12),  # fully round ends
    "card": (32, 8),    # panels and modals
    "disc": (24, 12),   # round badges
}

# ---------------------------------------------------------------------------
# ICONS, 16x16. Every one reads at 16px because that is the size it is drawn
# at -- which is the entire argument for doing this in 2D.
# ---------------------------------------------------------------------------
I = {}

I["coin"] = [
    "................",
    ".....KKKKKK.....",
    "...KKggggggKK...",
    "..KgggWWgggggK..",
    ".KggWWggggggggK.",
    ".KgWggGGGGggggK.",
    "KggggGggggGgggGK",
    "KgggGggggggGggGK",
    "KgggGggggggGggGK",
    "KggggGggggGggggK",
    ".KgggGGGGGggggK.",
    ".KggggggggggggK.",
    "..KggggggggggK..",
    "...KKggggggKK...",
    ".....KKKKKK.....",
    "................",
]

I["star"] = [
    ".......KK.......",
    ".......KK.......",
    "......KggK......",
    "......KggK......",
    "..KKKKKggKKKKK..",
    "..KggggWggggggK.",
    "...KgggggggggK..",
    "....KgggggggK...",
    "....KgggggggK...",
    "...KggggKggggK..",
    "..KgggKK.KKgggK.",
    "..KggK.....KggK.",
    "..KgK.......KgK.",
    "..KK.........KK.",
    "................",
    "................",
]

I["house"] = [
    ".......KK.......",
    "......KrrK......",
    ".....KrrrrK.....",
    "....KrrrrrrK....",
    "...KrrrrrrrrK...",
    "..KrrrrrrrrrrK..",
    ".KrrrrrrrrrrrrK.",
    "KKKKKKKKKKKKKKKK",
    "..KwwwwwwwwwwK..",
    "..KwKKwwwKKwwK..",
    "..KwKsKwwKsKwK..",
    "..KwKKwwwKKwwK..",
    "..KwwwKKKwwwwK..",
    "..KwwwKnKwwwwK..",
    "..KKKKKKKKKKKK..",
    "................",
]

I["bag"] = [
    "................",
    "....KKK..KKK....",
    "...KnnK..KnnK...",
    "...KnK....KnK...",
    "..KKKKKKKKKKKK..",
    "..KggggggggggK..",
    "..KgWggggggggK..",
    "..KgggggggggggK.",
    "..KggggKKggggK..",
    "..KgggKGGKgggK..",
    "..KgggKGGKgggK..",
    "..KggggKKggggK..",
    "..KggggggggggK..",
    "..KGGGGGGGGGGK..",
    "..KKKKKKKKKKKK..",
    "................",
]

I["heart"] = [
    "................",
    "...KKK....KKK...",
    "..KrrrKKKKrrrK..",
    ".KrWrrrrrrrrrrK.",
    ".KrWrrrrrrrrrrK.",
    ".KrrrrrrrrrrrrK.",
    ".KrrrrrrrrrrrrK.",
    "..KrrrrrrrrrrK..",
    "..KRrrrrrrrrRK..",
    "...KRrrrrrrRK...",
    "....KRrrrrRK....",
    ".....KRrrRK.....",
    "......KRRK......",
    ".......KK.......",
    "................",
    "................",
]

I["pin"] = [
    "......KKKK......",
    "....KKrrrrKK....",
    "...KrrrrrrrrK...",
    "..KrrrWKKrrrrK..",
    "..KrrWKwwKrrrK..",
    "..KrrKwwwwKrrK..",
    "..KrrKwwwwKrrK..",
    "..KrrrKwwKrrrK..",
    "...KrrrKKrrrK...",
    "...KRrrrrrrRK...",
    "....KRrrrrRK....",
    ".....KRrrRK.....",
    "......KRRK......",
    ".......KK.......",
    "................",
    "................",
]

I["gear"] = [
    "....KK....KK....",
    "...KyyK..KyyK...",
    "...KyyKKKKyyK...",
    "..KKyyyyyyyyKK..",
    ".KyyyyyyyyyyyyK.",
    ".KyyyyKKKKyyyyK.",
    "KKyyyKKwwKKyyyKK",
    "KyyyyKwwwwKyyyyK",
    "KyyyyKwwwwKyyyyK",
    "KKyyyKKwwKKyyyKK",
    ".KyyyyKKKKyyyyK.",
    ".KyyyyyyyyyyyyK.",
    "..KKyyyyyyyyKK..",
    "...KyyKKKKyyK...",
    "...KyyK..KyyK...",
    "....KK....KK....",
]

I["chart"] = [
    "................",
    ".KK.............",
    ".KK.........KKK.",
    ".KK.........KmK.",
    ".KK.........KmK.",
    ".KK.....KKK.KmK.",
    ".KK.....KmK.KmK.",
    ".KK.KKK.KmK.KmK.",
    ".KK.KsK.KmK.KmK.",
    ".KK.KsK.KmK.KmK.",
    ".KK.KsK.KmK.KmK.",
    ".KK.KsK.KmK.KmK.",
    ".KKKKKKKKKKKKKK.",
    ".KKKKKKKKKKKKKK.",
    "................",
    "................",
]

I["clock"] = [
    ".....KKKKKK.....",
    "...KKwwwwwwKK...",
    "..KwwwwwwwwwwK..",
    ".KwwKwwwwwwKwwK.",
    ".KwwwwwwwwwwwwK.",
    "KwwwwwKKwwwwwwwK",
    "KwwwwwwKwwwwwwwK",
    "KwwKwwwKwwwKwwwK",
    "KwwwwwwKKKwwwwwK",
    "KwwwwwwwwwwwwwwK",
    ".KwwwwwwwwwwwwK.",
    ".KwwKwwwwwwKwwK.",
    "..KwwwwwwwwwwK..",
    "...KKwwwwwwKK...",
    ".....KKKKKK.....",
    "................",
]

I["play"] = [
    "................",
    "...KK...........",
    "...KmKK.........",
    "...KmmmKK.......",
    "...KmmmmmKK.....",
    "...KmmmmmmmKK...",
    "...KmmmmmmmmmK..",
    "...KmmmmmmmmmK..",
    "...KmmmmmmmmmK..",
    "...KmmmmmmmKK...",
    "...KmmmmmKK.....",
    "...KmmmKK.......",
    "...KMKK.........",
    "...KK...........",
    "................",
    "................",
]

I["crown"] = [
    "................",
    ".KK.........KK..",
    ".KgK...KK..KgK..",
    ".KggK..KgK.KggK.",
    ".KgggK.KgK.KgggK",
    ".KggggKKgKKggggK",
    ".KggWggggggggggK",
    ".KggWggggggggggK",
    ".KgggggggggggggK",
    ".KggKgggKgggKggK",
    ".KggKgggKgggKggK",
    ".KGGGGGGGGGGGGGK",
    ".KKKKKKKKKKKKKKK",
    "................",
    "................",
    "................",
]

I["lock"] = [
    "................",
    ".....KKKKK......",
    "....KyyyyyK.....",
    "...KyyKKKyyK....",
    "...KyK...KyK....",
    "...KyK...KyK....",
    "..KKKKKKKKKKK...",
    "..KgggggggggK...",
    "..KgWgggggggK...",
    "..KgggKKKgggK...",
    "..KgggKKKgggK...",
    "..KggggKKgggK...",
    "..KgggggggggK...",
    "..KGGGGGGGGGK...",
    "..KKKKKKKKKKK...",
    "................",
]

I["shield"] = [
    "..KKKKKKKKKKKK..",
    "..KssssssssssK..",
    "..KsWsssssssSK..",
    "..KsWsssssssSK..",
    "..KssssssssssK..",
    "..KssssssssssK..",
    "...KsssssssssK..",
    "...KssssssssK...",
    "....KsssssssK...",
    "....KssssssK....",
    ".....KsssssK....",
    "......KsssK.....",
    ".......KsK......",
    ".......KK.......",
    "................",
    "................",
]

I["trophy"] = [
    "................",
    "..KKKKKKKKKKKK..",
    "..KggggggggggK..",
    ".KKgWgggggggKK..",
    "KyKgWgggggggKyK.",
    "KyKggggggggggKyK",
    "KyKggggggggggKyK",
    ".KKggggggggggKK.",
    "..KGggggggggGK..",
    "...KGGggggGGK...",
    "....KGGGGGGK....",
    "......KggK......",
    ".....KGGGGK.....",
    "...KKKKKKKKKK...",
    "...KGGGGGGGGK...",
    "...KKKKKKKKKK...",
]

I["friends"] = [
    "................",
    "................",
    "...KK......KK...",
    "..KssK....KppK..",
    "..KsWK....KpWK..",
    "...KK......KK...",
    "..KKKK....KKKK..",
    ".KssssK..KppppK.",
    "KssssssKKppppppK",
    "KssssssKKppppppK",
    "KssssssKKppppppK",
    "KSSSSSSKKPPPPPPK",
    "KKKKKKKKKKKKKKKK",
    "................",
    "................",
    "................",
]

I["capsule"] = [
    "................",
    ".....KKKKKK.....",
    "...KKrrrrrrKK...",
    "..KrrrrrrrrrrK..",
    "..KrWrrrrrrrrK..",
    ".KrWrrrrrrrrrrK.",
    ".KrrrrrrrrrrrrK.",
    ".KrrrrrrrrrrrrK.",
    "KKKKKKKKKKKKKKKK",
    "KwwwwwwwwwwwwwwK",
    ".KwWwwwwwwwwwwK.",
    ".KwwwwwwwwwwwwK.",
    ".KwwwwwwwwwwwwK.",
    "..KwwwwwwwwwwK..",
    "...KKwwwwwwKK...",
    ".....KKKKKK.....",
]

I["shirt"] = [
    "................",
    "..KKK......KKK..",
    ".KsssKKKKKKsssK.",
    "KsssssssssssssK.",
    "KssssssssssssssK",
    "KsssKsssssKssssK",
    "KsssKssssssKsssK",
    ".KKKKssssssKKKK.",
    "...KssssssssK...",
    "...KsWsssssssK..",
    "...KssssssssK...",
    "...KssssssssK...",
    "...KssssssssK...",
    "...KSSSSSSSSK...",
    "...KKKKKKKKKK...",
    "................",
]

I["bolt"] = [
    "........KK......",
    ".......KgK......",
    "......KggK......",
    ".....KgggK......",
    "....KgggKK......",
    "...KgggKK.......",
    "..KgggKKKKKK....",
    "..KggggggggK....",
    "..KKKKKKgggK....",
    "......KgggKK....",
    ".....KgggK......",
    "....KgggK.......",
    "...KggKK........",
    "..KgKK..........",
    "..KK............",
    "................",
]

I["paw"] = [
    "................",
    "..KKK....KKK....",
    ".KnnnK..KnnnK...",
    ".KnnnK..KnnnK...",
    "..KKK....KKK....",
    "KKK..........KKK",
    "KnnK........KnnK",
    "KnnK..KKKK..KnnK",
    ".KKKKKnnnnKKKKK.",
    "..KnnnnnnnnnnK..",
    "..KnnnnnnnnnnK..",
    "..KnnnnnnnnnnK..",
    "...KNnnnnnnNK...",
    "....KNNNNNNK....",
    ".....KKKKKK.....",
    "................",
]

I["dog"] = [
    "................",
    ".KKK........KKK.",
    ".KNK........KNK.",
    ".KNKKKKKKKKKKNK.",
    ".KNnnnnnnnnnnNK.",
    ".KNnnnnnnnnnnNK.",
    ".KnnKKnnnnKKnnK.",
    ".KnnKKnnnnKKnnK.",
    ".KnnnnnnnnnnnnK.",
    ".KnnnnKKKKnnnnK.",
    "..KnnKwwwwKnnK..",
    "..KnnnKKKKnnnK..",
    "...KnnnnnnnnK...",
    "....KKKKKKKK....",
    "................",
    "................",
]

I["hourglass"] = [
    "..KKKKKKKKKKKK..",
    "..KyyyyyyyyyyK..",
    "..KKKKKKKKKKKK..",
    "...KwgggggggK...",
    "....KwgggggK....",
    ".....KwgggK.....",
    "......KwgK......",
    "......KgK.......",
    "......KgK.......",
    ".....KgggK......",
    "....KgggggK.....",
    "...KgggggggK....",
    "..KKKKKKKKKKKK..",
    "..KyyyyyyyyyyK..",
    "..KKKKKKKKKKKK..",
    "................",
]

I["magnet"] = [
    "................",
    "....KKKKKKKK....",
    "...KrrrrrrrrK...",
    "..KrrKKKKKKrrK..",
    "..KrrK....KrrK..",
    "..KrrK....KrrK..",
    "..KrrK....KrrK..",
    "..KrrK....KrrK..",
    "..KrrK....KrrK..",
    "..KrrK....KrrK..",
    "..KssK....KssK..",
    "..KssK....KssK..",
    "..KSSK....KSSK..",
    "..KKKK....KKKK..",
    "................",
    "................",
]

I["x2"] = [
    "................",
    "................",
    ".KK.K.....KKKK..",
    ".KlKlK...KlllllK",
    "..KlKK...KlK.KlK",
    "...KK....KK..KlK",
    "..KlKK......KlK.",
    ".KlKlK.....KlK..",
    ".KK.KK....KlK...",
    "..........KlK...",
    ".........KlKKKK.",
    ".........KlllllK",
    ".........KKKKKKK",
    "................",
    "................",
    "................",
]

ALIASES = {"disc": None}  # handled as a slice, not an icon


def main(only=None):
    os.makedirs(OUT, exist_ok=True)
    made = []

    for name, (size, radius) in SLICES.items():
        if only and name not in only:
            continue
        img = grid(panel(size, radius, hi="W"))
        p = os.path.join(OUT, f"ui_{name}.png")
        img.save(p)
        made.append((f"ui_{name}", img.size))

    for name, rows in I.items():
        if only and name not in only:
            continue
        img = grid(rows)
        p = os.path.join(OUT, f"icon_{name}.png")
        img.save(p)
        made.append((f"icon_{name}", img.size))

    for n, sz in made:
        print(f"  {n:22s} {sz[0]}x{sz[1]}")
    print(f"{len(made)} files -> {OUT}")
    missing = sorted(set(ICON_NAMES) - set(I))
    if missing:
        print(f"NOT YET DRAWN ({len(missing)}): {', '.join(missing)}")


# the names game/Art.lua asks for, so the script can report its own gaps
ICON_NAMES = ["bag", "bolt", "capsule", "chart", "clock", "coin", "crown", "dog",
              "friends", "gear", "heart", "hourglass", "house", "lock", "magnet",
              "paw", "pin", "play", "shield", "shirt", "star", "trophy", "x2"]

if __name__ == "__main__":
    main(set(sys.argv[1:]) or None)
