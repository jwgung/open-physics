"""Parcel box (택배 박스) — the boxes' look (incline, push friction, lever / pulley loads, the
manipulation development scene; Phase 1 Task 4g), made in Blender Python.

Run (headless):
    blender -b --factory-startup -P apps/lab3d/art_src/props/parcel_box.py -- \
        [--out apps/lab3d/assets/props/parcel_box.glb] [--preview DIR]

A cube of side 1 m centred on the origin (the app bakes it to each box's size: uniform, so the
texture never stretches) with one texture: corrugated cardboard (a little redder and darker than
the bread cat's kraft bag) with darker edges, a packing tape band across the top and down two
sides, a white shipping label with a stripe and lines, a cat paw stamp and "this side up" arrows on
the front, flap seams on the top. The tape and the label stripe are marked by the texture's alpha
(0 = accent): the app colours them per box (ArtKit.parcel_box accent: brown tape by default, the
development scene's red / yellow / violet boxes by their colour); the rest is the cardboard as
painted.
- glTF / Godot: +Y up, +Z the front (the label side).
- Budget: 1 mesh, 1 material, 1 texture (512 x 512), 12 triangles.
"""

import math
import os
import sys

import bmesh
import bpy
import numpy as np

TEX = 512
CARD = np.array([0xc0, 0x86, 0x52]) / 255.0       # cardboard (the bag kraft is #d9a066)
CARD_DARK = np.array([0x9a, 0x66, 0x3a]) / 255.0  # edges, seams
TAPE = np.array([0.93, 0.93, 0.93])               # grey: times the accent colour in the app
LABEL = np.array([0.98, 0.97, 0.94])
INK = np.array([0x5a, 0x3a, 0x22]) / 255.0
# Atlas regions (x0, y0, x1, y1) in pixels, y down.
R_TOP = (0, 0, 256, 256)      # +Y: tape along x, flap seam
R_TAPE = (256, 0, 512, 256)   # +X / -X sides: the tape running down the middle
R_FRONT = (0, 256, 256, 512)  # +Z: label, paw stamp, arrows
R_PLAIN = (256, 256, 512, 512)  # -Z, -Y: cardboard


def grid(rect):
    x0, y0, x1, y1 = rect
    u = (np.arange(x1 - x0) + 0.5) / (x1 - x0)
    v = (np.arange(y1 - y0) + 0.5) / (y1 - y0)
    return np.meshgrid(u, v)   # u right, v down (0..1 on the face)


def smooth(sdf, aa=0.006):
    return np.clip(0.5 - sdf / aa, 0.0, 1.0)


def rect_sdf(u, v, cx, cy, hx, hy):
    return np.maximum(np.abs(u - cx) - hx, np.abs(v - cy) - hy)


def card(u, v, seed):
    rng = np.random.default_rng(seed)
    img = np.ones(u.shape + (3,)) * CARD
    flutes = 0.97 + 0.03 * np.cos(u * 2 * math.pi * 38)          # corrugation lines
    noise = 0.96 + 0.04 * np.sin(u * 23.1 + rng.random() * 6) * np.sin(v * 17.3 + rng.random() * 6)
    img *= (flutes * noise)[..., None]
    edge = np.minimum(np.minimum(u, 1 - u), np.minimum(v, 1 - v))
    img = img * (1 - 0.35 * np.clip(1 - edge / 0.035, 0, 1))[..., None] + CARD_DARK * 0.35 * np.clip(1 - edge / 0.035, 0, 1)[..., None]
    return img


def paint(img, alpha, mask, color, accent=False):
    img[:] = img * (1 - mask[..., None]) + color * mask[..., None]
    if accent:
        alpha[:] = alpha * (1 - mask)


def build_texture():
    canvas = np.zeros((TEX, TEX, 3))
    alpha = np.ones((TEX, TEX))
    for rect, seed in ((R_TOP, 1), (R_TAPE, 2), (R_FRONT, 3), (R_PLAIN, 4)):
        x0, y0, x1, y1 = rect
        u, v = grid(rect)
        img = card(u, v, seed)
        a = np.ones(u.shape)
        if rect == R_TOP:
            paint(img, a, smooth(np.abs(v - 0.5) - 0.004, 0.004) * 0.6, CARD_DARK)   # flap seam
            tape = smooth(rect_sdf(u, v, 0.5, 0.5, 0.6, 0.13))
            paint(img, a, tape, TAPE * (0.97 + 0.03 * np.sin(u * 90))[..., None], accent=True)
        elif rect == R_TAPE:
            tape = smooth(rect_sdf(u, v, 0.5, 0.5, 0.13, 0.6))
            paint(img, a, tape, TAPE * (0.97 + 0.03 * np.sin(v * 90))[..., None], accent=True)
        elif rect == R_FRONT:
            # Label: white card with an accent stripe and three ink lines, a bar code.
            lab = smooth(rect_sdf(u, v, 0.36, 0.62, 0.2, 0.15))
            paint(img, a, lab, LABEL)
            paint(img, a, smooth(rect_sdf(u, v, 0.36, 0.5, 0.2, 0.03)), TAPE, accent=True)
            for i, w in enumerate((0.15, 0.11, 0.13)):
                paint(img, a, smooth(rect_sdf(u, v, 0.21 + w, 0.585 + 0.05 * i, w, 0.008)), INK)
            for i in range(9):
                paint(img, a, smooth(rect_sdf(u, v, 0.43 + 0.012 * i, 0.725, 0.003 + 0.002 * (i % 3), 0.025)), INK)
            # Cat paw stamp (pad + four toes), a little rotated.
            px, py, s = 0.76, 0.66, 0.06
            c, sn = math.cos(0.3), math.sin(0.3)
            uu = (u - px) * c - (v - py) * sn
            vv = (u - px) * sn + (v - py) * c
            pad = np.hypot(uu / (1.1 * s), (vv - 0.25 * s) / (0.9 * s)) - 1.0
            toes = np.min([np.hypot(uu - tx * s, vv + ty * s) - 0.42 * s for tx, ty in ((-1.05, 0.55), (-0.38, 1.25), (0.38, 1.25), (1.05, 0.55))], axis=0)
            paint(img, a, smooth(np.minimum(pad * s, toes), 0.004) * 0.85, INK)
            # "This side up": two arrows top left.
            for ax in (0.14, 0.27):
                shaft = rect_sdf(u, v, ax, 0.24, 0.012, 0.07)
                head = np.maximum(np.abs(u - ax) - (0.045 - (0.17 - v) * 0.0) - (v - 0.115) * 0.55, 0.115 - v)
                head = np.maximum(np.abs(u - ax) * 1.0 - (v - 0.11) * 0.6, np.maximum(0.11 - v, v - 0.18))
                paint(img, a, smooth(np.minimum(shaft, head), 0.004), INK)
            paint(img, a, smooth(rect_sdf(u, v, 0.205, 0.335, 0.11, 0.008)), INK)
        canvas[y0:y1, x0:x1] = np.clip(img, 0, 1)
        alpha[y0:y1, x0:x1] = a
    rgba = np.concatenate([canvas, alpha[..., None]], axis=2)[::-1]   # Blender rows bottom to top
    img = bpy.data.images.new("parcel_box_atlas", TEX, TEX, alpha=True)
    img.pixels.foreach_set(rgba.astype(np.float32).ravel())
    img.alpha_mode = "STRAIGHT"
    return img


def face_uv(rect, corners):
    """UVs (Blender: v up) of a face's corners given as (u, v) in 0..1 of the region (v down)."""
    x0, y0, x1, y1 = rect
    return [((x0 + (x1 - x0) * cu) / TEX, 1.0 - (y0 + (y1 - y0) * cv) / TEX) for cu, cv in corners]


def build_mesh():
    # Blender axes: +Z up, the label side faces -Y (the glTF exporter turns -Y into +Z front).
    h = 0.5
    V = {}
    for x in (-h, h):
        for y in (-h, h):
            for z in (-h, h):
                V[(x, y, z)] = (x, y, z)
    faces = [
        # (region, 4 corners counter-clockwise seen from outside, region (u, v) for each corner)
        (R_TOP, [(-h, -h, h), (h, -h, h), (h, h, h), (-h, h, h)], [(0, 1), (1, 1), (1, 0), (0, 0)]),       # +Z top
        (R_PLAIN, [(-h, h, -h), (h, h, -h), (h, -h, -h), (-h, -h, -h)], [(0, 1), (1, 1), (1, 0), (0, 0)]),  # bottom
        (R_FRONT, [(-h, -h, -h), (h, -h, -h), (h, -h, h), (-h, -h, h)], [(0, 1), (1, 1), (1, 0), (0, 0)]),  # -Y front
        (R_PLAIN, [(h, h, -h), (-h, h, -h), (-h, h, h), (h, h, h)], [(0, 1), (1, 1), (1, 0), (0, 0)]),      # +Y back
        (R_TAPE, [(h, -h, -h), (h, h, -h), (h, h, h), (h, -h, h)], [(0, 1), (1, 1), (1, 0), (0, 0)]),       # +X
        (R_TAPE, [(-h, h, -h), (-h, -h, -h), (-h, -h, h), (-h, h, h)], [(0, 1), (1, 1), (1, 0), (0, 0)]),   # -X
    ]
    bm = bmesh.new()
    uv_layer = bm.loops.layers.uv.new("UVMap")
    for rect, corners, uvs in faces:
        verts = [bm.verts.new(c) for c in corners]
        f = bm.faces.new(verts)
        for loop, uv in zip(f.loops, face_uv(rect, uvs)):
            loop[uv_layer].uv = uv
    bm.normal_update()
    me = bpy.data.meshes.new("ParcelBox")
    bm.to_mesh(me)
    bm.free()
    return me


def make_material(img, accent=(1.0, 1.0, 1.0, 1.0)):
    mat = bpy.data.materials.new("ParcelBox")
    mat.use_nodes = True
    nt = mat.node_tree
    bsdf = nt.nodes["Principled BSDF"]
    tex = nt.nodes.new("ShaderNodeTexImage")
    tex.image = img
    if accent == (1.0, 1.0, 1.0, 1.0):
        nt.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
    else:   # preview: the accent where the alpha is 0, as the app does
        mul = nt.nodes.new("ShaderNodeMixRGB"); mul.blend_type = "MULTIPLY"; mul.inputs[0].default_value = 1.0
        mul.inputs[2].default_value = accent
        nt.links.new(tex.outputs["Color"], mul.inputs[1])
        mix = nt.nodes.new("ShaderNodeMixRGB")
        nt.links.new(tex.outputs["Alpha"], mix.inputs[0])
        nt.links.new(mul.outputs[0], mix.inputs[1])
        nt.links.new(tex.outputs["Color"], mix.inputs[2])
        nt.links.new(mix.outputs[0], bsdf.inputs["Base Color"])
    bsdf.inputs["Roughness"].default_value = 0.85
    return mat


def build(accent=(1.0, 1.0, 1.0, 1.0), img=None, name="ParcelBox"):
    img = img or build_texture()
    ob = bpy.data.objects.new(name, build_mesh())
    ob.data.materials.append(make_material(img, accent))
    bpy.context.scene.collection.objects.link(ob)
    return ob, img


def srgb_to_lin(c):
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def hexlin(hx):
    hx = hx.lstrip("#")
    return tuple(srgb_to_lin(int(hx[i:i + 2], 16) / 255) for i in (0, 2, 4)) + (1.0,)


def preview(out_dir):
    os.makedirs(out_dir, exist_ok=True)
    img = None
    for i, (col, x, s) in enumerate((("#8f5a32", -1.3, 0.7), ("#ff3b3b", 0.0, 0.5), ("#ffc61a", 0.8, 0.4), ("#4b2a9a", 1.5, 0.4))):
        ob, img = build(hexlin(col), img, "Box%d" % i)
        ob.scale = (s, s, s)
        ob.location = (x, 0.0, s * 0.5)
        ob.rotation_euler = (0, 0, 0.35 - 0.15 * i)
    scene = bpy.context.scene
    for eng in ("BLENDER_EEVEE_NEXT", "BLENDER_EEVEE"):
        try:
            scene.render.engine = eng
            break
        except TypeError:
            pass
    scene.view_settings.view_transform = "Standard"
    scene.render.resolution_x = 1000
    scene.render.resolution_y = 520
    world = bpy.data.worlds.new("W"); scene.world = world; world.use_nodes = True
    world.node_tree.nodes["Background"].inputs[0].default_value = hexlin("#62c0ff")
    bpy.ops.mesh.primitive_plane_add(size=20)
    g = bpy.context.active_object
    gm = bpy.data.materials.new("grass"); gm.use_nodes = True
    gm.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = hexlin("#5fd04a")
    g.data.materials.append(gm)
    sun_d = bpy.data.lights.new("sun", "SUN"); sun_d.energy = 3.0
    sun = bpy.data.objects.new("sun", sun_d); scene.collection.objects.link(sun)
    sun.rotation_euler = (math.radians(50), 0, math.radians(-35))
    from mathutils import Vector
    cam_d = bpy.data.cameras.new("cam"); cam_d.lens = 45
    cam = bpy.data.objects.new("cam", cam_d); scene.collection.objects.link(cam)
    scene.camera = cam
    for name, loc, look in (("front", (0.4, -4.2, 1.6), (0.1, 0.0, 0.3)), ("close", (-0.6, -1.9, 1.2), (-1.1, 0.0, 0.35))):
        cam.location = loc
        cam.rotation_euler = (Vector(look) - Vector(loc)).to_track_quat("-Z", "Y").to_euler()
        scene.render.filepath = os.path.join(out_dir, name + ".png")
        bpy.ops.render.render(write_still=True)


def export_glb(path):
    os.makedirs(os.path.dirname(os.path.abspath(path)), exist_ok=True)
    bpy.ops.export_scene.gltf(
        filepath=path, export_format="GLB", use_selection=False, export_yup=True, export_apply=False,
        export_texcoords=True, export_normals=True, export_materials="EXPORT", export_image_format="AUTO",
        export_cameras=False, export_lights=False, export_extras=False, export_animations=False,
    )


def parse_args():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    opts = {"out": None, "preview": None}
    for i, a in enumerate(argv):
        k = a.lstrip("-")
        if k in opts and i + 1 < len(argv):
            opts[k] = argv[i + 1]
    return opts


if __name__ == "__main__":
    opts = parse_args()
    bpy.ops.wm.read_factory_settings(use_empty=True)
    if opts["preview"]:
        preview(opts["preview"])
    else:
        ob, _ = build()
        ob.data.calc_loop_triangles()
        print("PARCEL_STATS triangles", len(ob.data.loop_triangles))
        if opts["out"]:
            export_glb(opts["out"])
            print("PARCEL_EXPORTED", opts["out"])
