"""Puppy (퍼피) — the flag-bearer puppy of the storybook, generated entirely in Blender Python.

Run (headless):
    blender -b --factory-startup -P apps/lab3d/art_src/characters/puppy.py -- \
        [--out apps/lab3d/assets/characters/puppy.glb] [--monocle on|off] [--flag on|off] [--hat on|off]

A golden-tan chibi puppy from the same storybook as the bread cat and Dugi (2026-10-23 user
reference 1792701655210.png, the centre character), standing on its hind legs like Dugi: a big round
head a little wider than the bean body, a cream mask over the muzzle and lower cheeks rising to a
point between the eyes, small dark dot eyes with one highlight dot, a big dark-brown nose on a soft
muzzle bump, a small open smile with a tongue, floppy ears with darker tips, a brown deerstalker
(front and back brims, tied flaps on the crown), a red bow tie, a cream bib, cream feet and paws and
a curly tail with a cream tip. Role (2026-10-24 user decision): Puppy stands at the back holding the
app's flag, a wooden pole with a butter-yellow swallowtail banner reading "과학섬" (the app is
"빵고양이 과학섬"). The text is real Hangul (Noto Sans CJK Bold, laid out by Blender's FreeType and
rasterised here) painted into the atlas,
once for each side of the cloth, so it reads left to right from the front and from behind. The
reference dog's monocle is Dugi's signature item (2026-10-23), so here it is an option
(`--monocle on`: a gold rim on the eye at the viewer's right, a thin chain to the bow tie), default
off. The earlier magnifying glass was dropped (the flag takes its mesh slots). Same style and
conventions as bread_cat.py and dugi.py, whose generic helpers (painting SDFs, bmesh sphere / tube
builders, export) this file imports; geometry, UVs and the single texture atlas are produced here,
nothing depends on a hand-made .blend. Other scripts may `import` it and call `build()` /
`pose_point()` / `pose_flag()` (the preview and trio renders do).

Conventions:
- Units are metres. Height ~1.27 m including the hat (head top ~1.11 m); the flag pole is 1.51 m,
  its top ~1.55 m above the ground at rest. Origin = between the feet on the ground.
- Blender: +Z up, the puppy faces -Y; glTF/Godot: +Y up, faces +Z (MODEL_FRONT), left side = +X.
- Node tree (no armature; animate by rotating nodes, each origin is its pivot):
    Puppy                   (empty, origin on the ground between the feet)
      Body                  (mesh: body, feet, curly tail, bow tie; pivot on the ground -> lean / bob)
        Head                (mesh incl. the hat and the optional monocle chain, pivot at the neck -> nod / tilt)
          EarL / EarR       (mesh, pivot at the ear root -> flop / wiggle)
        ArmL / ArmR         (one-segment arm mesh incl. the paw, pivot at the shoulder; L = the puppy's left = +X)
          HandL / HandR     (empty at the paw centre: grip point)
          Flag              (ArmR only, optional: the pole with its gold knob, pivot in the paw -> raise / sway)
            FlagCloth       (the banner, a thin closed slab with a baked gentle wave; pivot at the
                             pole top where the cloth's upper corner is tied -> flutter about the pole)
- Rest pose (arm variant A, 2026-10-24 user decision) = standing, both arms attached at the body's
  sides right under the head and hanging down, paws by the hips, the right paw gripping the pole,
  which leans out 13 deg (base by the right foot, behind the floppy ear, clear of the head) with the
  banner flying away from the puppy (toward the viewer's left). To raise the flag, `pose_flag()`
  swings ArmR about the shoulder so the paw heads for one target and turns the Flag about the paw
  so the pole top heads for another (two `pose_point()`s).
- The tail is part of Body (no wag): the flag needs two of the eight mesh slots.
- Budget (SM-P200 low): 8 meshes, 1 material, 1 texture (1024 px), < 6000 triangles: the segments
  go to the silhouette (head ring 36 x 22, ears, paws, hat crown), hidden parts stay coarse (head
  below -62 deg, body underside, the hat's bottom inside the head).
- Outline mesh contract (same as bread_cat.py): closed shells, outward faces, smooth shading only,
  so every glTF vertex at one position has the same NORMAL and an inverted hull grown along NORMAL
  (VERTEX += NORMAL * width, cull_front) has no cracks along the UV seams. The banner is a 1.2 cm
  slab whose front, back and rim share vertices (different UVs only); its outermost grid rows are
  narrow margins, so the averaged rim normals bend the shading only there, not under the text.
"""

import math
import os
import sys

sys.dont_write_bytecode = True  # importing the shared helpers must not write into the source tree

import bmesh  # noqa: E402
import bpy  # noqa: E402
import numpy as np  # noqa: E402
from mathutils import Matrix, Quaternion, Vector  # noqa: E402

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import bread_cat as bc  # noqa: E402  (generic helpers only; no cat geometry is built)
from bread_cat import (add_face, blend, build_sphere, build_tube, hexc, new_bm, paint_volume,  # noqa: E402
                       sd_ellipse, sd_segment, sd_triangle, smooth_fill, sph_dir)
import face_kit as fk  # noqa: E402  (portrait expressions only)

TEX = 1024
PAD = 3

P = dict(
    # storybook pastel (2026-10-23 user reference): golden tan, cream mask / bib / paws, darker ear tips
    fur="#e3aa68", fur_shade="#d29a5a", ear_tip="#b97b45", cream="#fff4e2", blush="#ff9e9a",
    eye="#2a1a14", nose="#4a2a1c", mouth="#6b3424", tongue="#ff7f8c",
    hat="#9a6440", hat_dark="#7a4a2e", hat_seam="#6e4630",
    bow="#e2493b", bow_dark="#b9342c", frame="#6e4630", gold="#e3b04b",
    # flag: butter yellow (bright against the sky and the grass), brown text like the outline
    pole="#c08a55", cloth="#ffe28a", cloth_trim="#f5b84e", ink="#6b3a1c",
)
FLAG_TEXT = "과학섬"
FONT = ("/usr/share/fonts/opentype/noto/NotoSansCJK-Bold.ttc",)   # Noto Sans CJK Bold (Blender reads its first face)

# Atlas layout (pixels, origin bottom-left like Blender UVs)
R_HEAD = (0, 512, 1024, 1024)
R_EAR = (0, 256, 256, 512)
R_TAIL = (256, 256, 512, 512)
R_BODY = (512, 256, 768, 512)
R_FLAG_B = (768, 256, 1024, 512)   # banner, back side (seen from behind)
R_HAT = (0, 0, 256, 256)
R_FLAG_F = (256, 0, 768, 256)      # banner, front side
SWATCH_ORIGIN = (768, 0)  # 4 x 4 swatches of 64 px
SWATCHES = ["fur", "cream", "hat", "hat_dark", "bow", "bow_dark", "frame", "gold", "nose", "pole", "cloth"]


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

# Proportions read off the reference puppy: the round head about as wide as the sitting body and
# almost half the height; the hat adds a crown on top.
HEAD_R = 0.300
HEAD_SX, HEAD_SY, HEAD_SZ = 1.12, 0.96, 0.98   # round mochi face, a little wider than tall
HEAD_C = Vector((0.0, -0.02, 0.815))
NECK = Vector((0.0, 0.0, 0.560))
BODY_C = Vector((0.0, 0.015, 0.300))
BODY_R = Vector((0.240, 0.215, 0.280))
# small, simple dot eyes (user: "눈도 너무 초롱초롱해"): a slightly tall bean, one small highlight
EYE_X, EYE_Z, EYE_RX, EYE_RZ = 0.118, -0.020, 0.025, 0.030
MONO_X, MONO_R = 0.118, 0.054   # optional monocle on the +X eye (the viewer's right), like the reference
NOSE_Z = -0.078
MUZZLE = (0.0, -0.105, 0.105, 0.080, 0.034)   # bump centre (x, z), half-sizes, height (m)


def head_point(d):
    x, y, z = d
    p = Vector((x * HEAD_R * HEAD_SX, y * HEAD_R * HEAD_SY * (0.92 if y < 0 else 1.0), z * HEAD_R * HEAD_SZ))
    if y < 0:  # a soft muzzle bump pushed straight forward (keeps the painted front projection exact)
        mx, mz, ax, az, h = MUZZLE
        p.y -= h * math.exp(-((p.x - mx) / ax) ** 2 - ((p.z - mz) / az) ** 2) * min(1.0, -y * 3)
    return HEAD_C + p


def face_dir(qx, qz):
    """Head direction whose painted face coordinate is (qx, qz) metres (inverse of paint_head's map)."""
    dx = qx / (HEAD_R * HEAD_SX)
    dz = qz / (HEAD_R * HEAD_SZ)
    return Vector((dx, -math.sqrt(max(0.0, 1 - dx * dx - dz * dz)), dz))


def body_point(d):
    lower = max(0.0, -d.z)
    upper = max(0.0, d.z)
    w = 1.0 + 0.12 * lower - 0.10 * upper ** 2   # soft standing bean, a little fuller low
    return BODY_C + Vector((d.x * BODY_R.x * w, d.y * BODY_R.y * w, d.z * BODY_R.z))


# --------------------------------------------------------------------------------------------
# Texture painting (numpy, sRGB)
# --------------------------------------------------------------------------------------------

def paint_head(monocle=False, face=None):
    """face (portraits only, face_kit): an expression; None paints the model's own face."""
    face = face or {}
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
    # cream mask: muzzle, lower cheeks and chin, rising to a soft point between the eyes
    mask = np.minimum(sd_ellipse(qx, qz, 0.0, -0.120, 0.118, 0.085),
                      np.minimum(sd_ellipse(qx, qz, -0.120, -0.150, 0.120, 0.085),
                                 sd_ellipse(qx, qz, 0.120, -0.150, 0.120, 0.085)))
    mask = np.minimum(mask, sd_ellipse(qx, qz, 0.0, -0.050, 0.030, 0.062))
    mask = np.minimum(mask, qz + 0.20)   # all of the chin
    blend(img, smooth_fill(mask, 0.004) * front, hexc(P["cream"]))
    blend(img, smooth_fill(qz + 0.16, 0.02) * (dy < 0.4), hexc(P["cream"]))   # under the chin
    # painted volume (soft warm shading low on the face and under the snout, a brighter snout)
    paint_volume(img, qx, qz, front, HEAD_R * HEAD_SX, HEAD_R * HEAD_SZ, (0.0, -0.110), (0.110, 0.075),
                 hexc("#fffbf3"), (0.94, 0.84, 0.78))
    bk = float(face.get("blush", 1.0))
    for s in (-1, 1):  # blush ovals, outside and below the eyes
        blend(img, smooth_fill(sd_ellipse(qx, qz, s * 0.190, -0.085, 0.040 * bk ** 0.5, 0.024 * bk ** 0.5), 0.012) * front,
              hexc(P["blush"]), min(1.0, 0.7 * bk))
    if face.get("eyes", "dot") != "dot":
        fk.eyes(img, qx, qz, front, aa, EYE_X, EYE_Z, EYE_RX, EYE_RZ, face["eyes"], hexc(P["eye"]))
    else:
        for s in (-1, 1):  # small dark bean eyes with one small highlight dot
            ex, ez = s * EYE_X, EYE_Z
            blend(img, smooth_fill(sd_ellipse(qx, qz, ex, ez, EYE_RX, EYE_RZ), aa) * front, hexc(P["eye"]))
            blend(img, smooth_fill(sd_ellipse(qx, qz, ex - 0.008, ez + 0.010, 0.0080, 0.0085), aa) * front, np.ones(3))
    fk.brows(img, qx, qz, front, aa, EYE_X, EYE_Z + 0.058, face.get("brows"), hexc(P["ear_tip"]) * 0.75)
    if monocle:
        mx, mz, rr = MONO_X, EYE_Z, MONO_R
        d = np.sqrt((qx - mx) ** 2 + (qz - mz) ** 2)
        blend(img, smooth_fill(d - rr, 0.002) * front, np.ones(3), 0.22)                 # lens tint
        glint = sd_segment(qx, qz, mx - 0.030, mz + 0.012, mx - 0.012, mz + 0.032) - 0.0035
        blend(img, smooth_fill(glint, 0.002) * front, np.ones(3), 0.9)
        blend(img, smooth_fill(np.abs(d - rr) - 0.0085, 0.002) * front, hexc(P["frame"]))  # brown edge
        blend(img, smooth_fill(np.abs(d - rr) - 0.0050, 0.002) * front, hexc(P["gold"]))   # gold rim
    nz = NOSE_Z  # big dark-brown nose: a soft rounded triangle with one shine
    nose = sd_triangle(qx, qz, (-0.026, nz + 0.012), (0.026, nz + 0.012), (0.0, nz - 0.014)) - 0.007
    blend(img, smooth_fill(nose, aa) * front, hexc(P["nose"]))
    blend(img, smooth_fill(sd_ellipse(qx, qz, -0.010, nz + 0.010, 0.009, 0.005), aa) * front, np.ones(3), 0.85)
    mcol = hexc(P["mouth"]); stroke = 0.0040
    sdf = sd_segment(qx, qz, 0.0, nz - 0.018, 0.0, nz - 0.030) - stroke * 0.8
    if face.get("mouth", "open") != "open":   # a portrait expression's mouth (face_kit)
        fk.mouth(img, qx, qz, front, aa, nz - 0.030, face["mouth"], mcol, hexc(P["tongue"]), sdf, 0.92)
        return img
    cz = nz - 0.030   # small open smile with a pink tongue, the corners curling up
    half = np.where(qz < cz, sd_ellipse(qx, qz, 0.0, cz, 0.040, 0.044), 1.0)
    for s in (-1, 1):
        cx, r = s * 0.040, 0.012
        ring = np.abs(np.sqrt((qx - cx - s * 0.004) ** 2 + (qz - cz - 0.006) ** 2) - r) - stroke * 0.8
        sdf = np.minimum(sdf, np.where((s * (qx - cx) > -0.002) & (qz < cz + 0.012), ring, 1.0))
    blend(img, smooth_fill(np.minimum(sdf, half), aa) * front, mcol)
    tongue = np.maximum(sd_ellipse(qx, qz, 0.0, cz - 0.040, 0.026, 0.022), half + 0.003)
    blend(img, smooth_fill(tongue, aa) * front, hexc(P["tongue"]))
    return img


def paint_ear():
    """u = around the ear section, v = root (0) -> tip (1): the tip a darker brown."""
    u, v = region_grid(R_EAR)
    img = np.zeros(u.shape + (3,)); img[...] = hexc(P["fur"])
    blend(img, np.clip((v - 0.50) / 0.18, 0, 1), hexc(P["ear_tip"]))
    return img


def paint_tail():
    """u = around, v = root (0) -> tip (1): a cream tip."""
    u, v = region_grid(R_TAIL)
    img = np.zeros(u.shape + (3,)); img[...] = hexc(P["fur"])
    blend(img, smooth_fill(0.74 - v, 0.04), hexc(P["cream"]))
    return img


def paint_body():
    u, v = region_grid(R_BODY)
    lon = (u - 0.5) * 2 * math.pi
    lat = (v - 0.5) * math.pi
    dy = -np.cos(lon) * np.cos(lat)
    img = np.zeros(u.shape + (3,)); img[...] = hexc(P["fur"])
    blend(img, np.clip((dy + 0.2) * 0.8, 0, 1), hexc(P["fur_shade"]), 0.4)
    # cream bib and tummy down the front, widest at the chest
    bib = sd_ellipse(lon, lat, 0.0, 0.25, 0.80, 1.25)
    blend(img, smooth_fill(bib * 0.3, 0.02), hexc(P["cream"]))
    return img


def paint_hat():
    """Deerstalker crown: u = longitude (front centre 0.5), v = latitude; six panels with brown seams."""
    u, v = region_grid(R_HAT)
    lon = (u - 0.5) * 2 * math.pi
    lat = (v - 0.5) * math.pi
    img = np.zeros(u.shape + (3,)); img[...] = hexc(P["hat"])
    blend(img, np.clip((0.15 - lat) / 0.4, 0, 1), hexc(P["hat_dark"]), 0.35)
    seam = np.abs(np.sin(3 * (lon + math.pi / 6))) * np.cos(lat) - 0.045
    blend(img, smooth_fill(seam, 0.02) * (lat < 1.35), hexc(P["hat_seam"]), 0.9)
    return img


def _box_blur(a, r, axis):
    """Box blur of radius r (pixels) along one axis, via a cumulative sum."""
    if r < 1:
        return a
    pad = [(0, 0)] * a.ndim; pad[axis] = (r + 1, r)
    c = np.cumsum(np.pad(a, pad, mode="edge"), axis=axis)
    n = a.shape[axis]
    hi = np.take(c, np.arange(2 * r + 1, 2 * r + 1 + n), axis=axis)
    lo = np.take(c, np.arange(0, n), axis=axis)
    return (hi - lo) / (2 * r + 1)


def text_mask(text, w, h, cx, height=0.56, ss=3):
    """Coverage mask (h x w, rows bottom-up like the atlas) of `text` set in FONT, centred at
    (cx * w, h / 2) with the glyphs `height` of the region tall. Blender's own FreeType lays out the
    glyphs (a temporary text curve, removed again); its triangles are rasterised here with ss x ss
    supersampling, so no image library is needed inside Blender."""
    font = bpy.data.fonts.load(FONT[0], check_existing=True)
    cu = bpy.data.curves.new("flag_text", "FONT")
    cu.body = text; cu.font = font; cu.align_x = "CENTER"
    ob = bpy.data.objects.new("flag_text", cu)
    bpy.context.scene.collection.objects.link(ob)
    deps = bpy.context.evaluated_depsgraph_get()
    me = ob.evaluated_get(deps).to_mesh()
    me.calc_loop_triangles()
    co = np.array([v.co[:2] for v in me.vertices])
    tris = np.array([t.vertices[:] for t in me.loop_triangles])
    ob.evaluated_get(deps).to_mesh_clear()
    bpy.data.objects.remove(ob); bpy.data.curves.remove(cu); bpy.data.fonts.remove(font)
    W, H = w * ss, h * ss
    lo, hi = co.min(0), co.max(0)
    k = height * H / (hi[1] - lo[1])
    px = (co[:, 0] - (lo[0] + hi[0]) / 2) * k + cx * W
    py = (co[:, 1] - (lo[1] + hi[1]) / 2) * k + 0.5 * H
    m = np.zeros((H, W))
    for a, b, c in tris:
        xs, ys = px[[a, b, c]], py[[a, b, c]]
        x0, x1 = int(max(0, np.floor(xs.min()))), int(min(W - 1, np.ceil(xs.max())))
        y0, y1 = int(max(0, np.floor(ys.min()))), int(min(H - 1, np.ceil(ys.max())))
        if x1 < x0 or y1 < y0:
            continue
        gx, gy = np.meshgrid(np.arange(x0, x1 + 1) + 0.5, np.arange(y0, y1 + 1) + 0.5)
        d = (ys[1] - ys[2]) * (xs[0] - xs[2]) + (xs[2] - xs[1]) * (ys[0] - ys[2])
        if abs(d) < 1e-12:
            continue
        l0 = ((ys[1] - ys[2]) * (gx - xs[2]) + (xs[2] - xs[1]) * (gy - ys[2])) / d
        l1 = ((ys[2] - ys[0]) * (gx - xs[2]) + (xs[0] - xs[2]) * (gy - ys[2])) / d
        inside = (l0 >= 0) & (l1 >= 0) & (l0 + l1 <= 1)
        m[y0:y1 + 1, x0:x1 + 1] = np.maximum(m[y0:y1 + 1, x0:x1 + 1], inside)
    return m.reshape(h, ss, w, ss).mean(axis=(1, 3))


def paint_flag(rect, aspect):
    """Banner side: u = across the cloth as the viewer of this side reads it (left -> right),
    v = bottom (0) -> top (1). Butter yellow with a deeper hem top and bottom; the text in bold
    brown with a soft cream halo, centred on the part of the cloth left of the swallowtail."""
    x0, y0, x1, y1 = rect
    w, h = x1 - x0, y1 - y0
    u, v = region_grid(rect)
    img = np.zeros(u.shape + (3,)); img[...] = hexc(P["cloth"])
    hem = np.minimum(v, 1 - v)
    blend(img, smooth_fill(hem - 0.085, 0.01), hexc(P["cloth_trim"]))
    cx = 0.54 if rect == R_FLAG_F else 0.46   # the notch is at u = 0 on the front, u = 1 on the back
    # the region may be squarer than the cloth: lay the text out in cloth proportions, then squeeze
    tw = int(round(h * aspect))
    m = text_mask(FLAG_TEXT, tw, h, cx, height=0.50)
    xs = (np.arange(w) + 0.5) / w * tw - 0.5
    i0 = np.clip(np.floor(xs).astype(int), 0, tw - 1); i1 = np.clip(i0 + 1, 0, tw - 1); f = xs - np.floor(xs)
    m = m[:, i0] * (1 - f) + m[:, i1] * f
    r = max(1, int(h * 0.018))
    halo = m
    for _ in range(3):
        halo = _box_blur(_box_blur(halo, r, 0), r, 1)
    blend(img, np.clip(halo * 6, 0, 1), hexc(P["cream"]))
    blend(img, m, hexc(P["ink"]))
    return img


def build_atlas(monocle=False, face=None):
    canvas = np.zeros((TEX, TEX, 3)); canvas[...] = hexc(P["fur"])
    for rect, fn in ((R_HEAD, lambda: paint_head(monocle, face)), (R_EAR, paint_ear), (R_TAIL, paint_tail),
                     (R_BODY, paint_body), (R_HAT, paint_hat),
                     (R_FLAG_F, lambda: paint_flag(R_FLAG_F, CLOTH_L / CLOTH_H)),
                     (R_FLAG_B, lambda: paint_flag(R_FLAG_B, CLOTH_L / CLOTH_H))):
        x0, y0, x1, y1 = rect
        canvas[y0:y1, x0:x1] = fn()
    for i, name in enumerate(SWATCHES):
        x = SWATCH_ORIGIN[0] + (i % 4) * 64; y = SWATCH_ORIGIN[1] + (i // 4) * 64
        canvas[y:y + 64, x:x + 64] = hexc(P[name])
    canvas = np.clip(canvas, 0, 1)
    rgba = np.concatenate([canvas, np.ones((TEX, TEX, 1))], axis=2)
    img = bpy.data.images.new("puppy_atlas", TEX, TEX, alpha=False)
    img.pixels.foreach_set(rgba.astype(np.float32).ravel())
    return img


# --------------------------------------------------------------------------------------------
# Parts
# --------------------------------------------------------------------------------------------

def ellipsoid(bm, centre, radii, uv, segs=12, rings=8, rot=None, uv_fn=None):
    def pt(d):
        q = Vector((d.x * radii[0], d.y * radii[1], d.z * radii[2]))
        if rot:
            q = rot @ q
        return centre + q
    build_sphere(bm, pt, uv_fn or (lambda u, v: uv), segs=segs, rings=rings)


def capsule(pts, radii, start=True, end=True):
    """Extend a tube's centre line with quarter-circle rings so its ends are round domes (sausage).
    The dome rings run from the tube end outward (75 -> 30 deg from the axis): dugi.py's copy lists
    them 30 -> 75, so its domes fold back on themselves (hidden there inside the paws / knot)."""
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


# Deerstalker: a six-panel crown over the top of the head, a brim at the front and one at the back,
# the ear flaps tied up on the crown in a little bow.
HAT_C = HEAD_C + Vector((0.0, 0.015, 0.105))
HAT_R = (0.300, 0.285, 0.215)


def hat_point(d):
    return HAT_C + Vector((d.x * HAT_R[0], d.y * HAT_R[1], d.z * HAT_R[2]))


def make_hat(bm):
    # the crown's bottom ring (-12 deg) is inside the head; capped there (hidden)
    build_sphere(bm, hat_point, lambda u, v: region_uv(R_HAT, u, v), segs=32, rings=9, lat_min=math.radians(-12))
    hat, dark = swatch_uv("hat"), swatch_uv("hat_dark")
    for sgn, (y, z, ry, tilt) in ((-1, (-0.240, 0.120, 0.125, 20)), (1, (0.255, 0.130, 0.090, -16))):
        rot = Matrix.Rotation(math.radians(tilt), 3, "X")   # brims droop away from the crown
        ellipsoid(bm, HEAD_C + Vector((0.0, y, z)), (0.175 if sgn < 0 else 0.160, ry, 0.018), hat, 20, 5, rot)
    top = hat_point(Vector((0, 0, 1)))
    ellipsoid(bm, top + Vector((0, 0, 0.010)), (0.024, 0.024, 0.020), dark, 6, 4)
    for s in (-1, 1):  # the tied flaps: two small loops leaning out from the button
        rot = Matrix.Rotation(math.radians(s * -35), 3, "Y")
        ellipsoid(bm, top + Vector((s * 0.040, 0.0, 0.010)), (0.040, 0.016, 0.022), dark, 6, 4, rot)


def make_head(bm, monocle=False, hat=True):
    # The head ring is the silhouette: 36 x 22 rings; below -62 deg the head sits in the body, so the
    # sphere stops there with a hidden cap.
    build_sphere(bm, head_point, lambda u, v: region_uv(R_HEAD, u, v), segs=36, rings=22, lat_min=math.radians(-62))
    if hat:
        make_hat(bm)
    if monocle:
        make_monocle_chain(bm)


BOW_C = Vector((0.0, -0.160, 0.555))   # bow tie knot, under the chin


def make_monocle_chain(bm):
    """The monocle's thin gold chain: from the rim's lower outer edge down over the cheek to the bow
    tie, lying just off the skin (the outline makes it read as a drawn line)."""
    gold = swatch_uv("gold")
    path = [(MONO_X + MONO_R * 0.70, EYE_Z - MONO_R * 0.72), (MONO_X + 0.066, EYE_Z - 0.10),
            (MONO_X + 0.060, EYE_Z - 0.16), (MONO_X + 0.030, EYE_Z - 0.215)]
    pts = []
    for qx, qz in path:
        q = head_point(face_dir(qx, qz))
        pts.append(q + (q - HEAD_C).normalized() * 0.006)
    pts.append(BOW_C + Vector((0.050, -0.020, 0.012)))   # tucked behind the bow's wing
    smooth = [pts[0]]
    for i in range(len(pts) - 1):   # a little sag between the anchor points
        for k in (1, 2):
            t = k / 2
            smooth.append(pts[i].lerp(pts[i + 1], t) + Vector((0, -0.004 * math.sin(math.pi * t), 0)) * (k == 1))
    build_tube(bm, smooth, [0.0026] * len(smooth), 5, lambda u, v: gold, up_hint=Vector((0, -1, 0)))


ES = 12  # ear ring segments
EAR_T = [0.0, 0.08, 0.18, 0.30, 0.42, 0.54, 0.65, 0.75, 0.84, 0.91, 0.96, 0.99]
EAR_W = 0.105
# the root sits in front of the head silhouette (lon < 90 deg), so the head outline passes behind the
# ear instead of showing through it in slivers
EAR_LON, EAR_LAT = 1.02, 0.62


def ear_root(side):
    d = sph_dir(side * EAR_LON, EAR_LAT)
    return head_point(d) - d * 0.050


def ear_path(side):
    """Floppy: out from under the hat's side, a soft bend, the tip hanging down beside the face."""
    b = ear_root(side)
    s = side
    n = sph_dir(side * EAR_LON, EAR_LAT)   # leave the head along its normal (no sliver of the head's outline)
    return (b, b + n * 0.070, b + Vector((s * 0.175, -0.06, 0.010)), b + Vector((s * 0.165, -0.10, -0.140)))


def make_ear(bm, side):
    p0, p1, p2, p3 = ear_path(side)

    def at(t):
        return p0 * (1 - t) ** 3 + p1 * 3 * t * (1 - t) ** 2 + p2 * 3 * t * t * (1 - t) + p3 * t ** 3
    uv = lambda u, v: region_uv(R_EAR, u, v)
    rows = []
    fwd0 = Vector((side * 0.55, -1.0, 0.25)).normalized()  # the broad side faces forward-out
    for t in EAR_T:
        c = at(t)
        tan = (at(min(t + 0.01, 1)) - at(max(t - 0.01, 0))).normalized()
        fwd = (fwd0 - tan * fwd0.dot(tan)).normalized()
        sideax = fwd.cross(tan).normalized()
        # one smooth convex profile, widest past the middle, a round tip (a flare or kink at the root
        # would be a concave crease that the ear's own outline hull shows through)
        w = EAR_W * (0.66 + 0.34 * math.sin(math.pi * t * 0.85)) * math.sqrt(max(0.0, 1 - t ** 4))
        d = 0.40 * w
        row = []
        for j in range(ES):
            a = 2 * math.pi * j / ES
            row.append(bm.verts.new(c + sideax * (math.cos(a) * w) + fwd * (math.sin(a) * d)))
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


def make_bow(bm):
    red, dark = swatch_uv("bow"), swatch_uv("bow_dark")
    for s in (-1, 1):  # two wings flaring out from the knot
        rot = Matrix.Rotation(math.radians(s * 8), 3, "Y")
        ellipsoid(bm, BOW_C + Vector((s * 0.050, 0.004, 0.0)), (0.050, 0.020, 0.036), red, 8, 5, rot)
    ellipsoid(bm, BOW_C + Vector((0.0, -0.010, 0.0)), (0.021, 0.020, 0.024), dark, 6, 4)


def make_body(bm):
    # the underside below -65 deg (between and under the feet) never shows: a hidden cap there
    build_sphere(bm, body_point, lambda u, v: region_uv(R_BODY, u, v), segs=24, rings=12, lat_min=math.radians(-65))
    cream = swatch_uv("cream")
    for s in (-1, 1):  # round cream feet poking out forward
        rot = Matrix.Rotation(s * math.radians(14), 3, "Z")
        ellipsoid(bm, Vector((s * 0.110, -0.085, 0.048)), (0.080, 0.105, 0.052), cream, 12, 7, rot)
    make_bow(bm)
    make_tail(bm)


# Short thick mitten arms, one segment each (user: "관절을 하나 빼란거야"; 2026-10-24 "팔이 너무
# 부자연스러워" -> like the reference: short, thick, the same width down to a round paw, held close to
# the body). SHOULDER / HAND below are the older v2 placement; the default is variant A (arms hanging
# along the sides, set_arm_variant("A") after ARM_VARIANTS); the pole runs through the right paw. The pole stays at the side, behind the
# floppy ear: in front of the chest the big head would hide behind it.
SHOULDER = {1: Vector((0.150, -0.055, 0.455)), -1: Vector((-0.150, -0.055, 0.455))}
HAND = {1: Vector((0.105, -0.210, 0.320)), -1: Vector((-0.270, 0.025, 0.360))}
ARM_R = 0.062
PAW_R = 0.068
# Flag: the pole runs through the right paw, leaning out POLE_TILT so it passes behind the floppy ear
# and clear of the head; the banner hangs from just under the knob and flies away from the puppy.
POLE_TILT = math.radians(13)
POLE_DIR = Vector((-math.sin(POLE_TILT), 0.0, math.cos(POLE_TILT)))
POLE_BASE_Z, POLE_LEN, POLE_R, KNOB_R = 0.030, 1.400, 0.016, 0.030
# Arm placement variants (2026-10-24 user: "팔 위치가 어색해" -> a contact sheet to pick from); the
# arms attach at the body's SIDES right under the head, like the reference. The pole always runs
# through the right paw; the flag pose raises that paw (pose_flag), except in B where both paws hold it.
#   v2: the earlier placement     A: arms hang along the sides, the right paw holds the pole by the hip
#   B: both paws hold the pole in front, the pole leaning out past the right cheek (face clear)
#   C: paws together in front of the tummy at rest     D: short arms angled forward, paws on the belly edge
ARM_VARIANTS = {
    "v2": dict(S=SHOULDER, H=HAND, tilt=13, length=1.40),
    "A": dict(S={1: Vector((0.185, 0.000, 0.465)), -1: Vector((-0.185, 0.000, 0.465))},
              H={1: Vector((0.275, -0.030, 0.285)), -1: Vector((-0.280, 0.020, 0.285))}, tilt=13, length=1.40),
    "B": dict(S={1: Vector((0.165, -0.090, 0.460)), -1: Vector((-0.175, -0.060, 0.460))},
              H={1: None, -1: Vector((-0.105, -0.330, 0.320))}, tilt=20, length=1.50),
    "C": dict(S={1: Vector((0.180, -0.030, 0.465)), -1: Vector((-0.180, -0.030, 0.465))},
              H={1: Vector((0.060, -0.245, 0.300)), -1: Vector((-0.060, -0.245, 0.300))}, tilt=13, length=1.40),
    "D": dict(S={1: Vector((0.180, -0.025, 0.470)), -1: Vector((-0.180, -0.025, 0.470))},
              H={1: Vector((0.205, -0.165, 0.320)), -1: Vector((-0.205, -0.165, 0.320))}, tilt=13, length=1.40),
}
ARM_VARIANT = "v2"


def set_arm_variant(name):
    global SHOULDER, HAND, POLE_TILT, POLE_DIR, POLE_LEN, ARM_VARIANT
    v = ARM_VARIANTS[name]; ARM_VARIANT = name
    POLE_TILT = math.radians(v["tilt"]); POLE_LEN = v["length"]
    POLE_DIR = Vector((-math.sin(POLE_TILT), 0.0, math.cos(POLE_TILT)))
    SHOULDER = dict(v["S"]); HAND = dict(v["H"])
    if HAND[1] is None:   # B: the left paw holds the pole a little higher than the right one
        r = HAND[-1]
        HAND[1] = r + POLE_DIR * (0.13 / POLE_DIR.z) + Vector((0.0, -0.005, 0.0))
CLOTH_L, CLOTH_H, CLOTH_T = 0.640, 0.320, 0.012   # banner length (out from the pole), height, thickness
CLOTH_NOTCH = 0.13                                # swallowtail notch depth (fraction of the length)
CLOTH_WAVE = 0.028                                # baked wave amplitude (m) toward the free end


set_arm_variant("A")   # 2026-10-24 user decision: A (side shoulders, arms hanging along the sides)


def arm_axis(side):
    return (HAND[side] - SHOULDER[side]).normalized()


def arm_reach(side):
    return (HAND[side] - SHOULDER[side]).length + PAW_R


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
    return make_mitten_arm(bm, SHOULDER[side], HAND[side], ARM_R, PAW_R, lambda u, v: swatch_uv("fur"),
                           swatch_uv("cream"))


def pole_base():
    H = HAND[-1]
    return H - POLE_DIR * ((H.z - POLE_BASE_Z) / POLE_DIR.z)


def pole_top():
    return pole_base() + POLE_DIR * POLE_LEN


def make_pole(bm):
    """Wooden pole from the ground by the right foot through the right paw, a gold knob on top."""
    a, b = pole_base(), pole_top()
    pts, radii = capsule([a.lerp(b, i / 3) for i in range(4)], [POLE_R] * 4)
    build_tube(bm, pts, radii, 8, lambda u, v: swatch_uv("pole"), up_hint=Vector((0, -1, 0)))
    ellipsoid(bm, b + POLE_DIR * (KNOB_R * 0.6), (KNOB_R,) * 3, swatch_uv("gold"), 10, 6)


def cloth_frame():
    """Banner frame under the knob: a = down the pole, o = out (away from the puppy, toward -X),
    n = the front face's normal (toward -Y)."""
    a = -POLE_DIR
    o = Vector((-1.0, 0.0, 0.0)); o = (o - a * o.dot(a)).normalized()
    n = o.cross(a).normalized()
    if n.y > 0:
        n = -n
    return pole_top() - POLE_DIR * 0.040, a, o, n


def make_cloth(bm):
    """Thin closed slab: front and back grids sharing their rim. The swallowtail notch only moves
    the last column; the wave is fixed at the pole and grows toward the free end. Each side has its
    own atlas region painted with the same text, mapped so it reads left -> right for its viewer."""
    top, a, o, n = cloth_frame()
    us = [0.0, 0.025, 0.12, 0.24, 0.36, 0.48, 0.60, 0.72, 0.82, 1.0]
    vs = [0.0, 0.045, 0.25, 0.50, 0.75, 0.955, 1.0]
    m_off = POLE_R / CLOTH_L   # the cloth starts at the pole's surface

    def mid(s, t):
        if s >= 1.0:   # swallowtail: the end column is pulled in toward the middle
            s = 1.0 - CLOTH_NOTCH * (1.0 - abs(2 * t - 1))
        s = m_off + s * (1 - m_off)
        wave = CLOTH_WAVE * s * math.sin(2 * math.pi * (1.15 * s) - 0.6)
        return top + o * (s * CLOTH_L) + a * ((1 - t) * CLOTH_H) + n * wave, s

    F, B, S = {}, {}, {}
    for i, s in enumerate(us):
        for j, t in enumerate(vs):
            p, se = mid(s, t)
            F[i, j] = bm.verts.new(p + n * (CLOTH_T / 2))
            B[i, j] = bm.verts.new(p - n * (CLOTH_T / 2))
            S[i, j] = se
    # From the front the banner flies to the viewer's left, so reading left -> right runs from the
    # free end to the pole (u = 1 - s); from behind it runs from the pole to the free end (u = s).
    fu = lambda i, j: region_uv(R_FLAG_F, 1.0 - S[i, j], vs[j])
    bu = lambda i, j: region_uv(R_FLAG_B, S[i, j], vs[j])
    nu, nv = len(us), len(vs)
    for i in range(nu - 1):
        for j in range(nv - 1):
            q = [(i, j), (i + 1, j), (i + 1, j + 1), (i, j + 1)]
            add_face(bm, [F[k] for k in q], [fu(*k) for k in q])
            add_face(bm, [B[k] for k in reversed(q)], [bu(*k) for k in reversed(q)])
    rim = [(i, 0) for i in range(nu)] + [(nu - 1, j) for j in range(1, nv)] + \
          [(i, nv - 1) for i in range(nu - 2, -1, -1)] + [(0, j) for j in range(nv - 2, 0, -1)]
    edge = swatch_uv("cloth")
    for k in range(len(rim)):
        p, q = rim[k], rim[(k + 1) % len(rim)]
        add_face(bm, [F[p], F[q], B[q], B[p]], [edge] * 4)
    return top


def make_tail(bm):
    """Curly tail (part of Body): out of the back toward the puppy's left (+X), rising and curling over."""
    from bread_cat import bezier
    p0 = Vector((0.05, 0.170, 0.200))
    pts = bezier(p0, Vector((0.24, 0.30, 0.17)), Vector((0.36, 0.30, 0.44)), Vector((0.24, 0.22, 0.52)), 9)
    radii = [0.050 - 0.012 * (i / (len(pts) - 1)) ** 1.5 for i in range(len(pts))]
    pts, radii = capsule(pts, radii)
    build_tube(bm, pts, radii, 10, lambda u, v: region_uv(R_TAIL, u, v), up_hint=Vector((0, -1, 0)))
    return p0


# --------------------------------------------------------------------------------------------
# Scene assembly
# --------------------------------------------------------------------------------------------

def make_material(img):
    mat = bpy.data.materials.new("Puppy")
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


SCALE = 1.08  # parts are authored ~1.18 m tall; scaled so the puppy with the hat is ~1.27 m


def mesh_object(name, bm, pivot_world, parent, parent_pivot, mat):
    bmesh.ops.translate(bm, verts=bm.verts, vec=-pivot_world)
    bmesh.ops.scale(bm, verts=bm.verts, vec=(SCALE, SCALE, SCALE))
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
    ob.location = (pivot_world - parent_pivot) * SCALE
    return ob


def empty(name, loc_world, parent, parent_pivot, size=0.03):
    ob = bpy.data.objects.new(name, None)
    ob.empty_display_size = size
    bpy.context.scene.collection.objects.link(ob)
    ob.parent = parent
    ob.location = (loc_world - parent_pivot) * SCALE
    return ob


def build(monocle=False, flag=True, hat=True, face=None):
    img = build_atlas(monocle, face)
    mat = make_material(img)
    origin = Vector((0, 0, 0))
    root = empty("Puppy", origin, None, origin, 0.2)
    bm = new_bm(); make_body(bm)
    body = mesh_object("Body", bm, origin, root, origin, mat)
    bm = new_bm(); make_head(bm, monocle, hat)
    head = mesh_object("Head", bm, NECK, body, origin, mat)
    for side, nm in ((1, "L"), (-1, "R")):
        bm = new_bm(); base = make_ear(bm, side)
        mesh_object("Ear" + nm, bm, base, head, NECK, mat)
    for side, nm in ((1, "L"), (-1, "R")):
        bm = new_bm(); paw = make_arm(bm, side)
        arm = mesh_object("Arm" + nm, bm, SHOULDER[side], body, origin, mat)
        empty("Hand" + nm, paw, arm, SHOULDER[side])
        if side == -1 and flag:
            bm = new_bm(); make_pole(bm)
            pole = mesh_object("Flag", bm, HAND[side], arm, SHOULDER[side], mat)
            bm = new_bm(); make_cloth(bm)
            mesh_object("FlagCloth", bm, pole_top(), pole, HAND[side], mat)
    return root, img


def _rotate_about_origin(ob, q):
    """Rotate object `ob` in world space by quaternion q about its own origin (its pivot)."""
    mw = ob.matrix_world.copy()
    loc = mw.translation.copy()
    ob.matrix_world = Matrix.Translation(loc) @ q.to_matrix().to_4x4() @ Matrix.Translation(-loc) @ mw


def pose_point(node, tip, target):
    """Swing `node` about its pivot so `tip` (a child empty) points at `target`."""
    bpy.context.view_layer.update()
    S = node.matrix_world.translation.copy()
    T = tip.matrix_world.translation.copy()
    _rotate_about_origin(node, (T - S).rotation_difference(Vector(target) - S))
    bpy.context.view_layer.update()


def pose_flag(arm, hand, flag, cloth, paw_target, top_target):
    """Raise / wave the flag: the arm swings so the paw heads for `paw_target` (the paw stays at
    arm's length), then the pole turns in the paw so its top (the FlagCloth pivot) heads for
    `top_target`."""
    pose_point(arm, hand, paw_target)
    pose_point(flag, cloth, top_target)
    # untwist: the swing can roll the pole about its own axis; turn it back so the banner faces the
    # puppy's front again (at rest its front normal is -Y in every arm variant: the pole leans in XZ)
    root = arm
    while root.parent:
        root = root.parent
    S = flag.matrix_world.translation.copy()
    ax = (cloth.matrix_world.translation - S).normalized()
    n = flag.matrix_world.to_3x3() @ Vector((0.0, -1.0, 0.0))
    f = root.matrix_world.to_3x3() @ Vector((0.0, -1.0, 0.0))
    n = (n - ax * n.dot(ax)).normalized(); f = (f - ax * f.dot(ax)).normalized()
    _rotate_about_origin(flag, Quaternion(ax, math.atan2(n.cross(f).dot(ax), n.dot(f))))
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
    opts = {"out": None, "monocle": "off", "flag": "on", "hat": "on", "arms": "A"}
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
    build(opts["monocle"] == "on", opts["flag"] != "off", opts["hat"] != "off")
    print("PUPPY_STATS", stats())
    if opts["out"]:
        bc.export_glb(opts["out"])
        print("PUPPY_EXPORTED", opts["out"])
