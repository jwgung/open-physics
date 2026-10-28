"""Puppy's dialogue portraits (2026-10-28, story "별 조각 찾기"; expressions 2026-10-29): transparent
bust renders of the approved puppy model in the same storybook look as Dugi's portraits
(dugi_portrait.py: the same cel ramp, warm key sun, cool sky fill, faint rim and brown inverted-hull
outline), for the retro game dialogue box when Puppy speaks (his clues, riddles, the prologue and
the finale).

Run (headless, Blender 4.5):
    blender -b --factory-startup -P apps/lab3d/art_src/characters/puppy_portrait.py -- \
        [--out apps/lab3d/assets/characters/portraits] [--size 512] [--only happy,thinking]

Writes puppy_<face>.webp (RGBA, size x size, lossless WebP), one per expression (Story.FACES):
  explain    the model's own face (open smile), the free paw (viewer's right) up towards the words:
             telling a clue (Puppy gives clues and story lines, never the science: that is Dugi's)
  happy      closed ^ ^ eyes, a wide open smile, more blush, the flag raised high
  surprised  wide round eyes, raised brows, a small "o" mouth, the free paw up
  thinking   eyes glancing up to the side, one brow raised, a short flat mouth, the paw at the chin
  worried    smaller, lower eyes, brows with the inner ends up, a wobbly mouth, the ears drooping,
             the head down a little
Like Dugi, the model has no face rig: the expression repaints a copy of the face (face_kit) and
poses the nodes it has (head, ears, arms, flag). The in-game model (puppy.glb) is not rebuilt. The
camera is fitted to Puppy's height (1.27 m) and looks at his chest from Dugi's direction (the
head tilted a little towards the words). Eevee, so the pixels are not guaranteed bit-identical
between machines.
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
# head: (tilt about y, turn about z) deg; nod: about x (+ = chin down); ears: (left, right) deg about x;
# arm_l: the free paw's target; flag: (paw target, pole top target) to raise the flag (pose_flag).
EXPRESSIONS = {
    "explain": {"head": (-5.0, 8.0), "ears": (6.0, 3.0), "arm_l": (0.62, -0.55, 0.92)},
    "happy": {"face": {"eyes": "happy", "mouth": "big", "blush": 1.5}, "head": (7.0, -3.0), "nod": -4.0,
              "ears": (-4.0, -4.0), "flag": ((-0.42, -0.30, 0.80), (-0.70, -0.22, 1.55))},
    "surprised": {"face": {"eyes": "wide", "brows": "raised", "mouth": "o"}, "head": (0.0, 4.0), "nod": -6.0,
                  "ears": (-10.0, -10.0), "arm_l": (0.45, -0.42, 0.78)},
    "thinking": {"face": {"eyes": "look", "brows": "think", "mouth": "hmm"}, "head": (-9.0, 8.0),
                 "ears": (4.0, 10.0), "arm_l": (0.06, -0.36, 0.58)},
    "worried": {"face": {"eyes": "soft", "brows": "worried", "mouth": "wavy", "blush": 0.8},
                "head": (4.0, 4.0), "nod": 8.0, "ears": (14.0, 14.0)},
}


def render(name, spec, out_dir, size):
    bc.clear_scene()
    puppy.set_arm_variant("A")
    puppy.build(False, True, True, spec.get("face"))
    objs = {o.name: o for o in bpy.data.objects}
    dp.rot_local(objs["Head"], (1, 0, 0), spec.get("nod", 0.0))
    dp.rot_local(objs["Head"], (0, 1, 0), spec["head"][0])
    dp.rot_local(objs["Head"], (0, 0, 1), spec["head"][1])
    dp.rot_local(objs["EarL"], (1, 0, 0), spec["ears"][0])
    dp.rot_local(objs["EarR"], (1, 0, 0), spec["ears"][1])
    if spec.get("arm_l") is not None:
        puppy.pose_point(objs["ArmL"], objs["HandL"], spec["arm_l"])
    if spec.get("flag") is not None:
        puppy.pose_flag(objs["ArmR"], objs["HandR"], objs["Flag"], objs["FlagCloth"], *spec["flag"])
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
    only = None
    for i, a in enumerate(argv):
        if a == "--out":
            out_dir = argv[i + 1]
        elif a == "--size":
            size = int(argv[i + 1])
        elif a == "--only":
            only = argv[i + 1].split(",")
    os.makedirs(out_dir, exist_ok=True)
    for name, spec in EXPRESSIONS.items():
        if only and name not in only:
            continue
        bpy.ops.wm.read_factory_settings(use_empty=True)
        render(name, spec, os.path.abspath(out_dir), size)


if __name__ == "__main__":
    main()
