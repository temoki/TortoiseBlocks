"""Build the 3D tortoise from the three-view drawing, and write a USDZ.

Run with:  blender --background --python build_tortoise.py -- [--out DIR]

Everything is parametric: the numbers below were read off the drawing (in
pixels) and normalised so the whole animal is **1.0 unit long**, nose tip to
brush tip.  The app scales that to whatever the canvas is.

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

# --------------------------------------------------------------------------
# Proportions, read off the three-view drawing.
#
# Top view was measured over 565px nose-to-brush; the side view over 540px.
# Both are the same animal, so every measurement below is divided by its own
# view's total and expressed as a fraction of the overall length L = 1.0.
# --------------------------------------------------------------------------

L = 1.0  # total length, nose tip to brush tip

# Shell — a low-poly dome.  325px across, 150px tall (side view).
#
# The rim height is the one number that has to be got right against the body,
# and getting it wrong is not subtle: with the rim *below* the body's top the
# golden ellipsoid rises through the dome and the animal reads as a sausage
# with a hat.  The rim must sit just inside the body's surface — see BODY_Z.
SHELL_R = 0.288  # radius in the ground plane
SHELL_BASE_Z = 0.115  # the dome's rim height
SHELL_TOP_Z = 0.380  # the animal's full height, from the side view
SHELL_H = SHELL_TOP_Z - SHELL_BASE_Z

# Body / plastron — the golden rim that shows under the shell in the front
# and rear views.  Barely wider than the dome (0.014 of rim, which is what the
# drawing shows) and *flat*: it is a rim, not a torso.
BODY_R_X = 0.302
BODY_R_Y = 0.312
BODY_R_Z = 0.082
BODY_Z = 0.098
# Where the body's surface crosses the dome's rim radius:
#   0.098 +- 0.082 * sqrt(1 - (0.288/0.302)^2) = 0.073 .. 0.123
# so a rim at 0.115 is buried 0.008 deep and the seam cannot open.

# Head — a teardrop: rounded point at the nose, widest about two thirds back.
HEAD_NOSE_Y = 0.543  # the nose, measured forward of the shell's centre
HEAD_LEN = 0.250
HEAD_R_X = 0.089
HEAD_R_Z = 0.093
HEAD_Z = 0.209
# How much narrower the nose is than the back of the head.  Applied through a
# smoothstep, not a power curve: an ellipsoid is already closing toward its
# own end, so a taper that keeps biting there compounds into a spike.  The
# drawing's head stays broad most of the way and only rounds off near the tip,
# which is a shallow taper, not a steep one.
HEAD_TAPER = 0.26

# Beret — a purple one, worn on the head with a backward tilt.
#
# The drawing reads as a collar round the neck and it is not one; this is a
# hat.  Taken literally the drawing puts the purple almost upright, facing
# forward, which is exactly why it reads as a collar: at that angle the crown
# points at the shell, the head hides it, and all that is left to see is the
# rolled edge — a ring.  Built that way once and it still looked like a
# collar, so the tilt is set by what makes it legible as a hat instead, and
# the drawing loses this one.  It is the element the drawing was wrong about.
#
# What makes it a beret rather than a purple disc: a domed crown wider than
# the skull, so it overhangs; the rolled band round the bottom edge; and the
# little nub on top.
# Every dimension goes through one factor, so resizing the hat stays a single
# number instead of four that can drift apart.  0.70 is against the first pass,
# which sat too big on the head.
BERET_SCALE = 0.70
BERET_R = 0.115 * BERET_SCALE  # the crown, and the ring the rolled edge follows
BERET_DOME = 0.065 * BERET_SCALE  # how far the crown rises above the band
BERET_RIM = 0.020 * BERET_SCALE  # the rolled edge; outer radius is R + this
BERET_NUB = 0.019 * BERET_SCALE
# Sitting a little lower and straighter than the big one did: a small cap at a
# steep angle perches rather than is worn, because its front edge lifts off the
# skull by more of the head's own height the smaller it gets.
BERET_POS = (0.0, 0.332, 0.274)
BERET_TILT = math.radians(28.0)

# Legs — four flippers, splayed out at roughly 40 degrees.
#
# Their centres sit almost exactly on the shell's edge circle (measured: 0.280
# from the centre against a shell radius of 0.288), so what shows outside the
# rim is roughly one half-length of flipper.  That is the drawing's silhouette.
LEG_R = (0.082, 0.068, 0.054)  # outward, along, up
LEG_Z = 0.048  # centre height; the underside just kisses the ground
FRONT_LEG = (0.220, 0.202)  # |x|, y
REAR_LEG = (0.236, -0.194)
LEG_SPLAY = math.radians(40.0)

# Tail — a tapering shaft ending in a paintbrush.  This is the pen.
#
# Both halves are generated from *one* segment, base to tip, and that is the
# point rather than tidiness: built separately, the shaft took a pitch to match
# its two end heights while the brush stayed level, and the join came out with
# a visible kink in it.  A brush is one straight object; there is nowhere for a
# second axis to come from.
TAIL_BASE = Vector((0.0, -0.270, 0.092))
TAIL_TIP = Vector((0.0, -0.457, 0.070))
FERRULE_T = 0.66  # where the golden shaft stops and the bristles start
TAIL_R_BASE = 0.050
TAIL_R_TIP = 0.034
BRUSH_R = 0.056
BRISTLES = 10
BRISTLE_NOTCH = 0.34  # how far back the gaps between hairs are cut

# This tip is **deliberately uneven**: alternate hairs stop a third of the
# bundle short, so the end is a zigzag rather than a cut.
#
# Which is worth a note, because it looks like an oversight and is not.  Three
# other tips were built after this one — the notch swapped for radial fluting
# so the end came out flat, then a bellied profile, then fourteen separately
# modelled strands splaying to a level cut.  The maintainer looked at all of
# them and chose this one to come back to.  So a future pass that "fixes" the
# ragged end is redoing work that was already done and already rejected.


# Eyes — big, forward, sitting proud of the snout.
#
# They have to read from *above* as well as from the front: the drawing shows
# both eyes whole in the top view, and the top view is the one the app will
# mostly show, since the tortoise is being watched drawing on a table.  So the
# pupils face up-and-forward rather than out to the sides.
EYE_X = 0.052
EYE_Y = 0.444
EYE_Z = 0.250
EYE_R = 0.043
PUPIL_R = 0.031
PUPIL_OUT = 0.017  # how far the pupil pokes out of the white
PUPIL_AIM = (0.42, 0.70, 0.58)  # outward, forward, up — normalised on use

# --------------------------------------------------------------------------
# Colours, sampled from the drawing.
# --------------------------------------------------------------------------

GOLD = (0.867, 0.706, 0.310)
PURPLE = (0.557, 0.184, 0.753)
SHELL_LOW = (0.341, 0.776, 0.910)  # blue, at the rim
SHELL_HIGH = (0.933, 0.447, 0.835)  # pink, at the apex
# The ramp runs up the dome's *height*, but the view that matters most is from
# above — the animal is being watched drawing on a table — and a dome seen from
# above shows only v^2 of its projected area below height v.  Mapped straight,
# three quarters of the top view comes out pink.  Squaring the coordinate puts
# the halfway colour at v = 0.71, which is where the drawing has it.
SHELL_RAMP_BIAS = 2.0
WHITE = (0.980, 0.980, 0.980)
BLACK = (0.055, 0.055, 0.060)

GRADIENT_PNG = "shell_gradient.png"


# --------------------------------------------------------------------------
# Scene plumbing
# --------------------------------------------------------------------------


def clear_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)


def srgb_to_linear(c):
    def one(u):
        return u / 12.92 if u <= 0.04045 else ((u + 0.055) / 1.055) ** 2.4

    return tuple(one(x) for x in c)


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
    mat.diffuse_color = (*lin, 1.0)
    return mat


def gradient_material(name, png_path, roughness=0.35):
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
    return mat


def write_gradient_png(path):
    """A 8x256 strip: blue at the bottom (v=0, the rim), pink at the top.

    Written by hand out of `zlib` and `struct` because Blender ships its own
    Python and it has no Pillow.  A PNG is a signature plus three chunks, and
    the whole image is 2KB — pulling a dependency into the build for that
    would cost more than the twenty lines.
    """
    import struct
    import zlib

    w, h = 8, 256
    raw = bytearray()
    for row in range(h):
        # Row 0 is the top of the image, which is v = 1.
        t = 1.0 - row / (h - 1)
        rgb = bytes(
            int(round(255 * (SHELL_LOW[i] + (SHELL_HIGH[i] - SHELL_LOW[i]) * t)))
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


def new_object(name, bm, material, smooth=True):
    mesh = bpy.data.meshes.new(name)
    bm.to_mesh(mesh)
    bm.free()
    for poly in mesh.polygons:
        poly.use_smooth = smooth
    mesh.materials.append(material)
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    return obj


def icosphere(bm, subdivisions, radius=1.0):
    try:
        bmesh.ops.create_icosphere(bm, subdivisions=subdivisions, radius=radius)
    except TypeError:  # older bmesh spelled it "diameter"
        bmesh.ops.create_icosphere(bm, subdivisions=subdivisions, diameter=radius)


def cone(bm, segments, r1, r2, depth, matrix=None):
    kwargs = dict(
        cap_ends=True,
        cap_tris=False,
        segments=segments,
        depth=depth,
        matrix=matrix or Matrix.Identity(4),
    )
    try:
        bmesh.ops.create_cone(bm, radius1=r1, radius2=r2, **kwargs)
    except TypeError:
        bmesh.ops.create_cone(bm, diameter1=r1, diameter2=r2, **kwargs)


def align_to(p0, p1):
    """The matrix that puts a part built along local +Z onto the segment
    p0 -> p1, centred on it."""
    axis = Vector(p1) - Vector(p0)
    rot = axis.to_track_quat("Z", "Y").to_matrix().to_4x4()
    return Matrix.Translation((Vector(p0) + Vector(p1)) / 2.0) @ rot


def apply_matrix(bm, m):
    for v in bm.verts:
        v.co = m @ v.co


def cone_between(bm, p0, p1, r0, r1, segments):
    """A frustum from p0 (radius r0) to p1 (radius r1)."""
    length = (Vector(p1) - Vector(p0)).length
    cone(bm, segments, r0, r1, length, matrix=align_to(p0, p1))


def torus(bm, major, minor, ring_n=24, tube_n=12):
    """A torus in the local XY plane, its axis along +Z."""
    rows = []
    for i in range(ring_n):
        a = 2 * math.pi * i / ring_n
        nx, ny = math.cos(a), math.sin(a)
        row = []
        for j in range(tube_n):
            b = 2 * math.pi * j / tube_n
            r = major + minor * math.cos(b)
            row.append(bm.verts.new((nx * r, ny * r, minor * math.sin(b))))
        rows.append(row)
    bm.verts.ensure_lookup_table()
    for i in range(ring_n):
        for j in range(tube_n):
            bm.faces.new(
                (
                    rows[i][j],
                    rows[i][(j + 1) % tube_n],
                    rows[(i + 1) % ring_n][(j + 1) % tube_n],
                    rows[(i + 1) % ring_n][j],
                )
            )


def scale_verts(bm, sx, sy, sz, offset=(0.0, 0.0, 0.0)):
    for v in bm.verts:
        v.co.x = v.co.x * sx + offset[0]
        v.co.y = v.co.y * sy + offset[1]
        v.co.z = v.co.z * sz + offset[2]


# --------------------------------------------------------------------------
# The parts
# --------------------------------------------------------------------------


def build_shell(material):
    """The dome: an icosphere squashed to the shell's proportions, with the
    bottom half thrown away.

    Subdivision 2 is what the drawing shows — about 160 triangles over the
    dome.  A subdivided icosahedron has a closed loop of vertices exactly at
    the equator (the cross-band edge midpoints land at z=0 and stay there
    through normalisation), so cutting it in half leaves a clean rim.

    Flat-shaded, and the only part of the animal that is: the faceting is the
    whole look, and everything golden is smooth in the drawing.
    """
    bm = bmesh.new()
    icosphere(bm, subdivisions=2, radius=1.0)

    # Keep the top half.  A small epsilon so the equatorial ring survives.
    doomed = [v for v in bm.verts if v.co.z < -1e-5]
    bmesh.ops.delete(bm, geom=doomed, context="VERTS")

    scale_verts(bm, SHELL_R, SHELL_R, SHELL_H, offset=(0, 0, SHELL_BASE_Z))

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


def build_body(material):
    bm = bmesh.new()
    icosphere(bm, subdivisions=3, radius=1.0)
    scale_verts(bm, BODY_R_X, BODY_R_Y, BODY_R_Z, offset=(0, 0, BODY_Z))
    return new_object("Body", bm, material)


def build_head(material):
    """An ellipsoid tapered toward the nose — the teardrop in the top view."""
    bm = bmesh.new()
    icosphere(bm, subdivisions=3, radius=1.0)
    half = HEAD_LEN / 2.0
    centre_y = HEAD_NOSE_Y - half
    scale_verts(bm, HEAD_R_X, half, HEAD_R_Z, offset=(0, centre_y, HEAD_Z))

    for v in bm.verts:
        # f = 0 at the back of the head, 1 at the nose.
        f = (v.co.y - (centre_y - half)) / HEAD_LEN
        f = min(max(f, 0.0), 1.0)
        k = 1.0 - HEAD_TAPER * (f * f * (3.0 - 2.0 * f))  # smoothstep
        v.co.x *= k
        v.co.z = HEAD_Z + (v.co.z - HEAD_Z) * k

    return new_object("Head", bm, material)


def build_beret(material):
    """A domed crown, the rolled band round its base, and the nub on top.

    All three are built flat in the local XY plane and tilted together, so the
    band stays in the crown's plane and the nub stays on the crown's axis
    whatever the tilt is set to.  The head pushes up into the open underside,
    which is what holds the hat on.
    """
    bm = bmesh.new()

    # The crown: the top half of a squashed sphere, capped underneath.
    icosphere(bm, subdivisions=3, radius=1.0)
    doomed = [v for v in bm.verts if v.co.z < -1e-5]
    bmesh.ops.delete(bm, geom=doomed, context="VERTS")
    scale_verts(bm, BERET_R, BERET_R, BERET_DOME)
    bmesh.ops.holes_fill(bm, edges=[e for e in bm.edges if len(e.link_faces) == 1])

    torus(bm, BERET_R, BERET_RIM, ring_n=24, tube_n=10)

    nub = bmesh.new()
    icosphere(nub, subdivisions=2, radius=BERET_NUB)
    for v in nub.verts:
        v.co.z += BERET_DOME
    mesh = bpy.data.meshes.new("_nub")
    nub.to_mesh(mesh)
    nub.free()
    bm.from_mesh(mesh)
    bpy.data.meshes.remove(mesh)

    m = Matrix.Translation(Vector(BERET_POS)) @ Matrix.Rotation(BERET_TILT, 4, "X")
    apply_matrix(bm, m)
    return new_object("Beret", bm, material)


def build_neck(material):
    """Joins the head to the body.

    It has real work to do now that the purple is a hat rather than a collar:
    the head's centre sits above the body's top, so with the collar gone this
    is the only thing bridging them, and a gap here would be visible from
    every angle rather than hidden under a ruff.
    """
    bm = bmesh.new()
    cone_between(bm, (0.0, 0.200, 0.130), (0.0, 0.345, 0.207), 0.080, 0.070, 16)
    return new_object("Neck", bm, material)


def build_leg(name, x, y, splay, material):
    bm = bmesh.new()
    icosphere(bm, subdivisions=2, radius=1.0)
    scale_verts(bm, LEG_R[0], LEG_R[1], LEG_R[2])
    rot = Matrix.Rotation(splay, 4, "Z")
    for v in bm.verts:
        v.co = rot @ v.co + Vector((x, y, LEG_Z))
    return new_object(name, bm, material)


def build_legs(material):
    fx, fy = FRONT_LEG
    rx, ry = REAR_LEG
    return [
        build_leg("LegFrontLeft", -fx, fy, LEG_SPLAY, material),
        build_leg("LegFrontRight", fx, fy, -LEG_SPLAY, material),
        build_leg("LegRearLeft", -rx, ry, -LEG_SPLAY, material),
        build_leg("LegRearRight", rx, ry, LEG_SPLAY, material),
    ]


def ferrule_point():
    """Where the shaft ends and the bristles begin, on the one tail segment."""
    return TAIL_BASE.lerp(TAIL_TIP, FERRULE_T)


def build_tail(material):
    """The golden shaft, sloping gently down and back."""
    bm = bmesh.new()
    cone_between(bm, TAIL_BASE, ferrule_point(), TAIL_R_BASE, TAIL_R_TIP, 16)
    return new_object("Tail", bm, material)


def build_brush(material):
    """The bristles: a flared cone with a notched end.

    Built along +Z and swung onto the tail's own segment afterwards, so the
    ferrule cannot develop a kink: there is only one axis in the file.

    The notch takes alternate rim vertices *back* along the axis as well as
    inward, so half the hairs finish a third of the bundle short of the other
    half.  The end is therefore a zigzag, not a cut — see the note by
    BRISTLE_NOTCH, which is the whole reason it is like this.
    """
    bm = bmesh.new()
    ferrule = ferrule_point()
    length = (TAIL_TIP - ferrule).length
    cone(bm, BRISTLES, TAIL_R_TIP * 1.04, BRUSH_R, length)

    tip_z = length / 2.0
    rim = sorted(
        (v for v in bm.verts if abs(v.co.z - tip_z) < 1e-4),
        key=lambda v: math.atan2(v.co.y, v.co.x),
    )
    for i, v in enumerate(rim):
        if i % 2:
            v.co.z -= length * BRISTLE_NOTCH
            v.co.x *= 0.86
            v.co.y *= 0.86

    apply_matrix(bm, align_to(ferrule, TAIL_TIP))
    return new_object("Brush", bm, material)


def build_eyes(white, black):
    objs = []
    for side, sx in (("Left", -1.0), ("Right", 1.0)):
        bm = bmesh.new()
        icosphere(bm, subdivisions=2, radius=EYE_R)
        for v in bm.verts:
            v.co += Vector((sx * EYE_X, EYE_Y, EYE_Z))
        objs.append(new_object(f"Eye{side}", bm, white))

        # The pupil sits on the outward-forward-upper face of the white, poking
        # through it — the same trick the drawing uses to read from any angle.
        n = Vector((sx * PUPIL_AIM[0], PUPIL_AIM[1], PUPIL_AIM[2])).normalized()
        bm = bmesh.new()
        icosphere(bm, subdivisions=2, radius=PUPIL_R)
        for v in bm.verts:
            v.co += Vector((sx * EYE_X, EYE_Y, EYE_Z)) + n * PUPIL_OUT
        objs.append(new_object(f"Pupil{side}", bm, black))
    return objs


# --------------------------------------------------------------------------
# Assembly and export
# --------------------------------------------------------------------------


def build(out_dir):
    clear_scene()
    png = write_gradient_png(os.path.join(out_dir, GRADIENT_PNG))

    gold = plain_material("Gold", GOLD, roughness=0.42)
    purple = plain_material("Purple", PURPLE, roughness=0.38)
    white = plain_material("EyeWhite", WHITE, roughness=0.22)
    black = plain_material("EyeBlack", BLACK, roughness=0.14)
    # Matte rather than glossy: a tight highlight on a faceted dome blows one
    # or two facets to white and breaks the ramp exactly where it is meant to
    # be read.
    shell_mat = gradient_material("Shell", png, roughness=0.52)

    parts = [
        build_shell(shell_mat),
        build_body(gold),
        build_head(gold),
        build_neck(gold),
        build_beret(purple),
        build_tail(gold),
        build_brush(purple),
    ]
    parts += build_legs(gold)
    parts += build_eyes(white, black)

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


def export_usdz(path):
    for obj in bpy.context.scene.objects:
        obj.select_set(True)
    kwargs = dict(
        filepath=path,
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
        # collar's quads are triangulated by Blender, where the result can be
        # looked at, rather than at runtime where it cannot.
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
            return
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
