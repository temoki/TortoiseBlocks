# The 3D tortoise

`App/Resources/Tortoise.usdz` is generated, not modelled. This directory is
what generates it.

The design came in as a three-view drawing (top / side / front / rear, #53),
and every shape in it is a primitive — a domed shell, an ellipsoid head,
four flipper blobs, a beret, a tail ending in a brush. That is what makes a
script the right tool rather than the lazy one: the numbers in
`build_tortoise.py` *are* the drawing's measurements, so a proportion can be
argued about and changed in one place instead of being pushed around by hand
and then lost.

## Running it

```bash
cd Tools/tortoise-model

# Build the model.  Writes Tortoise.usdz, tortoise.blend and the shell's
# gradient texture into --out.
blender --background --python build_tortoise.py -- --out /tmp/tortoise

# Render the same views as the drawing, to compare against it.  --only takes
# a comma-separated subset (top side front rear hero tail head); a full sheet
# is seven renders and several minutes.
blender --background /tmp/tortoise/tortoise.blend --python render_views.py -- \
    --out /tmp/tortoise --only tail,side
python3 sheet.py /tmp/tortoise      # composites them, needs Pillow

# Then copy the result over the committed asset.
cp /tmp/tortoise/Tortoise.usdz ../../App/Resources/Tortoise.usdz
```

Built with Blender 5.2 LTS. `build_tortoise.py` needs nothing but Blender's
own bundled Python — the shell's gradient PNG is written out of `zlib` and
`struct` rather than Pillow for exactly that reason. Only `sheet.py`, which
is a convenience for looking at renders, wants Pillow, and it runs under the
system `python3`.

## Verifying it

Blender rendering the model proves nothing about whether *RealityKit* can
read it. Ask Apple's own USD stack instead:

```bash
xcrun swiftc -O qlcheck.swift -o /tmp/qlcheck
/tmp/qlcheck ../../App/Resources/Tortoise.usdz /tmp/tortoise-ql.png
```

That runs the file through QuickLook, which parses and renders it with the
same USD implementation the app will. `qlmanage -t` is the obvious
alternative and tends to hang — the same trap as the thumbnail extension
(see the root `CLAUDE.md`).

Worth checking the stage metadata too, since it is what decides which way up
the animal arrives:

```bash
usdcat --flatten ../../App/Resources/Tortoise.usdz -o /tmp/flat.usda
grep -m3 -E 'upAxis|metersPerUnit|defaultPrim' /tmp/flat.usda
```

## The contract the app depends on

These are the things app code will assume, so changing one is a change to
the app and not just to the asset.

- **`upAxis = "Y"`, forward is `-Z`** — RealityKit's convention, not
  Blender's. The model is authored Z-up with the head at `+Y` and the
  exporter puts a `rotateXYZ = (-90, 0, 0)` on the root prim to convert.
  Confirm with `usdcat` after any change to the export settings; getting it
  wrong is invisible until the tortoise drives sideways.
- **Total length is 1.0**, nose tip to brush tip, with `metersPerUnit = 1`.
  Deliberately normalised rather than given a real-world size: the canvas is
  a gesture between 0.2m and 2m (#53), so the tortoise's size is always
  computed anyway, and a unit-length model makes that `scale = the length you
  want`.
- **The origin is the point on the ground under the shell's centre** — the
  tortoise's position, and the point it turns about. Not the brush tip. The
  brush is the pen, so the drawn line trails *behind* the animal; putting the
  origin at the brush instead would make the line exact and the turning
  strange, and that trade was decided in favour of ordinary turning.
- Bounds, for framing: `x ±0.309`, `y 0 .. 0.386` (height), `z -0.543` (nose)
  `.. +0.457` (brush). The brush tip is at `(0, 0.066, 0.457)`.
- Fifteen named meshes under one `Tortoise` xform, five materials, one
  915-byte texture; about 2,200 triangles.

## Two things that look like mistakes and are not

**The shell's ramp is squared** (`SHELL_RAMP_BIAS`). It runs blue at the rim
to pink at the apex, by height — but the view that matters is from above,
and a dome seen from above shows only `v²` of its projected area below height
`v`. Mapped straight, three quarters of the top view comes out pink.

**The brush tip is uneven.** Alternate hairs stop a third of the bundle
short. Three level-tipped versions were built after this one — radial fluting,
a bellied profile, and fourteen separately modelled strands — and the
maintainer chose this shape to come back to. There is a longer note at
`BRISTLE_NOTCH`.
