"""Painted face expressions for the dialogue portraits (2026-10-29 user request "대화시 표정을 좀 더
다양하게"). Dugi's and Puppy's faces are painted into their texture atlases by numpy SDFs
(dugi.paint_head / puppy.paint_head). This module paints the expression variants with the same
helpers, the same colours and the same stroke widths, so a portrait's face stays in the storybook
style. It is used only when a portrait asks for a face (`face` dict); without one the head is
painted exactly as before, so the in-game models (dugi.glb, puppy.glb) do not change.

A face is a dict (every key optional):
  eyes   "dot" (the model's small bean, default) | "happy" (closed upward arcs ^ ^) |
         "wide" (bigger round eyes, two highlights) | "look" (beans glancing up to the viewer's right) |
         "soft" (beans a little smaller and lower: worried)
  brows  None | "raised" (high arches) | "worried" (inner ends up) | "think" (one raised, one flat) |
         "happy" (small high arcs)
  mouth  a model mouth ("open", "calm" for Dugi, "open" for Puppy) | "big" (wide open smile) |
         "o" (small round open mouth) | "hmm" (short flat line, a little to one side) |
         "wavy" (a wobbly line)
  blush  multiplier of the blush's opacity / size (1 = the model's)
"""
import numpy as np

from bread_cat import blend, sd_ellipse, sd_segment, smooth_fill


def eyes(img, qx, qz, front, aa, ex_abs, ez, rx, rz, style, eye_col):
    """The two eyes at (+-ex_abs, ez) in the head's painted face coordinates (metres)."""
    white = np.ones(3)
    for s in (-1, 1):
        ex = s * ex_abs
        if style == "happy":
            # an upward arc (^): a ring's upper half around a centre a little below the eye
            r = rx * 1.15
            cx, cz = ex, ez - rz * 0.35
            ring = np.abs(np.sqrt((qx - cx) ** 2 + (qz - cz) ** 2) - r) - 0.0052
            arc = np.where(qz > cz + r * 0.05, ring, 1.0)
            blend(img, smooth_fill(arc, aa) * front, eye_col)
        elif style == "wide":
            blend(img, smooth_fill(sd_ellipse(qx, qz, ex, ez + 0.004, rx * 1.28, rz * 1.22), aa) * front, eye_col)
            blend(img, smooth_fill(sd_ellipse(qx, qz, ex - rx * 0.38, ez + rz * 0.48, rx * 0.36, rz * 0.33), aa) * front, white)
            blend(img, smooth_fill(sd_ellipse(qx, qz, ex + rx * 0.35, ez - rz * 0.35, rx * 0.16, rz * 0.15), aa) * front, white)
        elif style == "look":
            ox, oz = rx * 0.32, rz * 0.30
            blend(img, smooth_fill(sd_ellipse(qx, qz, ex + ox, ez + oz, rx * 0.95, rz * 0.95), aa) * front, eye_col)
            blend(img, smooth_fill(sd_ellipse(qx, qz, ex + ox - rx * 0.30, ez + oz + rz * 0.33, rx * 0.30, rz * 0.28), aa) * front, white)
        elif style == "soft":
            blend(img, smooth_fill(sd_ellipse(qx, qz, ex, ez - rz * 0.12, rx * 0.88, rz * 0.86), aa) * front, eye_col)
            blend(img, smooth_fill(sd_ellipse(qx, qz, ex - rx * 0.30, ez + rz * 0.18, rx * 0.30, rz * 0.27), aa) * front, white)
        else:   # "dot": the model's bean with one small highlight
            blend(img, smooth_fill(sd_ellipse(qx, qz, ex, ez, rx, rz), aa) * front, eye_col)
            blend(img, smooth_fill(sd_ellipse(qx, qz, ex - rx * 0.33, ez + rz * 0.34, rx * 0.32, rz * 0.29), aa) * front, white)


def brows(img, qx, qz, front, aa, ex_abs, bz, style, col, length=0.034, alpha=0.9):
    """Small brow strokes above the eyes (bz = their height)."""
    if not style:
        return
    w = 0.0042
    for s in (-1, 1):
        cx = s * ex_abs
        inner, outer = cx - s * length * 0.5, cx + s * length * 0.5
        if style == "worried":      # inner ends up
            sdf = sd_segment(qx, qz, inner, bz + 0.010, outer, bz - 0.006) - w
        elif style == "raised":     # a high arch
            r = length * 0.75
            ring = np.abs(np.sqrt((qx - cx) ** 2 + (qz - (bz + 0.004 - r * 0.55)) ** 2) - r) - w
            sdf = np.where((qz > bz + 0.004 - r * 0.25) & (np.abs(qx - cx) < length * 0.55), ring, 1.0)
        elif style == "think":      # the viewer's right brow up, the left one flat and a little low
            if s > 0:
                sdf = sd_segment(qx, qz, inner, bz + 0.004, outer, bz + 0.014) - w
            else:
                sdf = sd_segment(qx, qz, inner, bz - 0.006, outer, bz - 0.004) - w
        elif style == "happy":      # small soft arcs
            r = length * 0.9
            ring = np.abs(np.sqrt((qx - cx) ** 2 + (qz - (bz - r * 0.75)) ** 2) - r) - w * 0.9
            sdf = np.where((qz > bz - r * 0.45) & (np.abs(qx - cx) < length * 0.5), ring, 1.0)
        else:
            continue
        blend(img, smooth_fill(sdf, aa) * front, col, alpha)


def mouth(img, qx, qz, front, aa, cz, style, mcol, tongue_col, philtrum, scale=1.0, stroke=0.0040):
    """A mouth under the nose. `cz` = the model mouth's top line, `philtrum` = the sdf of the short
    line from the nose (kept on every face), `scale` the model's mouth width (Dugi 1, Puppy ~0.95)."""
    if style == "big":
        half = np.where(qz < cz, sd_ellipse(qx, qz, 0.0, cz, 0.054 * scale, 0.066 * scale), 1.0)
        blend(img, smooth_fill(np.minimum(philtrum, half), aa) * front, mcol)
        tongue = np.maximum(sd_ellipse(qx, qz, 0.0, cz - 0.062 * scale, 0.034 * scale, 0.030 * scale), half + 0.003)
        blend(img, smooth_fill(tongue, aa) * front, tongue_col)
    elif style == "o":
        oc = cz - 0.026 * scale
        o = sd_ellipse(qx, qz, 0.0, oc, 0.021 * scale, 0.026 * scale)
        blend(img, smooth_fill(np.minimum(philtrum, o), aa) * front, mcol)
        tongue = np.maximum(sd_ellipse(qx, qz, 0.0, oc - 0.020 * scale, 0.014 * scale, 0.011 * scale), o + 0.003)
        blend(img, smooth_fill(tongue, aa) * front, tongue_col)
    elif style == "hmm":
        mz = cz - 0.012 * scale
        line = sd_segment(qx, qz, -0.008 * scale, mz - 0.002, 0.026 * scale, mz + 0.003) - stroke
        blend(img, smooth_fill(np.minimum(philtrum, line), aa) * front, mcol)
    elif style == "wavy":
        mz = cz - 0.012 * scale
        span = 0.030 * scale
        wave = mz + 0.0045 * np.sin((qx / span) * np.pi * 2.0)
        sdf = np.where(np.abs(qx) < span, np.abs(qz - wave) - stroke, 1.0)
        blend(img, smooth_fill(np.minimum(philtrum, sdf), aa) * front, mcol)
    else:
        raise ValueError("face_kit.mouth: unknown style %r" % style)
