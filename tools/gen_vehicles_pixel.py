#!/usr/bin/env python3
"""Generates assets/images/vehicles/vehicles_pixel.png: a clean pixel-art
vehicle sheet drawn for small sizes, replacing the chunky legacy art.

Layout: 6 paint colors x 8 orientations, 32x28 frames (1536x28 sheet).
Orientation index inside each color block:
  0: horizontal -> right   1: horizontal -> left
  2: vertical   -> up      3: vertical   -> down
  4: oblique down-right (grid E)   5: oblique down-left  (grid S)
  6: oblique up-left   (grid W)   7: oblique up-right   (grid N)
"""

from PIL import Image
import math

FRAME_W, FRAME_H = 32, 28
COLORS = 6
ORIENTS = 8

# 6 paints sampled in spirit from the legacy sheet
PAINTS = [
    ((70, 110, 200), (50, 80, 155), (120, 160, 230)),    # blue
    ((200, 60, 50), (150, 40, 35), (235, 105, 95)),      # red
    ((230, 190, 60), (180, 145, 40), (245, 215, 110)),   # yellow
    ((225, 225, 225), (175, 175, 180), (255, 255, 255)), # white
    ((70, 70, 78), (45, 45, 52), (110, 110, 120)),       # dark
    ((80, 170, 90), (55, 130, 65), (125, 205, 135)),     # green
]
GLASS = (60, 75, 105)
WHEEL = (30, 30, 34)


def base_car(paint):
    """Side view facing right, 18x10 canvas. Returns set of (x,y,rgba)."""
    body, dark, light = paint
    px = {}

    def put(x, y, c):
        px[(x, y)] = (c[0], c[1], c[2], 255)

    # wheels first (stick out below the body)
    for wx in (2, 3, 12, 13):
        put(wx, 7, WHEEL); put(wx, 8, WHEEL)
    # body slab rows 3..6, x 1..16 with slanted hood/trunk
    for y in range(3, 7):
        for x in range(1, 17):
            put(x, y, body)
    # hood slope: front tip lower
    put(16, 3, dark); put(16, 6, dark); put(15, 6, body)
    # cabin block rows 1..3, x 5..11 (roof + pillars)
    for y in range(1, 3):
        for x in range(5, 12):
            put(x, y, light if y == 1 else body)
    # windshield + rear window
    put(11, 2, GLASS); put(11, 3, GLASS)
    put(5, 2, GLASS)
    # roof highlight
    for x in range(6, 11):
        put(x, 1, light)
    # shadow line under the body
    for x in range(2, 16):
        put(x, 6, dark)
    return px


def render(canvas_px, art, ox, oy):
    for (x, y), c in art.items():
        canvas_px[(ox + x, oy + y)] = c


def rotated(art, angle_deg):
    """Rotate pixel art with 4x supersampling so diagonals stay solid."""
    cx = sum(x for x, y in art) / len(art)
    cy = sum(y for x, y in art) / len(art)
    a = math.radians(angle_deg)
    ca, sa = math.cos(a), math.sin(a)
    S = 4
    fine = {}
    for (x, y), c in art.items():
        for sy in range(S):
            for sx in range(S):
                fx = x - 0.5 + (sx + 0.5) / S
                fy = y - 0.5 + (sy + 0.5) / S
                rx = cx + (fx - cx) * ca - (fy - cy) * sa
                ry = cy + (fx - cx) * sa + (fy - cy) * ca
                fine[(round(rx * S) / S, round(ry * S) / S)] = c
    out = {}
    for (fx, fy), c in fine.items():
        out[(round(fx), round(fy))] = c
    return out


def mirrored(art):
    xs = [x for x, y in art]
    mx = (min(xs) + max(xs)) / 2
    return {(round(2 * mx - x), y): c for (x, y), c in art.items()}


def bounds(art):
    xs = [x for x, y in art]; ys = [y for x, y in art]
    return min(xs), min(ys), max(xs), max(ys)


def centered(art):
    x0, y0, x1, y1 = bounds(art)
    dx = (FRAME_W - 1 - x1 - x0) // 2 - x0 + x0  # shift so the blob is centred
    cx = (x0 + x1) / 2; cy = (y0 + y1) / 2
    return {(round(x - cx + FRAME_W / 2), round(y - cy + FRAME_H / 2)): c
            for (x, y), c in art.items()}


sheet = Image.new("RGBA", (FRAME_W * ORIENTS * COLORS, FRAME_H), (0, 0, 0, 0))
sp = sheet.load()
for ci in range(COLORS):
    base = base_car(PAINTS[ci])
    variants = [
        base,                                   # 0 H right
        mirrored(base),                         # 1 H left
        rotated(base, -90),                     # 2 V up
        rotated(base, 90),                      # 3 V down
        rotated(base, 26.57),                   # 4 oblique down-right (E)
        mirrored(rotated(base, 26.57)),         # 5 oblique down-left  (S)
        mirrored(rotated(base, -26.57)),        # 6 oblique up-left   (W)
        rotated(base, -26.57),                  # 7 oblique up-right  (N)
    ]
    for oi, art in enumerate(variants):
        render(sp, centered(art), (ci * ORIENTS + oi) * FRAME_W, 0)

sheet.save("assets/images/vehicles/vehicles_pixel.png")
print("sheet:", sheet.size)

# 4x preview of the first two color blocks for eyeballing
prev = sheet.crop((0, 0, FRAME_W * ORIENTS * 2, FRAME_H))
prev = prev.resize((prev.width * 4, prev.height * 4), Image.NEAREST)
prev.save("/tmp/vehicles_pixel_preview.png")
print("preview: /tmp/vehicles_pixel_preview.png")
