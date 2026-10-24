"""Dugi's dialogue portraits as a clean 2D storybook illustration (Phase 1 Task 4h).

    python3 apps/lab3d/art_src/characters/dugi_portrait_2d.py [--out apps/lab3d/assets/characters/portraits] [--size 512]

Writes dugi_talk.webp, dugi_smile.webp and dugi_point.webp (RGBA, size x size, lossless WebP) for
the dialogue box (scripts/shell/dialogue_box.gd). Drawn after the user's reference pictures
(pasted-2026-10-23T06-40-54.png, the rabbit in 1792701655210.png; 2026-10-24 user: "잉크 선이 너무
별로임. 원본에 가깝게"): clean, smooth, anti-aliased warm reddish-brown lines of nearly uniform weight
(the outer silhouette a little heavier than the inner lines), flat cream fills with only a very soft
shade along the edges, long ears gently curved and splayed outward with a soft pink inner ear, a
round head about 1.15 : 1, small black dot eyes with one white highlight, a small nose, an open smile
with a tongue, soft round pink blush, a red scarf with a knot. Our additions match the 3D model: the
gold monocle on the eye at the viewer's right with a thin chain, and the pointer stick (red tip) in
the pointing pose, in the same line style.

  talk   open smile
  smile  happy closed eyes and a small "w" mouth, ears a little more apart
  point  open smile, a paw raised at the viewer's right holding the stick up toward the words

Every shape is a smooth closed Bezier curve (Catmull-Rom points turned into cubic segments) filled
and stroked by cairo, supersampled 2x and reduced; nothing is random, so the files are the same on
every run.
"""
import math
import os
import sys

import cairo
from PIL import Image

SS = 2
BASE = 512.0

LINE = (0.47, 0.24, 0.17)           # warm reddish brown
LINE_SOFT = (0.66, 0.36, 0.33)      # inner-ear outline
FUR = (1.0, 0.978, 0.945)
FUR_EDGE = (0.95, 0.88, 0.82)       # the soft shade along the edges
EAR_IN = (0.97, 0.69, 0.66)
EAR_IN_DEEP = (0.93, 0.57, 0.56)
BLUSH = (0.98, 0.62, 0.62)
EYE = (0.13, 0.08, 0.06)
MOUTH = (0.55, 0.20, 0.17)
TONGUE = (0.98, 0.52, 0.52)
SCARF = (0.86, 0.27, 0.22)
SCARF_EDGE = (0.70, 0.18, 0.15)
GOLD = (0.90, 0.70, 0.30)
STICK = (0.60, 0.38, 0.24)
TIP = (0.88, 0.25, 0.22)

OUTER_W = 5.0                       # silhouette line (design px)
INNER_W = 3.4                       # lines inside the silhouette


def smooth(ctx, pts, closed=True):
    """A smooth Bezier path through `pts` (Catmull-Rom tangents)."""
    n = len(pts)
    ctx.move_to(*pts[0])
    last = n if closed else n - 1
    for i in range(last):
        p0 = pts[(i - 1) % n] if closed or i > 0 else pts[i]
        p1 = pts[i]
        p2 = pts[(i + 1) % n]
        p3 = pts[(i + 2) % n] if closed or i + 2 < n else pts[(i + 1) % n]
        c1 = (p1[0] + (p2[0] - p0[0]) / 6.0, p1[1] + (p2[1] - p0[1]) / 6.0)
        c2 = (p2[0] - (p3[0] - p1[0]) / 6.0, p2[1] - (p3[1] - p1[1]) / 6.0)
        ctx.curve_to(*c1, *c2, *p2)
    if closed:
        ctx.close_path()


def ellipse_pts(cx, cy, rx, ry, n=12, rot=0.0):
    c, s = math.cos(rot), math.sin(rot)
    out = []
    for i in range(n):
        a = 2 * math.pi * i / n
        x, y = rx * math.cos(a), ry * math.sin(a)
        out.append((cx + x * c - y * s, cy + x * s + y * c))
    return out


def shape(ctx, pts, fill, line_w=INNER_W, line=LINE, edge=FUR_EDGE, edge_w=22.0, edge_a=0.55, light=(-0.4, -0.9)):
    """Flat fill, a very soft shade inside the edge (stronger away from the light), then the line."""
    smooth(ctx, pts)
    ctx.set_source_rgb(*fill)
    ctx.fill()
    if edge is not None:
        xs = [p[0] for p in pts]
        ys = [p[1] for p in pts]
        cx, cy = (min(xs) + max(xs)) / 2, (min(ys) + max(ys)) / 2
        r = max(max(xs) - min(xs), max(ys) - min(ys)) / 2
        steps = 6
        g = cairo.LinearGradient(cx + light[0] * r, cy + light[1] * r, cx - light[0] * r, cy - light[1] * r)
        g.add_color_stop_rgba(0.0, *edge, edge_a * 0.15 / steps)
        g.add_color_stop_rgba(1.0, *edge, edge_a / steps)
        ctx.save()
        smooth(ctx, pts)
        ctx.clip()
        for k in range(steps):   # a soft band inside the edge: stacked faint strokes, widest first
            smooth(ctx, pts)
            ctx.set_line_width(edge_w * 2.0 * (1.0 - k / steps))
            ctx.set_source(g)
            ctx.stroke()
        ctx.restore()
    smooth(ctx, pts)
    if line_w > 0:
        ctx.set_source_rgb(*line)
        ctx.set_line_width(line_w)
        ctx.stroke()
    else:
        ctx.new_path()


def stroke_line(ctx, pts, w, color=LINE, closed=False):
    smooth(ctx, pts, closed)
    ctx.set_source_rgb(*color)
    ctx.set_line_width(w)
    ctx.stroke()


def soft_dot(ctx, cx, cy, rx, ry, color, alpha):
    ctx.save()
    ctx.translate(cx, cy)
    ctx.scale(rx, ry)
    g = cairo.RadialGradient(0, 0, 0, 0, 0, 1)
    g.add_color_stop_rgba(0, *color, alpha)
    g.add_color_stop_rgba(0.55, *color, alpha * 0.8)
    g.add_color_stop_rgba(1, *color, 0)
    ctx.set_source(g)
    ctx.arc(0, 0, 1, 0, 2 * math.pi)
    ctx.fill()
    ctx.restore()


def rot(pts, ang, ox, oy):
    c, s = math.cos(ang), math.sin(ang)
    return [(ox + (x - ox) * c - (y - oy) * s, oy + (x - ox) * s + (y - oy) * c) for x, y in pts]


def ear_pts(root, length, half_w, tilt, bend):
    """A long, flat, round-tipped ear from `root` (bottom centre), turned by `tilt` (rad, + = to the
    viewer's right) and bowing sideways by `bend` (px, at the middle)."""
    x0, y0 = root
    prof = [(-0.70, 0.00), (-0.98, -0.22), (-1.00, -0.50), (-0.86, -0.78), (-0.50, -0.95), (0.00, -1.00),
            (0.50, -0.95), (0.86, -0.78), (1.00, -0.50), (0.98, -0.22), (0.70, 0.00)]
    pts = []
    for u, v in prof:
        t = -v                                   # 0 at the root, 1 at the tip
        bow = bend * math.sin(math.pi * min(1.0, t * 1.1))
        pts.append((x0 + u * half_w + bow, y0 + v * length))
    return rot(pts, tilt, x0, y0)


def draw(expr, size):
    S = int(size * SS)
    surf = cairo.ImageSurface(cairo.FORMAT_ARGB32, S, S)
    ctx = cairo.Context(surf)
    ctx.scale(S / BASE, S / BASE)
    ctx.translate(256, 512)   # bust framing: a little closer than the page layout
    ctx.scale(1.08, 1.08)
    ctx.translate(-256, -512)
    ctx.set_line_join(cairo.LINE_JOIN_ROUND)
    ctx.set_line_cap(cairo.LINE_CAP_ROUND)
    ctx.set_antialias(cairo.ANTIALIAS_BEST)

    hx, hy, hrx, hry = 256.0, 330.0, 130.0, 113.0   # head 1.15 : 1

    # Shoulders (cut by the frame).
    body = [(150, 560), (156, 486), (196, 446), (256, 436), (316, 446), (356, 486), (362, 560)]
    shape(ctx, body, FUR, OUTER_W)

    # The pointing arm (behind the scarf), paw and stick.
    if expr == "point":
        arm = [(318, 470), (346, 440), (376, 404), (398, 384), (418, 394), (410, 418), (384, 452), (360, 488), (330, 494)]
        shape(ctx, arm, FUR, OUTER_W, light=(-0.9, -0.3))
        stick = [(394, 386), (418, 328), (440, 272)]
        stroke_line(ctx, stick, 9.5, LINE)
        stroke_line(ctx, stick, 5.5, STICK)
        shape(ctx, ellipse_pts(441, 268, 12, 12), TIP, INNER_W, edge=(0.6, 0.12, 0.1), edge_w=6, edge_a=0.6)
        soft_dot(ctx, 437, 264, 3.5, 3.0, (1, 1, 1), 0.85)
        shape(ctx, ellipse_pts(402, 386, 21, 19, rot=-0.5), FUR, INNER_W, light=(-0.6, -0.8))

    # Scarf: a band around the neck, a knot at the viewer's left, two short tails.
    scarf = [(160, 436), (206, 452), (256, 458), (306, 452), (352, 436), (356, 458), (308, 476), (256, 482), (204, 476), (156, 458)]
    shape(ctx, scarf, SCARF, INNER_W, edge=SCARF_EDGE, edge_w=10, edge_a=0.5)
    for x in (226, 286, 330):   # simple folds
        stroke_line(ctx, [(x, 458), (x + 4, 470)], 2.2, SCARF_EDGE)
    for tail in ([(184, 470), (172, 498), (166, 520), (188, 518), (198, 486)], [(200, 472), (214, 498), (222, 520), (242, 512), (220, 474)]):
        shape(ctx, tail, SCARF, INNER_W, edge=SCARF_EDGE, edge_w=8, edge_a=0.5)
    shape(ctx, ellipse_pts(198, 462, 19, 15, rot=0.3), SCARF, INNER_W, edge=SCARF_EDGE, edge_w=8, edge_a=0.6)

    # Ears: long and splayed, the viewer's left one nearly upright, the right one leaning and bowing out.
    splay = 1.25 if expr == "smile" else 1.0
    for root, length, half_w, tilt, bend in (((214, 238), 190, 43, -0.18 * splay, -16), ((296, 234), 184, 43, 0.34 * splay, 26)):
        outer = ear_pts(root, length, half_w, tilt, bend)
        inner = ear_pts((root[0], root[1] - 14), length * 0.80, half_w * 0.56, tilt, bend * 0.85)
        shape(ctx, outer, FUR, OUTER_W, light=(-0.8, -0.4), edge_w=14)
        smooth(ctx, inner)
        g = cairo.LinearGradient(root[0], root[1] - 12, root[0] + math.sin(tilt) * length, root[1] - math.cos(tilt) * length)
        g.add_color_stop_rgb(0.0, *EAR_IN_DEEP)
        g.add_color_stop_rgb(0.45, *EAR_IN)
        g.add_color_stop_rgb(1.0, *EAR_IN)
        ctx.set_source(g)
        ctx.fill_preserve()
        ctx.set_source_rgb(*LINE_SOFT)
        ctx.set_line_width(2.2)
        ctx.stroke()

    # Head: round, a little wider than tall, fuller at the cheeks.
    head = []
    for k in range(16):
        a = 2 * math.pi * k / 16
        c, s = math.cos(a), math.sin(a)
        rx = hrx * (1.0 + 0.04 * max(0.0, s))
        head.append((hx + rx * c, hy + hry * s * (0.96 if s < 0 else 1.0)))
    shape(ctx, head, FUR, OUTER_W, edge_w=26, edge_a=0.6)

    # Face.
    ex_l, ex_r, ey = hx - 58, hx + 58, hy + 18
    soft_dot(ctx, ex_l - 14, ey + 32, 27, 17, BLUSH, 0.85)
    soft_dot(ctx, ex_r + 14, ey + 32, 27, 17, BLUSH, 0.85)
    if expr == "smile":
        for x in (ex_l, ex_r):
            stroke_line(ctx, [(x - 11, ey + 3), (x, ey - 7), (x + 11, ey + 3)], 4.0)
    else:
        for x in (ex_l, ex_r):
            smooth(ctx, ellipse_pts(x, ey, 11.5, 13.5))
            ctx.set_source_rgb(*EYE)
            ctx.fill()
            soft_dot(ctx, x - 3.5, ey - 5, 4.2, 4.2, (1, 1, 1), 1.0)
    # nose: a small rounded triangle and the short line down to the mouth
    smooth(ctx, [(hx - 7, ey + 16), (hx + 7, ey + 16), (hx, ey + 23)])
    ctx.set_source_rgb(*LINE)
    ctx.fill()
    stroke_line(ctx, [(hx, ey + 22), (hx, ey + 28)], 2.6)
    if expr == "smile":
        stroke_line(ctx, [(hx - 16, ey + 27), (hx - 8, ey + 33), (hx, ey + 28), (hx + 8, ey + 33), (hx + 16, ey + 27)], INNER_W)
    else:
        mouth = [(hx - 15, ey + 29), (hx, ey + 31), (hx + 15, ey + 29), (hx + 10, ey + 44), (hx, ey + 48), (hx - 10, ey + 44)]
        smooth(ctx, mouth)
        ctx.set_source_rgb(*MOUTH)
        ctx.fill_preserve()
        ctx.save()
        ctx.clip()
        soft_dot(ctx, hx, ey + 47, 11, 9, TONGUE, 1.0)
        ctx.restore()
        ctx.new_path()
        smooth(ctx, mouth)
        ctx.set_source_rgb(*LINE)
        ctx.set_line_width(2.8)
        ctx.stroke()
    # monocle on the eye at the viewer's right, a thin chain down to the scarf
    ring = ellipse_pts(ex_r, ey, 19, 19, n=16)
    smooth(ctx, ring)
    ctx.set_source_rgba(1, 1, 1, 0.18)
    ctx.fill_preserve()
    ctx.set_source_rgb(*LINE)
    ctx.set_line_width(7.6)
    ctx.stroke_preserve()
    ctx.set_source_rgb(*GOLD)
    ctx.set_line_width(4.2)
    ctx.stroke()
    chain = [(ex_r + 14, ey + 14), (ex_r + 24, ey + 50), (ex_r + 14, ey + 84), (ex_r - 2, ey + 104)]
    smooth(ctx, chain, closed=False)
    ctx.set_source_rgb(*GOLD)
    ctx.set_line_width(2.4)
    ctx.set_dash([2.5, 4.0])
    ctx.stroke()
    ctx.set_dash([])

    surf.flush()
    img = Image.frombuffer("RGBa", (S, S), bytes(surf.get_data()), "raw", "BGRa", 0, 1).convert("RGBA")
    return img.resize((size, size), Image.LANCZOS)


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
    for expr in ("talk", "smile", "point"):
        p = os.path.join(out_dir, "dugi_%s.webp" % expr)
        draw(expr, size).save(p, "WEBP", lossless=True, quality=100, method=6, exact=True)
        print("PORTRAIT", p)


if __name__ == "__main__":
    main()
