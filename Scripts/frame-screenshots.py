#!/usr/bin/env python3
"""Wraps simulator screenshots in a simple iPhone frame for the README.

Usage: frame-screenshots.py <screenshots directory> <output directory>
"""
import sys
from pathlib import Path

from PIL import Image, ImageDraw

OUTPUT_WIDTH = 660
SCREEN_WIDTH_POINTS = 402  # iPhone 17 Pro


def rounded_mask(size, radius):
    mask = Image.new("L", size, 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, size[0] - 1, size[1] - 1), radius=radius, fill=255)
    return mask


def frame(screenshot):
    screen = screenshot.convert("RGBA")
    width, height = screen.size
    scale = width / SCREEN_WIDTH_POINTS

    def pt(value):
        return round(value * scale)

    screen_radius, bezel, rim, margin = pt(62), pt(11), pt(3.5), pt(4)
    body_width = width + 2 * (bezel + rim)
    body_height = height + 2 * (bezel + rim)
    canvas = Image.new("RGBA", (body_width + 2 * margin, body_height + 2 * margin), (0, 0, 0, 0))
    draw = ImageDraw.Draw(canvas)

    # Action button and volume buttons on the left, side button on the right.
    buttons = (58, 58, 62, 255)
    for top, length in ((122, 34), (178, 62), (252, 62)):
        draw.rounded_rectangle((margin - pt(2.5), margin + pt(top), margin + rim, margin + pt(top + length)), radius=pt(1.5), fill=buttons)
    right = margin + body_width
    draw.rounded_rectangle((right - rim, margin + pt(205), right + pt(2.5), margin + pt(301)), radius=pt(1.5), fill=buttons)

    # Titanium rim, black bezel, then the screen with rounded corners.
    outer_radius = screen_radius + bezel + rim
    draw.rounded_rectangle((margin, margin, right - 1, margin + body_height - 1), radius=outer_radius, fill=(74, 74, 78, 255))
    draw.rounded_rectangle((margin + rim, margin + rim, right - rim - 1, margin + body_height - rim - 1), radius=outer_radius - rim, fill=(6, 6, 8, 255))
    origin = (margin + rim + bezel, margin + rim + bezel)
    canvas.paste(screen, origin, rounded_mask(screen.size, screen_radius))

    # Dynamic Island.
    island_width, island_height = pt(125), pt(37)
    left = origin[0] + (width - island_width) // 2
    top = origin[1] + pt(11)
    draw.rounded_rectangle((left, top, left + island_width, top + island_height), radius=island_height // 2, fill=(0, 0, 0, 255))
    return canvas


def main():
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    source, destination = Path(sys.argv[1]), Path(sys.argv[2])
    shots = sorted(source.glob("*.png"))
    if not shots:
        sys.exit(f"No screenshots found in {source}")
    destination.mkdir(parents=True, exist_ok=True)
    for path in shots:
        framed = frame(Image.open(path))
        height = round(framed.height * OUTPUT_WIDTH / framed.width)
        framed.resize((OUTPUT_WIDTH, height), Image.LANCZOS).save(destination / path.name, optimize=True)
        print(f"Framed {path.name}")


if __name__ == "__main__":
    main()
