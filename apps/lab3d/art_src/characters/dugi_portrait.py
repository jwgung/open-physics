"""Dugi's dialogue portraits (Phase 1 Task 4h): transparent bust renders of the approved model in the
storybook look, for the retro game dialogue box (apps/lab3d/scripts/shell/dialogue_box.gd).

Run (headless, Blender 4.5):
    blender -b --factory-startup -P apps/lab3d/art_src/characters/dugi_portrait.py -- \
        [--out apps/lab3d/assets/characters/portraits] [--size 512]

Writes dugi_talk.webp, dugi_smile.webp and dugi_point.webp (RGBA, size x size, lossless WebP):
  talk   the model as exported (open smile), head tilted a little, listening ears
  smile  the calm mouth (dugi.py --mouth calm), a happy tilt the other way
  point  the open smile, the left arm (viewer's right) raised so the pointer stick's red tip is up
         beside the head, towards the words: the portrait always stands on the box's left end
The model is built by dugi.py in this process (the same code as assets/characters/dugi.glb, arm
variant A, monocle on) and rendered like the user-approved trio picture: a two-step cel ramp under a
warm key sun and a cool sky fill, a faint rim on the lit side, and the brown inverted-hull outline
(#6e4630) grown along the mesh normals, the app's outline. Transparent background (film
transparent); Eevee, so the pixels are not guaranteed bit-identical between machines.
"""
import math
import os
import sys

sys.dont_write_bytecode = True
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import bpy  # noqa: E402
import numpy as np  # noqa: E402
from mathutils import Matrix, Quaternion, Vector  # noqa: E402

import bread_cat as bc  # noqa: E402
import dugi  # noqa: E402

OUTLINE_COL = "#6e4630"
OUTLINE = 0.009          # m, at the portrait camera's distance
SHADE = 0.86
TOON_T = 0.30
CAM_POS = Vector((0.55, -3.55, 1.02))
CAM_TGT = Vector((0.0, 0.0, 1.02))
LENS = 85.0
EXPRESSIONS = {
    "talk": {"mouth": "open", "head": (-6.0, 4.0), "ears": (8.0, 4.0), "point": None},
    "smile": {"mouth": "calm", "head": (7.0, -5.0), "ears": (4.0, 10.0), "point": None},
    "point": {"mouth": "open", "head": (-4.0, 6.0), "ears": (10.0, 6.0), "point": (1.05, -0.55, 1.30)},
}


def srgb_to_lin(c):
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def hexlin(h):
    h = h.lstrip("#")
    return tuple(srgb_to_lin(int(h[i:i + 2], 16) / 255) for i in (0, 2, 4)) + (1.0,)


def rot_local(ob, axis, deg):
    ob.rotation_mode = "QUATERNION"
    ob.rotation_quaternion = ob.rotation_quaternion @ Quaternion(axis, math.radians(deg))


def make_outline_material():
    m = bpy.data.materials.new("Outline")
    m.use_nodes = True
    nt = m.node_tree
    for n in list(nt.nodes):
        if n.type != "OUTPUT_MATERIAL":
            nt.nodes.remove(n)
    em = nt.nodes.new("ShaderNodeEmission")
    em.inputs[0].default_value = hexlin(OUTLINE_COL)
    tr = nt.nodes.new("ShaderNodeBsdfTransparent")
    geo = nt.nodes.new("ShaderNodeNewGeometry")
    mx = nt.nodes.new("ShaderNodeMixShader")
    nt.links.new(geo.outputs["Backfacing"], mx.inputs[0])
    nt.links.new(tr.outputs[0], mx.inputs[1])
    nt.links.new(em.outputs[0], mx.inputs[2])
    nt.links.new(mx.outputs[0], nt.nodes["Material Output"].inputs[0])
    for attr, val in (("surface_render_method", "DITHERED"), ("blend_method", "HASHED")):
        if hasattr(m, attr):
            setattr(m, attr, val)
    return m


def base_color(nt):
    b = [n for n in nt.nodes if n.type == "BSDF_PRINCIPLED"][0]
    if b.inputs["Base Color"].links:
        return b.inputs["Base Color"].links[0].from_socket
    rgb = nt.nodes.new("ShaderNodeRGB")
    rgb.outputs[0].default_value = b.inputs["Base Color"].default_value
    return rgb.outputs[0]


def toon(mat, rim=0.12):
    """Colour x two-step ramp of the diffuse light, a faint warm rim on the lit side -> emission."""
    nt = mat.node_tree
    out = [n for n in nt.nodes if n.type == "OUTPUT_MATERIAL"][0]
    col = base_color(nt)
    dif = nt.nodes.new("ShaderNodeBsdfDiffuse")
    s2r = nt.nodes.new("ShaderNodeShaderToRGB")
    bw = nt.nodes.new("ShaderNodeRGBToBW")
    ramp = nt.nodes.new("ShaderNodeValToRGB")
    ramp.color_ramp.interpolation = "LINEAR"
    e = ramp.color_ramp.elements
    e[0].position = TOON_T
    e[0].color = (SHADE * 0.95, SHADE * 0.90, SHADE * 0.97, 1)
    e[1].position = TOON_T + 0.03
    e[1].color = (1.0, 0.985, 0.955, 1)
    mul = nt.nodes.new("ShaderNodeMix")
    mul.data_type = "RGBA"
    mul.blend_type = "MULTIPLY"
    mul.inputs[0].default_value = 1.0
    nt.links.new(dif.outputs[0], s2r.inputs[0])
    nt.links.new(s2r.outputs[0], bw.inputs[0])
    nt.links.new(bw.outputs[0], ramp.inputs[0])
    nt.links.new(col, mul.inputs[6])
    nt.links.new(ramp.outputs[0], mul.inputs[7])
    last = mul.outputs[2]
    lw = nt.nodes.new("ShaderNodeLayerWeight")
    lw.inputs[0].default_value = 0.35
    rr = nt.nodes.new("ShaderNodeValToRGB")
    rr.color_ramp.interpolation = "LINEAR"
    rr.color_ramp.elements[0].position = 0.62
    rr.color_ramp.elements[0].color = (0, 0, 0, 1)
    rr.color_ramp.elements[1].position = 0.70
    rr.color_ramp.elements[1].color = (1, 1, 1, 1)
    nt.links.new(lw.outputs["Facing"], rr.inputs[0])
    lit = nt.nodes.new("ShaderNodeMath")
    lit.operation = "GREATER_THAN"
    lit.inputs[1].default_value = TOON_T + 0.03
    nt.links.new(bw.outputs[0], lit.inputs[0])
    m1 = nt.nodes.new("ShaderNodeMath")
    m1.operation = "MULTIPLY"
    nt.links.new(rr.outputs[0], m1.inputs[0])
    nt.links.new(lit.outputs[0], m1.inputs[1])
    m2 = nt.nodes.new("ShaderNodeMath")
    m2.operation = "MULTIPLY"
    m2.inputs[1].default_value = rim
    nt.links.new(m1.outputs[0], m2.inputs[0])
    add = nt.nodes.new("ShaderNodeMix")
    add.data_type = "RGBA"
    add.blend_type = "SCREEN"
    add.inputs[7].default_value = (1.0, 0.95, 0.82, 1)
    nt.links.new(m2.outputs[0], add.inputs[0])
    nt.links.new(last, add.inputs[6])
    emi = nt.nodes.new("ShaderNodeEmission")
    nt.links.new(add.outputs[2], emi.inputs[0])
    nt.links.new(emi.outputs[0], out.inputs[0])


def add_outline(ob, outline_mat):
    """Inverted hull grown along the mesh's normals (the app's outline pass)."""
    dup = ob.copy()
    dup.data = ob.data.copy()
    bpy.context.scene.collection.objects.link(dup)
    dup.parent = ob
    dup.matrix_parent_inverse = Matrix.Identity(4)
    dup.location = (0, 0, 0)
    dup.rotation_mode = "XYZ"
    dup.rotation_euler = (0, 0, 0)
    dup.scale = (1, 1, 1)
    dup.modifiers.clear()
    me = dup.data
    for i in range(len(me.materials)):
        me.materials[i] = outline_mat
    for slot in dup.material_slots:
        slot.link = "OBJECT"
        slot.material = outline_mat
    n = len(me.vertices)
    cn = np.empty(len(me.loops) * 3)
    me.corner_normals.foreach_get("vector", cn)
    lv = np.empty(len(me.loops), dtype=np.int64)
    me.loops.foreach_get("vertex_index", lv)
    vn = np.zeros((n, 3))
    vn[lv] = cn.reshape(-1, 3)
    co = np.empty(n * 3)
    me.vertices.foreach_get("co", co)
    sc = np.array(ob.matrix_world.to_scale())
    co = co.reshape(-1, 3) + vn * (OUTLINE / sc)[None, :]
    me.vertices.foreach_set("co", co.ravel())
    me.update()


def setup_scene(size):
    scene = bpy.context.scene
    for eng in ("BLENDER_EEVEE_NEXT", "BLENDER_EEVEE"):
        try:
            scene.render.engine = eng
            break
        except TypeError:
            pass
    scene.view_settings.view_transform = "Standard"
    scene.render.resolution_x = scene.render.resolution_y = size
    scene.render.film_transparent = True
    scene.render.filter_size = 1.2
    scene.eevee.taa_render_samples = 64
    scene.render.image_settings.file_format = "WEBP"
    scene.render.image_settings.color_mode = "RGBA"
    scene.render.image_settings.quality = 100   # lossless
    world = bpy.data.worlds.new("W")
    scene.world = world
    world.use_nodes = True
    bg = world.node_tree.nodes["Background"]
    bg.inputs[0].default_value = hexlin("#e6f0ff")
    bg.inputs[1].default_value = 0.38
    sun_d = bpy.data.lights.new("sun", "SUN")
    sun_d.energy = 3.0
    sun_d.angle = math.radians(14)
    sun_d.color = (1.0, 0.95, 0.86)
    sun = bpy.data.objects.new("sun", sun_d)
    scene.collection.objects.link(sun)
    sun.rotation_euler = Vector((0.45, 1.0, -1.1)).normalized().to_track_quat("-Z", "Y").to_euler()
    cam_d = bpy.data.cameras.new("cam")
    cam = bpy.data.objects.new("cam", cam_d)
    scene.collection.objects.link(cam)
    scene.camera = cam
    cam.location = CAM_POS
    cam.rotation_euler = (CAM_TGT - CAM_POS).to_track_quat("-Z", "Y").to_euler()
    cam_d.lens = LENS
    return scene


def render(name, spec, out_dir, size):
    bc.clear_scene()
    dugi.set_arm_variant("A")
    dugi.build(True, spec["mouth"], True, 1 if spec["point"] is not None else -1)
    objs = {o.name: o for o in bpy.data.objects}
    rot_local(objs["Head"], (0, 1, 0), spec["head"][0])
    rot_local(objs["Head"], (0, 0, 1), spec["head"][1])
    rot_local(objs["EarL"], (1, 0, 0), spec["ears"][0])
    rot_local(objs["EarR"], (1, 0, 0), spec["ears"][1])
    if spec["point"] is None:
        objs["Pointer"].hide_render = True   # resting arm: no stick (as in the app)
    else:
        dugi.pose_point(objs["ArmL"], objs["PointerTip"], spec["point"])
    bpy.context.view_layer.update()
    scene = setup_scene(size)
    outline_mat = make_outline_material()
    chars = [o for o in bpy.data.objects if o.type == "MESH"]
    for m in {s.material for o in chars for s in o.material_slots if s.material}:
        toon(m)
    for o in chars:
        add_outline(o, outline_mat)
        if o.hide_render:
            for ch in o.children:
                ch.hide_render = True
    scene.render.filepath = os.path.join(out_dir, "dugi_%s.webp" % name)
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
