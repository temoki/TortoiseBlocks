# The 3D tortoise

`App/Resources/Tortoise.usdz` is generated, not modelled. This directory is
what generates it.

The design has two sources. The **shell** came in as a three-view drawing
(top / side / front / rear, #53): a low-poly dome, blue at the rim to pink at
the apex. The **character** around it — a big round head, the eyes, the
smile, stubby legs, the beret and the brush — was redrawn after the app
icon's mascot, so the animal on the table is the one on the icon.

Every shape is still a primitive, and that is what makes a script the right
tool rather than the lazy one: the numbers in `build_tortoise.py` are the
design's measurements, so a proportion can be argued about and changed in one
place instead of being pushed around by hand and then lost. The golden parts
are then fused into one surface, so the joins between them are rounded
without anyone modelling a join.

## Running it

```bash
cd Tools/tortoise-model

# Build the model.  Writes Tortoise.usdz, tortoise.blend, the shell's gradient
# textures and a usd/ staging directory into --out.
blender --background --python build_tortoise.py -- --out /tmp/tortoise

# Render the same views as the drawing, to compare against it.  --only takes
# a comma-separated subset (top side front rear hero tail head).
blender --background /tmp/tortoise/tortoise.blend --python render_views.py -- \
    --out /tmp/tortoise --only tail,side
python3 sheet.py /tmp/tortoise      # composites them, needs Pillow

# Then copy the result over the committed asset.
cp /tmp/tortoise/Tortoise.usdz ../../App/Resources/Tortoise.usdz
```

Built with Blender 5.2 LTS, and it needs nothing Blender does not ship: the
fusing is Blender's volume grid nodes, the normals pass is the `pxr` and
`numpy` in Blender's own Python, and the shell's gradient PNG is written out
of `zlib` and `struct` rather than Pillow for exactly that reason. Only
`sheet.py`, which is a convenience for looking at renders, wants Pillow, and
it runs under the system `python3`.

## Verifying it

Blender rendering the model proves nothing about whether *RealityKit* can
read it. Ask Apple's own USD stack instead:

```bash
xcrun swiftc -O qlcheck.swift -o /tmp/qlcheck
/tmp/qlcheck ../../App/Resources/Tortoise.usdz /tmp/tortoise-ql.png
usdchecker --arkit ../../App/Resources/Tortoise.usdz
```

`qlcheck` runs the file through QuickLook, which parses and renders it with
the same USD implementation the app will. `qlmanage -t` is the obvious
alternative and tends to hang — the same trap as the thumbnail extension (see
the root `CLAUDE.md`). QuickLook's camera looks at the tortoise's back, so the
face is for the visionOS simulator (the viewer's own `CLAUDE.md` has the
launch line).

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
- **Total length is exactly 1.0**, nose tip to brush tip, with
  `metersPerUnit = 1`. Deliberately normalised rather than given a real-world
  size: the canvas is a gesture between 0.2m and 2m (#53), so the tortoise's
  size is always computed anyway, and a unit-length model makes that
  `scale = the length you want`. The build scales the finished parts to hit
  1.0 (`normalise_length`), so moving a part cannot quietly break it.
- **The origin is the point on the ground under the shell's centre** — the
  tortoise's position, and the point it turns about. Not the brush tip. The
  brush is the pen, so the drawn line trails *behind* the animal; putting the
  origin at the brush instead would make the line exact and the turning
  strange, and that trade was decided in favour of ordinary turning. The
  soles stand exactly on it; the app still measures that rather than assuming
  it.
- Bounds, for framing, in the exported (Y-up) axes: `x ±0.303`, `y 0 .. 0.434`
  (height), `z -0.525` (nose) `.. +0.475` (brush). The brush tip is at
  `(0, 0.014, 0.475)`, just clear of the paper.
- Nine meshes under one `Tortoise` xform — the shell, one fused golden body,
  the brush, the beret, two eyes, two catchlights and the mouth — nine
  materials, two small textures (the shell's ramp, and the same ramp dimmed
  for emission); about 34,000 triangles and 0.5MB.
- **Every material emits a third of its own colour** (`EMISSION`). Not
  decoration — see below.

## Things that look like mistakes and are not

**The shell's ramp is squared** (`SHELL_RAMP_BIAS`). It runs blue at the rim
to pink at the apex, by height — but the view that matters is from above,
and a dome seen from above shows only `v²` of its projected area below height
`v`. Mapped straight, three quarters of the top view comes out pink.

**The shell has 40 facets, and the note beside it used to say 160.**
`SHELL_SUBDIVISIONS = 2` is 80 faces on a whole sphere, because Blender counts
the bare icosahedron as 1 — 160 is what 3 gives. The two were compared when
the rest of the animal went smooth, and 40 stayed: the big facets are the
digital half of the look, and at 160 the dome reads as a smooth one that
happens to be tiled.

**Every material has an `emissiveColor`, and the shell has a second texture
for it.** A tortoise is not a lamp, so this looks like a mistake in the PBR
setup, and removing it is a one-line change that will look correct and undo
the reason it is here.

In a `.mixed` immersive space RealityKit lights the model with the **real
room**. Measured against the shipped no-emission build under a lamp-lit
evening room, the pastels came out at 39 of 255 in luminance — the gold read
brown, the blue-to-pink dome read muddy teal — which is the state the
maintainer reported from the headset. At `EMISSION = 0.35` the same render is
111, a factor of 2.8, and the facets still step (all of it, and the tortoise
flattens into a sticker). Under QuickLook's bright studio lighting the same
change is only +12%, which is the point: emission is a floor that a dark room
cannot take away, not a brightness knob. Lightening the colours instead was
the alternative and is wrong: emission leaves the design alone and lets it
read at its own value in any room.

The shell needs a *second* PNG because `UsdPreviewSurface` has no emissive
strength — only `emissiveColor` — so feeding it the diffuse texture makes the
dome emit at full value while every other part emits at a third, and the shell
washes out. A multiply node in Blender does not survive the export either: the
preview-surface writer follows a fixed set of node patterns and drops the rest,
silently. The dimming is baked in **linear** light, and the ratio is checked at
three points along the ramp (0.347–0.354 against the flat materials' 0.35).

**The gold and the purple are the drawing's, not the icon's**, though
everything else about the character follows the icon. The icon's are paler
(`#FCD878` against `#DDB44F`), and lit in 3D they washed out to cream: flat
artwork carries its own shading in its colours, and a lit model gets shading
on top. These two had already been judged on the headset, in a room. The parts
the old model did not have take the icon's colours — the grey pupil and the
mouth.

**The tail trails along the paper, where the icon curls it over the back.**
The brush is the pen, so it rides on the end of the line being drawn. Curled
up, it would be a brush held in the air while something else draws.

**The golden body is one mesh.** Head, neck, plastron, legs and tail are built
as separate primitives, turned into one signed distance field, and put through
a morphological *closing* — grown by `FUSE_FILLET` and shrunk back by the same
distance — which rounds every join into a fillet of that radius and leaves
convex surfaces where they were. Splitting it back into named parts would give
back the hard creases the fusing is there to remove. The voxel surface that
comes out is several hundred thousand triangles and is decimated to
`GOLD_TRIANGLES`, which is why its triangles are irregular: it is smooth
enough that nothing shows.

**The normals are rewritten after Blender has written them.** Blender stores a
normal per triangle *corner* whatever the shading, and on a smooth mesh every
corner at a vertex carries the same one — most of the file was the same
numbers again. `per_vertex_normals` keeps one per vertex wherever the corners
agree, and leaves the faceted shell as it was; that pass is the difference
between 1.5MB and 0.5MB. It writes a *new* file on purpose: saving a crate
file over itself appends the edited values and keeps the old ones, and the
file comes out bigger than it went in.

**The paint's edge is ragged.** The brush used to end in a flared cone with
alternate hairs cut a third short — chosen, after three level-tipped versions
(radial fluting, a bellied profile, fourteen separate strands), over all of
them. When the character was redrawn after the icon, the brush became the
icon's: a bulb of bristles tapering to a point, dipped in paint. The
unevenness survives as the edge of the paint, which runs down between the
hairs in streaks (`PAINT_STREAKS`), and that edge is geometry — the brush's
rings are bent to follow it — so it is as sharp as the mesh, not as a
texture's pixels.
