"""Outline mesh contract of the character glbs (art-direction.md section 11), checked in Blender.

    blender -b --factory-startup -P apps/lab3d/tools/mesh_contract.py -- apps/lab3d/assets/characters/*.glb

Per mesh: glTF vertex / triangle counts; seam normal agreement (vertices at one position must share
one normal, else the inverted-hull outline tears there); and, after welding the UV-seam copies,
open / non-manifold edges (closed shells -> 0) and shells wound inward (signed volume <= 0).
Exits 1 when any mesh breaks the contract. The app's headless tests check the seam normals and the
closed shells on the imported meshes (tests/island_cast_checks.gd), so CI needs no Blender; the
inward-shell check is Blender-only.
"""
import math
import sys

import bmesh
import bpy
import numpy as np

SPLIT_DEG = 0.5
bad = 0
for path in sys.argv[sys.argv.index("--") + 1:]:
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=path)
    print("==", path.split("/")[-1])
    total_v = total_t = 0
    for ob in sorted(bpy.data.objects, key=lambda o: o.name):
        if ob.type != "MESH":
            continue
        me = ob.data
        nv = len(me.vertices)
        me.calc_loop_triangles()
        nt = len(me.loop_triangles)
        cn = np.array([c.vector[:] for c in me.corner_normals])
        lv = np.array([lp.vertex_index for lp in me.loops])
        vn = np.zeros((nv, 3))
        vn[lv] = cn
        co = np.array([v.co[:] for v in me.vertices])
        _, inv = np.unique(np.round(co / 1e-5).astype(np.int64), axis=0, return_inverse=True)
        inv = inv.ravel()
        worst = 0.0
        for g in np.unique(inv):
            idx = np.where(inv == g)[0]
            if len(idx) > 1:
                d = vn[idx] @ vn[idx].T
                worst = max(worst, math.degrees(math.acos(max(-1.0, min(1.0, d.min())))))
        bm = bmesh.new()
        bm.from_mesh(me)
        bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-5)
        open_e = sum(1 for e in bm.edges if not e.is_manifold)
        bm.faces.ensure_lookup_table()
        seen, shells, inward = set(), 0, 0
        for f in bm.faces:
            if f.index in seen:
                continue
            stack, vol = [f], 0.0
            seen.add(f.index)
            while stack:
                g = stack.pop()
                vs = [v.co for v in g.verts]
                for i in range(1, len(vs) - 1):
                    vol += vs[0].dot(vs[i].cross(vs[i + 1])) / 6.0
                for e in g.edges:
                    for h in e.link_faces:
                        if h.index not in seen:
                            seen.add(h.index)
                            stack.append(h)
            shells += 1
            inward += vol <= 0.0
        bm.free()
        ok = worst <= SPLIT_DEG and open_e == 0 and inward == 0
        bad += not ok
        print(f"  {'ok ' if ok else 'BAD'} {ob.name:10s} verts {nv:5d} tris {nt:5d} worst seam split {worst:5.1f} deg"
              f"  shells {shells:2d} open edges {open_e:3d} inward shells {inward}")
        total_v += nv
        total_t += nt
    print(f"  TOTAL verts {total_v} tris {total_t}")
print("MESH CONTRACT:", "PASS" if bad == 0 else f"FAIL ({bad} mesh(es))")
sys.exit(1 if bad else 0)
