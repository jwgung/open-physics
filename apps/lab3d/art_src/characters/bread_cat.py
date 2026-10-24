"""Bread Cat (빵고양이) — the Open Physics 3D main character, generated entirely in Blender Python.

Run (headless):
    blender -b --factory-startup -P apps/lab3d/art_src/characters/bread_cat.py -- \
        [--out apps/lab3d/assets/characters/bread_cat.glb] [--mouth omega|smile|calm] [--palette cheese|cream] [--eyes dot|sparkle]

Nothing depends on a hand-made .blend: geometry, UVs and the single texture atlas (face, fur stripes,
bag print, baguette scoring) are produced by this file. Other scripts may `import` it and call
`build(mouth=..., palette=...)` to get the objects in the current scene (the preview renderer does).

Conventions (see also the module docstring of the Godot side when it loads this asset):
- Units are metres. Total height ~1.4 m including ears. Origin = centre of the bag bottom.
- Blender: +Z up, the cat faces -Y. The glTF exporter converts to +Y up, so in glTF/Godot the cat faces
  +Z (Godot's Vector3.MODEL_FRONT) and its left side is +X (MODEL_LEFT). Rotate the instance 180 deg
  about Y if a scene expects -Z forward.
- Node tree (no armature; animate by rotating nodes, each origin is its pivot):
    BreadCat                (empty, origin at bag bottom centre)
      Bag                   (mesh)
      Baguette              (mesh, pivot at its lower end inside the bag)
      Body                  (mesh, pivot at the hips inside the bag)
        Head                (mesh incl. ears, pivot at the neck -> nod/tilt)
        ArmL / ArmR         (mesh, pivot at the shoulder; L = cat's left = +X)
          HandL / HandR     (empty at the paw centre: ball grip point)
        Tail                (mesh, pivot at the tail root)
          Tail2             (mesh, pivot at the tail joint)
            TailTip         (empty)
- Bag front: one toast slice (2026-10-23 user decision).
- Head: round from the front (width:height 1:1) with round-tipped ears (2026-10-23 user feedback: rounder is cuter).
- Budget (SM-P200 low): 8 meshes, 1 material, 1 texture (1024 px), < 6000 triangles (5,840), and the
  app draws <= 3,500 vertices (3,184 glTF vertices + the actor's shadow). Segments go where the
  silhouette shows (head ring, ears, paws, tail); hidden parts (chin under -60 deg, body in the bag,
  the inside wall below the rim) stay coarse.
- Outline mesh contract (storybook inverted-hull outline, Blender preview and the app's future
  next_pass: VERTEX += NORMAL * width, cull_front): the exported mesh itself carries the averaged
  normals. Every part is a closed shell with outward faces and smooth shading only, no sharp edges
  (the bag's crisp corners are a bevel column BAG_BEVEL from each corner, not split normals), so
  all glTF vertices at one position (UV-seam copies) have the same NORMAL and the grown hull is
  watertight (no cracks or doubled lines). No extra vertex attribute is needed. Concave creases
  are kept soft (rounded gusset fold, wrinkles fading out) so the hull does not show through them.
"""

import math
import os
import sys

import bmesh
import bpy
import numpy as np
from mathutils import Matrix, Vector

TEX = 1024

# --------------------------------------------------------------------------------------------
# Palette (sRGB)
# --------------------------------------------------------------------------------------------

PALETTES = {
    # Saturated cheese tabby that sits well next to the island primaries.
    "cheese": dict(
        fur="#ffbf4d", fur_light="#ffd77a", stripe="#f08a1e", cream="#fff3dc",
        pink="#ff8fa8", blush="#ff8aa0", eye="#2b1a14", eye_low="#5a3626", mouth="#6b3420",
        kraft="#d9a066", kraft_dark="#c98c52", kraft_in="#9c6534", ink="#6b3a1c",
        crust="#d9812e", crust_dark="#b45f22", score="#f7d38c", toe="#e0a070",
    ),
    # Softer, paler cat closer to the second reference sketch.
    "cream": dict(
        fur="#ffd98c", fur_light="#ffe8b5", stripe="#f2a649", cream="#fff7ea",
        pink="#ff9db2", blush="#ff9cb0", eye="#2b1a14", eye_low="#5a3626", mouth="#6b3420",
        kraft="#d9a066", kraft_dark="#c98c52", kraft_in="#9c6534", ink="#6b3a1c",
        crust="#d9812e", crust_dark="#b45f22", score="#f7d38c", toe="#e8b088",
    ),
}


def hexc(h):
    h = h.lstrip("#")
    return np.array([int(h[i:i + 2], 16) / 255.0 for i in (0, 2, 4)])


# --------------------------------------------------------------------------------------------
# Atlas layout (pixels, origin bottom-left like Blender UVs)
# --------------------------------------------------------------------------------------------

R_HEAD = (0, 512, 1024, 1024)
R_BAGF = (0, 0, 512, 512)
R_BODY = (512, 256, 768, 512)
R_ARM = (768, 256, 1024, 512)
R_TAIL = (512, 0, 768, 256)
R_BAGU = (768, 128, 1024, 256)
SWATCH_ORIGIN = (768, 0)  # 4 x 2 swatches of 64 px
SWATCHES = ["kraft", "kraft_in", "pink", "cream", "fur", "stripe", "eye", "crust"]
PAD = 3  # texels of inset so mip filtering does not bleed between regions


def region_uv(rect, u, v):
    x0, y0, x1, y1 = rect
    return ((x0 + PAD + u * (x1 - x0 - 2 * PAD)) / TEX, (y0 + PAD + v * (y1 - y0 - 2 * PAD)) / TEX)


def swatch_uv(name):
    i = SWATCHES.index(name)
    cx = SWATCH_ORIGIN[0] + (i % 4) * 64 + 32
    cy = SWATCH_ORIGIN[1] + (i // 4) * 64 + 32
    return (cx / TEX, cy / TEX)


# --------------------------------------------------------------------------------------------
# Shapes (Blender space). Shared by geometry and painting so features land where expected.
# --------------------------------------------------------------------------------------------

HEAD_R = 0.275
FACE_R = 0.235  # face features are authored for this radius and scale with the head
HEAD_SX, HEAD_SY, HEAD_SZ = 1.06, 0.98, 1.06  # SX == SZ: a round face seen from the front
HEAD_C = Vector((0.0, -0.01, 0.959))  # keeps the total height (ear tips) at 1.398 m
NECK = Vector((0.0, 0.0, 0.78))
BODY_C = Vector((0.0, 0.03, 0.62))
BODY_R = Vector((0.19, 0.15, 0.20))
HIPS = Vector((0.0, 0.03, 0.45))
BAG_H = 0.70
BAG_W0, BAG_D0 = 0.56, 0.37  # bottom
BAG_W1, BAG_D1 = 0.66, 0.44  # top


def sph_dir(lon, lat):
    """lon 0 = front (-Y), positive toward the cat's left (+X)."""
    return Vector((math.sin(lon) * math.cos(lat), -math.cos(lon) * math.cos(lat), math.sin(lat)))


def head_point(d):
    x, y, z = d
    r = HEAD_R
    # chibi, truly round (2026-10-23 user feedback): the front silhouette is a circle (no flat top,
    # no bulging lower cheeks, no narrow chin); the plump cheeks are the painted blush. Only the face
    # plane is a little flatter front-to-back.
    sx = HEAD_SX
    sy = HEAD_SY * (0.93 if y < 0 else 1.0)
    sz = HEAD_SZ
    return HEAD_C + Vector((x * r * sx, y * r * sy, z * r * sz))


# --------------------------------------------------------------------------------------------
# Texture painting (numpy, sRGB)
# --------------------------------------------------------------------------------------------

def smooth_fill(sdf, aa):
    """1 inside (sdf<0), 0 outside, anti-aliased over `aa`."""
    return np.clip(0.5 - sdf / aa, 0.0, 1.0)


def blend(canvas, mask, color, alpha=1.0):
    m = (mask * alpha)[..., None]
    canvas[...] = canvas * (1 - m) + color[None, None, :] * m


def sd_ellipse(px, py, cx, cy, rx, ry):
    k = np.sqrt(((px - cx) / rx) ** 2 + ((py - cy) / ry) ** 2)
    return (k - 1.0) * min(rx, ry)


def sd_segment(px, py, ax, ay, bx, by):
    pax, pay = px - ax, py - ay
    bax, bay = bx - ax, by - ay
    h = np.clip((pax * bax + pay * bay) / (bax * bax + bay * bay), 0, 1)
    return np.sqrt((pax - bax * h) ** 2 + (pay - bay * h) ** 2)


def sd_triangle(px, py, a, b, c):
    """Signed distance to triangle (iq)."""
    def dot2(x, y):
        return x * x + y * y
    e0 = (b[0] - a[0], b[1] - a[1]); e1 = (c[0] - b[0], c[1] - b[1]); e2 = (a[0] - c[0], a[1] - c[1])
    v0 = (px - a[0], py - a[1]); v1 = (px - b[0], py - b[1]); v2 = (px - c[0], py - c[1])
    def pq(v, e):
        h = np.clip((v[0] * e[0] + v[1] * e[1]) / (e[0] ** 2 + e[1] ** 2), 0, 1)
        return (v[0] - e[0] * h, v[1] - e[1] * h)
    p0, p1, p2 = pq(v0, e0), pq(v1, e1), pq(v2, e2)
    s = np.sign(e0[0] * e2[1] - e0[1] * e2[0])
    d = np.minimum(np.minimum(dot2(*p0), dot2(*p1)), dot2(*p2))
    c0 = s * (v0[0] * e0[1] - v0[1] * e0[0])
    c1 = s * (v1[0] * e1[1] - v1[1] * e1[0])
    c2 = s * (v2[0] * e2[1] - v2[1] * e2[0])
    sg = np.minimum(np.minimum(c0, c1), c2)
    return -np.sqrt(d) * np.sign(sg)


def region_grid(rect):
    x0, y0, x1, y1 = rect
    xs = (np.arange(x0, x1) + 0.5 - x0 - PAD) / (x1 - x0 - 2 * PAD)
    ys = (np.arange(y0, y1) + 0.5 - y0 - PAD) / (y1 - y0 - 2 * PAD)
    u, v = np.meshgrid(np.clip(xs, 0, 1), np.clip(ys, 0, 1))
    return u, v


def value_noise(u, v, freq, seed):
    rng = np.random.default_rng(seed)
    g = rng.random((freq + 2, freq + 2))
    x = u * freq; y = v * freq
    xi = np.floor(x).astype(int); yi = np.floor(y).astype(int)
    xf = x - xi; yf = y - yi
    xf = xf * xf * (3 - 2 * xf); yf = yf * yf * (3 - 2 * yf)
    a = g[yi, xi]; b = g[yi, xi + 1]; c = g[yi + 1, xi]; d = g[yi + 1, xi + 1]
    return (a * (1 - xf) + b * xf) * (1 - yf) + (c * (1 - xf) + d * xf) * yf


def paint_volume(img, qx, qz, front, hw, hh, muzzle_c, muzzle_r, glow, warm, amount=1.0):
    """Painted volume, like the storybook reference (2026-10-24 user: round heads stay round, the
    face reads 3D through soft colour, not geometry): very soft warm shading toward the lower rim of
    the face (lower cheeks, jaw) and just under the muzzle, and a gently brighter muzzle centre.
    All smooth gradients (no edges for the filter to alias); applied before blush and features.
    hw / hh: the face's half width / height in the qx / qz units; warm: a multiply tint."""
    ex, ez = qx / hw, qz / hh
    r = np.sqrt(ex * ex + ez * ez)
    low = np.clip((0.30 - ez) / 1.0, 0.0, 1.0)
    rim = np.clip((r - 0.60) / 0.40, 0.0, 1.0) ** 1.6 * low * 0.60
    cx, cz = muzzle_c; rx, rz = muzzle_r
    d = ((qx - cx) / (rx * 1.15)) ** 2 + ((qz - (cz - rz * 0.95)) / (rz * 0.55)) ** 2
    under = np.exp(-d * 1.6) * (qz < cz) * 0.45
    m = np.clip((rim + under) * amount, 0.0, 0.7) * front
    img *= (1.0 - m[..., None] * (1.0 - np.array(warm))[None, None, :])
    dm = ((qx - cx) / (rx * 0.8)) ** 2 + ((qz - (cz + rz * 0.15)) / (rz * 0.75)) ** 2
    blend(img, np.exp(-dm * 1.8) * front, glow, 0.55 * amount)


def paint_head(P, mouth, eyes="dot"):
    u, v = region_grid(R_HEAD)
    lon = (u - 0.5) * 2 * math.pi
    lat = (v - 0.5) * math.pi
    dx = np.sin(lon) * np.cos(lat); dy = -np.cos(lon) * np.cos(lat); dz = np.sin(lat)
    img = np.zeros(u.shape + (3,))
    # base fur with a gentle lighter face / darker crown
    img[...] = hexc(P["fur"])
    blend(img, np.clip((-dy - 0.2) * 1.2, 0, 1) * np.clip(1 - dz * 1.5, 0, 1), hexc(P["fur_light"]), 0.6)
    aa_ang = 0.012
    # --- stripes (angular coordinates) ---
    stripe = hexc(P["stripe"])
    coslat = np.cos(lat)
    # forehead "M": three stripes running from brow over the crown
    for c, lo, w in ((-0.21, 0.50, 0.050), (0.0, 0.42, 0.058), (0.21, 0.50, 0.050)):
        cc = c * (1 + 0.6 * np.clip(lat - lo, 0, 2))  # fan out slightly over the crown
        taper = np.clip((lat - lo) / 0.18, 0, 1) * np.clip((1.35 - lat) / 0.3, 0, 1)
        sdf = np.abs((lon - cc) * coslat) - w * taper
        blend(img, smooth_fill(sdf, aa_ang) * (dy < 0.6) * np.clip(taper * 4, 0, 1), stripe)
    # back of head: vertical bands
    for side in (-1, 1):
        for c in (1.85, 2.3, 2.75):
            taper = np.clip((lat + 0.55) / 0.3, 0, 1) * np.clip((1.25 - lat) / 0.3, 0, 1)
            sdf = np.abs((lon - side * c) * coslat) - 0.075 * taper
            blend(img, smooth_fill(sdf, aa_ang) * np.clip(taper * 4, 0, 1), stripe)
    # cheek whisker stripes: two short bands on each side
    for side in (-1, 1):
        for la, l0 in ((0.02, 1.08), (-0.16, 1.12)):
            t = np.clip((side * lon - l0) / 0.32, 0, 1)
            taper = np.clip((side * lon - l0) / 0.08, 0, 1) * (1 - 0.4 * t)
            inside_lon = (side * lon > l0) & (side * lon < 1.62)
            sdf = np.abs(lat - la) - 0.035 * taper
            blend(img, smooth_fill(sdf, aa_ang) * inside_lon * np.clip(taper * 4, 0, 1), stripe)
    # --- front face, measured in metres on the front view of the deformed head ---
    front = dy < 0.0
    qx = dx * FACE_R * HEAD_SX
    qz = dz * FACE_R * HEAD_SZ
    aa = 0.0022
    cream = hexc(P["cream"])
    # muzzle + chin
    sdf = np.minimum(sd_ellipse(qx, qz, 0.0, -0.085, 0.085, 0.055), sd_ellipse(qx, qz, 0.0, -0.14, 0.12, 0.06))
    blend(img, smooth_fill(sdf, 0.02) * front, cream)
    # painted volume (soft warm shading low on the face and under the muzzle, a brighter muzzle)
    paint_volume(img, qx, qz, front, FACE_R * HEAD_SX, FACE_R * HEAD_SZ, (0.0, -0.090), (0.090, 0.058),
                 hexc("#fffbf2"), (0.95, 0.84, 0.78))
    # blush
    for s in (-1, 1):
        sdf = sd_ellipse(qx, qz, s * 0.150, -0.060, 0.045, 0.026)
        blend(img, smooth_fill(sdf, 0.02) * front, hexc(P["blush"]), 0.75)
    # eyes: big glossy, a touch taller than wide, warm lower gradient
    for s in (-1, 1):
        if eyes == "dot":  # default (2026-10-23 user decision): small simple storybook eyes, one dot
            ex, ez = s * 0.092, -0.008
            blend(img, smooth_fill(sd_ellipse(qx, qz, ex, ez, 0.022, 0.026), aa) * front, hexc(P["eye"]))
            blend(img, smooth_fill(sd_ellipse(qx, qz, ex - 0.007, ez + 0.009, 0.0065, 0.007), aa) * front, np.ones(3))
            continue
        ex, ez, rx, rz = s * 0.098, 0.0, 0.046, 0.053
        sdf = sd_ellipse(qx, qz, ex, ez, rx, rz)
        m = smooth_fill(sdf, aa) * front
        blend(img, m, hexc(P["eye"]))
        low = np.clip((ez - qz) / rz, 0, 1) ** 1.5
        blend(img, m * low, hexc(P["eye_low"]), 0.8)
        hx = ex - 0.014; hz = ez + 0.020
        blend(img, smooth_fill(sd_ellipse(qx, qz, hx, hz, 0.016, 0.017), aa) * front, np.ones(3))
        blend(img, smooth_fill(sd_ellipse(qx, qz, ex + 0.017, ez - 0.022, 0.0075, 0.0075), aa) * front, np.ones(3))
    # nose: soft inverted triangle
    nz = -0.058
    sdf = sd_triangle(qx, qz, (-0.017, nz + 0.009), (0.017, nz + 0.009), (0.0, nz - 0.010)) - 0.004
    blend(img, smooth_fill(sdf, aa) * front, hexc(P["pink"]))
    # mouth
    mcol = hexc(P["mouth"])
    stroke = 0.0042
    if mouth == "omega":
        r = 0.0165
        sdf = sd_segment(qx, qz, 0.0, nz - 0.012, 0.0, nz - 0.021) - stroke * 0.8
        for s in (-1, 1):
            cx, cz = s * r, nz - 0.021
            ring = np.abs(np.sqrt((qx - cx) ** 2 + (qz - cz) ** 2) - r) - stroke
            ring = np.where(qz < cz + 0.002, ring, 1.0)
            sdf = np.minimum(sdf, ring)
        blend(img, smooth_fill(sdf, aa) * front, mcol)
    elif mouth == "smile":
        # small open happy mouth with a pink tongue (reference 1)
        sdf = sd_segment(qx, qz, 0.0, nz - 0.012, 0.0, nz - 0.019) - stroke * 0.8
        blend(img, smooth_fill(sdf, aa) * front, mcol)
        cz = nz - 0.019
        half = np.where(qz < cz, sd_ellipse(qx, qz, 0.0, cz, 0.024, 0.026), 1.0)
        half = np.maximum(half, cz - 0.0 - qz - 0.03)
        blend(img, smooth_fill(half, aa) * front, mcol)
        tongue = np.maximum(sd_ellipse(qx, qz, 0.0, cz - 0.028, 0.016, 0.014), half + 0.003)
        blend(img, smooth_fill(tongue, aa) * front, hexc(P["pink"]))
    else:  # calm: tiny "ㅅ"
        sdf = sd_segment(qx, qz, 0.0, nz - 0.012, 0.0, nz - 0.020)
        sdf = np.minimum(sdf, sd_segment(qx, qz, 0.0, nz - 0.020, -0.013, nz - 0.030))
        sdf = np.minimum(sdf, sd_segment(qx, qz, 0.0, nz - 0.020, 0.013, nz - 0.030))
        blend(img, smooth_fill(sdf - stroke * 0.8, aa) * front, mcol)
    # whiskers: three thin lines per side starting outside the muzzle
    for s in (-1, 1):
        for (ax, az, bx, bz) in ((0.185, -0.075, 0.250, -0.060), (0.185, -0.090, 0.252, -0.092),):
            sdf = sd_segment(qx, qz, s * ax, az, s * bx, bz) - 0.0018
            blend(img, smooth_fill(sdf, aa) * front, hexc(P["mouth"]), 0.55)
    return img


def paint_body(P):
    u, v = region_grid(R_BODY)
    lon = (u - 0.5) * 2 * math.pi
    lat = (v - 0.5) * math.pi
    dy = -np.cos(lon) * np.cos(lat)
    img = np.zeros(u.shape + (3,)); img[...] = hexc(P["fur"])
    belly = np.clip((-dy - 0.35) * 3, 0, 1)
    blend(img, belly, hexc(P["cream"]))
    for c in (2.2, 2.7, 3.14, -2.2, -2.7):
        sdf = np.abs((lon - c) * np.cos(lat)) - 0.08 * np.clip((1.2 - lat) / 0.4, 0, 1)
        blend(img, smooth_fill(sdf, 0.02), hexc(P["stripe"]))
    return img


def paint_arm(P):
    """u = around (0 = up), v = shoulder(0) -> paw tip(1)."""
    u, v = region_grid(R_ARM)
    img = np.zeros(u.shape + (3,)); img[...] = hexc(P["fur"])
    for c in (0.18, 0.36):
        sdf = np.abs(v - c) - 0.035
        blend(img, smooth_fill(sdf, 0.01) * (np.abs(u - 0.5) > 0.12), hexc(P["stripe"]))
    paw = np.clip((v - 0.60) / 0.06, 0, 1)
    blend(img, paw, hexc(P["cream"]))
    # toe separations on the top-front of the paw
    for c in (-0.075, 0.075):
        uu = np.where(u > 0.5, u - 1.0, u)
        sdf = np.maximum(np.abs(uu - c) - 0.008, np.maximum(0.86 - v, v - 0.985))
        blend(img, smooth_fill(sdf, 0.006), hexc(P["toe"]))
    return img


def paint_tail(P):
    u, v = region_grid(R_TAIL)
    img = np.zeros(u.shape + (3,)); img[...] = hexc(P["fur"])
    for c in np.linspace(0.12, 0.92, 6):
        sdf = np.abs(v - c) - 0.035
        blend(img, smooth_fill(sdf, 0.01), hexc(P["stripe"]))
    return img


def paint_baguette(P):
    u, v = region_grid(R_BAGU)
    img = np.zeros(u.shape + (3,)); img[...] = hexc(P["crust"])
    under = np.clip(1 - np.abs(u - 0.5) * 4, 0, 1)  # u=0.5 is the underside
    blend(img, under, hexc(P["crust_dark"]), 0.8)
    ends = np.clip((np.abs(v - 0.5) - 0.38) / 0.1, 0, 1)
    blend(img, ends, hexc(P["crust_dark"]), 0.7)
    uu = np.where(u > 0.5, u - 1.0, u)  # top centred at 0
    for c in (0.24, 0.40, 0.56, 0.72):
        # diagonal slash across the top
        d = (v - c) - 0.30 * uu
        sdf = np.maximum(np.abs(d) - 0.022 * (1 - (uu / 0.16) ** 2).clip(0, 1), np.abs(uu) - 0.16)
        blend(img, smooth_fill(sdf, 0.008), hexc(P["score"]))
    n = value_noise(u, v, 24, 3)
    img *= (0.94 + 0.08 * n)[..., None]
    return img


def paint_bag_front(P):
    """u = left->right across the front panel, v = bottom->top. Panel is ~0.55 x 0.80 m."""
    u, v = region_grid(R_BAGF)
    img = np.zeros(u.shape + (3,)); img[...] = hexc(P["kraft"])
    n = value_noise(u, v, 18, 1) * 0.6 + value_noise(u, v, 60, 2) * 0.4
    img *= (0.95 + 0.08 * n)[..., None]
    # metric coordinates on the panel (centre-origin)
    x = (u - 0.5) * 0.55
    y = v * BAG_H
    ink = hexc(P["ink"])
    aa = 0.0025
    cy = 0.36
    # The logo is one toast slice (2026-10-23 user decision: no croissant, no label lines), centred
    # and a little larger: a rounded-top loaf outline with its crumb.
    tx, k = 0.0, 1.35
    body = sd_ellipse(x, y, tx, cy + 0.035 * k, 0.068 * k, 0.045 * k)
    box = np.maximum(np.abs(x - tx) - 0.055 * k, np.abs(y - (cy - 0.005 * k)) - 0.045 * k)
    toast = np.minimum(body, box)
    blend(img, smooth_fill(toast, aa), ink)
    crumb = np.minimum(sd_ellipse(x, y, tx, cy + 0.033 * k, 0.054 * k, 0.033 * k),
                       np.maximum(np.abs(x - tx) - 0.042 * k, np.abs(y - (cy - 0.006 * k)) - 0.034 * k))
    blend(img, smooth_fill(crumb, aa), hexc(P["kraft"]) * 1.06)
    # folded bottom band and vertical crease shading
    blend(img, np.clip((0.06 - y) / 0.01, 0, 1), hexc(P["kraft_dark"]), 0.5)
    crease = value_noise(u * 0.999, v * 0.1, 9, 5)
    img *= (0.97 + 0.06 * crease)[..., None]
    return img


def build_atlas(P, mouth, eyes="dot"):
    canvas = np.zeros((TEX, TEX, 3))
    for rect, fn in ((R_HEAD, lambda: paint_head(P, mouth, eyes)), (R_BODY, lambda: paint_body(P)),
                     (R_ARM, lambda: paint_arm(P)), (R_TAIL, lambda: paint_tail(P)),
                     (R_BAGU, lambda: paint_baguette(P)), (R_BAGF, lambda: paint_bag_front(P))):
        x0, y0, x1, y1 = rect
        canvas[y0:y1, x0:x1] = fn()
    for i, name in enumerate(SWATCHES):
        x = SWATCH_ORIGIN[0] + (i % 4) * 64; y = SWATCH_ORIGIN[1] + (i // 4) * 64
        canvas[y:y + 64, x:x + 64] = hexc(P[name])
    canvas = np.clip(canvas, 0, 1)
    rgba = np.concatenate([canvas, np.ones((TEX, TEX, 1))], axis=2)
    img = bpy.data.images.new("bread_cat_atlas", TEX, TEX, alpha=False)
    img.pixels.foreach_set(rgba.astype(np.float32).ravel())
    return img


# --------------------------------------------------------------------------------------------
# Geometry helpers
# --------------------------------------------------------------------------------------------

def new_bm():
    bm = bmesh.new()
    bm.loops.layers.uv.new("UVMap")
    return bm


def add_face(bm, verts, uvs):
    try:
        f = bm.faces.new(verts)
    except ValueError:
        return None
    uvl = bm.loops.layers.uv.active
    for loop, uv in zip(f.loops, uvs):
        loop[uvl].uv = uv
    return f


def build_sphere(bm, point_fn, uv_fn, segs, rings, lat_min=-math.pi / 2):
    """Lat/long sphere; point_fn(dir)->Vector, uv_fn(u,v)->(s,t) with u,v in 0..1."""
    rows = []
    lats = [lat_min + (math.pi / 2 - lat_min) * i / rings for i in range(rings + 1)]
    for i, lat in enumerate(lats):
        row = []
        if i == 0 and lat_min <= -math.pi / 2 + 1e-6 or i == rings:
            row = [bm.verts.new(point_fn(sph_dir(0.0, lat)))] * (segs + 1)
        else:
            for j in range(segs):
                lon = (j / segs - 0.5) * 2 * math.pi
                row.append(bm.verts.new(point_fn(sph_dir(lon, lat))))
            row.append(row[0])
        rows.append((row, (lat - (-math.pi / 2)) / math.pi))
    for i in range(rings):
        (ra, va), (rb, vb) = rows[i], rows[i + 1]
        for j in range(segs):
            u0, u1 = j / segs, (j + 1) / segs
            a, b, c, d = ra[j], ra[j + 1], rb[j + 1], rb[j]
            if a is b:  # bottom pole
                add_face(bm, [a, c, d], [uv_fn((u0 + u1) / 2, va), uv_fn(u1, vb), uv_fn(u0, vb)])
            elif c is d:  # top pole
                add_face(bm, [a, b, c], [uv_fn(u0, va), uv_fn(u1, va), uv_fn((u0 + u1) / 2, vb)])
            else:
                add_face(bm, [a, b, c, d], [uv_fn(u0, va), uv_fn(u1, va), uv_fn(u1, vb), uv_fn(u0, vb)])
    if lat_min > -math.pi / 2 + 1e-6:  # cap the open bottom (hidden inside the body)
        row, v0 = rows[0][0], rows[0][1]
        center = bm.verts.new(sum((v.co for v in row[:-1]), Vector()) / segs)
        for j in range(segs):  # the ring's own UVs (no extra seam vertices), the centre one UV
            add_face(bm, [row[j + 1], row[j], center], [uv_fn((j + 1) / segs, v0), uv_fn(j / segs, v0), uv_fn(0.5, v0)])


def frames_along(points, up_hint):
    """Parallel-transport frames (tangent, normal, binormal) along a polyline."""
    n = len(points)
    tangents = []
    for i in range(n):
        a = points[max(i - 1, 0)]; b = points[min(i + 1, n - 1)]
        tangents.append((b - a).normalized())
    normal = (up_hint - tangents[0] * up_hint.dot(tangents[0])).normalized()
    frames = []
    for i in range(n):
        t = tangents[i]
        normal = (normal - t * normal.dot(t)).normalized()
        frames.append((t, normal, t.cross(normal)))
    return frames


def build_tube(bm, points, radii, segs, uv_fn, up_hint=Vector((0, 0, 1)), squash=1.0, cap_start=True, cap_end=True,
               v_range=(0.0, 1.0)):
    """Tube through points. Ring angle 0 points along up_hint (u = 0 is the top)."""
    frames = frames_along(points, up_hint)
    n = len(points)
    rings = []
    for i, (p, r, (t, nrm, bin_)) in enumerate(zip(points, radii, frames)):
        row = []
        for j in range(segs):
            a = 2 * math.pi * j / segs
            off = nrm * (math.cos(a) * r) + bin_ * (math.sin(a) * r * squash)
            row.append(bm.verts.new(p + off))
        row.append(row[0])
        rings.append(row)
    vs = [v_range[0] + (v_range[1] - v_range[0]) * i / (n - 1) for i in range(n)]
    for i in range(n - 1):
        for j in range(segs):
            u0, u1 = j / segs, (j + 1) / segs
            add_face(bm, [rings[i][j], rings[i][j + 1], rings[i + 1][j + 1], rings[i + 1][j]],
                     [uv_fn(u0, vs[i]), uv_fn(u1, vs[i]), uv_fn(u1, vs[i + 1]), uv_fn(u0, vs[i + 1])])
    for cap, idx, sign in ((cap_start, 0, -1), (cap_end, n - 1, 1)):
        if not cap:
            continue
        t = frames[idx][0]
        tip = bm.verts.new(points[idx] + t * sign * radii[idx] * 0.35)
        row = rings[idx]
        for j in range(segs):  # the ring's own UVs and one for the tip: no extra seam vertices
            uv0, uv1, uvt = uv_fn(j / segs, vs[idx]), uv_fn((j + 1) / segs, vs[idx]), uv_fn(0.5, vs[idx])
            if sign > 0:
                add_face(bm, [row[j], row[j + 1], tip], [uv0, uv1, uvt])
            else:
                add_face(bm, [row[j + 1], row[j], tip], [uv1, uv0, uvt])
    return frames


def bezier(p0, p1, p2, p3, n):
    pts = []
    for i in range(n):
        t = i / (n - 1)
        pts.append(p0 * (1 - t) ** 3 + p1 * 3 * t * (1 - t) ** 2 + p2 * 3 * t * t * (1 - t) + p3 * t ** 3)
    return pts


# --------------------------------------------------------------------------------------------
# Parts
# --------------------------------------------------------------------------------------------

ES = 14  # ear ring segments


def make_head(bm):
    # The silhouette needs the segments (36 x 22 rings, 6.8 deg apart); the chin below -60 deg sits
    # inside the body, so the sphere stops there with a hidden cap (vertex budget: the app's cat
    # draws <= 3500 vertices).
    build_sphere(bm, head_point, lambda u, v: region_uv(R_HEAD, u, v), segs=36, rings=22, lat_min=math.radians(-60))
    pink = swatch_uv("pink"); fur = swatch_uv("fur")
    for side in (-1, 1):
        base_d = sph_dir(side * 0.60, 0.88)
        base = head_point(base_d) - Vector((0, 0, 0.02))
        up = Vector((side * 0.42, 0.10, 1.0)).normalized()
        fwd = Vector((0, -1, 0)); fwd = (fwd - up * fwd.dot(up)).normalized()
        side_ax = up.cross(fwd)
        # rounded tip: the last rings close in like a quarter circle instead of a cone point
        # (the first ring is sunk in the head)
        prof = [(-0.30, 1.0), (0.0, 1.0), (0.2, 0.97), (0.40, 0.90), (0.55, 0.80), (0.68, 0.68), (0.78, 0.56),
                (0.86, 0.45), (0.92, 0.35), (0.96, 0.25), (0.985, 0.15)]

        def ear(scale_w, scale_d, height, push, uv):
            rings = []
            for t, s in prof:
                row = []
                for j in range(ES):
                    a = 2 * math.pi * j / ES
                    p = base + up * (t * height) + side_ax * (math.cos(a) * 0.105 * s * scale_w) \
                        + fwd * (math.sin(a) * 0.050 * s * scale_d + push)
                    if t < 0:  # keep the sunk root ring inside the head (no ledge pokes out)
                        q = p - HEAD_C
                        k = Vector((q.x / (HEAD_R * HEAD_SX), q.y / (HEAD_R * HEAD_SY * (0.93 if q.y < 0 else 1.0)),
                                    q.z / (HEAD_R * HEAD_SZ))).length
                        p = HEAD_C + q * min(1.0, 0.94 / k)
                    row.append(bm.verts.new(p))
                rings.append(row)
            tip = bm.verts.new(base + up * height * 0.995 + fwd * push)
            for i in range(len(rings) - 1):
                for j in range(ES):
                    k = (j + 1) % ES
                    add_face(bm, [rings[i][j], rings[i][k], rings[i + 1][k], rings[i + 1][j]], [uv] * 4)
            for j in range(ES):
                add_face(bm, [rings[-1][j], rings[-1][(j + 1) % ES], tip], [uv] * 3)
            # bottom cap (hidden inside head, keeps the mesh closed)
            c = bm.verts.new(sum((v.co for v in rings[0]), Vector()) / ES)
            for j in range(ES):
                add_face(bm, [rings[0][(j + 1) % ES], rings[0][j], c], [uv] * 3)

        ear(1.0, 1.0, 0.130, 0.0, fur)
        # the pink inner ear only just shows through the front of the ear and its middle stays inside
        # it, so the outline hull of the pink shell stays hidden (no line round the pink)
        ear(0.70, 0.65, 0.092, 0.024, pink)


def make_body(bm):
    def pt(d):
        return BODY_C + Vector((d.x * BODY_R.x, d.y * BODY_R.y, d.z * BODY_R.z))
    build_sphere(bm, pt, lambda u, v: region_uv(R_BODY, u, v), segs=12, rings=8)  # mostly inside the bag


ARM_UP = Vector((0, 0, 1))


def arm_points(side):
    s = side
    p0 = Vector((s * 0.140, -0.03, 0.66))
    p1 = Vector((s * 0.150, -0.15, 0.775))
    p2 = Vector((s * 0.140, -0.235, 0.775))
    p3 = Vector((s * 0.135, -0.265, 0.735))
    return bezier(p0, p1, p2, p3, 9)


def make_arm(bm, side):
    pts = arm_points(side)
    n = len(pts)
    radii = []
    for i in range(n):
        t = i / (n - 1)
        r = 0.047 - 0.006 * t + 0.022 * math.exp(-((t - 0.86) / 0.13) ** 2)
        if t > 0.95:
            r *= 0.85
        radii.append(r)
    build_tube(bm, pts, radii, 16, lambda u, v: region_uv(R_ARM, u, v), up_hint=ARM_UP, squash=1.12)  # round paws
    return pts


def tail_points():
    p0 = Vector((-0.08, 0.12, 0.55))
    a = bezier(p0, Vector((-0.14, 0.20, 0.80)), Vector((-0.24, 0.30, 0.78)), Vector((-0.30, 0.34, 0.80)), 9)
    b = bezier(a[-1], Vector((-0.36, 0.38, 0.84)), Vector((-0.38, 0.38, 0.98)), Vector((-0.31, 0.34, 1.06)), 9)
    return a, b


def make_tail(bm1, bm2):
    a, b = tail_points()
    uv = lambda u, v: region_uv(R_TAIL, u, v)
    ra = [0.050 - 0.004 * i / (len(a) - 1) for i in range(len(a))]
    rb = [0.046 - 0.008 * (i / (len(b) - 1)) ** 2 for i in range(len(b))]
    build_tube(bm1, a, ra, 10, uv, cap_start=True, cap_end=True, v_range=(0.0, 0.5),
               up_hint=Vector((0, -1, 0)))
    build_tube(bm2, b, rb, 10, uv, cap_start=True, cap_end=True, v_range=(0.5, 1.0),
               up_hint=Vector((0, -1, 0)))
    return a, b


def make_baguette(bm):
    base = Vector((0.0, 0.10, 0.12))
    axis = Vector((0.45, 0.10, 1.0)).normalized()
    L, R = 1.0, 0.064
    n = 12
    pts, radii = [], []
    bend = Vector((0.0, -0.025, 0.0))
    for i in range(n):
        t = i / (n - 1)
        pts.append(base + axis * (L * t) + bend * math.sin(math.pi * t))
        k = abs(2 * t - 1)
        radii.append(R * max(0.15, (1 - k ** 5)) ** 0.5)
    up = Vector((-0.6, -1.0, 0.25)).normalized()  # scores face the viewer/top
    build_tube(bm, pts, radii, 10, lambda u, v: region_uv(R_BAGU, u, v), up_hint=up, squash=0.85)
    return base


# The zigzag top is real geometry: every column of the rim is a tooth peak or valley (7 teeth across
# the front, 5 on each side, a peak on each corner), so the cut edge is a clean line at any
# resolution. The corners are crisp with smooth normals (no hard edges, see mesh_object) because a
# bevel column sits BAG_BEVEL from each corner; it lies on a tooth's straight flank.
BAG_TEETH = {"front": 7, "side": 5}
BAG_TOOTH_H = 0.024
BAG_BEVEL = 0.010   # m


def bag_panel_us(panel):
    n = 2 * BAG_TEETH["front" if panel in ("front", "back") else "side"]
    w = BAG_W1 if panel in ("front", "back") else BAG_D1
    b = BAG_BEVEL / w
    return [0.0, b] + [i / n for i in range(1, n)] + [1.0 - b], n


def bag_ring(t):
    """Perimeter points of the bag cross-section at height fraction t (0 bottom, 1 top).
    Returns list of (x, y, panel, panel_u, columns) going around: front(-Y) left->right, right side,
    back, left side."""
    w = BAG_W0 + (BAG_W1 - BAG_W0) * t
    d = BAG_D0 + (BAG_D1 - BAG_D0) * t
    pts = []
    for panel, at in (("front", lambda u: (-w / 2 + w * u, -d / 2)), ("right", lambda u: (w / 2, -d / 2 + d * u)),
                      ("back", lambda u: (w / 2 - w * u, d / 2)), ("left", lambda u: (-w / 2, d / 2 - d * u))):
        us, n = bag_panel_us(panel)
        for u in us:
            pts.append(at(u) + (panel, u, n))
    return pts


def bag_top_z(u, n):
    """Tooth profile along a panel: peaks at even columns (and the corners), valleys at odd ones."""
    ph = (u * n) % 2.0
    return BAG_H - BAG_TOOTH_H * (1.0 - abs(ph - 1.0))


def make_bag(bm):
    rows_t = [0.0, 0.02, 0.07, 0.25, 0.45, 0.65, 0.82, 0.93, 0.975, 1.0]
    inner_ri = [0, 5, 6, 7, 9]   # the inside wall only needs rows where it shows (near the top)
    rng = np.random.default_rng(11)
    ring0 = bag_ring(0.0)
    per = len(ring0)
    cols = rng.normal(0, 1, per)
    rows = rng.normal(0, 1, len(rows_t))

    def crease(ri, k):  # mostly per column (vertical creases) plus a little per row
        return cols[k] * 0.8 + rows[ri] * 0.4
    kraft = swatch_uv("kraft"); inner = swatch_uv("kraft_in")

    def displaced(t, ri, k, item, inward):
        x, y, panel, pu, n = item
        z = BAG_H * t
        # gusset: side panels fold inward along their middle, more at the top (a rounded fold: a
        # sharp inward V would show the outline hull through the crease)
        if panel in ("left", "right"):
            fold = math.sin(math.pi * pu) * 0.05 * (0.3 + 0.7 * t)
            x -= math.copysign(fold, x)
        # soft wrinkles, fading out towards the corners, the bottom and the rim (no sharp dents)
        corner = min(pu, 1 - pu) * n
        if corner > 0.5:
            amp = 0.007 * min(1.0, t / 0.25) * min(1.0, max(0.0, 1.0 - t) / 0.12)
            nx = 0 if panel in ("front", "back") else math.copysign(1, x)
            ny = math.copysign(1, y) if panel in ("front", "back") else 0
            x += nx * amp * crease(ri, k); y += ny * amp * crease(ri, k)
        if inward:
            x -= math.copysign(0.010, x) if panel in ("left", "right") else 0
            y -= math.copysign(0.010, y) if panel in ("front", "back") else 0
            if panel in ("front", "back"):
                x *= (abs(x) - 0.010) / max(abs(x), 1e-6) if abs(x) > 0.02 else 1
            else:
                y *= (abs(y) - 0.010) / max(abs(y), 1e-6) if abs(y) > 0.02 else 1
        if t >= 1.0:
            z = bag_top_z(pu, n)
        return Vector((x, y, z))

    def uv_for(item, t):
        x, y, panel, pu, n = item
        if panel == "front":
            return region_uv(R_BAGF, pu, t)
        return kraft

    outer, inner_rows = [], []
    for ri, t in enumerate(rows_t):
        ring = bag_ring(t)
        outer.append([(bm.verts.new(displaced(t, ri, k, item, False)), item) for k, item in enumerate(ring)])
        if ri in inner_ri:
            irow = []
            for k, item in enumerate(ring):
                pi = displaced(t, ri, k, item, True)
                if ri == 0:
                    pi.z = 0.012
                irow.append(bm.verts.new(pi))
            inner_rows.append(irow)

    for ri in range(len(rows_t) - 1):
        ta, tb = rows_t[ri], rows_t[ri + 1]
        for k in range(per):
            k2 = (k + 1) % per
            a, ia = outer[ri][k]; b, ib = outer[ri][k2]
            c, ic = outer[ri + 1][k2]; d, id_ = outer[ri + 1][k]
            if ia[2] == "front":
                uvs = [uv_for(ia, ta),
                       region_uv(R_BAGF, 1.0, ta) if ib[2] != "front" else uv_for(ib, ta),
                       region_uv(R_BAGF, 1.0, tb) if ic[2] != "front" else uv_for(ic, tb),
                       uv_for(id_, tb)]
            else:
                uvs = [kraft] * 4
            add_face(bm, [a, b, c, d], uvs)
    for i in range(len(inner_rows) - 1):  # inner wall, reversed winding
        ra, rb = inner_rows[i], inner_rows[i + 1]
        for k in range(per):
            k2 = (k + 1) % per
            add_face(bm, [rb[k], rb[k2], ra[k2], ra[k]], [inner] * 4)
    # zigzag rim
    top = outer[-1]
    for k in range(per):
        k2 = (k + 1) % per
        add_face(bm, [top[k][0], top[k2][0], inner_rows[-1][k2], inner_rows[-1][k]], [kraft] * 4)
    # bottoms
    for ring, flip, uv in (([v for v, _ in outer[0]], True, kraft), (inner_rows[0], False, inner)):
        c = bm.verts.new(sum((v.co for v in ring), Vector()) / len(ring))
        for k in range(per):
            vs = [ring[(k + 1) % per], ring[k], c] if flip else [ring[k], ring[(k + 1) % per], c]
            add_face(bm, vs, [uv] * 3)


# --------------------------------------------------------------------------------------------
# Scene assembly
# --------------------------------------------------------------------------------------------

def make_material(img):
    mat = bpy.data.materials.new("BreadCat")
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


SCALE = 1.085  # parts are authored ~1.29 m tall; scaled so the whole character is ~1.4 m


def mesh_object(name, bm, pivot_world, parent, parent_pivot, mat):
    """Mesh contract (outline): every part is a closed shell with outward faces and smooth shading
    only (no sharp edges), so all glTF vertices at one position (UV-seam copies) carry the same
    normal. An inverted-hull outline that grows the mesh along NORMAL then stays watertight."""
    bmesh.ops.translate(bm, verts=bm.verts, vec=-pivot_world)
    bmesh.ops.scale(bm, verts=bm.verts, vec=(SCALE, SCALE, SCALE))
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-6)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    me.materials.append(mat)
    me.shade_smooth()
    ob = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(ob)
    ob.parent = parent
    ob.location = (pivot_world - parent_pivot) * SCALE
    return ob


def empty(name, loc_world, parent, parent_pivot, size=0.03):
    ob = bpy.data.objects.new(name, None)
    ob.empty_display_size = size
    bpy.context.scene.collection.objects.link(ob)
    ob.parent = parent
    ob.location = (loc_world - parent_pivot) * SCALE
    return ob


def build(mouth="omega", palette="cheese", eyes="dot"):
    P = PALETTES[palette]
    img = build_atlas(P, mouth, eyes)
    mat = make_material(img)
    origin = Vector((0, 0, 0))
    root = empty("BreadCat", origin, None, origin, 0.2)

    bm = new_bm(); make_bag(bm)
    mesh_object("Bag", bm, origin, root, origin, mat)

    bm = new_bm(); bag_base = make_baguette(bm)
    mesh_object("Baguette", bm, bag_base, root, origin, mat)

    bm = new_bm(); make_body(bm)
    body = mesh_object("Body", bm, HIPS, root, origin, mat)

    bm = new_bm(); make_head(bm)
    mesh_object("Head", bm, NECK, body, HIPS, mat)

    for side, nm in ((1, "L"), (-1, "R")):
        bm = new_bm(); pts = make_arm(bm, side)
        shoulder = pts[0]
        arm = mesh_object("Arm" + nm, bm, shoulder, body, HIPS, mat)
        paw = pts[-2] + Vector((0, -0.015, 0.0))
        empty("Hand" + nm, paw, arm, shoulder)

    bm1, bm2 = new_bm(), new_bm()
    a, b = make_tail(bm1, bm2)
    tail = mesh_object("Tail", bm1, a[0], body, HIPS, mat)
    tail2 = mesh_object("Tail2", bm2, b[0], tail, a[0], mat)
    empty("TailTip", b[-1], tail2, b[0])
    return root, img


def export_glb(path):
    os.makedirs(os.path.dirname(os.path.abspath(path)), exist_ok=True)
    bpy.ops.export_scene.gltf(
        filepath=path, export_format="GLB", use_selection=False, export_yup=True,
        export_apply=False, export_texcoords=True, export_normals=True, export_materials="EXPORT",
        export_image_format="AUTO", export_cameras=False, export_lights=False, export_extras=False,
        export_animations=False,
    )


def clear_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)


def stats():
    tris = 0; meshes = 0
    deps = bpy.context.evaluated_depsgraph_get()
    for ob in bpy.context.scene.objects:
        if ob.type == "MESH":
            meshes += 1
            me = ob.evaluated_get(deps).to_mesh()
            me.calc_loop_triangles()
            tris += len(me.loop_triangles)
    zs = [(ob.matrix_world @ v.co) for ob in bpy.context.scene.objects if ob.type == "MESH" for v in ob.data.vertices]
    bounds = [round(min(p[i] for p in zs), 3) for i in range(3)] + [round(max(p[i] for p in zs), 3) for i in range(3)]
    hands = {n: tuple(round(c, 3) for c in bpy.data.objects[n].matrix_world.translation)
             for n in ("HandL", "HandR", "TailTip")}
    pivots = {ob.name: tuple(round(c, 3) for c in ob.matrix_world.translation)
              for ob in bpy.context.scene.objects}
    return dict(bounds_min_max=bounds, hands=hands, pivots=pivots, meshes=meshes, triangles=tris, materials=len([m for m in bpy.data.materials if m.users]),
                nodes=len(bpy.context.scene.objects))


def parse_args():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    opts = {"out": None, "mouth": "omega", "palette": "cheese", "eyes": "dot"}
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
    clear_scene()
    build(opts["mouth"], opts["palette"], opts["eyes"])
    print("BREADCAT_STATS", stats())
    if opts["out"]:
        export_glb(opts["out"])
        print("BREADCAT_EXPORTED", opts["out"])
