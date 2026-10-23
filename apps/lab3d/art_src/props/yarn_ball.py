"""Yarn ball (털실 공) — the free-fall and projectile balls' look (Phase 1 Task 4g), made in Blender Python.

Run (headless):
    blender -b --factory-startup -P apps/lab3d/art_src/props/yarn_ball.py -- \
        [--out apps/lab3d/assets/props/yarn_ball.glb] [--preview DIR]

A sphere of exactly the balls' radius (0.25 m, so what is seen is the physics size) with smooth
normals and its own latitude-longitude UVs, and one grey texture of wound yarn (light: ridges 1.0, grooves 0.8, so the ball keeps its colour; the app
also divides by the texture's mean so the average is the ball's colour): a base winding and
several wraps on great circles in different directions, each a band of parallel strands with dark
grooves, the upper wraps casting a little shade on the ones below. The colour is not baked: the app
multiplies the texture by each ball's colour (ArtKit.lit_texture_material tint), so one asset makes
the red / yellow / violet free-fall balls and the red thrown ball, the strands a darker shade of the
same colour. The strands run in many directions, so a turning ball is seen turning.
- Units are metres; origin = the ball's centre. glTF / Godot: +Y up.
- Budget: 1 mesh, 1 material, 1 texture (512 x 256), < 400 triangles.
"""

import math
import os
import sys

import bmesh
import bpy
import numpy as np
from mathutils import Vector

RADIUS = 0.25
SEGMENTS = 20
RINGS = 11
TEX_W, TEX_H = 512, 256
RIDGE = 1.0          # strand top (sRGB grey, times the ball colour)
GROOVE = 0.8         # between strands (light enough that the ball keeps its colour: the mean is near 1)
EDGE_SHADE = 0.84    # a wrap's edge darkens the winding under it
# Wraps: (normal of the great circle, half width of the band as sin of the angle, strand spacing rad).
# The first is the base winding over the whole ball.
WRAPS = [
    ((0.0, 0.0, 1.0), 1.01, 0.115),
    ((0.83, 0.2, 0.52), 0.42, 0.105),
    ((-0.35, 0.86, 0.37), 0.4, 0.105),
    ((0.25, -0.55, 0.8), 0.36, 0.1),
    ((-0.7, -0.45, -0.55), 0.38, 0.105),
    ((0.1, 0.95, -0.3), 0.33, 0.1),
]


def unit(v):
    v = np.asarray(v, dtype=float)
    return v / np.linalg.norm(v)


def direction(u, v):
    """Unit direction of texture coordinate (u, v): u = longitude / 2 pi, v = 0 south pole .. 1 north."""
    lon = u * 2.0 * math.pi
    lat = (v - 0.5) * math.pi
    return np.stack([np.cos(lat) * np.cos(lon), np.cos(lat) * np.sin(lon), np.sin(lat) * np.ones_like(lon)], axis=-1)


def value_noise(d, freq, seed):
    rng = np.random.default_rng(seed)
    w = rng.normal(size=(3, 6))
    return 0.5 + 0.5 * np.sin((d @ w[:, :3]) * freq + w[0, 3:]).mean(axis=-1)


def build_texture():
    u = (np.arange(TEX_W) + 0.5) / TEX_W
    v = (np.arange(TEX_H) + 0.5) / TEX_H
    uu, vv = np.meshgrid(u, v)
    d = direction(uu, vv)
    grey = np.zeros(uu.shape)
    for k, (n, half, spacing) in enumerate(WRAPS):
        s = d @ unit(n)
        a = np.arcsin(np.clip(s, -1, 1))                  # angle off the great circle
        inside = np.abs(s) < half
        # Strands: parallel circles every `spacing` rad, a rounded profile (ridge .. groove).
        phase = np.cos(2.0 * math.pi * a / spacing)
        strand = GROOVE + (RIDGE - GROOVE) * (0.5 + 0.5 * phase) ** 0.6
        # A soft twist along each strand (the plies), so a strand is not a flat line.
        lon_k = np.arctan2(d @ unit(np.cross(n, [0.3, 0.5, 0.8])), d @ unit(np.cross(n, np.cross(n, [0.3, 0.5, 0.8]))))
        strand *= 0.97 + 0.03 * np.cos(lon_k * 40.0 + a * 25.0)
        if k == 0:
            grey = strand
        else:
            edge = np.clip((half - np.abs(s)) / 0.05, 0.0, 1.0)
            shade = np.where((np.abs(s) >= half) & (np.abs(s) < half + 0.06), EDGE_SHADE + (1 - EDGE_SHADE) * (np.abs(s) - half) / 0.06, 1.0)
            grey = np.where(inside, strand * (0.88 + 0.12 * edge), grey * shade)
    grey *= 0.97 + 0.03 * value_noise(d, 9.0, 3)
    lin = np.where(grey <= 0.04045, grey / 12.92, ((grey + 0.055) / 1.055) ** 2.4)
    print("YARN_TEXTURE mean sRGB %.3f, mean linear %.3f" % (grey.mean(), lin.mean()))
    grey = np.clip(grey, 0.0, 1.0)
    rgba = np.stack([grey, grey, grey, np.ones_like(grey)], axis=-1)
    img = bpy.data.images.new("yarn_ball_atlas", TEX_W, TEX_H, alpha=False)
    img.pixels.foreach_set(rgba.astype(np.float32).ravel())   # Blender rows go bottom to top: v as above
    return img


def build_mesh():
    bm = bmesh.new()
    uv_layer = bm.loops.layers.uv.new("UVMap")
    rows = []
    for r in range(RINGS + 1):
        v = r / RINGS
        lat = (v - 0.5) * math.pi
        row = []
        for s in range(SEGMENTS + 1):
            u = s / SEGMENTS
            lon = u * 2.0 * math.pi
            p = Vector((math.cos(lat) * math.cos(lon), math.cos(lat) * math.sin(lon), math.sin(lat))) * RADIUS
            row.append((bm.verts.new(p), u, v))
        rows.append(row)
    for r in range(RINGS):
        for s in range(SEGMENTS):
            a, b, c, e = rows[r][s], rows[r][s + 1], rows[r + 1][s + 1], rows[r + 1][s]
            if r == 0:
                quad = [a, c, e]          # south cap: triangles
            elif r == RINGS - 1:
                quad = [a, b, e]          # north cap
            else:
                quad = [a, b, c, e]
            try:
                f = bm.faces.new([q[0] for q in quad])
            except ValueError:
                continue
            for loop, q in zip(f.loops, quad):
                loop[uv_layer].uv = (q[1], q[2])
            f.smooth = True
    me = bpy.data.meshes.new("YarnBall")
    bm.normal_update()
    bm.to_mesh(me)
    bm.free()
    for poly in me.polygons:
        poly.use_smooth = True
    return me


def make_material(img, tint=(1.0, 1.0, 1.0, 1.0)):
    mat = bpy.data.materials.new("YarnBall")
    mat.use_nodes = True
    nt = mat.node_tree
    bsdf = nt.nodes["Principled BSDF"]
    tex = nt.nodes.new("ShaderNodeTexImage")
    tex.image = img
    tex.interpolation = "Linear"
    if tint == (1.0, 1.0, 1.0, 1.0):
        nt.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
    else:   # preview only: the app tints the grey texture per ball
        mix = nt.nodes.new("ShaderNodeMixRGB")
        mix.blend_type = "MULTIPLY"
        mix.inputs[0].default_value = 1.0
        mix.inputs[2].default_value = tint
        nt.links.new(tex.outputs["Color"], mix.inputs[1])
        nt.links.new(mix.outputs[0], bsdf.inputs["Base Color"])
    bsdf.inputs["Roughness"].default_value = 0.9
    if "Specular IOR Level" in bsdf.inputs:
        bsdf.inputs["Specular IOR Level"].default_value = 0.1
    return mat


def build(tint=(1.0, 1.0, 1.0, 1.0), img=None, name="YarnBall"):
    img = img or build_texture()
    ob = bpy.data.objects.new(name, build_mesh())
    ob.data.materials.append(make_material(img, tint))
    bpy.context.scene.collection.objects.link(ob)
    return ob, img


def triangles(ob):
    me = ob.data
    me.calc_loop_triangles()
    return len(me.loop_triangles)


def srgb_to_lin(c):
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def hexlin(h):
    h = h.lstrip("#")
    return tuple(srgb_to_lin(int(h[i:i + 2], 16) / 255) for i in (0, 2, 4)) + (1.0,)


def preview(out_dir):
    """Renders the red / yellow / violet balls (the app's ball colours) on grass, front and close."""
    os.makedirs(out_dir, exist_ok=True)
    img = None
    for i, (col, x) in enumerate((("#ff3b3b", -0.65), ("#ffc61a", 0.0), ("#4b2a9a", 0.65))):
        ob, img = build(hexlin(col), img, "Ball%d" % i)
        ob.location = (x, 0.0, RADIUS)
        ob.rotation_euler = (0.4 * i, 0.7 * i, 0.3)
    scene = bpy.context.scene
    for eng in ("BLENDER_EEVEE_NEXT", "BLENDER_EEVEE"):
        try:
            scene.render.engine = eng
            break
        except TypeError:
            pass
    scene.view_settings.view_transform = "Standard"
    scene.render.resolution_x = 900
    scene.render.resolution_y = 500
    world = bpy.data.worlds.new("W")
    scene.world = world
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs[0].default_value = hexlin("#62c0ff")
    bpy.ops.mesh.primitive_plane_add(size=20)
    g = bpy.context.active_object
    gm = bpy.data.materials.new("grass"); gm.use_nodes = True
    gm.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = hexlin("#5fd04a")
    g.data.materials.append(gm)
    sun_d = bpy.data.lights.new("sun", "SUN"); sun_d.energy = 3.0
    sun = bpy.data.objects.new("sun", sun_d); scene.collection.objects.link(sun)
    sun.rotation_euler = (math.radians(50), 0, math.radians(-35))
    cam_d = bpy.data.cameras.new("cam"); cam_d.lens = 50
    cam = bpy.data.objects.new("cam", cam_d); scene.collection.objects.link(cam)
    scene.camera = cam
    for name, loc, look in (("front", (0.0, -3.2, 0.7), (0.0, 0.0, 0.25)), ("close", (0.35, -1.0, 0.5), (0.0, 0.0, 0.25))):
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
        print("YARN_STATS triangles", triangles(ob))
        if opts["out"]:
            export_glb(opts["out"])
            print("YARN_EXPORTED", opts["out"])
