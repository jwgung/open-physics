"""Dugi (두기두기) — the science rabbit who explains the experiments, generated entirely in Blender Python.

Run (headless):
    blender -b --factory-startup -P apps/lab3d/art_src/characters/dugi.py -- \
        [--out apps/lab3d/assets/characters/dugi.glb] [--monocle on|off] [--mouth open|calm] [--pointer on|off]

A creamy white chibi rabbit from the same storybook as the bread cat (2026-10-23 user reference
1792701655210.png): a round head a little wider than the small bean body, long wide ears (pink
inside, round tips, gently spread), small dark bean eyes with one highlight dot, pink blush and
nose, a small open smile with a tongue and two front teeth, a red scarf with a knot, short stubby
arms with the paws on the tummy; a monocle on the eye at the viewer's right (2026-10-23 user decision, like the
reference dog's) for the know-it-all scientist: the rim drawn on the face, a thin gold chain mesh down
to the scarf (optional). Same style and conventions as bread_cat.py,
whose generic helpers (painting SDFs, bmesh sphere / tube builders) this file imports; geometry, UVs
and the single texture atlas are produced here, nothing depends on a hand-made .blend. Other scripts
may `import` it and call `build()` / `pose_point()` (the preview and duo renders do).

Conventions:
- Units are metres. Height ~1.65 m including the ears (head top ~1.13 m). Origin = between the feet
  on the ground.
- Blender: +Z up, Dugi faces -Y; glTF/Godot: +Y up, faces +Z (MODEL_FRONT), left side = +X.
- Node tree (no armature; animate by rotating nodes, each origin is its pivot):
    Dugi                    (empty, origin on the ground between the feet)
      Body                  (mesh: body, feet, tail puff, scarf; pivot on the ground -> lean / bob)
        Head                (mesh incl. the monocle chain, pivot at the neck -> nod / tilt)
          EarL / EarR       (mesh, pivot at the ear root -> perk up / flop / wiggle)
        ArmL / ArmR         (one-segment arm mesh incl. the paw, pivot at the shoulder; L = Dugi's left = +X)
          HandL / HandR     (empty at the paw tip: grip point)
          Pointer           (ArmR only, optional: stick mesh, pivot in the paw -> hide when not pointing)
            PointerTip      (empty at the stick's red tip)
- Rest pose (arm variant A, 2026-10-24 user decision) = the arms attach at the body's sides right
  under the head and hang down along the sides, paws by the hips. To point, swing ArmR about the
  shoulder so PointerTip aims at the target: `pose_point()` below does exactly that on the Blender objects.
- Budget (SM-P200 low): 7 meshes, 1 material, 1 texture (1024 px), < 6000 triangles (5,626): the
  segments go to the silhouette (head ring 40 x 24, ears, paws), hidden parts stay coarse (head
  below -62 deg, body underside, tail puff).
- Outline mesh contract (same as bread_cat.py): closed shells, outward faces, smooth shading only,
  so every glTF vertex at one position has the same NORMAL and an inverted hull grown along NORMAL
  (VERTEX += NORMAL * width, cull_front) has no cracks along the UV seams.
"""

import math
import os
import sys

import bmesh
import bpy
import numpy as np
from mathutils import Matrix, Quaternion, Vector

sys.dont_write_bytecode = True
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import bread_cat as bc  # noqa: E402  (generic helpers only; no cat geometry is built)
from bread_cat import (add_face, bezier, blend, build_sphere, build_tube, hexc, new_bm, paint_volume,  # noqa: E402
                       sd_ellipse, sd_segment, smooth_fill, sph_dir)

TEX = 1024
PAD = 3

P = dict(
    # storybook pastel (2026-10-23 user reference 1792701655210.png): creamy white fur, salmon-pink ears
    fur="#fdf6ee", fur_shade="#efe4d8", white="#fffaf3", cream="#fbe9d3", pink="#f7a9b2", pink_deep="#f08f9c",
    blush="#ff9aa6", eye="#2a1a14", mouth="#6b3424", tongue="#ff7f8c", tooth="#ffffff",
    scarf="#e2493b", scarf_dark="#b9342c", frame="#7a4a2e", gold="#e3b04b",
)

# Atlas layout (pixels, origin bottom-left like Blender UVs)
R_HEAD = (0, 512, 1024, 1024)
R_EAR = (0, 0, 512, 512)
R_BODY = (512, 256, 768, 512)
R_ARM = (512, 0, 768, 256)
SWATCH_ORIGIN = (768, 0)  # 4 x 4 swatches of 64 px
SWATCHES = ["fur", "white", "pink", "scarf", "scarf_dark", "frame", "fur_shade", "eye", "gold"]


def region_uv(rect, u, v):
    x0, y0, x1, y1 = rect
    return ((x0 + PAD + u * (x1 - x0 - 2 * PAD)) / TEX, (y0 + PAD + v * (y1 - y0 - 2 * PAD)) / TEX)


def swatch_uv(name):
    i = SWATCHES.index(name)
    return ((SWATCH_ORIGIN[0] + (i % 4) * 64 + 32) / TEX, (SWATCH_ORIGIN[1] + (i // 4) * 64 + 32) / TEX)


def region_grid(rect):
    x0, y0, x1, y1 = rect
    xs = (np.arange(x0, x1) + 0.5 - x0 - PAD) / (x1 - x0 - 2 * PAD)
    ys = (np.arange(y0, y1) + 0.5 - y0 - PAD) / (y1 - y0 - 2 * PAD)
    return np.meshgrid(np.clip(xs, 0, 1), np.clip(ys, 0, 1))


# --------------------------------------------------------------------------------------------
# Shapes (Blender space), shared by geometry and painting
# --------------------------------------------------------------------------------------------

# Proportions read off the reference rabbit: head, body (with feet) and ears each about a third of
# the height; the round head a little wider than the soft bean body.
HEAD_R = 0.300
HEAD_SX, HEAD_SY, HEAD_SZ = 1.15, 0.96, 1.00  # a soft round mochi face, wide like the reference (1.15)
HEAD_C = Vector((0.0, -0.01, 0.830))
NECK = Vector((0.0, 0.0, 0.560))
BODY_C = Vector((0.0, 0.01, 0.305))
BODY_R = Vector((0.250, 0.220, 0.275))
# small, simple dot eyes (user: "눈도 너무 초롱초롱해"): a slightly tall bean, one small highlight
EYE_X, EYE_Z, EYE_RX, EYE_RZ = 0.128, -0.045, 0.027, 0.032
MONO_X, MONO_R = 0.128, 0.056   # monocle on the +X eye (the viewer's right)
NOSE_Z = -0.070


def head_point(d):
    x, y, z = d
    return HEAD_C + Vector((x * HEAD_R * HEAD_SX, y * HEAD_R * HEAD_SY * (0.92 if y < 0 else 1.0),
                            z * HEAD_R * HEAD_SZ))


def face_dir(qx, qz):
    """Head direction whose painted face coordinate is (qx, qz) metres (inverse of paint_head's map)."""
    dx = qx / (HEAD_R * HEAD_SX)
    dz = qz / (HEAD_R * HEAD_SZ)
    return Vector((dx, -math.sqrt(max(0.0, 1 - dx * dx - dz * dz)), dz))


def body_point(d):
    lower = max(0.0, -d.z)
    w = 1.0 + 0.12 * lower - 0.06 * max(0.0, d.z) ** 2  # soft bean, a little fuller low
    return BODY_C + Vector((d.x * BODY_R.x * w, d.y * BODY_R.y * w, d.z * BODY_R.z))


# --------------------------------------------------------------------------------------------
# Texture painting (numpy, sRGB)
# --------------------------------------------------------------------------------------------

def paint_head(mouth="open", monocle=True):
    u, v = region_grid(R_HEAD)
    lon = (u - 0.5) * 2 * math.pi
    lat = (v - 0.5) * math.pi
    dx = np.sin(lon) * np.cos(lat); dy = -np.cos(lon) * np.cos(lat); dz = np.sin(lat)
    img = np.zeros(u.shape + (3,)); img[...] = hexc(P["fur"])
    blend(img, np.clip((dy + 0.3) * 0.7, 0, 1), hexc(P["fur_shade"]), 0.5)   # faint shade behind
    front = dy < 0.0
    qx = dx * HEAD_R * HEAD_SX
    qz = dz * HEAD_R * HEAD_SZ
    aa = 0.0020
    # soft cream muzzle patch for a little depth on the white face
    muzzle = np.minimum(sd_ellipse(qx, qz, -0.034, -0.100, 0.056, 0.046), sd_ellipse(qx, qz, 0.034, -0.100, 0.056, 0.046))
    blend(img, smooth_fill(muzzle, 0.02) * front, hexc(P["cream"]), 0.7)
    # painted volume (soft warm shading low on the face and under the muzzle, a brighter muzzle)
    paint_volume(img, qx, qz, front, HEAD_R * HEAD_SX, HEAD_R * HEAD_SZ, (0.0, -0.100), (0.090, 0.050),
                 np.ones(3), (0.96, 0.88, 0.86))
    for s in (-1, 1):  # blush ovals, outside and below the eyes
        blend(img, smooth_fill(sd_ellipse(qx, qz, s * 0.192, -0.095, 0.046, 0.028), 0.012) * front,
              hexc(P["blush"]), 0.85)
    for s in (-1, 1):  # small dark bean eyes with one small highlight dot
        ex, ez = s * EYE_X, EYE_Z
        blend(img, smooth_fill(sd_ellipse(qx, qz, ex, ez, EYE_RX, EYE_RZ), aa) * front, hexc(P["eye"]))
        blend(img, smooth_fill(sd_ellipse(qx, qz, ex - 0.009, ez + 0.011, 0.0085, 0.0090), aa) * front, np.ones(3))
    if monocle:
        # a monocle on the eye at the viewer's right (Dugi's left, +X), like the reference dog's: a
        # round gold rim edged in the outline brown, a faint glint on the lens
        mx, mz, rr = MONO_X, EYE_Z, MONO_R
        d = np.sqrt((qx - mx) ** 2 + (qz - mz) ** 2)
        blend(img, smooth_fill(d - rr, 0.002) * front, np.ones(3), 0.22)                 # lens tint
        glint = sd_segment(qx, qz, mx - 0.030, mz + 0.012, mx - 0.012, mz + 0.032) - 0.0035
        blend(img, smooth_fill(glint, 0.002) * front, np.ones(3), 0.9)
        blend(img, smooth_fill(np.abs(d - rr) - 0.0085, 0.002) * front, hexc(P["frame"]))  # brown edge
        blend(img, smooth_fill(np.abs(d - rr) - 0.0050, 0.002) * front, hexc(P["gold"]))   # gold rim
    nz = NOSE_Z  # small pink nose: a soft rounded triangle
    from bread_cat import sd_triangle
    nose = sd_triangle(qx, qz, (-0.015, nz + 0.008), (0.015, nz + 0.008), (0.0, nz - 0.009)) - 0.003
    blend(img, smooth_fill(nose, aa) * front, hexc(P["pink_deep"]))
    mcol = hexc(P["mouth"]); stroke = 0.0040
    sdf = sd_segment(qx, qz, 0.0, nz - 0.009, 0.0, nz - 0.017) - stroke * 0.8
    if mouth == "open":  # small open smile with a pink tongue and two little front teeth
        cz = nz - 0.019
        half = np.where(qz < cz, sd_ellipse(qx, qz, 0.0, cz, 0.044, 0.054), 1.0)
        blend(img, smooth_fill(np.minimum(sdf, half), aa) * front, mcol)
        tongue = np.maximum(sd_ellipse(qx, qz, 0.0, cz - 0.050, 0.028, 0.024), half + 0.003)
        blend(img, smooth_fill(tongue, aa) * front, hexc(P["tongue"]))
        for s in (-1, 1):
            tooth = np.maximum(np.abs(qx - s * 0.0065) - 0.0050, np.abs(qz - (cz - 0.0055)) - 0.0055) - 0.0010
            blend(img, smooth_fill(np.maximum(tooth, half + 0.001), aa) * front, hexc(P["tooth"]))
    else:  # calm "w" smile
        for s in (-1, 1):
            cx, cz, r = s * 0.014, nz - 0.017, 0.014
            ring = np.abs(np.sqrt((qx - cx) ** 2 + (qz - cz) ** 2) - r) - stroke
            sdf = np.minimum(sdf, np.where(qz < cz + 0.002, ring, 1.0))
        blend(img, smooth_fill(sdf, aa) * front, mcol)
    return img


def paint_ear():
    """u = around the ear section (front centre at u = 0.25), v = root (0) -> tip (1)."""
    u, v = region_grid(R_EAR)
    a = 2 * math.pi * u
    across = np.cos(a)
    front = np.sin(a) > 0.10
    img = np.zeros(u.shape + (3,)); img[...] = hexc(P["fur"])
    k = np.sqrt((across / 0.78) ** 2 + ((v - 0.50) / 0.42) ** 2)
    blend(img, smooth_fill((k - 1.0) * 0.2, 0.010) * front, hexc(P["pink"]))
    return img


def paint_body():
    u, v = region_grid(R_BODY)
    lon = (u - 0.5) * 2 * math.pi
    lat = (v - 0.5) * math.pi
    dy = -np.cos(lon) * np.cos(lat)
    img = np.zeros(u.shape + (3,)); img[...] = hexc(P["fur"])
    blend(img, np.clip((dy + 0.2) * 0.8, 0, 1), hexc(P["fur_shade"]), 0.5)
    return img


def paint_arm():
    """Arm tube: u = around (0 = top), v = shoulder (0) -> paw tip (1)."""
    u, v = region_grid(R_ARM)
    img = np.zeros(u.shape + (3,)); img[...] = hexc(P["fur"])
    return img


def build_atlas(mouth="open", monocle=True):
    canvas = np.zeros((TEX, TEX, 3)); canvas[...] = hexc(P["fur"])
    for rect, fn in ((R_HEAD, lambda: paint_head(mouth, monocle)), (R_EAR, paint_ear), (R_BODY, paint_body), (R_ARM, paint_arm)):
        x0, y0, x1, y1 = rect
        canvas[y0:y1, x0:x1] = fn()
    for i, name in enumerate(SWATCHES):
        x = SWATCH_ORIGIN[0] + (i % 4) * 64; y = SWATCH_ORIGIN[1] + (i // 4) * 64
        canvas[y:y + 64, x:x + 64] = hexc(P[name])
    canvas = np.clip(canvas, 0, 1)
    rgba = np.concatenate([canvas, np.ones((TEX, TEX, 1))], axis=2)
    img = bpy.data.images.new("dugi_atlas", TEX, TEX, alpha=False)
    img.pixels.foreach_set(rgba.astype(np.float32).ravel())
    return img


# --------------------------------------------------------------------------------------------
# Parts
# --------------------------------------------------------------------------------------------

def ellipsoid(bm, centre, radii, uv, segs=12, rings=8, rot=None, shape=None):
    def pt(d):
        q = Vector((d.x * radii[0], d.y * radii[1], d.z * radii[2]))
        if shape:
            q = shape(d, q)
        if rot:
            q = rot @ q
        return centre + q
    build_sphere(bm, pt, lambda u, v: uv, segs=segs, rings=rings)


def make_head(bm, monocle=True):
    # The head ring is the silhouette: 40 x 24 rings (6.4 deg apart); below -62 deg the head sits in
    # the body / scarf, so the sphere stops there with a hidden cap.
    build_sphere(bm, head_point, lambda u, v: region_uv(R_HEAD, u, v), segs=40, rings=24, lat_min=math.radians(-62))
    if monocle:
        make_monocle_chain(bm)


def make_monocle_chain(bm):
    """The monocle's thin gold chain: from the rim's lower outer edge down over the cheek and under
    the chin to the scarf, lying just off the skin (the outline makes it read as a drawn line)."""
    gold = swatch_uv("gold")
    a = 0.75  # rad below the outer side of the rim
    path = [(MONO_X + MONO_R * math.sin(a + 1.2), EYE_Z - MONO_R * math.cos(a + 1.2) * 0.0 - MONO_R * 0.75),
            (MONO_X + 0.062, EYE_Z - 0.10), (MONO_X + 0.064, EYE_Z - 0.16), (MONO_X + 0.040, EYE_Z - 0.215),
            (MONO_X + 0.005, EYE_Z - 0.245)]
    pts = []
    for qx, qz in path:
        q = head_point(face_dir(qx, qz))
        pts.append(q + (q - HEAD_C).normalized() * 0.006)
    end = Vector((MONO_X - 0.01, -0.175, SCARF_Z + 0.03))   # tucked into the scarf
    pts.append(end)
    smooth = [pts[0]]
    for i in range(len(pts) - 1):   # a little sag between the anchor points
        for k in (1, 2):
            t = k / 2
            smooth.append(pts[i].lerp(pts[i + 1], t) + Vector((0, -0.004 * math.sin(math.pi * t), 0)) * (k == 1))
    build_tube(bm, smooth, [0.0026] * len(smooth), 5, lambda u, v: gold, up_hint=Vector((0, -1, 0)))


ES = 16  # ear ring segments
EAR_T = [0.0, 0.07, 0.16, 0.27, 0.39, 0.51, 0.62, 0.72, 0.80, 0.865, 0.915, 0.952, 0.978, 0.994]
EAR_LEN = 0.56
EAR_W = 0.150   # long and wide (reference), round tip


def ear_root(side):
    return head_point(sph_dir(side * 0.80, 1.10)) - Vector((0, 0, 0.03))


def ear_path(side):
    """Gently spread, the left one (+X, the viewer's right) leaning out a little more like the
    reference, both curving back a touch."""
    b = ear_root(side)
    s = side
    out = 0.30 if side > 0 else 0.20
    return (b, b + Vector((s * out * 0.25, -0.01, 0.20)), b + Vector((s * out * 0.65, 0.02, 0.40)),
            b + Vector((s * out, 0.06, EAR_LEN)))


def make_ear(bm, side):
    p0, p1, p2, p3 = ear_path(side)

    def at(t):
        return p0 * (1 - t) ** 3 + p1 * 3 * t * (1 - t) ** 2 + p2 * 3 * t * t * (1 - t) + p3 * t ** 3
    uv = lambda u, v: region_uv(R_EAR, u, v)
    rows = []
    fwd0 = Vector((side * 0.15, -1.0, 0.0)).normalized()  # the pink faces forward
    for t in EAR_T:
        c = at(t)
        tan = (at(min(t + 0.01, 1)) - at(max(t - 0.01, 0))).normalized()
        fwd = (fwd0 - tan * fwd0.dot(tan)).normalized()
        sideax = fwd.cross(tan).normalized() * side
        w = EAR_W * math.sqrt(max(0.0, 1 - ((t - 0.54) / 0.46) ** 2))  # widest high up, round tip
        w = max(w, 0.075 * (1 - t) ** 0.5 * (t < 0.5))
        d = 0.48 * w   # plump
        row = []
        for j in range(ES):
            a = 2 * math.pi * j / ES
            sa = math.sin(a)
            off_f = d * (0.62 * sa - 0.40 * sa ** 6) if sa > 0 else d * sa
            row.append(bm.verts.new(c + sideax * (math.cos(a) * w * side) + fwd * off_f))
        rows.append((row, t))
    tip = bm.verts.new(at(1.0))
    for i in range(len(rows) - 1):
        (ra, ta), (rb, tb) = rows[i], rows[i + 1]
        for j in range(ES):
            k = (j + 1) % ES
            u0, u1 = j / ES, (j + 1) / ES
            add_face(bm, [ra[j], ra[k], rb[k], rb[j]], [uv(u0, ta), uv(u1, ta), uv(u1, tb), uv(u0, tb)])
    ra, ta = rows[-1]
    for j in range(ES):
        k = (j + 1) % ES
        add_face(bm, [ra[j], ra[k], tip], [uv(j / ES, ta), uv((j + 1) / ES, ta), uv((j + 0.5) / ES, 1.0)])
    c = bm.verts.new(p0)
    r0 = rows[0][0]
    for j in range(ES):
        add_face(bm, [r0[(j + 1) % ES], r0[j], c], [uv(0.5, 0.0)] * 3)
    return p0


SCARF_Z = 0.545   # where the head meets the body


def make_scarf(bm):
    """Red scarf: a soft band round the neck, a knot on Dugi's left front and two short tails."""
    red = swatch_uv("scarf"); dark = swatch_uv("scarf_dark")
    N = 22
    loop = []
    for i in range(N + 1):
        a = 2 * math.pi * i / N
        loop.append(Vector((0.200 * math.sin(a), -0.178 * math.cos(a) + 0.01, SCARF_Z - 0.012 * math.cos(a))))
    before = set(bm.verts)
    build_tube(bm, loop, [0.036] * len(loop), 8, lambda u, v: red, up_hint=Vector((0, 0, 1)), squash=0.55,
               cap_start=False, cap_end=False)
    # the band's first and last rings meet only approximately (their end tangents differ), which
    # left 16 open edges at the seam: weld them so the band is a closed ring (outline contract)
    bmesh.ops.remove_doubles(bm, verts=[v for v in bm.verts if v not in before], dist=0.006)
    knot = Vector((0.095, -0.200, SCARF_Z - 0.02))
    ellipsoid(bm, knot, (0.040, 0.030, 0.036), dark, 10, 6)
    for k, (dxz, ang) in enumerate((((0.025, -0.115), -25), ((0.075, -0.100), -50))):  # hanging down
        a = knot + Vector((0.0, -0.005, -0.01))
        b = knot + Vector((dxz[0], -0.006 - 0.008 * k, dxz[1]))
        pts, radii = capsule([a.lerp(b, i / 3) for i in range(4)], [0.026, 0.030, 0.032, 0.030], start=False)
        build_tube(bm, pts, radii, 8, lambda u, v: red, up_hint=Vector((0, -1, 0)), squash=0.45)


def make_body(bm):
    # the underside below -65 deg (between and under the feet) never shows: a hidden cap there
    build_sphere(bm, body_point, lambda u, v: region_uv(R_BODY, u, v), segs=26, rings=13, lat_min=math.radians(-65))
    white = swatch_uv("white")
    for s in (-1, 1):  # small round feet
        rot = Matrix.Rotation(s * math.radians(14), 3, "Z")
        ellipsoid(bm, Vector((s * 0.105, -0.080, 0.048)), (0.078, 0.105, 0.052), white, 14, 8, rot)
    ellipsoid(bm, Vector((0.0, 0.205, 0.17)), (0.065, 0.058, 0.062), white, 10, 6)  # tail puff (behind)
    make_scarf(bm)


# Short thick mitten arms, one segment each (user: "관절을 하나 빼란거야"; 2026-10-24 "팔이 너무
# 부자연스러워" -> like the reference: short, thick, the same width down to a round paw, held close).
# The shoulder pivot sits under the body's surface. SHOULDER / HAND below are the older v2 placement;
# the default is variant A (set_arm_variant("A") after ARM_VARIANTS).
SHOULDER = {1: Vector((0.150, -0.060, 0.450)), -1: Vector((-0.150, -0.060, 0.450))}
HAND = {1: Vector((0.110, -0.215, 0.320)), -1: Vector((-0.205, -0.150, 0.320))}
# Arm placement variants (2026-10-24 user: "팔 위치가 어색해" -> a contact sheet to pick from). All
# attach at the body's SIDES right under the head / scarf line, like the reference rabbit.
#   v2: the earlier placement (shoulders on the front-sides, paws on the tummy)
#   A: arms hang down along the body sides, paws by the hips
#   B: arms crossed on the chest (the reference rabbit's rest pose)
#   C: arms slightly forward, paws together in front of the tummy
#   D: short arms angled forward-down, paws resting on the front edge of the belly silhouette
ARM_VARIANTS = {
    "v2": (SHOULDER, HAND),
    "A": ({1: Vector((0.190, -0.010, 0.465)), -1: Vector((-0.190, -0.010, 0.465))},
          {1: Vector((0.275, -0.040, 0.285)), -1: Vector((-0.275, -0.040, 0.285))}),
    "B": ({1: Vector((0.180, -0.050, 0.465)), -1: Vector((-0.180, -0.050, 0.465))},
          {1: Vector((-0.030, -0.255, 0.395)), -1: Vector((0.030, -0.265, 0.365))}),
    "C": ({1: Vector((0.185, -0.040, 0.465)), -1: Vector((-0.185, -0.040, 0.465))},
          {1: Vector((0.060, -0.250, 0.300)), -1: Vector((-0.060, -0.250, 0.300))}),
    "D": ({1: Vector((0.185, -0.030, 0.470)), -1: Vector((-0.185, -0.030, 0.470))},
          {1: Vector((0.215, -0.170, 0.320)), -1: Vector((-0.215, -0.170, 0.320))}),
}


def set_arm_variant(name):
    global SHOULDER, HAND
    SHOULDER, HAND = ARM_VARIANTS[name]


set_arm_variant("A")   # 2026-10-24 user decision: A (side shoulders, arms hanging along the sides)
# Pointer stick held in the right paw (user: "가리키고 싶으면 손가락 봉같은걸 하나 주자"), continuing the
# arm out of the fist, so swinging the arm at a target aims the stick's red tip at it.
POINTER_LEN, POINTER_R, POINTER_TIP_R = 0.36, 0.009, 0.020
ARM_R = 0.064
PAW_R = 0.070


def capsule(pts, radii, start=True, end=True):
    """Extend a tube's centre line with quarter-circle rings so its ends are round domes (sausage).
    The rings run from the end outward (75 -> 30 deg); listing them 30 -> 75 folded the dome back."""
    pts, radii = list(pts), list(radii)
    for at_end in ((False,) if start else ()) + ((True,) if end else ()):
        i, j = (-1, -2) if at_end else (0, 1)
        ax = (pts[i] - pts[j]).normalized()
        r = radii[i]
        dome = [(pts[i] + ax * r * math.cos(f), r * math.sin(f)) for f in (math.radians(a) for a in (75, 55, 30))]
        if at_end:
            pts += [p for p, _ in dome]; radii += [q for _, q in dome]
        else:
            pts = [p for p, _ in reversed(dome)] + pts; radii = [q for _, q in reversed(dome)] + radii
    return pts, radii


def arm_axis(side):
    return (HAND[side] - SHOULDER[side]).normalized()


def arm_reach(side):
    """Shoulder -> paw tip along the (straight, single-segment) arm."""
    return (HAND[side] - SHOULDER[side]).length + PAW_R * 1.10


def make_mitten_arm(bm, S, H, arm_r, paw_r, uv_fn, paw_uv):
    """Short thick mitten arm like the storybook reference: one straight sausage, the same width all
    the way to a generous round paw (no thin wrist, no elbow). Its root starts deep inside the body
    (S is under the body's surface at the shoulder), so the arm grows out of the rounded shoulder
    without an outline ring; returns the paw centre."""
    ax = (H - S).normalized()
    root = S - ax * arm_r * 0.9
    n = 4
    line = [root.lerp(H, i / (n - 1)) for i in range(n)]
    radii = [arm_r * (1.0 + 0.04 * math.sin(math.pi * i / (n - 1))) for i in range(n)]
    pts, radii = capsule(line, radii, end=False)
    build_tube(bm, pts, radii, 12, uv_fn, up_hint=Vector((0, 0, 1)))
    rot = Vector((1, 0, 0)).rotation_difference(ax).to_matrix()
    ellipsoid(bm, H + ax * paw_r * 0.10, (paw_r * 1.05, paw_r, paw_r * 0.97), paw_uv, 14, 8, rot)
    return H


def make_arm(bm, side):
    return make_mitten_arm(bm, SHOULDER[side], HAND[side], ARM_R, PAW_R, lambda u, v: region_uv(R_ARM, u, v),
                           swatch_uv("white"))


def make_pointer(bm, side):
    """Thin brown stick through the centre of the right paw along the arm, a red ball at its tip;
    returns the tip."""
    ax = arm_axis(side)
    start = HAND[side] - ax * PAW_R * 0.5
    end = start + ax * POINTER_LEN
    build_tube(bm, [start.lerp(end, t / 3) for t in range(4)], [POINTER_R] * 4, 6,
               lambda u, v: swatch_uv("frame"), up_hint=Vector((0, 0, 1)))
    ellipsoid(bm, end, (POINTER_TIP_R,) * 3, swatch_uv("scarf"), 8, 6)
    return end + ax * POINTER_TIP_R


# --------------------------------------------------------------------------------------------
# Scene assembly
# --------------------------------------------------------------------------------------------

def make_material(img):
    mat = bpy.data.materials.new("Dugi")
    mat.use_nodes = True
    nt = mat.node_tree
    bsdf = nt.nodes["Principled BSDF"]
    tex = nt.nodes.new("ShaderNodeTexImage")
    tex.image = img
    tex.interpolation = "Linear"
    nt.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
    bsdf.inputs["Roughness"].default_value = 0.75
    bsdf.inputs["Metallic"].default_value = 0.0
    if "Specular IOR Level" in bsdf.inputs:
        bsdf.inputs["Specular IOR Level"].default_value = 0.25
    return mat


def mesh_object(name, bm, pivot_world, parent, parent_pivot, mat):
    bmesh.ops.translate(bm, verts=bm.verts, vec=-pivot_world)
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-6)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)  # every part is closed: make all faces point out
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    me.materials.append(mat)
    me.shade_smooth()
    ob = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(ob)
    ob.parent = parent
    ob.location = pivot_world - parent_pivot
    return ob


def empty(name, loc_world, parent, parent_pivot, size=0.03):
    ob = bpy.data.objects.new(name, None)
    ob.empty_display_size = size
    bpy.context.scene.collection.objects.link(ob)
    ob.parent = parent
    ob.location = loc_world - parent_pivot
    return ob


def build(monocle=True, mouth="open", pointer=True):
    img = build_atlas(mouth, monocle)
    mat = make_material(img)
    origin = Vector((0, 0, 0))
    root = empty("Dugi", origin, None, origin, 0.2)
    bm = new_bm(); make_body(bm)
    body = mesh_object("Body", bm, origin, root, origin, mat)
    bm = new_bm(); make_head(bm, monocle)
    head = mesh_object("Head", bm, NECK, body, origin, mat)
    for side, nm in ((1, "L"), (-1, "R")):
        bm = new_bm(); base = make_ear(bm, side)
        mesh_object("Ear" + nm, bm, base, head, NECK, mat)
    for side, nm in ((1, "L"), (-1, "R")):
        bm = new_bm(); tip = make_arm(bm, side)
        arm = mesh_object("Arm" + nm, bm, SHOULDER[side], body, origin, mat)
        empty("Hand" + nm, tip, arm, SHOULDER[side])
        if side == -1 and pointer:
            bm = new_bm(); ptip = make_pointer(bm, side)
            stick = mesh_object("Pointer", bm, HAND[side], arm, SHOULDER[side], mat)
            empty("PointerTip", ptip, stick, HAND[side])
    return root, img


def _rotate_about_origin(ob, q):
    """Rotate object `ob` in world space by quaternion q about its own origin (its pivot)."""
    mw = ob.matrix_world.copy()
    loc = mw.translation.copy()
    ob.matrix_world = Matrix.Translation(loc) @ q.to_matrix().to_4x4() @ Matrix.Translation(-loc) @ mw


def pose_point(arm, tip, target):
    """Swing the arm about the shoulder so `tip` (the paw, or the PointerTip) points at `target`."""
    bpy.context.view_layer.update()
    S = arm.matrix_world.translation.copy()
    T = tip.matrix_world.translation.copy()
    _rotate_about_origin(arm, (T - S).rotation_difference(Vector(target) - S))
    bpy.context.view_layer.update()


def stats():
    tris = 0; meshes = 0
    deps = bpy.context.evaluated_depsgraph_get()
    per = {}
    for ob in bpy.context.scene.objects:
        if ob.type == "MESH":
            meshes += 1
            me = ob.evaluated_get(deps).to_mesh()
            me.calc_loop_triangles()
            per[ob.name] = len(me.loop_triangles)
            tris += per[ob.name]
    pts = [(ob.matrix_world @ v.co) for ob in bpy.context.scene.objects if ob.type == "MESH" for v in ob.data.vertices]
    bounds = [round(min(p[i] for p in pts), 3) for i in range(3)] + [round(max(p[i] for p in pts), 3) for i in range(3)]
    pivots = {ob.name: tuple(round(c, 3) for c in ob.matrix_world.translation) for ob in bpy.context.scene.objects}
    head_d = 2 * HEAD_R * HEAD_SX
    return dict(arm_reach_over_head_d=[round(arm_reach(sd) / head_d, 3) for sd in (1, -1)], head_d=round(head_d, 3),
                bounds_min_max=bounds, pivots=pivots, per_mesh=per, meshes=meshes, triangles=tris,
                materials=len([m for m in bpy.data.materials if m.users]), nodes=len(bpy.context.scene.objects))


def parse_args():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    opts = {"out": None, "monocle": "on", "mouth": "open", "pointer": "on", "arms": "A"}
    i = 0
    while i < len(argv):
        k = argv[i].lstrip("-")
        if k in opts and i + 1 < len(argv):
            opts[k] = argv[i + 1]; i += 2
        else:
            i += 1
    return opts


if __name__ == "__main__":
    opts = parse_args()
    bc.clear_scene()
    set_arm_variant(opts["arms"])
    build(opts["monocle"] != "off", opts["mouth"], opts["pointer"] != "off")
    print("DUGI_STATS", stats())
    if opts["out"]:
        bc.export_glb(opts["out"])
        print("DUGI_EXPORTED", opts["out"])
