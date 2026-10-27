"""The app icon (빵고양이 과학섬): the bread cat's and Dugi's faces side by side, rendered in the
dialogue portraits' storybook look (dugi_portrait.py: cel ramp, warm key sun, brown outline).

Run (headless, Blender 4.5):
    blender -b --factory-startup -P apps/lab3d/art_src/characters/app_icon.py -- \
        [--out apps/lab3d/assets/icon]

Writes (PNG):
  icon_fg_432.png    adaptive icon foreground, transparent; the faces inside the 288 px safe circle
  icon_bg_432.png    adaptive icon background, the island sky with a sea band
  icon_mono_432.png  monochrome layer (themed icons): the foreground's alpha in white
  icon_192.png       legacy launcher icon, foreground over background in a rounded square
  icon.png           512 px, the same picture (project icon)
"""
import math
import os
import sys

sys.dont_write_bytecode = True
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import bpy  # noqa: E402
import numpy as np  # noqa: E402
from mathutils import Vector  # noqa: E402

import bread_cat as bc  # noqa: E402
import dugi  # noqa: E402
import dugi_portrait as dp  # noqa: E402

FG = 432
RENDER = FG * 3   # rendered large, then box-filtered down (the legacy crops need more pixels)
SKY_TOP = "#9fd4f5"
SKY_LOW = "#e3f4ff"
SEA = "#4fb3d9"
SAND = "#f6dfa4"
CAM_POS = Vector((0.0, -6.0, 1.12))
CAM_TGT = Vector((0.0, 0.0, 1.12))
LENS = 100.0
# Each face: root offset, scale, head turn (deg about z, towards the other face).
CAT = {"at": Vector((-0.30, 0.0, 0.0)), "scale": 1.0, "turn": 12.0}
DUGI = {"at": Vector((0.34, 0.10, 0.28)), "scale": 1.0, "turn": -12.0}


def place(root, spec):
    root.location = spec["at"]
    root.scale = (spec["scale"],) * 3


def render_fg(path):
    bc.clear_scene()
    cat, _ = bc.build()
    place(cat, CAT)
    dugi.set_arm_variant("A")
    place(dugi.build(True, "open", False)[0], DUGI)
    heads = [o for o in bpy.data.objects if o.name.split(".")[0] == "Head"]
    for h, spec in zip(sorted(heads, key=lambda o: o.matrix_world.translation.x), (CAT, DUGI)):
        dp.rot_local(h, (0, 0, 1), spec["turn"])
    bpy.context.view_layer.update()
    scene = dp.setup_scene(RENDER)
    scene.render.image_settings.file_format = "PNG"
    scene.render.image_settings.color_mode = "RGBA"
    cam = scene.camera
    cam.location = CAM_POS
    cam.rotation_euler = (CAM_TGT - CAM_POS).to_track_quat("-Z", "Y").to_euler()
    cam.data.lens = LENS
    dp.OUTLINE = 0.014   # the camera stands farther back than the portraits'
    outline_mat = dp.make_outline_material()
    chars = [o for o in bpy.data.objects if o.type == "MESH"]
    for m in {s.material for o in chars for s in o.material_slots if s.material}:
        dp.toon(m)
    for o in chars:
        dp.add_outline(o, outline_mat)
        if o.hide_render:
            for ch in o.children:
                ch.hide_render = True
    scene.render.filepath = path
    bpy.ops.render.render(write_still=True)


def rgb(h):
    h = h.lstrip("#")
    return np.array([int(h[i:i + 2], 16) / 255 for i in (0, 2, 4)])


def background(size):
    y = np.linspace(0.0, 1.0, size)[:, None, None]
    img = (1 - y) * rgb(SKY_TOP) + y * rgb(SKY_LOW)
    img = np.broadcast_to(img, (size, size, 3)).copy()
    yy = np.arange(size)[:, None] / size
    xx = np.arange(size)[None, :] / size
    wave = 0.79 + 0.012 * np.sin(xx * math.tau * 2.0)
    img[(yy > wave)[..., None].repeat(3, 2)] = np.broadcast_to(rgb(SEA), (size, size, 3))[(yy > wave)[..., None].repeat(3, 2)]
    sand = yy > wave + 0.10
    img[sand] = rgb(SAND)
    return img


def load_rgba(path):
    im = bpy.data.images.load(path)
    w, h = im.size
    px = np.array(im.pixels[:]).reshape(h, w, 4)[::-1]   # Blender rows run bottom-up
    bpy.data.images.remove(im)
    return px


def save_rgba(arr, path):
    h, w = arr.shape[:2]
    im = bpy.data.images.new("out", w, h, alpha=True)
    im.pixels = np.ascontiguousarray(arr[::-1]).ravel()
    im.filepath_raw = path
    im.file_format = "PNG"
    im.save()
    bpy.data.images.remove(im)


def resize(arr, size):
    """Box-filtered downscale (premultiplied) to size x size."""
    n = arr.shape[0]
    idx = (np.arange(size + 1) * n / size).astype(int)
    pre = arr.copy()
    pre[..., :3] *= pre[..., 3:4]
    out = np.zeros((size, size, 4))
    for i in range(size):
        for j in range(size):
            out[i, j] = pre[idx[i]:idx[i + 1], idx[j]:idx[j + 1]].mean((0, 1))
    a = out[..., 3:4]
    out[..., :3] = np.where(a > 0, out[..., :3] / np.maximum(a, 1e-6), 0)
    return out


def composite(fg, size, radius):
    """`fg` is the large render; the result is `size` px with rounded corners."""
    bg = background(fg.shape[0])
    a = fg[..., 3:4]
    flat = np.concatenate([fg[..., :3] * a + bg * (1 - a), np.ones_like(a)], 2)
    # Legacy icons: the adaptive picture cropped to its middle 2/3, as a launcher's mask shows it.
    n = fg.shape[0]
    c = n // 6
    flat = resize(flat[c:n - c, c:n - c], size)
    yy, xx = np.mgrid[0:size, 0:size] + 0.5
    r = radius * size
    dx = np.maximum(np.abs(xx - size / 2) - (size / 2 - r), 0)
    dy = np.maximum(np.abs(yy - size / 2) - (size / 2 - r), 0)
    flat[..., 3] = np.clip(r - np.hypot(dx, dy) + 0.5, 0, 1)
    return flat


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    out_dir = "apps/lab3d/assets/icon"
    for i, a in enumerate(argv):
        if a == "--out":
            out_dir = argv[i + 1]
    out_dir = os.path.abspath(out_dir)
    os.makedirs(out_dir, exist_ok=True)
    fg_path = os.path.join(out_dir, "icon_fg_432.png")
    render_fg(fg_path)
    big = load_rgba(fg_path)
    fg = resize(big, FG)
    save_rgba(fg, fg_path)
    bg = np.concatenate([background(FG), np.ones((FG, FG, 1))], 2)
    save_rgba(bg, os.path.join(out_dir, "icon_bg_432.png"))
    mono = np.zeros_like(fg)
    mono[..., :3] = 1.0
    mono[..., 3] = fg[..., 3]
    save_rgba(mono, os.path.join(out_dir, "icon_mono_432.png"))
    save_rgba(composite(big, 192, 0.18), os.path.join(out_dir, "icon_192.png"))
    save_rgba(composite(big, 512, 0.18), os.path.join(out_dir, "icon.png"))
    print("ICON", out_dir)


if __name__ == "__main__":
    main()
