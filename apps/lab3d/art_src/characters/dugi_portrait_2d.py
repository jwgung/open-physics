"""Dugi's dialogue portraits as a hand-drawn 2D storybook illustration (Phase 1 Task 4h).

    python3 apps/lab3d/art_src/characters/dugi_portrait_2d.py [--out apps/lab3d/assets/characters/portraits] [--size 512]

Writes dugi_talk.webp, dugi_smile.webp and dugi_point.webp (RGBA, size x size, lossless WebP) for
the dialogue box (scripts/shell/dialogue_box.gd). The look follows the user's reference pictures
(2026-10-23: the rabbit in pasted-2026-10-23T06-40-54.png and the storybook scene
1792701655210.png): a warm brown ink outline that is slightly uneven and varies in weight, flat
cream fills with soft watercolour shading and a paper grain, pink inner ears and blush, small dot
eyes with a highlight, a small open smile, the red scarf with its knot; plus the app's own additions
that match the 3D model: the gold monocle on the eye at the viewer's right with a thin chain, and
the pointer stick (red tip) in the pointing pose. Bust framing, like a visual-novel portrait.

  talk   open smile, head tilted a little
  smile  happy closed eyes, a calm "w" smile, ears a bit apart
  point  open smile, a paw raised holding the pointer stick up and out to the viewer's right (the
         portrait stands at the dialogue's left end, so the stick points into the box and the scene)

Pure Python + pycairo + Pillow; every wobble comes from a seeded random generator, so the output is
the same on every run (the files are deterministic).
"""
import math
import os
import random
import sys

import cairo
from PIL import Image, ImageChops, ImageFilter

SS = 2                      # supersampling: drawn at size * SS, then reduced
BASE = 512.0                # design units (the drawing is laid out on a 512 x 512 page)

INK = (0.40, 0.25, 0.17)    # warm brown ink
FUR = (1.0, 0.976, 0.94)
FUR_SHADE = (0.94, 0.86, 0.80)
PINK = (0.97, 0.70, 0.73)
PINK_DEEP = (0.93, 0.56, 0.62)
BLUSH = (1.0, 0.58, 0.62)
EYE = (0.20, 0.12, 0.09)
MOUTH = (0.45, 0.17, 0.14)
TONGUE = (1.0, 0.52, 0.56)
SCARF = (0.88, 0.29, 0.23)
SCARF_SHADE = (0.70, 0.19, 0.16)
GOLD = (0.89, 0.69, 0.29)
STICK = (0.55, 0.34, 0.20)
TIP = (0.88, 0.25, 0.22)


# --- path helpers ---------------------------------------------------------------------------------

def catmull(points, closed=True, steps=14):
    """Smooth curve through `points` (Catmull-Rom), sampled."""
    out = []
    n = len(points)
    rng = range(n) if closed else range(n - 1)
    for i in rng:
        p0 = points[(i - 1) % n] if closed or i > 0 else points[0]
        p1 = points[i]
        p2 = points[(i + 1) % n]
        p3 = points[(i + 2) % n] if closed or i + 2 < n else points[-1]
        for s in range(steps):
            t = s / steps
            t2, t3 = t * t, t * t * t
            out.append(tuple(0.5 * ((2 * p1[k]) + (-p0[k] + p2[k]) * t + (2 * p0[k] - 5 * p1[k] + 4 * p2[k] - p3[k]) * t2
                                    + (-p0[k] + 3 * p1[k] - 3 * p2[k] + p3[k]) * t3) for k in (0, 1)))
    if not closed:
        out.append(points[-1])
    return out


def ellipse(cx, cy, rx, ry, n=48, rot=0.0):
    c, s = math.cos(rot), math.sin(rot)
    pts = []
    for i in range(n):
        a = 2 * math.pi * i / n
        x, y = rx * math.cos(a), ry * math.sin(a)
        pts.append((cx + x * c - y * s, cy + x * s + y * c))
    return pts


class Wobble:
    """Smooth seeded noise along a stroke (a few sines with random phases)."""
    def __init__(self, rng, amp, waves=3):
        self.terms = [(rng.uniform(0.5, 3.5) * (k + 1), rng.uniform(0, 2 * math.pi), amp / (k + 1)) for k in range(waves)]

    def __call__(self, t):
        return sum(a * math.sin(f * 2 * math.pi * t + p) for f, p, a in self.terms)


def path(ctx, pts, closed=True):
    ctx.move_to(*pts[0])
    for p in pts[1:]:
        ctx.line_to(*p)
    if closed:
        ctx.close_path()


def ink(ctx, rng, pts, closed=True, w=4.2, var=0.45, jitter=0.9, taper=True, color=INK, alpha=1.0):
    """A hand-inked line: a ribbon whose width breathes along the stroke (and tapers at open ends),
    nudged off the exact curve by a smooth wobble."""
    n = len(pts)
    if n < 2:
        return
    width = Wobble(rng, var)
    offset = Wobble(rng, jitter, 2)
    left, right = [], []
    for i in range(n):
        a = pts[(i - 1) % n] if closed or i > 0 else pts[i]
        b = pts[(i + 1) % n] if closed or i < n - 1 else pts[i]
        dx, dy = b[0] - a[0], b[1] - a[1]
        ln = math.hypot(dx, dy) or 1.0
        nx, ny = -dy / ln, dx / ln
        t = i / (n - 1 if not closed else n)
        h = w * (1.0 + width(t)) * 0.5
        if taper and not closed:
            h *= min(1.0, 0.25 + 3.0 * min(t, 1.0 - t))
        o = offset(t)
        cx, cy = pts[i][0] + nx * o, pts[i][1] + ny * o
        left.append((cx + nx * h, cy + ny * h))
        right.append((cx - nx * h, cy - ny * h))
    ctx.set_source_rgba(*color, alpha)
    if closed:
        path(ctx, left)
        path(ctx, list(reversed(right)))
        ctx.set_fill_rule(cairo.FILL_RULE_EVEN_ODD)
        ctx.fill()
        ctx.set_fill_rule(cairo.FILL_RULE_WINDING)
    else:
        path(ctx, left + list(reversed(right)))
        ctx.fill()


def wash(ctx, rng, pts, base, shade, light_dir=(-0.5, -0.8), blobs=7, blob_alpha=0.05, rim=0.55):
    """Flat fill + a soft watercolour shading: darker toward the side away from the light, a few
    faint blotches, all clipped to the shape."""
    xs = [p[0] for p in pts]
    ys = [p[1] for p in pts]
    x0, x1, y0, y1 = min(xs), max(xs), min(ys), max(ys)
    cx, cy = (x0 + x1) / 2, (y0 + y1) / 2
    r = max(x1 - x0, y1 - y0) / 2
    ctx.save()
    path(ctx, pts)
    ctx.clip()
    ctx.set_source_rgb(*base)
    ctx.paint()
    # shade from the lit side to the far side
    lx, ly = light_dir
    g = cairo.LinearGradient(cx + lx * r, cy + ly * r, cx - lx * r, cy - ly * r)
    g.add_color_stop_rgba(0.0, *shade, 0.0)
    g.add_color_stop_rgba(0.55, *shade, 0.0)
    g.add_color_stop_rgba(1.0, *shade, rim)
    ctx.set_source(g)
    ctx.paint()
    for _ in range(blobs):
        bx = rng.uniform(x0, x1)
        by = rng.uniform(y0, y1)
        br = rng.uniform(0.2, 0.45) * r
        rg = cairo.RadialGradient(bx, by, 0, bx, by, br)
        rg.add_color_stop_rgba(0, *shade, blob_alpha)
        rg.add_color_stop_rgba(1, *shade, 0)
        ctx.set_source(rg)
        ctx.paint()
    ctx.restore()


def soft_spot(ctx, cx, cy, rx, ry, color, alpha):
    ctx.save()
    ctx.translate(cx, cy)
    ctx.scale(rx, ry)
    rg = cairo.RadialGradient(0, 0, 0, 0, 0, 1)
    rg.add_color_stop_rgba(0, *color, alpha)
    rg.add_color_stop_rgba(0.6, *color, alpha * 0.6)
    rg.add_color_stop_rgba(1, *color, 0)
    ctx.set_source(rg)
    ctx.arc(0, 0, 1, 0, 2 * math.pi)
    ctx.fill()
    ctx.restore()


def rotate_pts(pts, ang, ox, oy):
    c, s = math.cos(ang), math.sin(ang)
    return [(ox + (x - ox) * c - (y - oy) * s, oy + (x - ox) * s + (y - oy) * c) for x, y in pts]


# --- the character --------------------------------------------------------------------------------

def ear(cx, base_y, tip_y, half_w, lean):
    """An ear as a long rounded leaf from the head top (base) up to a round tip."""
    pts = [
        (cx - half_w * 0.55, base_y),
        (cx - half_w * 0.95 + lean * 0.35, base_y - (base_y - tip_y) * 0.45),
        (cx - half_w * 0.70 + lean * 0.85, tip_y + half_w * 0.55),
        (cx + lean, tip_y),
        (cx + half_w * 0.75 + lean * 0.85, tip_y + half_w * 0.6),
        (cx + half_w * 0.95 + lean * 0.35, base_y - (base_y - tip_y) * 0.45),
        (cx + half_w * 0.55, base_y),
    ]
    return catmull(pts, closed=True, steps=10)


def draw(expr, size, seed=7):
    S = int(size * SS)
    surf = cairo.ImageSurface(cairo.FORMAT_ARGB32, S, S)
    ctx = cairo.Context(surf)
    ctx.scale(S / BASE, S / BASE)
    # Bust framing: a little closer than the page layout (the ear tips may leave the frame).
    ctx.translate(256, 512)
    ctx.scale(1.12, 1.12)
    ctx.translate(-256, -512)
    ctx.set_line_join(cairo.LINE_JOIN_ROUND)
    rng = random.Random(seed)

    tilt = {"talk": -0.06, "smile": 0.07, "point": -0.04}[expr]
    neck = (256.0, 452.0)
    hx, hy, hrx, hry = 252.0, 336.0, 150.0, 120.0

    # Body / shoulders (behind the head), cut by the frame bottom.
    body = catmull([(104, 560), (112, 482), (166, 438), (256, 426), (346, 438), (400, 482), (408, 560)], closed=True, steps=10)
    wash(ctx, rng, body, FUR, FUR_SHADE, rim=0.45)
    ink(ctx, rng, catmull([(108, 560), (114, 482), (168, 440)], closed=False), closed=False, w=5.2, taper=False)
    ink(ctx, rng, catmull([(344, 440), (398, 482), (404, 560)], closed=False), closed=False, w=5.2, taper=False)

    # The pointing paw and stick (viewer's right), behind the scarf and the head's cheek.
    if expr == "point":
        arm = catmull([(338, 470), (360, 430), (392, 392), (418, 372), (436, 384), (424, 410), (392, 448), (372, 486)], closed=True, steps=8)
        wash(ctx, rng, arm, FUR, FUR_SHADE, light_dir=(-0.8, -0.4), rim=0.5)
        ink(ctx, rng, arm, w=4.0)
        # stick from the paw up and out to the right, red ball tip
        stick = [(410, 392), (440, 316), (458, 262)]
        ink(ctx, rng, catmull(stick, closed=False, steps=12), closed=False, w=8.0, var=0.12, jitter=0.4, taper=False, color=STICK)
        ink(ctx, rng, catmull(stick, closed=False, steps=12), closed=False, w=2.0, var=0.3, jitter=0.4, color=INK, alpha=0.55)
        tip = ellipse(460, 256, 13, 13, n=28)
        wash(ctx, rng, tip, TIP, (0.6, 0.12, 0.10), rim=0.5, blobs=2)
        ink(ctx, rng, tip, w=3.0)
        soft_spot(ctx, 456, 251, 4, 3, (1, 1, 1), 0.8)
        paw = ellipse(422, 384, 24, 22, n=32, rot=-0.5)
        wash(ctx, rng, paw, FUR, FUR_SHADE, rim=0.45)
        ink(ctx, rng, paw, w=4.0)

    # Scarf around the neck and the knot with two tails (front, at the viewer's left of centre).
    scarf = catmull([(156, 440), (200, 456), (256, 462), (316, 455), (360, 438), (366, 470), (318, 488), (256, 494), (196, 488), (150, 470)], closed=True, steps=8)
    wash(ctx, rng, scarf, SCARF, SCARF_SHADE, light_dir=(-0.3, -0.9), rim=0.55, blob_alpha=0.12)
    ink(ctx, rng, scarf, w=4.2)
    for k in range(3):   # a few soft folds
        x = 190 + 55 * k + rng.uniform(-6, 6)
        ink(ctx, rng, catmull([(x, 462), (x + 6, 476), (x + 2, 488)], closed=False, steps=6), closed=False, w=2.2, color=SCARF_SHADE, alpha=0.8)
    tails = [
        catmull([(220, 478), (206, 506), (196, 530), (218, 530), (232, 500)], closed=True, steps=6),
        catmull([(236, 480), (252, 508), (262, 530), (282, 524), (256, 486)], closed=True, steps=6),
    ]
    for t in tails:
        wash(ctx, rng, t, SCARF, SCARF_SHADE, rim=0.5, blobs=3)
        ink(ctx, rng, t, w=3.8)
    knot = ellipse(232, 474, 22, 18, n=28, rot=0.2)
    wash(ctx, rng, knot, SCARF, SCARF_SHADE, rim=0.6, blobs=2)
    ink(ctx, rng, knot, w=4.0)

    # Ears (behind the head): long, slightly spread, round tips; pink inside.
    spread = 1.25 if expr == "smile" else 1.0
    ears = [
        (ear(208, 252, 60, 46, -60 * spread), ear(209, 246, 88, 26, -55 * spread)),
        (ear(298, 250, 64, 46, 62 * spread), ear(297, 244, 92, 26, 57 * spread)),
    ]
    for outer, inner in ears:
        outer = rotate_pts(outer, tilt, *neck)
        inner = rotate_pts(inner, tilt, *neck)
        wash(ctx, rng, outer, FUR, FUR_SHADE, light_dir=(-0.7, -0.3), rim=0.5, blobs=3)
        wash(ctx, rng, inner, PINK, PINK_DEEP, light_dir=(0, -1), rim=0.65, blobs=3, blob_alpha=0.18)
        ink(ctx, rng, inner, w=2.2, var=0.5, color=(0.78, 0.42, 0.46), alpha=0.75)
        ink(ctx, rng, outer, w=5.6)

    # Head: a round, slightly wider-than-tall face.
    head_pts = []
    for k in range(64):
        a = 2 * math.pi * k / 64
        c, sn = math.cos(a), math.sin(a)
        e = 2.0 / 2.25   # a soft superellipse: round, a little fuller than an ellipse
        x = math.copysign(abs(c) ** e, c) * hrx * (1.0 + 0.05 * max(0.0, sn))   # fuller cheeks below
        y = math.copysign(abs(sn) ** e, sn) * hry * (0.94 if sn < 0 else 1.0)
        head_pts.append((hx + x, hy + y))
    head = rotate_pts(head_pts, tilt, *neck)
    wash(ctx, rng, head, FUR, FUR_SHADE, light_dir=(-0.55, -0.85), rim=0.5, blobs=8, blob_alpha=0.07)

    # Face features in the head's tilted frame.
    ctx.save()
    ctx.translate(*neck)
    ctx.rotate(tilt)
    ctx.translate(-neck[0], -neck[1])
    ex_l, ex_r, ey = hx - 60, hx + 56, hy + 14
    soft_spot(ctx, ex_l - 20, ey + 40, 32, 20, BLUSH, 0.7)
    soft_spot(ctx, ex_r + 24, ey + 40, 32, 20, BLUSH, 0.7)
    if expr == "smile":
        for x in (ex_l, ex_r):   # happy closed eyes: little arches
            ink(ctx, rng, catmull([(x - 13, ey + 4), (x, ey - 9), (x + 13, ey + 4)], closed=False, steps=8), closed=False, w=5.0, var=0.2)
    else:
        for x in (ex_l, ex_r):
            e = ellipse(x, ey, 15, 18, n=28)
            ctx.set_source_rgb(*EYE)
            path(ctx, e)
            ctx.fill()
            soft_spot(ctx, x - 5, ey - 7, 6.0, 6.0, (1, 1, 1), 1.0)
            soft_spot(ctx, x + 4, ey + 5, 2.0, 2.0, (1, 1, 1), 0.8)
    # nose
    nose = catmull([(hx - 9, ey + 26), (hx + 9, ey + 26), (hx, ey + 37)], closed=True, steps=6)
    ctx.set_source_rgb(*PINK_DEEP)
    path(ctx, nose)
    ctx.fill()
    ink(ctx, rng, nose, w=1.8, var=0.2, alpha=0.7)
    if expr == "smile":
        ink(ctx, rng, catmull([(hx - 22, ey + 44), (hx - 11, ey + 53), (hx, ey + 44), (hx + 11, ey + 53), (hx + 22, ey + 44)], closed=False, steps=6),
            closed=False, w=3.4, var=0.2)
    else:
        mouth = catmull([(hx - 22, ey + 44), (hx, ey + 50), (hx + 22, ey + 44), (hx + 14, ey + 66), (hx, ey + 72), (hx - 14, ey + 66)], closed=True, steps=8)
        ctx.set_source_rgb(*MOUTH)
        path(ctx, mouth)
        ctx.fill()
        ctx.save()
        path(ctx, mouth)
        ctx.clip()
        soft_spot(ctx, hx, ey + 72, 15, 11, TONGUE, 1.0)
        ctx.set_source_rgb(1, 1, 1)
        ctx.rectangle(hx - 8, ey + 45, 7, 8)
        ctx.rectangle(hx + 1, ey + 45, 7, 8)
        ctx.fill()
        ctx.restore()
        ink(ctx, rng, mouth, w=3.0, var=0.3)
    # monocle on the eye at the viewer's right, with a thin chain to the scarf
    if True:
        mono = ellipse(ex_r, ey, 27, 27, n=40)
        ctx.save()
        path(ctx, mono)
        ctx.set_source_rgba(1, 1, 1, 0.16)
        ctx.fill()
        ctx.restore()
        ink(ctx, rng, mono, w=7.5, var=0.1, jitter=0.3, color=GOLD)
        ink(ctx, rng, mono, w=1.6, var=0.3, jitter=0.3, color=INK, alpha=0.85)
        ink(ctx, rng, ellipse(ex_r, ey, 22, 22, n=40), w=1.4, var=0.3, jitter=0.3, color=INK, alpha=0.6)
        chain = catmull([(ex_r + 20, ey + 18), (ex_r + 34, ey + 58), (ex_r + 22, ey + 92), (ex_r + 4, ey + 112)], closed=False, steps=10)
        for i, p in enumerate(chain):
            if i % 2 == 0:
                soft_spot(ctx, p[0], p[1], 2.6, 2.6, GOLD, 1.0)
    ctx.restore()

    ink(ctx, rng, head, w=6.2)

    # Paper grain over the drawing (multiply, inside the drawing only).
    surf.flush()
    img = Image.frombuffer("RGBa", (S, S), bytes(surf.get_data()), "raw", "BGRa", 0, 1).convert("RGBA")
    grain = paper(S, seed)
    rgb = ImageChops.multiply(img.convert("RGB"), grain)
    out = Image.merge("RGBA", (*rgb.split(), img.getchannel("A")))
    return out.resize((size, size), Image.LANCZOS)


def paper(S, seed):
    """A soft paper grain: two layers of seeded value noise, 0.93-1.0."""
    rng = random.Random(seed * 31 + 5)
    layers = []
    for cells, lo in ((24, 0.975), (128, 0.985)):
        small = Image.new("L", (cells, cells))
        small.putdata([int(255 * rng.uniform(lo, 1.0)) for _ in range(cells * cells)])
        layers.append(small.resize((S, S), Image.BICUBIC).filter(ImageFilter.GaussianBlur(1)))
    g = ImageChops.multiply(layers[0], layers[1])
    return Image.merge("RGB", (g, g, g))


def main():
    argv = sys.argv[1:]
    out_dir = "apps/lab3d/assets/characters/portraits"
    size = 512
    for i, a in enumerate(argv):
        if a == "--out":
            out_dir = argv[i + 1]
        elif a == "--size":
            size = int(argv[i + 1])
    os.makedirs(out_dir, exist_ok=True)
    for k, expr in enumerate(("talk", "smile", "point")):
        img = draw(expr, size, seed=11 + k)
        p = os.path.join(out_dir, "dugi_%s.webp" % expr)
        img.save(p, "WEBP", lossless=True, quality=100, method=6, exact=True)
        print("PORTRAIT", p)


if __name__ == "__main__":
    main()
