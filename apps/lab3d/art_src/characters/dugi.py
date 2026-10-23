"""Dugi (두기두기) — the science rabbit who explains the experiments, generated entirely in Blender Python.

Run (headless):
    blender -b --factory-startup -P apps/lab3d/art_src/characters/dugi.py -- \
        [--out apps/lab3d/assets/characters/dugi.glb] [--glasses on|off]

A white chibi rabbit with very long ears (pink inside), big round glossy eyes, an open happy mouth,
blush, a red bow tie and arms folded across the chest; round wire glasses for the know-it-all
scientist (2026-10-23 reference image + user brief). Same style and conventions as bread_cat.py,
whose generic helpers (painting SDFs, bmesh sphere / tube builders) this file imports; geometry, UVs
and the single texture atlas are produced here, nothing depends on a hand-made .blend. Other scripts
may `import` it and call `build()` / `pose_point()` (the preview and duo renders do).

Conventions:
- Units are metres. Height ~1.72 m including the ears (head top ~1.14 m). Origin = between the feet
  on the ground.
- Blender: +Z up, Dugi faces -Y; glTF/Godot: +Y up, faces +Z (MODEL_FRONT), left side = +X.
- Node tree (no armature; animate by rotating nodes, each origin is its pivot):
    Dugi                    (empty, origin on the ground between the feet)
      Body                  (mesh: body, feet, tail puff, bow tie; pivot on the ground -> lean / bob)
        Head                (mesh incl. glasses, pivot at the neck -> nod / tilt)
          EarL / EarR       (mesh, pivot at the ear root -> perk up / flop / wiggle)
        ArmL / ArmR         (upper arm mesh, pivot at the shoulder; L = Dugi's left = +X)
          ForearmL / R      (mesh incl. the paw, pivot at the elbow)
            HandL / HandR   (empty at the paw tip: pointing tip / grip point)
- Rest pose = arms folded (ArmL's forearm in front, lower). To point, straighten the forearm about
  the elbow (rotate it so it continues the upper arm) and swing the arm about the shoulder toward
  the target: `pose_point()` below does exactly that on the Blender objects.
- Budget (SM-P200 low): 7 meshes, 1 material, 1 texture (1024 px), < 6000 triangles.
"""

import math
import os
import sys

import bmesh
import bpy
import numpy as np
from mathutils import Matrix, Quaternion, Vector

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import bread_cat as bc  # noqa: E402  (generic helpers only; no cat geometry is built)
from bread_cat import (add_face, bezier, blend, build_sphere, build_tube, hexc, new_bm,  # noqa: E402
                       sd_ellipse, sd_segment, smooth_fill, sph_dir)

TEX = 1024
PAD = 3

P = dict(
    fur="#f7f2ee", fur_shade="#ebe2dc", white="#fffdfb", pink="#ffadc0", pink_deep="#ff8fa8",
    blush="#ff9cb0", eye="#2b1a14", eye_low="#5a3626", mouth="#6b2a22", tongue="#ff7d92",
    bow="#e8413c", bow_dark="#b8292b", frame="#9a6334",
)

# Atlas layout (pixels, origin bottom-left like Blender UVs)
R_HEAD = (0, 512, 1024, 1024)
R_EAR = (0, 0, 512, 512)
R_BODY = (512, 256, 768, 512)
R_ARM = (512, 0, 768, 256)
SWATCH_ORIGIN = (768, 0)  # 4 x 4 swatches of 64 px
SWATCHES = ["fur", "white", "pink", "bow", "bow_dark", "frame", "fur_shade", "eye"]


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

HEAD_R = 0.300
HEAD_SX, HEAD_SY, HEAD_SZ = 1.16, 0.96, 0.88
HEAD_C = Vector((0.0, -0.01, 0.835))
NECK = Vector((0.0, 0.0, 0.590))
BODY_C = Vector((0.0, 0.01, 0.350))
BODY_R = Vector((0.225, 0.195, 0.290))
EYE_X, EYE_Z, EYE_RX, EYE_RZ = 0.115, 0.012, 0.050, 0.058
NOSE_Z = -0.052


def head_point(d):
    x, y, z = d
    cheek = 1.0 + 0.08 * max(0.0, -z + 0.10) * (1.0 - abs(y))
    sx = HEAD_SX * cheek
    sy = HEAD_SY * (0.90 if y < 0 else 1.0)
    sz = HEAD_SZ * (0.90 if z < 0 else 1.0)
    return HEAD_C + Vector((x * HEAD_R * sx, y * HEAD_R * sy, z * HEAD_R * sz))


def face_dir(qx, qz):
    """Head direction whose painted face coordinate is (qx, qz) metres (inverse of paint_head's map)."""
    dx = qx / (HEAD_R * HEAD_SX)
    dz = qz / (HEAD_R * HEAD_SZ * (0.90 if qz < 0 else 1.0))
    return Vector((dx, -math.sqrt(max(0.0, 1 - dx * dx - dz * dz)), dz))


def body_point(d):
    lower = max(0.0, -d.z)
    w = 1.0 + 0.16 * lower - 0.06 * max(0.0, d.z) ** 2  # pear: fuller bottom, narrower shoulders
    return BODY_C + Vector((d.x * BODY_R.x * w, d.y * BODY_R.y * w, d.z * BODY_R.z))


# --------------------------------------------------------------------------------------------
# Texture painting (numpy, sRGB)
# --------------------------------------------------------------------------------------------

def paint_head():
    u, v = region_grid(R_HEAD)
    lon = (u - 0.5) * 2 * math.pi
    lat = (v - 0.5) * math.pi
    dx = np.sin(lon) * np.cos(lat); dy = -np.cos(lon) * np.cos(lat); dz = np.sin(lat)
    img = np.zeros(u.shape + (3,)); img[...] = hexc(P["fur"])
    # a touch of warm shade on the back / under the chin, brighter face
    blend(img, np.clip((dy + 0.2) * 0.8, 0, 1), hexc(P["fur_shade"]), 0.6)
    blend(img, np.clip(-dz * 1.6 - 0.6, 0, 1), hexc(P["fur_shade"]), 0.5)
    front = dy < 0.0
    qx = dx * HEAD_R * HEAD_SX
    qz = dz * HEAD_R * HEAD_SZ * np.where(dz < 0, 0.90, 1.0)
    aa = 0.0022
    blend(img, smooth_fill(sd_ellipse(qx, qz, 0.0, -0.075, 0.11, 0.07), 0.03) * front, hexc(P["white"]))
    for s in (-1, 1):  # blush
        blend(img, smooth_fill(sd_ellipse(qx, qz, s * 0.170, -0.058, 0.048, 0.028), 0.022) * front,
              hexc(P["blush"]), 0.8)
    for s in (-1, 1):  # big glossy eyes
        ex, ez = s * EYE_X, EYE_Z
        m = smooth_fill(sd_ellipse(qx, qz, ex, ez, EYE_RX, EYE_RZ), aa) * front
        blend(img, m, hexc(P["eye"]))
        low = np.clip((ez - qz) / EYE_RZ, 0, 1) ** 1.5
        blend(img, m * low, hexc(P["eye_low"]), 0.8)
        blend(img, smooth_fill(sd_ellipse(qx, qz, ex - 0.016, ez + 0.022, 0.018, 0.019), aa) * front, np.ones(3))
        blend(img, smooth_fill(sd_ellipse(qx, qz, ex + 0.018, ez - 0.024, 0.008, 0.008), aa) * front, np.ones(3))
    # nose: small pink rounded oval
    nz = NOSE_Z
    blend(img, smooth_fill(sd_ellipse(qx, qz, 0.0, nz, 0.020, 0.013), aa) * front, hexc(P["pink_deep"]))
    # open happy mouth: short philtrum, a "w" upper lip and an open half-moon with a tongue
    mcol = hexc(P["mouth"]); stroke = 0.0040
    sdf = sd_segment(qx, qz, 0.0, nz - 0.012, 0.0, nz - 0.022) - stroke * 0.8
    for s in (-1, 1):
        cx, cz, r = s * 0.018, nz - 0.022, 0.018
        ring = np.abs(np.sqrt((qx - cx) ** 2 + (qz - cz) ** 2) - r) - stroke
        sdf = np.minimum(sdf, np.where(qz < cz + 0.002, ring, 1.0))
    blend(img, smooth_fill(sdf, aa) * front, mcol)
    cz = nz - 0.032
    half = np.where(qz < cz, sd_ellipse(qx, qz, 0.0, cz, 0.030, 0.036), 1.0)
    blend(img, smooth_fill(half, aa) * front, mcol)
    tongue = np.maximum(sd_ellipse(qx, qz, 0.0, cz - 0.037, 0.021, 0.018), half + 0.003)
    blend(img, smooth_fill(tongue, aa) * front, hexc(P["tongue"]))
    return img


def paint_ear():
    """u = around the ear section (front centre at u = 0.25), v = root (0) -> tip (1)."""
    u, v = region_grid(R_EAR)
    a = 2 * math.pi * u
    across = np.cos(a)          # -1..1 side to side
    front = np.sin(a) > 0.15
    img = np.zeros(u.shape + (3,)); img[...] = hexc(P["fur"])
    k = (across / 0.80) ** 2 + ((v - 0.50) / 0.43) ** 2
    m = smooth_fill((np.sqrt(k) - 1.0) * 0.2, 0.012) * front
    blend(img, m, hexc(P["pink"]))
    deep = smooth_fill((np.sqrt((across / 0.42) ** 2 + ((v - 0.42) / 0.30) ** 2) - 1.0) * 0.2, 0.03) * front
    blend(img, deep, hexc(P["pink_deep"]), 0.35)
    return img


def paint_body():
    u, v = region_grid(R_BODY)
    lon = (u - 0.5) * 2 * math.pi
    lat = (v - 0.5) * math.pi
    dy = -np.cos(lon) * np.cos(lat)
    img = np.zeros(u.shape + (3,)); img[...] = hexc(P["fur"])
    blend(img, np.clip((dy + 0.1) * 0.9, 0, 1), hexc(P["fur_shade"]), 0.5)
    blend(img, np.clip((-dy - 0.3) * 2.5, 0, 1), hexc(P["white"]), 0.9)  # light belly
    return img


def paint_arm():
    """Forearm tube: u = around (0 = top), v = elbow (0) -> paw tip (1). White paw with two toe lines."""
    u, v = region_grid(R_ARM)
    img = np.zeros(u.shape + (3,)); img[...] = hexc(P["fur"])
    blend(img, np.clip((v - 0.62) / 0.08, 0, 1), hexc(P["white"]))
    uu = np.where(u > 0.5, u - 1.0, u)  # top centred at 0
    for c in (-0.06, 0.06):
        sdf = np.maximum(np.abs(uu - c) - 0.007, np.maximum(0.84 - v, v - 0.99))
        blend(img, smooth_fill(sdf, 0.006), hexc(P["fur_shade"]) * 0.88)
    return img


def build_atlas():
    canvas = np.zeros((TEX, TEX, 3)); canvas[...] = hexc(P["fur"])
    for rect, fn in ((R_HEAD, paint_head), (R_EAR, paint_ear), (R_BODY, paint_body), (R_ARM, paint_arm)):
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


def make_head(bm, glasses):
    build_sphere(bm, head_point, lambda u, v: region_uv(R_HEAD, u, v), segs=32, rings=18)
    if not glasses:
        return
    frame = swatch_uv("frame")
    rim_r, wire = 0.072, 0.0062
    rims = []
    for s in (-1, 1):
        d = face_dir(s * EYE_X, EYE_Z - 0.004)
        c = head_point(d)
        n = (head_point(face_dir(s * EYE_X + 0.01, EYE_Z)) - head_point(face_dir(s * EYE_X - 0.01, EYE_Z))) \
            .cross(head_point(face_dir(s * EYE_X, EYE_Z + 0.01)) - head_point(face_dir(s * EYE_X, EYE_Z - 0.01)))
        n = n.normalized()
        if n.y > 0:
            n = -n
        n = (n + Vector((0, -0.6, 0))).normalized()  # face the viewer a bit more than the skin does
        c = c + n * 0.021
        ax1 = Vector((0, 0, 1)).cross(n).normalized()
        ax2 = n.cross(ax1).normalized()
        N = 24
        loop = [c + (ax1 * math.cos(2 * math.pi * i / N) + ax2 * math.sin(2 * math.pi * i / N)) * rim_r
                for i in range(N + 1)]
        build_tube(bm, loop, [wire] * len(loop), 6, lambda u, v: frame, up_hint=n, cap_start=False, cap_end=False)
        rims.append((c, ax1, n))
    # bridge: a little arch between the rims
    (cl, axl, _), (cr, axr, _) = rims
    a = cl + axl * rim_r * 0.98 * (1 if axl.x > 0 else -1)
    b = cr - axr * rim_r * 0.98 * (1 if axr.x > 0 else -1)
    a, b = (a, b) if a.x < b.x else (b, a)
    mid = (a + b) / 2 + Vector((0, -0.006, 0.020))
    build_tube(bm, bezier(a, a.lerp(mid, 0.7), b.lerp(mid, 0.7), b, 5), [wire] * 5, 6, lambda u, v: frame)
    # temples: from each outer rim edge back over the cheek into the head side
    for c, ax, n in rims:
        out = Vector((math.copysign(1, c.x), 0, 0))
        e = c + (ax if ax.dot(out) > 0 else -ax) * rim_r
        sgn = math.copysign(1, c.x)
        lon0 = math.atan2(e.x - HEAD_C.x, -(e.y - HEAD_C.y)) * sgn
        pts = [e]
        for i in range(1, 6):  # hug the head surface back toward the ear, sinking in at the end
            lon = lon0 + (1.25 - lon0) * i / 5
            d = sph_dir(sgn * lon, 0.10 + 0.02 * (1 - i / 5))
            q = head_point(d)
            pts.append(q + (q - HEAD_C).normalized() * (0.009 if i < 5 else -0.012))
        build_tube(bm, pts, [wire] * len(pts), 6, lambda u, v: frame)


ES = 16  # ear ring segments
EAR_T = [0.0, 0.06, 0.14, 0.24, 0.36, 0.48, 0.60, 0.71, 0.80, 0.87, 0.925, 0.965]
EAR_LEN = 0.60
EAR_W = 0.128


def ear_root(side):
    return head_point(sph_dir(side * 0.95, 1.12)) - Vector((0, 0, 0.03))


def ear_path(side):
    b = ear_root(side)
    s = side
    return (b, b + Vector((s * 0.05, -0.01, 0.22)), b + Vector((s * 0.13, 0.01, 0.42)),
            b + Vector((s * 0.21, 0.05, EAR_LEN)))


def make_ear(bm, side):
    p0, p1, p2, p3 = ear_path(side)

    def at(t):
        return p0 * (1 - t) ** 3 + p1 * 3 * t * (1 - t) ** 2 + p2 * 3 * t * t * (1 - t) + p3 * t ** 3
    uv = lambda u, v: region_uv(R_EAR, u, v)
    rows = []
    fwd0 = Vector((side * 0.22, -1.0, 0.0)).normalized()  # the pink faces forward and a bit out
    for t in EAR_T:
        c = at(t)
        tan = (at(min(t + 0.01, 1)) - at(max(t - 0.01, 0))).normalized()
        fwd = (fwd0 - tan * fwd0.dot(tan)).normalized()
        sideax = fwd.cross(tan).normalized() * side  # outward
        w = EAR_W * math.sqrt(max(0.0, 1 - ((t - 0.44) / 0.565) ** 2))
        w = max(w, 0.058 * (1 - t))
        d = 0.42 * w
        row = []
        for j in range(ES):
            a = 2 * math.pi * j / ES
            sa = math.sin(a)
            off_f = d * (0.62 * sa - 0.42 * sa ** 6) if sa > 0 else d * sa  # dished front
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


def make_body(bm):
    build_sphere(bm, body_point, lambda u, v: region_uv(R_BODY, u, v), segs=20, rings=12)
    fur = swatch_uv("fur"); white = swatch_uv("white")
    for s in (-1, 1):  # feet: soft ovals toeing out a little
        rot = Matrix.Rotation(s * math.radians(12), 3, "Z")
        ellipsoid(bm, Vector((s * 0.112, -0.08, 0.052)), (0.088, 0.130, 0.056), white, 12, 8, rot)
    ellipsoid(bm, Vector((0.0, 0.185, 0.20)), (0.075, 0.065, 0.070), white, 12, 8)  # tail puff
    # bow tie under the chin
    bow = swatch_uv("bow"); dark = swatch_uv("bow_dark")
    knot = Vector((0.0, -0.165, 0.585))
    for s in (-1, 1):
        def lobe(d, q, s=s):
            flare = 0.40 + 0.60 * (0.5 + 0.5 * d.x * s)  # thin at the knot, wide at the outer end
            return Vector((q.x, q.y, q.z * flare))
        ellipsoid(bm, knot + Vector((s * 0.068, 0.01, 0.0)), (0.072, 0.030, 0.055), bow, 12, 8,
                  Matrix.Rotation(s * math.radians(-8), 3, "Y"), lobe)
    ellipsoid(bm, knot + Vector((0, -0.012, 0)), (0.030, 0.026, 0.034), dark, 10, 6)


SHOULDER = {1: Vector((0.135, -0.01, 0.515)), -1: Vector((-0.135, -0.01, 0.515))}
ELBOW = {1: Vector((0.232, -0.165, 0.390)), -1: Vector((-0.228, -0.140, 0.445))}
HAND = {1: Vector((-0.090, -0.285, 0.418)), -1: Vector((0.095, -0.238, 0.478))}
ARM_R = 0.054


def make_upper_arm(bm, side):
    S, E = SHOULDER[side], ELBOW[side]
    pts = [S.lerp(E, t / 4) for t in range(5)]
    build_tube(bm, pts, [ARM_R * (1.02 - 0.05 * t / 4) for t in range(5)], 12, lambda u, v: swatch_uv("fur"),
               up_hint=Vector((0, -1, 0)))


def make_forearm(bm, side):
    E, H = ELBOW[side], HAND[side]
    ellipsoid(bm, E, (ARM_R * 0.98,) * 3, swatch_uv("fur"), 12, 6)
    n = 7
    pts = [E.lerp(H, i / (n - 1)) for i in range(n)]
    radii = []
    for i in range(n):
        t = i / (n - 1)
        radii.append(ARM_R * (0.94 + 0.30 * math.exp(-((t - 0.86) / 0.14) ** 2)) * (0.85 if t > 0.95 else 1.0))
    build_tube(bm, pts, radii, 12, lambda u, v: region_uv(R_ARM, u, v), up_hint=Vector((0, 0, 1)), squash=1.1)
    return H + (H - E).normalized() * radii[-1] * 0.35


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


def build(glasses=True):
    img = build_atlas()
    mat = make_material(img)
    origin = Vector((0, 0, 0))
    root = empty("Dugi", origin, None, origin, 0.2)
    bm = new_bm(); make_body(bm)
    body = mesh_object("Body", bm, origin, root, origin, mat)
    bm = new_bm(); make_head(bm, glasses)
    head = mesh_object("Head", bm, NECK, body, origin, mat)
    for side, nm in ((1, "L"), (-1, "R")):
        bm = new_bm(); base = make_ear(bm, side)
        mesh_object("Ear" + nm, bm, base, head, NECK, mat)
    for side, nm in ((1, "L"), (-1, "R")):
        bm = new_bm(); make_upper_arm(bm, side)
        arm = mesh_object("Arm" + nm, bm, SHOULDER[side], body, origin, mat)
        bm = new_bm(); tip = make_forearm(bm, side)
        fore = mesh_object("Forearm" + nm, bm, ELBOW[side], arm, SHOULDER[side], mat)
        empty("Hand" + nm, tip, fore, ELBOW[side])
    return root, img


def _rotate_about_origin(ob, q):
    """Rotate object `ob` in world space by quaternion q about its own origin (its pivot)."""
    mw = ob.matrix_world.copy()
    loc = mw.translation.copy()
    ob.matrix_world = Matrix.Translation(loc) @ q.to_matrix().to_4x4() @ Matrix.Translation(-loc) @ mw


def pose_point(arm, forearm, hand, target):
    """Straighten the forearm, then swing the arm about the shoulder so the paw points at `target`."""
    bpy.context.view_layer.update()
    S = arm.matrix_world.translation.copy()
    E = forearm.matrix_world.translation.copy()
    H = hand.matrix_world.translation.copy()
    _rotate_about_origin(forearm, (H - E).rotation_difference(E - S))
    bpy.context.view_layer.update()
    H = hand.matrix_world.translation.copy()
    _rotate_about_origin(arm, (H - S).rotation_difference(Vector(target) - S))
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
    return dict(bounds_min_max=bounds, pivots=pivots, per_mesh=per, meshes=meshes, triangles=tris,
                materials=len([m for m in bpy.data.materials if m.users]), nodes=len(bpy.context.scene.objects))


def parse_args():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    opts = {"out": None, "glasses": "on"}
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
    build(opts["glasses"] != "off")
    print("DUGI_STATS", stats())
    if opts["out"]:
        bc.export_glb(opts["out"])
        print("DUGI_EXPORTED", opts["out"])
