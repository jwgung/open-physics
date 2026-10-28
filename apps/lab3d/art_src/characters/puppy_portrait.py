"""Puppy's dialogue portrait (2026-10-28, story "별 조각 찾기"): a transparent bust render of the
approved puppy model in the same storybook look as Dugi's portraits (dugi_portrait.py: the same
cel ramp, warm key sun, cool sky fill, faint rim and brown inverted-hull outline), for the retro game
dialogue box when Puppy speaks (his clues, the prologue and the finale).

Run (headless, Blender 4.5):
    blender -b --factory-startup -P apps/lab3d/art_src/characters/puppy_portrait.py -- \
        [--out apps/lab3d/assets/characters/portraits] [--size 512]

Writes puppy_talk.webp (RGBA, size x size, lossless WebP): the model as exported by puppy.py (hat,
bow tie, the "과학섬" flag in his right paw), the head tilted a little towards the words. The
portrait always stands on the box's left end, so he turns a little to the viewer's right. Eevee, so
the pixels are not guaranteed bit-identical between machines.
"""
import os
import sys

sys.dont_write_bytecode = True
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import bpy  # noqa: E402
from mathutils import Vector  # noqa: E402

import bread_cat as bc  # noqa: E402
import dugi_portrait as dp  # noqa: E402
import puppy  # noqa: E402

# Puppy is 1.27 m tall (Dugi 1.65 m): the camera looks at his bust from the same direction, nearer.
CAM_POS = Vector((0.66, -3.25, 0.98))
CAM_TGT = Vector((0.0, 0.0, 0.90))
EXPRESSIONS = {
    "talk": {"head": (-5.0, 8.0), "ears": (6.0, 3.0)},
}


def render(name, spec, out_dir, size):
    bc.clear_scene()
    puppy.set_arm_variant("A")
    puppy.build(False, True, True)
    objs = {o.name: o for o in bpy.data.objects}
    dp.rot_local(objs["Head"], (0, 1, 0), spec["head"][0])
    dp.rot_local(objs["Head"], (0, 0, 1), spec["head"][1])
    dp.rot_local(objs["EarL"], (1, 0, 0), spec["ears"][0])
    dp.rot_local(objs["EarR"], (1, 0, 0), spec["ears"][1])
    bpy.context.view_layer.update()
    dp.CAM_POS = CAM_POS
    dp.CAM_TGT = CAM_TGT
    scene = dp.setup_scene(size)
    outline_mat = dp.make_outline_material()
    chars = [o for o in bpy.data.objects if o.type == "MESH"]
    for m in {s.material for o in chars for s in o.material_slots if s.material}:
        dp.toon(m)
    for o in chars:
        dp.add_outline(o, outline_mat)
    scene.render.filepath = os.path.join(out_dir, "puppy_%s.webp" % name)
    bpy.ops.render.render(write_still=True)
    print("PORTRAIT", scene.render.filepath)


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    out_dir = "apps/lab3d/assets/characters/portraits"
    size = 512
    for i, a in enumerate(argv):
        if a == "--out":
            out_dir = argv[i + 1]
        elif a == "--size":
            size = int(argv[i + 1])
    os.makedirs(out_dir, exist_ok=True)
    for name, spec in EXPRESSIONS.items():
        bpy.ops.wm.read_factory_settings(use_empty=True)
        render(name, spec, os.path.abspath(out_dir), size)


if __name__ == "__main__":
    main()
