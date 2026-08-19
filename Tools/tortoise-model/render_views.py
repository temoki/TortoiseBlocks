"""Render the same four orthographic views as the drawing, plus a hero shot.

Run with:  blender --background tortoise.blend --python render_views.py -- --out DIR

Kept apart from the builder on purpose: judging the shape means rendering it
many times, and there is no reason to re-export a USDZ for each look.
"""

import math
import os
import sys

import bpy
from mathutils import Vector

SIZE = 640
CENTRE = Vector((0.0, 0.0, 0.19))  # mid-height of the animal
ORTHO = 1.16  # the animal is 1.0 long; a little air around it

# The head is at +Y, so the camera that *sees* the face stands at +Y looking
# back along -Y.  Naming these the other way round is an easy mistake and a
# confusing one, because the renders still look fine — they are just labelled
# with each other's name.
VIEWS = [
    # name, camera location, euler XYZ in degrees, orthographic
    ("top", (0.0, 0.0, 4.0), (0.0, 0.0, 0.0), True),
    ("side", (-4.0, 0.0, CENTRE.z), (90.0, 0.0, -90.0), True),
    ("front", (0.0, 4.0, CENTRE.z), (90.0, 0.0, 180.0), True),
    ("rear", (0.0, -4.0, CENTRE.z), (90.0, 0.0, 0.0), True),
    ("hero", (-1.05, 1.25, 0.78), None, False),
]

# Close-ups.  The brush is a tenth of the animal long, so at the scale of the
# view sheet it is a dozen pixels and any judgement about it is guesswork.
DETAILS = [
    # name, camera location, target, orthographic scale
    ("tail", (-0.55, -0.34, 0.22), (0.0, -0.37, 0.085), 0.26),
    ("head", (-0.45, 0.62, 0.42), (0.0, 0.40, 0.245), 0.40),
]


def aim(obj, target):
    direction = Vector(target) - obj.location
    obj.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()


def add_light(name, location, energy, size):
    data = bpy.data.lights.new(name, type="AREA")
    data.energy = energy
    data.size = size
    obj = bpy.data.objects.new(name, data)
    obj.location = location
    bpy.context.collection.objects.link(obj)
    aim(obj, CENTRE)
    return obj


def setup_world():
    world = bpy.data.worlds.new("World")
    world.use_nodes = True
    bg = world.node_tree.nodes["Background"]
    bg.inputs["Color"].default_value = (0.55, 0.60, 0.66, 1.0)
    bg.inputs["Strength"].default_value = 0.28
    bpy.context.scene.world = world


def setup_render(out_dir):
    scene = bpy.context.scene
    for engine in ("BLENDER_EEVEE_NEXT", "BLENDER_EEVEE", "CYCLES"):
        try:
            scene.render.engine = engine
            break
        except TypeError:
            continue
    print(f"[render] engine={scene.render.engine}")
    scene.render.resolution_x = SIZE
    scene.render.resolution_y = SIZE
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = "PNG"
    scene.render.image_settings.color_mode = "RGBA"
    scene.render.film_transparent = True
    scene.view_settings.view_transform = "Standard"
    if hasattr(scene, "eevee"):
        for attr, value in (("taa_render_samples", 64), ("use_gtao", True)):
            if hasattr(scene.eevee, attr):
                setattr(scene.eevee, attr, value)


def render_view(name, location, euler, ortho, out_dir, scale=ORTHO, target=None):
    data = bpy.data.cameras.new(f"cam_{name}")
    data.type = "ORTHO" if ortho else "PERSP"
    if ortho:
        data.ortho_scale = scale
    else:
        data.lens = 55
    cam = bpy.data.objects.new(f"cam_{name}", data)
    cam.location = location
    bpy.context.collection.objects.link(cam)
    if euler is None:
        aim(cam, target or CENTRE)
    else:
        cam.rotation_euler = [math.radians(a) for a in euler]

    bpy.context.scene.camera = cam
    path = os.path.join(out_dir, f"view_{name}.png")
    bpy.context.scene.render.filepath = path
    bpy.ops.render.render(write_still=True)
    bpy.data.objects.remove(cam, do_unlink=True)
    print(f"[render] {path}")


def main():
    argv = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
    out_dir = os.path.abspath(argv[argv.index("--out") + 1] if "--out" in argv else ".")
    os.makedirs(out_dir, exist_ok=True)

    setup_world()
    setup_render(out_dir)
    # Key from the upper front-left, a soft fill opposite, and a rim behind —
    # enough separation to read the facets without hiding the gradient.
    #
    # An area light's power spreads as 1/(4*pi*d^2), so at d ~ 3.5 the visible
    # radiance is roughly P/490 for these albedos: past ~500W everything clips
    # to white and the shell's ramp disappears along with it.
    add_light("Key", (-2.0, 2.4, 2.8), 300.0, 3.0)
    add_light("Fill", (2.6, 1.4, 1.0), 90.0, 4.0)
    add_light("Rim", (0.8, -3.0, 2.2), 100.0, 2.5)

    # --only tail,head renders a subset.  A full sheet is seven renders and
    # about seven minutes; iterating on one part should not cost that.
    wanted = set(argv[argv.index("--only") + 1].split(",")) if "--only" in argv else None

    for name, loc, euler, ortho in VIEWS:
        if wanted is None or name in wanted:
            render_view(name, loc, euler, ortho, out_dir)
    for name, loc, target, scale in DETAILS:
        if wanted is None or name in wanted:
            render_view(name, loc, None, True, out_dir, scale=scale, target=target)


if __name__ == "__main__":
    main()
