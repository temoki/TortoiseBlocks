"""Composite the rendered views into one sheet laid out like the drawing."""

import os
import sys

from PIL import Image, ImageDraw, ImageFont

OUT = sys.argv[1] if len(sys.argv) > 1 else "."
CELL = 460
PAD = 18
LABEL = 26
BG = (246, 246, 248)


def load(name):
    img = Image.open(os.path.join(OUT, f"view_{name}.png")).convert("RGBA")
    return img.resize((CELL, CELL), Image.LANCZOS)


def font(size):
    for path in (
        "/System/Library/Fonts/Supplemental/Arial Bold.ttf",
        "/System/Library/Fonts/SFNS.ttf",
    ):
        if os.path.exists(path):
            try:
                return ImageFont.truetype(path, size)
            except OSError:
                pass
    return ImageFont.load_default()


names = ["top", "side", "front", "rear", "hero", "tail", "head"]
titles = {
    "top": "TOP",
    "side": "SIDE (Left)",
    "front": "FRONT",
    "rear": "REAR",
    "hero": "3/4",
    "tail": "TAIL (close)",
    "head": "HEAD (close)",
}

cols = 4
rows = (len(names) + cols - 1) // cols
W = PAD + cols * (CELL + PAD)
H = PAD + rows * (CELL + LABEL + PAD)
sheet = Image.new("RGB", (W, H), BG)
draw = ImageDraw.Draw(sheet)
f = font(20)

for i, name in enumerate(names):
    cx = PAD + (i % cols) * (CELL + PAD)
    cy = PAD + (i // cols) * (CELL + LABEL + PAD)
    cell = Image.new("RGB", (CELL, CELL), (236, 238, 242))
    img = load(name)
    cell.paste(img, (0, 0), img)
    sheet.paste(cell, (cx, cy))
    draw.rectangle([cx, cy, cx + CELL - 1, cy + CELL - 1], outline=(200, 202, 208))
    draw.text((cx + 4, cy + CELL + 4), titles[name], fill=(40, 40, 46), font=f)

path = os.path.join(OUT, "sheet.png")
sheet.save(path)
print(path)
