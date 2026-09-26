"""Build the 3D tortoise, and write a USDZ.

Run with:  blender --background --python build_tortoise.py -- [--out DIR]

Everything is parametric.  The shell's numbers were read off the three-view
drawing (#53); the character around it — head, eyes, mouth, legs, beret and
brush — was redrawn after the app icon's mascot, which is what the animal is
meant to look like.  The whole thing is normalised so it is **exactly 1.0 unit
long**, nose tip to brush tip, and the app scales that to whatever the canvas
is.

Axes while building (Blender's own): +X right, +Y forward (the head), +Z up.
The origin is the point on the ground directly under the shell's centre — the
tortoise's "position", i.e. what turns when it turns.  Export converts to
USD/RealityKit convention (+Y up, -Z forward).
"""

import math
import os
import sys

import bmesh
import bpy
from mathutils import Matrix, Vector
from mathutils.bvhtree import BVHTree

# --------------------------------------------------------------------------
# Shell — from the three-view drawing, and left exactly as it was.
# --------------------------------------------------------------------------

SHELL_R = 0.288  # radius in the ground plane
SHELL_BASE_Z = 0.115  # the dome's rim height
SHELL_TOP_Z = 0.380  # the shell's apex
SHELL_H = SHELL_TOP_Z - SHELL_BASE_Z

# 40 facets over the dome.  Blender counts the bare icosahedron as
# subdivision 1, so 2 is 80 faces on the whole sphere and 40 on the top half.
#
# This used to say "about 160", which is what 3 gives.  Both were put side by
# side when the rest of the animal went smooth, and the maintainer kept 40:
# the big facets are the digital half of the look, and at 160 the dome reads
# as a smooth one that happens to be tiled.
SHELL_SUBDIVISIONS = 2

# --------------------------------------------------------------------------
# The golden body.
#
# Head, neck, plastron, legs and tail are built as separate primitives and
# then *fused* into one surface — see FUSE_FILLET.  So the numbers below say
# where each part is; the smooth joins between them come from the fusing and
# are not modelled anywhere.
# --------------------------------------------------------------------------

# Plastron — the flat golden band the shell sits on, showing just outside the
# rim.  The rim has to stay buried in it: at the rim's radius this band's
# surface spans z = 0.118 +- 0.054 * sqrt(1 - (0.288/0.300)^2) = 0.103 .. 0.133,
# so a rim at 0.115 cannot open a seam.
BODY_R = (0.300, 0.306, 0.054)
BODY_Z = 0.118

# Head — big and round, the icon's proportions: a character's head rather
# than a reptile's snout.  The taper is small on purpose; the icon's face is a
# broad curve, and a strong taper turns it back into the teardrop this
# replaced.
HEAD_CENTRE = Vector((0.0, 0.392, 0.258))
HEAD_R = (0.122, 0.128, 0.114)  # half-width, half-length, half-height
HEAD_TAPER = 0.10  # how much narrower the face is than the back of the head
HEAD_PITCH = math.radians(6.0)  # nose up, so the face meets someone looking down

# Neck — short and thick, so the head sits on the body instead of on a stalk.
NECK = (Vector((0.0, 0.200, 0.150)), Vector((0.0, 0.330, 0.222)))
NECK_R = (0.086, 0.084)

# Legs — the icon's stubby pillars rather than the drawing's flippers: flat
# soles with a rounded edge, wider at the foot than where they meet the body.
#
# They lean *out* toward the foot, and that lean is a shear, not a tilt: a
# tilted pillar stands on the edge of its sole, a sheared one keeps the sole
# level on the paper.  Placed so each foot shows outside the shell's rim from
# above — the view the table mostly gets.
LEG_TOP_Z = 0.130
LEG_R_TOP = 0.046
LEG_R_FOOT = 0.068
FOOT_ROUND = 0.024  # radius of the sole's rounded edge
LEG_LEAN = 0.046  # how far outboard of its top each foot sits
FRONT_LEG = (0.222, 0.186)  # |x|, y of the sole's centre
REAR_LEG = (0.230, -0.172)

# Tail — a thick, gently drooping stalk that is the brush's handle.
#
# The icon curls it up over the back, and this one does not follow: the brush
# is the pen, so it trails along the paper behind the animal and sits on the
# end of the line being drawn.  Curled up, it would be a brush held in the air
# while something else draws.
TAIL = (
    Vector((0.0, -0.200, 0.125)),
    Vector((0.0, -0.320, 0.112)),
    Vector((0.0, -0.366, 0.084)),
)
TAIL_R = (0.052, 0.034)  # at the body, at the brush

# Fusing.  Every golden part becomes one signed distance field, sampled at
# FUSE_VOXEL, and then goes through a morphological *closing*: grown by
# FUSE_FILLET and shrunk back by the same distance.  Growing merges the parts
# and fills every crease where two of them meet; shrinking gives back exactly
# what was added everywhere else.  What is left is the same shapes joined by
# fillets of that radius, and convex surfaces exactly where they were.
#
# Blender's own "SDF Grid Fillet" node was the obvious tool and is not this:
# it smooths concave regions by a number of iterations rather than a
# distance, so the radius it gives cannot be written down.
FUSE_VOXEL = 0.0025
FUSE_FILLET = 0.024
GOLD_TRIANGLES = 16000  # the fused surface is decimated to this

# --------------------------------------------------------------------------
# The brush — a bulb of bristles tapering to a point, its tip dipped in paint.
# --------------------------------------------------------------------------

TUFT_BASE = Vector((0.0, -0.346, 0.090))  # inside the tail's end
TUFT_TIP = Vector((0.0, -0.470, 0.014))  # just clear of the paper
TUFT_R = 0.050
TUFT_WAIST = 0.30  # where along the tuft it is widest, 0 = base, 1 = tip
TUFT_NECK = 0.56  # radius at the base, as a fraction of TUFT_R
PAINT_LINE = 0.60  # where the paint starts, 0 = base, 1 = tip

# The paint runs down between the hairs in streaks, so its edge is ragged:
# (angle round the tuft in radians, how far down it runs, half-width).
#
# This is where the old tip's unevenness went.  The brush used to be a flared
# cone with alternate hairs cut a third short — chosen, after three
# level-tipped versions, over all of them.  The icon pass replaced it with the
# icon's pointed brush, and the unevenness survives as the paint's edge
# rather than the bristles'.
PAINT_STREAKS = [
    (0.15, 0.18, 0.20),
    (0.75, 0.10, 0.15),
    (1.30, 0.24, 0.19),
    (1.95, 0.13, 0.16),
    (2.55, 0.21, 0.20),
    (3.15, 0.09, 0.14),
    (3.70, 0.19, 0.18),
    (4.35, 0.26, 0.20),
    (4.95, 0.12, 0.15),
    (5.60, 0.20, 0.19),
]

# --------------------------------------------------------------------------
# Face
# --------------------------------------------------------------------------

# Eyes — the icon's: a white eye, a black ring, a grey pupil and a catchlight.
#
# They sit at the top front of the head, gazing up and ahead, because they
# have to read from above as well as from the front: the tortoise is mostly
# watched from over a table.  Half sunk into the head, so they are set in the
# face rather than stuck on it — prouder than this and the side view turns
# frog-eyed.
EYE_R = 0.052
EYE_ELEVATION = math.radians(27.0)  # where on the head, seen from its centre
EYE_AZIMUTH = math.radians(33.0)  # outward from straight ahead
EYE_PROUD = 0.46  # fraction of the radius standing out of the head
GAZE_FORWARD = 0.35  # how far the gaze leans from the surface normal toward ahead
# Measured off the icon's eye as the fraction of the white each disc covers:
# sin(39 deg) = 0.63 for the ring, sin(25 deg) = 0.42 for the pupil.
IRIS_ANGLE = math.radians(39.0)
PUPIL_ANGLE = math.radians(25.0)
# The catchlight sits low and toward the back of the pupil, where the icon
# draws it.
CATCHLIGHT_AT = math.radians(20.0)  # how far off the gaze
CATCHLIGHT_R = (0.20, 0.13, 0.05)  # as fractions of EYE_R; the last is its thickness

# Mouth — the icon's open smile: flat along the top with its corners turned
# up, round underneath.  Laid onto the face a hair proud of it.
MOUTH_DROP = -0.052  # below the head's centre, in the face's own frame
MOUTH_W = 0.034  # half-width
MOUTH_H = 0.020  # how far the open mouth drops
MOUTH_SMILE = 0.012  # how far the corners turn up

# --------------------------------------------------------------------------
# Beret
#
# The icon's: a soft pancake wider than the skull, so it overhangs, a little
# stalk on the crown, and worn tilted.  What makes it a beret rather than a
# purple disc is the overhang and the puff — the rim bulges out and rounds
# over into a gently domed top — and the stalk.  The old one had a rolled
# band round its edge instead, and read as a lid.
#
# Tilted back as well as to the side: a hat tipped forward covers the eyes
# from the angle the table sees it at.
# --------------------------------------------------------------------------

BERET_R = 0.100
BERET_POS = Vector((0.0, 0.370, 0.346))  # the centre of its band, on the head
BERET_TILT_BACK = math.radians(14.0)
BERET_TILT_SIDE = math.radians(-16.0)
# (radius, height) as fractions of BERET_R, from under the band to the crown,
# joined by a Catmull-Rom curve.  The band is at (0.60, 0); the widest point
# is the rim, at (1.00, 0.27).
BERET_PROFILE = [
    (0.00, 0.04),
    (0.60, 0.00),
    (0.80, 0.05),
    (0.95, 0.15),
    (1.00, 0.27),
    (0.97, 0.39),
    (0.86, 0.50),
    (0.64, 0.59),
    (0.34, 0.64),
    (0.00, 0.65),
]
STALK_R = 0.10  # as fractions of BERET_R
STALK_H = 0.24

# --------------------------------------------------------------------------
# Colours.
#
# The gold and the purple are the three-view drawing's, not the icon's.  The
# icon's are paler (#FCD878 against #DDB44F), and lit in 3D they washed out to
# cream — flat artwork carries its own shading in its colour, a lit model gets
# shading on top.  These two were already judged on the headset, in a room.
# The new parts take theirs from the icon: the grey pupil and the mouth.
# --------------------------------------------------------------------------

GOLD = (0.867, 0.706, 0.310)  # #DDB44F
# #ECCC85: the gold paled toward cream, so the bristles read as hair.
BRISTLE = (0.925, 0.800, 0.520)
PURPLE = (0.557, 0.184, 0.753)  # #8E2FC0: the beret, and the paint
WHITE = (0.980, 0.980, 0.980)
RING = (0.030, 0.030, 0.034)
PUPIL = (0.200, 0.200, 0.200)  # #333333, the icon's
MOUTH = (0.647, 0.216, 0.310)  # #A5374F, the icon's
SHELL_LOW = (0.341, 0.776, 0.910)  # blue, at the rim
SHELL_HIGH = (0.933, 0.447, 0.835)  # pink, at the apex
# The ramp runs up the dome's *height*, but the view that matters most is from
# above — the animal is being watched drawing on a table — and a dome seen from
# above shows only v^2 of its projected area below height v.  Mapped straight,
# three quarters of the top view comes out pink.  Squaring the coordinate puts
# the halfway colour at v = 0.71, which is where the drawing has it.
SHELL_RAMP_BIAS = 2.0

# How much of its own colour each material gives off, on top of what the room
# lends it.
#
# **This is not decoration, it is what makes the colours survive the room.** In
# a `.mixed` immersive space RealityKit lights the model with the *real* room,
# so a lamp-lit living room in the evening dims every one of these and tints
# what is left.  Lightening the colours instead would move the design to suit
# one room; emission leaves the design alone and lets it read at its own value
# in any room.
#
# 0.35 rather than more: the shading is what makes a model look solid, and
# emission is flat by definition, so all of it and the tortoise turns into a
# sticker.  At this level the facets still step and the pastels stop going
# grey.  Judged on the headset, in a room — a render cannot tell you this,
# because the renderer's lights are not the room's.
EMISSION = 0.35

GRADIENT_PNG = "shell_gradient.png"
EMISSION_PNG = "shell_gradient_emission.png"


# --------------------------------------------------------------------------
# Scene plumbing
# --------------------------------------------------------------------------


def clear_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)


def srgb_to_linear_one(u):
    return u / 12.92 if u <= 0.04045 else ((u + 0.055) / 1.055) ** 2.4


def linear_to_srgb(u):
    u = min(max(u, 0.0), 1.0)
    return 12.92 * u if u <= 0.0031308 else 1.055 * u ** (1 / 2.4) - 0.055


def srgb_to_linear(c):
    return tuple(srgb_to_linear_one(x) for x in c)


def plain_material(name, colour, roughness=0.45):
    """A Principled BSDF in one flat colour, which is all UsdPreviewSurface
    needs for everything except the shell."""
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes["Principled BSDF"]
    lin = srgb_to_linear(colour)
    bsdf.inputs["Base Color"].default_value = (*lin, 1.0)
    bsdf.inputs["Roughness"].default_value = roughness
    bsdf.inputs["Metallic"].default_value = 0.0
    # Its own colour, not white: emission at white would wash every part toward
    # grey and take the pastels with it, which is the problem, not the fix.
    bsdf.inputs["Emission Color"].default_value = (*lin, 1.0)
    bsdf.inputs["Emission Strength"].default_value = EMISSION
    mat.diffuse_color = (*lin, 1.0)
    return mat


def gradient_material(name, png_path, emission_png_path, roughness=0.35):
    """The shell's blue-to-pink ramp, as an image texture.

    A texture rather than vertex colours on purpose: `primvars:displayColor`
    is not reliably honoured once a material is bound, while an image feeding
    UsdPreviewSurface's diffuse is exactly what RealityKit reads.
    """
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    tree = mat.node_tree
    bsdf = tree.nodes["Principled BSDF"]
    bsdf.inputs["Roughness"].default_value = roughness
    bsdf.inputs["Metallic"].default_value = 0.0

    tex = tree.nodes.new("ShaderNodeTexImage")
    tex.image = bpy.data.images.load(png_path)
    tex.image.colorspace_settings.name = "sRGB"
    tex.interpolation = "Closest"
    tex.location = (-320, 260)
    tree.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])

    # The same ramp again, pre-dimmed — see `write_gradient_png`. A *ramp* and
    # not one flat emissive tint, because a single colour here would drag the
    # blue rim and the pink apex toward each other and flatten the gradient the
    # dome exists to show.
    emis = tree.nodes.new("ShaderNodeTexImage")
    emis.image = bpy.data.images.load(emission_png_path)
    emis.image.colorspace_settings.name = "sRGB"
    emis.interpolation = "Closest"
    emis.location = (-320, -80)
    tree.links.new(emis.outputs["Color"], bsdf.inputs["Emission Color"])
    # 1.0: the dimming is in the image, so a strength here would apply it twice.
    bsdf.inputs["Emission Strength"].default_value = 1.0
    return mat


def write_gradient_png(path, scale=1.0):
    """A 8x256 strip: blue at the bottom (v=0, the rim), pink at the top.

    Written by hand out of `zlib` and `struct` because Blender ships its own
    Python and it has no Pillow.  A PNG is a signature plus three chunks, and
    the whole image is 2KB — pulling a dependency into the build for that
    would cost more than the twenty lines.

    `scale` dims the whole ramp, and exists because the shell needs a *second*
    copy of it for emission.  Everything else can say "my own colour times
    EMISSION" in one shader input, but UsdPreviewSurface has no emissive
    strength — only `emissiveColor` — so feeding the diffuse texture straight
    into it makes the shell emit at full value while every other part emits at
    a third, and the dome washes out.  A Blender multiply node in between does
    not survive the export either: the preview-surface writer follows a fixed
    set of node patterns and drops the rest, silently.  So the scaling is baked
    into a second image.

    It is done in **linear** light, not on the stored bytes.  These ramp
    endpoints are sRGB, the texture is tagged sRGB, and the shader decodes it
    before shading — so scaling the bytes would darken the shell well past the
    third the other materials give off (0.35 of an sRGB byte is nearer 0.1 of
    the light it stands for).
    """
    import struct
    import zlib

    w, h = 8, 256
    raw = bytearray()
    for row in range(h):
        # Row 0 is the top of the image, which is v = 1.
        t = 1.0 - row / (h - 1)
        rgb = bytes(
            int(
                round(
                    255
                    * linear_to_srgb(
                        srgb_to_linear_one(
                            SHELL_LOW[i] + (SHELL_HIGH[i] - SHELL_LOW[i]) * t
                        )
                        * scale
                    )
                )
            )
            for i in range(3)
        )
        raw.append(0)  # filter type 0 (None) for this scanline
        raw += rgb * w

    def chunk(kind, payload):
        return (
            struct.pack(">I", len(payload))
            + kind
            + payload
            + struct.pack(">I", zlib.crc32(kind + payload) & 0xFFFFFFFF)
        )

    png = (
        b"\x89PNG\r\n\x1a\n"
        + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0))
        + chunk(b"IDAT", zlib.compress(bytes(raw), 9))
        + chunk(b"IEND", b"")
    )
    with open(path, "wb") as f:
        f.write(png)
    return path


def new_object(name, bm, materials, smooth=True):
    """`materials` is one material or a list, indexed by each face's
    `material_index`."""
    mesh = bpy.data.meshes.new(name)
    bm.to_mesh(mesh)
    bm.free()
    for poly in mesh.polygons:
        poly.use_smooth = smooth
    for material in materials if isinstance(materials, (list, tuple)) else [materials]:
        mesh.materials.append(material)
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    return obj


def icosphere(bm, subdivisions, radius=1.0):
    try:
        made = bmesh.ops.create_icosphere(bm, subdivisions=subdivisions, radius=radius)
    except TypeError:  # older bmesh spelled it "diameter"
        made = bmesh.ops.create_icosphere(
            bm, subdivisions=subdivisions, diameter=radius
        )
    return made["verts"]


def frame_along(axis, up=Vector((0.0, 0.0, 1.0))):
    """Two unit vectors square to `axis`, the first as near to `up` as it can be."""
    a = axis.normalized()
    e1 = up - a * up.dot(a)
    if e1.length < 1e-6:
        e1 = Vector((1.0, 0.0, 0.0)) - a * a.x
    e1.normalize()
    return e1, a.cross(e1).normalized()


def revolve(bm, profile, segments, origin, axis):
    """Sweep (r, h) points round `axis` through `origin`.

    A point with r == 0 at either end becomes a pole; an end that is not one
    is capped flat.  Returns the faces, so a caller can colour them.
    """
    a = axis.normalized()
    e1, e2 = frame_along(a)
    rings = []
    for r, h in profile:
        c = origin + a * h
        if r < 1e-9:
            rings.append([bm.verts.new(c)])
            continue
        rings.append(
            [
                bm.verts.new(c + (e1 * math.cos(ang) + e2 * math.sin(ang)) * r)
                for ang in (2 * math.pi * j / segments for j in range(segments))
            ]
        )
    faces = []
    for lo, hi in zip(rings, rings[1:]):
        for j in range(segments):
            k = (j + 1) % segments
            if len(lo) == 1:
                faces.append(bm.faces.new((lo[0], hi[k], hi[j])))
            elif len(hi) == 1:
                faces.append(bm.faces.new((lo[j], lo[k], hi[0])))
            else:
                faces.append(bm.faces.new((lo[j], lo[k], hi[k], hi[j])))
    for ring in (rings[0], rings[-1]):
        if len(ring) > 2:
            faces.append(bm.faces.new(ring))
    return faces


def catmull_rom(points, samples_per_span):
    """A smooth curve through `points`, as a list of (x, y)."""
    pts = [Vector(p) for p in points]
    out = []
    for i in range(len(pts) - 1):
        p0, p1, p2 = pts[max(i - 1, 0)], pts[i], pts[i + 1]
        p3 = pts[min(i + 2, len(pts) - 1)]
        for s in range(samples_per_span):
            t = s / samples_per_span
            out.append(
                0.5
                * (
                    2 * p1
                    + (p2 - p0) * t
                    + (2 * p0 - 5 * p1 + 4 * p2 - p3) * t * t
                    + (3 * p1 - p0 - 3 * p2 + p3) * t * t * t
                )
            )
    out.append(pts[-1])
    return [(max(p.x, 0.0), p.y) for p in out]


def head_forward():
    return Vector((0.0, math.cos(HEAD_PITCH), math.sin(HEAD_PITCH)))


def head_up():
    return Vector((0.0, -math.sin(HEAD_PITCH), math.cos(HEAD_PITCH)))


# --------------------------------------------------------------------------
# The shell
# --------------------------------------------------------------------------


def build_shell(material):
    """The dome: an icosphere squashed to the shell's proportions, with the
    bottom half thrown away.

    A subdivided icosahedron has a closed loop of vertices exactly at the
    equator (the cross-band edge midpoints land at z=0 and stay there through
    normalisation), so cutting it in half leaves a clean rim.

    Flat-shaded, and the only part of the animal that is: the faceting is the
    digital half of the look, and everything else is smooth.
    """
    bm = bmesh.new()
    icosphere(bm, subdivisions=SHELL_SUBDIVISIONS, radius=1.0)

    # Keep the top half.  A small epsilon so the equatorial ring survives.
    doomed = [v for v in bm.verts if v.co.z < -1e-5]
    bmesh.ops.delete(bm, geom=doomed, context="VERTS")
    for v in bm.verts:
        v.co = Vector(
            (v.co.x * SHELL_R, v.co.y * SHELL_R, v.co.z * SHELL_H + SHELL_BASE_Z)
        )

    # Cap the open rim.  It sits inside the golden body, so it is never seen —
    # but an open mesh shows its own inside through the silhouette at grazing
    # angles, and a cap costs a dozen triangles.
    rim = [e for e in bm.edges if len(e.link_faces) == 1]
    bmesh.ops.holes_fill(bm, edges=rim)

    # Per-face UVs: all three corners of a triangle take the v of the face's
    # centre, so each facet is one flat colour and the ramp still runs up the
    # dome.  That is the low-poly look in the drawing — flat steps, not a
    # smooth wash.
    uv = bm.loops.layers.uv.new("UVMap")
    lo, hi = SHELL_BASE_Z, SHELL_TOP_Z
    for face in bm.faces:
        v = (face.calc_center_median().z - lo) / (hi - lo)
        v = min(max(v, 0.0), 1.0) ** SHELL_RAMP_BIAS
        for loop in face.loops:
            loop[uv].uv = (0.5, v)

    return new_object("Shell", bm, material, smooth=False)


# --------------------------------------------------------------------------
# The golden body
# --------------------------------------------------------------------------


def add_ellipsoid(bm, centre, radii, subdivisions):
    for v in icosphere(bm, subdivisions=subdivisions, radius=1.0):
        v.co = centre + Vector(
            (v.co.x * radii[0], v.co.y * radii[1], v.co.z * radii[2])
        )


def add_sphere_sweep(bm, points, radii, samples):
    """Spheres along a path — a straight segment, or a quadratic Bezier
    through three points — which the distance field turns into one tube.

    Overlapping spheres rather than a swept tube with caps, because the field
    does not care how its input is put together, and a row of spheres has no
    ends to get wrong.  Spaced this closely the scallops between them are far
    below one voxel.
    """
    for i in range(samples + 1):
        t = i / samples
        if len(points) == 2:
            p = points[0].lerp(points[1], t)
        else:
            p = (
                points[0] * (1 - t) ** 2
                + points[1] * (2 * (1 - t) * t)
                + points[2] * (t * t)
            )
        r = radii[0] + (radii[1] - radii[0]) * t
        for v in icosphere(bm, subdivisions=3, radius=r):
            v.co += p


def add_head(bm):
    """An ellipsoid narrowed a little toward the face, then pitched nose-up."""
    rx, ry, rz = HEAD_R
    pitch = Matrix.Rotation(HEAD_PITCH, 3, "X")
    for v in icosphere(bm, subdivisions=5, radius=1.0):
        x, y, z = v.co.x * rx, v.co.y * ry, v.co.z * rz
        # f = 0 at the back of the head, 1 at the nose.  Through a smoothstep,
        # so the taper eases in rather than biting into the tip.
        f = min(max((y + ry) / (2 * ry), 0.0), 1.0)
        k = 1.0 - HEAD_TAPER * (f * f * (3.0 - 2.0 * f))
        v.co = HEAD_CENTRE + pitch @ Vector((x * k, y, z * k))


def add_leg(bm, x, y):
    """A pillar with a flat, round-edged sole, leaning out toward the foot."""
    c = FOOT_ROUND
    profile = [(0.0, 0.0)]
    for i in range(7):
        a = -math.pi / 2 + (math.pi / 2) * i / 6
        profile.append((LEG_R_FOOT - c + c * math.cos(a), c + c * math.sin(a)))
    profile += [(LEG_R_TOP, LEG_TOP_Z), (0.0, LEG_TOP_Z)]
    faces = revolve(bm, profile, 48, Vector((0.0, 0.0, 0.0)), Vector((0.0, 0.0, 1.0)))
    out = Vector((x, y, 0.0)).normalized()
    for v in {v for f in faces for v in f.verts}:
        # Sheared rather than tilted: every height moves sideways by an amount
        # that shrinks from LEG_LEAN at the sole to nothing at the top, so the
        # sole stays level.
        lean = LEG_LEAN * (1.0 - v.co.z / LEG_TOP_Z)
        v.co = Vector((x, y, 0.0)) + v.co + out * (lean - LEG_LEAN)


def fuse(obj):
    """Union every part of `obj` into one distance field, close it by
    FUSE_FILLET, and mesh it again.

    Built as a geometry-nodes modifier and applied, because the volume grid
    nodes are the only distance-field tools Blender's Python can reach.  The
    mesh that comes back is a voxel surface of several hundred thousand
    triangles, so it is decimated to GOLD_TRIANGLES; it is smooth enough that
    collapsing edges loses nothing that shows.
    """
    group = bpy.data.node_groups.new("Fuse", "GeometryNodeTree")
    group.interface.new_socket(
        "Geometry", in_out="INPUT", socket_type="NodeSocketGeometry"
    )
    group.interface.new_socket(
        "Geometry", in_out="OUTPUT", socket_type="NodeSocketGeometry"
    )
    nodes, link = group.nodes, group.links.new
    inputs, outputs = nodes.new("NodeGroupInput"), nodes.new("NodeGroupOutput")
    field = nodes.new("GeometryNodeMeshToSDFGrid")
    field.inputs["Voxel Size"].default_value = FUSE_VOXEL
    field.inputs["Band Width"].default_value = 3
    grow = nodes.new("GeometryNodeSDFGridOffset")
    grow.inputs["Distance"].default_value = FUSE_FILLET
    shrink = nodes.new("GeometryNodeSDFGridOffset")
    shrink.inputs["Distance"].default_value = -FUSE_FILLET
    surface = nodes.new("GeometryNodeGridToMesh")
    # The surface is where the distance is zero.  The node's default is 0.1,
    # which in a narrow-band field is outside every stored voxel — and meshes
    # to nothing at all, without an error.
    surface.inputs["Threshold"].default_value = 0.0
    smooth = nodes.new("GeometryNodeSetShadeSmooth")
    link(inputs.outputs[0], field.inputs["Mesh"])
    link(field.outputs[0], grow.inputs["Grid"])
    link(grow.outputs[0], shrink.inputs["Grid"])
    link(shrink.outputs[0], surface.inputs["Grid"])
    link(surface.outputs[0], smooth.inputs["Geometry"])
    link(smooth.outputs[0], outputs.inputs[0])

    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    obj.modifiers.new("Fuse", "NODES").node_group = group
    bpy.ops.object.modifier_apply(modifier="Fuse")
    voxels = sum(len(p.vertices) - 2 for p in obj.data.polygons)
    decimate = obj.modifiers.new("Decimate", "DECIMATE")
    decimate.ratio = min(1.0, GOLD_TRIANGLES / max(voxels, 1))
    bpy.ops.object.modifier_apply(modifier="Decimate")
    for poly in obj.data.polygons:
        poly.use_smooth = True


def build_body(material):
    bm = bmesh.new()
    add_ellipsoid(bm, Vector((0.0, 0.0, BODY_Z)), BODY_R, subdivisions=6)
    add_head(bm)
    add_sphere_sweep(bm, list(NECK), NECK_R, 12)
    for x, y in (FRONT_LEG, REAR_LEG):
        add_leg(bm, -x, y)
        add_leg(bm, x, y)
    add_sphere_sweep(bm, list(TAIL), TAIL_R, 24)
    obj = new_object("Body", bm, material)
    fuse(obj)
    # The meshing hands back a surface that has forgotten its material.
    obj.data.materials.clear()
    obj.data.materials.append(material)
    return obj


# --------------------------------------------------------------------------
# The brush
# --------------------------------------------------------------------------


def tuft_radius(t):
    """The bulb's profile: swelling from the tail to its waist, then tapering
    to a point with a slight inward curve, the way a wet round brush does."""
    if t <= TUFT_WAIST:
        g = TUFT_NECK + (1.0 - TUFT_NECK) * math.sin(0.5 * math.pi * t / TUFT_WAIST)
    else:
        u = (t - TUFT_WAIST) / (1.0 - TUFT_WAIST)
        g = max(1.0 - u * u, 0.0) ** 0.5 * max(1.0 - u, 0.0) ** 0.45
    return TUFT_R * g


def paint_line(theta):
    """Where the paint starts at this angle round the tuft."""
    drop = 0.0
    for at, depth, width in PAINT_STREAKS:
        d = abs((theta - at + math.pi) % (2 * math.pi) - math.pi)
        if d < width:
            drop = max(drop, depth * (1.0 - d / width))
    return PAINT_LINE - drop


def build_brush(bristle, paint):
    """A bulb of bristles tapering to a point, its tip dipped in paint.

    One mesh in two materials, and the edge between them is geometry, not a
    texture: the rings are *bent* so that one of them runs exactly along the
    paint's ragged line, everything above it is paint and everything below is
    bristle.  The streaks come out as sharp as the mesh rather than as sharp
    as a texture's pixels, and no UVs are needed.
    """
    segments, below, above = 96, 16, 22
    axis = TUFT_TIP - TUFT_BASE
    length = axis.length
    a = axis.normalized()
    e1, e2 = frame_along(a)
    bm = bmesh.new()
    rings = []
    for k in range(below + above):
        ring = []
        for j in range(segments):
            th = 2 * math.pi * j / segments
            edge = paint_line(th)
            if k <= below:
                t = edge * k / below
            else:
                t = edge + (1.0 - edge) * (k - below) / above
            radial = e1 * math.cos(th) + e2 * math.sin(th)
            point = TUFT_BASE + a * (t * length) + radial * tuft_radius(t)
            ring.append(bm.verts.new(point))
        rings.append(ring)
    tip = bm.verts.new(TUFT_TIP)
    for k in range(len(rings) - 1):
        lo, hi = rings[k], rings[k + 1]
        for j in range(segments):
            n = (j + 1) % segments
            face = bm.faces.new((lo[j], lo[n], hi[n], hi[j]))
            face.material_index = 1 if k >= below else 0
    last = rings[-1]
    for j in range(segments):
        bm.faces.new((last[j], last[(j + 1) % segments], tip)).material_index = 1
    # The base is inside the tail's end and never seen; capped so the mesh is
    # closed.
    bm.faces.new(rings[0])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    return new_object("Brush", bm, [bristle, paint])


# --------------------------------------------------------------------------
# Face
# --------------------------------------------------------------------------


def surface_hit(tree, origin, direction):
    """Where a ray first meets the golden body, and the surface normal there."""
    location, normal, _, _ = tree.ray_cast(origin, direction)
    if location is None:
        raise RuntimeError(
            f"nothing on the body along {tuple(direction)} from {tuple(origin)}"
        )
    return location, normal


def build_eyes(tree, white, ring, pupil):
    """Each eye is a sphere whose pole looks along its gaze, so the ring and
    the pupil end exactly on lines of latitude and come out as true circles —
    three materials on one mesh, no texture.  The catchlight is a flattened
    bead lying on the pupil.

    Placed against the *fused* head, found by casting a ray at it, so the eyes
    sit on the surface that is actually there rather than on the ellipsoid it
    started from.
    """
    objs = []
    fwd = head_forward()
    for side, sx in (("Left", -1.0), ("Right", 1.0)):
        d = Vector(
            (
                sx * math.sin(EYE_AZIMUTH) * math.cos(EYE_ELEVATION),
                math.cos(EYE_AZIMUTH) * math.cos(EYE_ELEVATION),
                math.sin(EYE_ELEVATION),
            )
        )
        d = (Matrix.Rotation(HEAD_PITCH, 3, "X") @ d).normalized()
        p, n = surface_hit(tree, HEAD_CENTRE + d * 0.5, -d)
        centre = p - n * (EYE_R * (1.0 - EYE_PROUD))
        gaze = (n + fwd * GAZE_FORWARD).normalized()

        latitudes = [PUPIL_ANGLE * i / 5 for i in range(1, 6)]
        latitudes += [
            PUPIL_ANGLE + (IRIS_ANGLE - PUPIL_ANGLE) * i / 4 for i in range(1, 5)
        ]
        latitudes += [
            IRIS_ANGLE + (math.pi - IRIS_ANGLE) * i / 18 for i in range(1, 18)
        ]
        profile = [(0.0, EYE_R)]
        profile += [(EYE_R * math.sin(t), EYE_R * math.cos(t)) for t in latitudes]
        profile += [(0.0, -EYE_R)]
        bm = bmesh.new()
        for face in revolve(bm, profile, 48, centre, gaze):
            h = (face.calc_center_median() - centre).normalized().dot(gaze)
            off = math.acos(max(-1.0, min(1.0, h)))
            if off < PUPIL_ANGLE:
                face.material_index = 2
            elif off < IRIS_ANGLE:
                face.material_index = 1
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
        objs.append(new_object(f"Eye{side}", bm, [white, ring, pupil]))

        # The catchlight: a bead flattened against the eye's surface, standing
        # a hair proud of it, low and toward the back of the pupil.
        up, _ = frame_along(gaze)
        back = -(fwd - gaze * fwd.dot(gaze)).normalized()
        towards = (back * 0.55 - up * 0.45).normalized()
        at = gaze * math.cos(CATCHLIGHT_AT) + towards * math.sin(CATCHLIGHT_AT)
        at.normalize()
        across = (towards - at * towards.dot(at)).normalized()
        along = at.cross(across).normalized()
        c = centre + at * EYE_R
        rx, ry, rz = (f * EYE_R for f in CATCHLIGHT_R)
        bm = bmesh.new()
        for v in icosphere(bm, subdivisions=3, radius=1.0):
            x, y, z = v.co
            v.co = c + across * (x * rx) + along * (y * ry) + at * (z * rz)
        objs.append(new_object(f"Catchlight{side}", bm, white))
    return objs


def build_mouth(tree, material):
    """The icon's open smile, laid onto the face a hair proud of it.

    A grid in the face's own frame, projected onto the fused head along the
    line of sight from the front — so it follows the curve of the face
    exactly.  Its corners are single points, where the flat top and the round
    bottom meet.
    """
    fwd, up = head_forward(), head_up()
    right = Vector((1.0, 0.0, 0.0))
    centre = HEAD_CENTRE + up * MOUTH_DROP
    columns, rows = 40, 8
    bm = bmesh.new()

    def laid(u, w):
        origin = centre + right * (u * MOUTH_W) + up * w + fwd * 0.4
        p, n = surface_hit(tree, origin, -fwd)
        return bm.verts.new(p + n * 0.0012)

    grid = []
    for i in range(columns + 1):
        u = -1.0 + 2.0 * i / columns
        top = MOUTH_SMILE * u * u
        bottom = top - MOUTH_H * max(1.0 - u * u, 0.0) ** 0.5
        if i in (0, columns):
            grid.append([laid(u, top)] * (rows + 1))
            continue
        grid.append([laid(u, top + (bottom - top) * k / rows) for k in range(rows + 1)])
    for i in range(columns):
        for k in range(rows):
            corners = []
            for v in (grid[i][k], grid[i + 1][k], grid[i + 1][k + 1], grid[i][k + 1]):
                if v not in corners:
                    corners.append(v)
            bm.faces.new(corners)
    bm.normal_update()
    for face in bm.faces:
        if face.normal.dot(fwd) < 0:
            face.normal_flip()
    return new_object("Mouth", bm, material)


# --------------------------------------------------------------------------
# Beret
# --------------------------------------------------------------------------


def build_beret(material):
    """The pancake swept round its own axis, the stalk on top, both tilted
    together so the stalk stays on the crown whatever the tilt is set to.  The
    head fills the band, which is what holds it on."""
    bm = bmesh.new()
    profile = [(r * BERET_R, h * BERET_R) for r, h in catmull_rom(BERET_PROFILE, 4)]
    revolve(bm, profile, 64, Vector((0.0, 0.0, 0.0)), Vector((0.0, 0.0, 1.0)))

    top = BERET_PROFILE[-1][1] * BERET_R
    sr, sh = STALK_R * BERET_R, STALK_H * BERET_R
    stalk = [(0.0, top - sh * 0.5), (sr, top - sh * 0.5)]
    for i in range(1, 6):
        a = (math.pi / 2) * i / 6
        stalk.append((sr * math.cos(a), top + sh - sr + sr * math.sin(a)))
    stalk.append((0.0, top + sh))
    revolve(bm, stalk, 24, Vector((0.0, 0.0, 0.0)), Vector((0.0, 0.0, 1.0)))

    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    m = (
        Matrix.Translation(BERET_POS)
        @ Matrix.Rotation(BERET_TILT_SIDE, 4, "Y")
        @ Matrix.Rotation(BERET_TILT_BACK, 4, "X")
    )
    for v in bm.verts:
        v.co = m @ v.co
    return new_object("Beret", bm, material)


# --------------------------------------------------------------------------
# Assembly and export
# --------------------------------------------------------------------------


def normalise_length(parts):
    """Scale everything about the origin so nose-to-brush is exactly 1.0.

    The parts are placed by eye, so their total lands near 1.0 but never on
    it; the app treats the model's scale as its length, so the contract is
    enforced here rather than hoped for.  Scaling about the origin keeps the
    origin on the ground under the shell's centre.
    """
    ys = [v.co.y for p in parts for v in p.data.vertices]
    k = 1.0 / (max(ys) - min(ys))
    for p in parts:
        p.data.transform(Matrix.Scale(k, 4))
    return k


def build(out_dir):
    clear_scene()
    png = write_gradient_png(os.path.join(out_dir, GRADIENT_PNG))
    emission_png = write_gradient_png(
        os.path.join(out_dir, EMISSION_PNG), scale=EMISSION
    )

    gold = plain_material("Gold", GOLD, roughness=0.50)
    bristle = plain_material("Bristle", BRISTLE, roughness=0.55)
    # Glossier than the beret, which is felt: wet paint shines.
    paint = plain_material("Paint", PURPLE, roughness=0.20)
    purple = plain_material("Purple", PURPLE, roughness=0.62)
    white = plain_material("EyeWhite", WHITE, roughness=0.22)
    ring = plain_material("EyeRing", RING, roughness=0.14)
    pupil = plain_material("EyePupil", PUPIL, roughness=0.14)
    mouth = plain_material("Mouth", MOUTH, roughness=0.40)
    # Matte rather than glossy: a tight highlight on a faceted dome blows one
    # or two facets to white and breaks the ramp exactly where it is meant to
    # be read.
    shell = gradient_material("Shell", png, emission_png, roughness=0.52)

    body = build_body(gold)
    tree = BVHTree.FromObject(body, bpy.context.evaluated_depsgraph_get())
    parts = [build_shell(shell), body, build_brush(bristle, paint), build_beret(purple)]
    parts += build_eyes(tree, white, ring, pupil)
    parts.append(build_mouth(tree, mouth))
    k = normalise_length(parts)
    tip = tuple(round(c * k, 3) for c in TUFT_TIP)
    print(f"[tortoise] normalised by {k:.4f}; brush tip at {tip}")

    root = bpy.data.objects.new("Tortoise", None)
    bpy.context.collection.objects.link(root)
    for p in parts:
        p.parent = root
    return root, parts


def report(parts):
    tris = 0
    for p in parts:
        for poly in p.data.polygons:
            tris += max(0, len(poly.vertices) - 2)
    lo = Vector((1e9, 1e9, 1e9))
    hi = Vector((-1e9, -1e9, -1e9))
    for p in parts:
        for v in p.data.vertices:
            lo = Vector((min(lo[i], v.co[i]) for i in range(3)))
            hi = Vector((max(hi[i], v.co[i]) for i in range(3)))
    print(f"[tortoise] parts={len(parts)} triangles={tris}")
    print(f"[tortoise] bounds x {lo.x:+.3f}..{hi.x:+.3f}  (width {hi.x - lo.x:.3f})")
    print(f"[tortoise] bounds y {lo.y:+.3f}..{hi.y:+.3f}  (length {hi.y - lo.y:.3f})")
    print(f"[tortoise] bounds z {lo.z:+.3f}..{hi.z:+.3f}  (height {hi.z - lo.z:.3f})")


def per_vertex_normals(source, destination):
    """Rewrite every smooth mesh's normals as one per vertex.

    Blender writes normals per *corner* — three per triangle, 36 bytes a
    triangle — whatever the shading, and on a smooth mesh all the corners that
    share a vertex carry the same normal, so two thirds of the file was the
    same numbers written again.  One per vertex is 12 bytes a vertex, and it
    more than halves the USDZ.  A mesh whose corners disagree anywhere has
    hard edges on purpose — the faceted shell — and keeps what Blender wrote.

    Written to a *new* file.  Saving a crate file over itself appends the
    edited values and leaves the old ones in place, so the file comes out
    bigger than it went in, with every normal now stored twice.
    """
    import numpy
    from pxr import Usd, UsdGeom, Vt

    stage = Usd.Stage.Open(source)
    for prim in stage.Traverse():
        if not prim.IsA(UsdGeom.Mesh):
            continue
        mesh = UsdGeom.Mesh(prim)
        if mesh.GetNormalsInterpolation() != UsdGeom.Tokens.faceVarying:
            continue
        corners = numpy.array(mesh.GetNormalsAttr().Get(), dtype=numpy.float64)
        indices = numpy.array(mesh.GetFaceVertexIndicesAttr().Get(), dtype=numpy.int64)
        summed = numpy.zeros((len(mesh.GetPointsAttr().Get()), 3))
        numpy.add.at(summed, indices, corners)
        length = numpy.linalg.norm(summed, axis=1, keepdims=True)
        merged = numpy.where(
            length > 0, summed / numpy.maximum(length, 1e-12), [0.0, 0.0, 1.0]
        )
        if numpy.abs(merged[indices] - corners).max() > 1e-3:
            continue
        mesh.GetNormalsAttr().Set(Vt.Vec3fArray.FromNumpy(merged.astype(numpy.float32)))
        mesh.SetNormalsInterpolation(UsdGeom.Tokens.vertex)
    stage.GetRootLayer().Export(destination)


def export_usdz(path):
    """Write the scene as a crate file, trim it, then package it.

    Blender can write a USDZ directly, and did until the normals pass: it
    packages as it writes, which leaves nothing to edit afterwards.  So the
    crate file comes out beside the textures it names, is rewritten into a
    second one next to it, and `UsdUtils` zips that together with the
    textures — which is what Blender's own USDZ path does anyway.
    """
    from pxr import UsdUtils

    staging = os.path.join(os.path.dirname(path), "usd")
    os.makedirs(staging, exist_ok=True)
    blender_usdc = os.path.join(staging, "Blender.usdc")
    usdc = os.path.join(staging, "Tortoise.usdc")
    for obj in bpy.context.scene.objects:
        obj.select_set(True)
    kwargs = dict(
        filepath=blender_usdc,
        selected_objects_only=False,
        export_animation=False,
        export_materials=True,
        export_uvmaps=True,
        export_normals=True,
        export_lights=False,
        export_cameras=False,
        generate_preview_surface=True,
        export_textures_mode="NEW",
        # RealityKit triangulates on load anyway; doing it here means the
        # quads are triangulated by Blender, where the result can be looked
        # at, rather than at runtime where it cannot.
        triangulate_meshes=True,
        # Blender is Z-up, USD/RealityKit is Y-up with -Z forward.  The
        # selections here are the operator's own defaults, written out so the
        # convention this asset is authored in is stated rather than assumed.
        convert_orientation=True,
        export_global_forward_selection="NEGATIVE_Z",
        export_global_up_selection="Y",
        root_prim_path="/Tortoise",
    )
    while True:
        try:
            bpy.ops.wm.usd_export(**kwargs)
            break
        except TypeError as exc:
            # Drop whichever keyword this Blender does not know and retry, so
            # the script survives an API rename rather than failing outright.
            message = str(exc).replace('"', "'")
            bad = message.split("'")
            dropped = next((k for k in list(kwargs) if k in bad), None)
            if dropped is None or dropped == "filepath":
                raise
            print(f"[tortoise] usd_export: dropping unsupported '{dropped}'")
            kwargs.pop(dropped)
    per_vertex_normals(blender_usdc, usdc)
    if os.path.exists(path):
        os.remove(path)
    if not UsdUtils.CreateNewUsdzPackage(usdc, path):
        raise RuntimeError(f"could not package {usdc}")


def main():
    argv = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
    out_dir = os.path.abspath(argv[argv.index("--out") + 1] if "--out" in argv else ".")
    os.makedirs(out_dir, exist_ok=True)

    _, parts = build(out_dir)
    report(parts)

    blend = os.path.join(out_dir, "tortoise.blend")
    bpy.ops.wm.save_as_mainfile(filepath=blend)
    usdz = os.path.join(out_dir, "Tortoise.usdz")
    export_usdz(usdz)
    print(f"[tortoise] wrote {blend}")
    print(f"[tortoise] wrote {usdz} ({os.path.getsize(usdz)} bytes)")


if __name__ == "__main__":
    main()
