"""The start screen picture (빵고양이 과학섬, 2026-10-27 user request): the faces of Puppy, the bread
cat and Dugi side by side (the map's order: Puppy left, the cat in the middle, Dugi right), rendered
in the dialogue portraits' storybook look (dugi_portrait.py: cel ramp, warm key sun, brown outline),
transparent. splash_banner.py then adds the "빵고양이 과학섬" banner under them.

Run (headless, Blender 4.5), then the banner (system Python with Pillow):
    blender -b --factory-startup -P apps/lab3d/art_src/characters/splash.py -- [--out <dir>]
    python3 apps/lab3d/art_src/characters/splash_banner.py [--trio <dir>/splash_trio.png]

Writes splash_trio.png (RGBA, W x H) into --out (default: the scratch dir /tmp/op-splash).
"""
import math
import os
import sys

sys.dont_write_bytecode = True
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import bpy  # noqa: E402
from mathutils import Vector  # noqa: E402

import bread_cat as bc  # noqa: E402
import dugi  # noqa: E402
import dugi_portrait as dp  # noqa: E402
import puppy  # noqa: E402

W, H = 1500, 720
CAM_POS = Vector((0.0, -7.0, 1.1))
CAM_TGT = Vector((0.0, 0.0, 1.0))
LENS = 70.0
# Each: root offset (x, y, z), scale, turn (deg about z, towards the middle).
PUPPY = {"at": Vector((-1.0, 0.0, 0.0)), "scale": 1.0, "turn": 14.0}
CAT = {"at": Vector((0.0, -0.15, -0.25)), "scale": 1.15, "turn": 0.0}
DUGI = {"at": Vector((1.0, 0.0, 0.0)), "scale": 1.0, "turn": -14.0}


def place(root, spec):
    root.location = spec["at"]
    root.scale = (spec["scale"],) * 3
    root.rotation_euler = (0.0, 0.0, math.radians(spec["turn"]))


def new_roots(before):
    return [o for o in bpy.data.objects if o.name not in before and o.parent is None]


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    out_dir = "/tmp/op-splash"
    for i, a in enumerate(argv):
        if a == "--out":
            out_dir = argv[i + 1]
    out_dir = os.path.abspath(out_dir)
    os.makedirs(out_dir, exist_ok=True)

    bc.clear_scene()
    cat, _ = bc.build()
    place(cat, CAT)
    dugi.set_arm_variant("A")
    d_root, _ = dugi.build(True, "open", False)
    place(d_root, DUGI)
    p_root, _ = puppy.build(False, False, True)
    place(p_root, PUPPY)
    bpy.context.view_layer.update()

    scene = dp.setup_scene(W)
    scene.render.resolution_x = W
    scene.render.resolution_y = H
    scene.render.image_settings.file_format = "PNG"
    scene.render.image_settings.color_mode = "RGBA"
    cam = scene.camera
    cam.location = CAM_POS
    cam.rotation_euler = (CAM_TGT - CAM_POS).to_track_quat("-Z", "Y").to_euler()
    cam.data.lens = LENS
    dp.OUTLINE = 0.016   # the camera stands farther back than the portraits'
    outline_mat = dp.make_outline_material()
    chars = [o for o in bpy.data.objects if o.type == "MESH"]
    for m in {s.material for o in chars for s in o.material_slots if s.material}:
        dp.toon(m)
    for o in chars:
        dp.add_outline(o, outline_mat)
        if o.hide_render:
            for ch in o.children:
                ch.hide_render = True
    scene.render.filepath = os.path.join(out_dir, "splash_trio.png")
    bpy.ops.render.render(write_still=True)
    print("TRIO", scene.render.filepath)


if __name__ == "__main__":
    main()
