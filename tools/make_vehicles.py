#!/usr/bin/env python3
"""Generates the vehicle sprite sheet used by the traffic simulation.

The legacy Cytopia asset pack contains no driving vehicles, so Citopia draws
its own: small pixel-art cars projected with the same 2:1 isometric transform
as the map ((x - y), (x + y) / 2 - z), rendered at 4x and downscaled with
nearest-neighbor to stay crisp. The dark outline is computed by dilating the
whole silhouette so the car reads as one shape.

Sheet layout: 6 car colors x 4 directions, frames of 28x28 px.
Frame index = color_index * 4 + direction, with directions:
  0 = E (screen down-right)   1 = S (screen down-left)
  2 = W (screen up-left)      3 = N (screen up-right)
The car's ground center sits exactly at the frame center (14, 14).

Usage: python3 tools/make_vehicles.py  (run from the citopia/ directory)
License: GPL-3 (part of the Citopia project).
"""

from PIL import Image, ImageDraw

FRAME = 28          # frame size in final pixels
SS = 4              # supersampling factor
ANCHOR = (14, 14)   # ground center inside the frame

# car length / width / height (screen pixels at 1x)
LENGTH, WIDTH, HEIGHT = 12.0, 6.0, 3.2

# body base colors: red, blue, white, gray, black, taxi yellow
COLORS = [
    (198, 62, 52),
    (74, 116, 198),
    (224, 224, 218),
    (132, 136, 142),
    (56, 56, 62),
    (228, 178, 44),
]
WINDOW = (44, 56, 72)
OUTLINE = (26, 26, 32)

# direction -> (front unit vector, right unit vector) in world grid coords
DIRS = [
    ((1, 0), (0, 1)),    # E
    ((0, 1), (-1, 0)),   # S
    ((-1, 0), (0, -1)),  # W
    ((0, -1), (1, 0)),   # N
]


def project(x: float, y: float, z: float):
    """World grid coords -> screen coords (same 2:1 transform as the map)."""
    return (x - y, (x + y) * 0.5 - z)


def pts(corners):
    out = []
    for (x, y, z) in corners:
        sx, sy = project(x, y, z)
        out.append(((ANCHOR[0] + sx) * SS, (ANCHOR[1] + sy) * SS))
    return out


def shade(color, factor):
    return tuple(min(255, int(c * factor)) for c in color)


def draw_car(draw: ImageDraw.ImageDraw, color_index: int, direction: int) -> None:
    front, right = DIRS[direction]
    base = COLORS[color_index]

    def world(u, v, z):
        return (front[0] * u + right[0] * v, front[1] * u + right[1] * v, z)

    L, W, H = LENGTH, WIDTH, HEIGHT

    # vertical faces: only normals +x / +y face the camera
    def face_visible(normal):
        return normal in ((1, 0), (0, 1))

    # front face (normal = front vector)
    if face_visible(front):
        draw.polygon(pts([world(L, 0, 0), world(L, W, 0), world(L, W, H), world(L, 0, H)]),
                     fill=shade(base, 0.88))
    # right side face (normal = right vector)
    if face_visible(right):
        draw.polygon(pts([world(0, W, 0), world(L, W, 0), world(L, W, H), world(0, W, H)]),
                     fill=shade(base, 0.66))

    # top face
    draw.polygon(pts([world(0, 0, H), world(L, 0, H), world(L, W, H), world(0, W, H)]),
                 fill=shade(base, 1.22))

    # windshield: dark band across the front third of the roof
    draw.polygon(pts([world(L * 0.68, 0.7, H), world(L * 0.92, 0.7, H),
                      world(L * 0.92, W - 0.7, H), world(L * 0.68, W - 0.7, H)]),
                 fill=WINDOW)
    # side windows: dark strip along the top edge of the visible side
    if face_visible(right):
        draw.polygon(pts([world(L * 0.12, W - 0.05, H - 1.3), world(L * 0.62, W - 0.05, H - 1.3),
                          world(L * 0.62, W - 0.05, H), world(L * 0.12, W - 0.05, H)]),
                     fill=shade(WINDOW, 0.85))
    if face_visible(front):
        draw.polygon(pts([world(L - 0.05, 0.8, H - 1.3), world(L - 0.05, W - 0.8, H - 1.3),
                          world(L - 0.05, W - 0.8, H), world(L - 0.05, 0.8, H)]),
                     fill=shade(WINDOW, 0.85))


def outline_silhouette(body: Image.Image) -> Image.Image:
    """1px outline around the union of all drawn faces."""
    alpha = body.split()[3]
    dilated = alpha.point(lambda a: 255 if a > 10 else 0)
    # max filter dilates by 1 final pixel (SS sup pixels)
    dilated = dilated.filter(ImageFilter.MaxFilter(2 * SS + 1))
    outline_img = Image.new("RGBA", body.size, (0, 0, 0, 0))
    outline_px = outline_img.load()
    dil_px = dilated.load()
    a_px = alpha.load()
    for y in range(body.size[1]):
        for x in range(body.size[0]):
            if dil_px[x, y] and a_px[x, y] < 10:
                outline_px[x, y] = OUTLINE + (255,)
    return outline_img


from PIL import ImageFilter


def main() -> None:
    n_colors, n_dirs = len(COLORS), len(DIRS)
    sheet = Image.new("RGBA", (FRAME * n_colors * n_dirs, FRAME), (0, 0, 0, 0))
    for color_index in range(n_colors):
        for direction in range(n_dirs):
            canvas = Image.new("RGBA", (FRAME * SS, FRAME * SS), (0, 0, 0, 0))
            draw = ImageDraw.Draw(canvas)
            draw_car(draw, color_index, direction)
            canvas.alpha_composite(outline_silhouette(canvas))
            frame = canvas.resize((FRAME, FRAME), Image.NEAREST)
            sheet.paste(frame, ((color_index * n_dirs + direction) * FRAME, 0))
    out = "assets/images/vehicles/vehicles.png"
    sheet.save(out)
    print(f"wrote {out}: {sheet.size[0]}x{sheet.size[1]}, "
          f"{n_colors * n_dirs} frames of {FRAME}x{FRAME}")


if __name__ == "__main__":
    main()
