#!/usr/bin/env python3
"""Fill large enclosed transparent cavities in the split muscle-map PNGs.

The Wikimedia source uses transparent, unfilled regions inside several muscle
outlines. That is valid source artwork, but on Cladiron's dark glass card those
large cavities look like missing black muscles. The map assets intentionally
keep their outside background transparent; this script only fills enclosed
alpha cavities above the area threshold with the source blood-red muscle color.

This is an asset-preparation tool, not an app-runtime dependency. Pillow is
used because ImageMagick's flood-fill operation does not expose component area
reliably enough for this distinction.
"""

from __future__ import annotations

import argparse
from collections import deque
from pathlib import Path

from PIL import Image


DEFAULT_RED = (181, 18, 18, 255)  # #b51212 from the credited source SVG.
DEFAULT_ALPHA_CUTOFF = 32
DEFAULT_MIN_AREA = 1_500
MIRROR_CENTERS = {
    # The split renders have slightly different horizontal crops. These are
    # the anatomical center lines in their 1024 px coordinate spaces.
    "MuscleMapFront": 512,
    "MuscleMapBack": 560,
}


def enclosed_cavities(image: Image.Image, alpha_cutoff: int, min_area: int) -> list[tuple[int, int]]:
    pixels = image.load()
    width, height = image.size
    seen = bytearray(width * height)
    fill: list[tuple[int, int]] = []

    def is_cavity(x: int, y: int) -> bool:
        return pixels[x, y][3] < alpha_cutoff

    for y in range(height):
        for x in range(width):
            index = y * width + x
            if seen[index] or not is_cavity(x, y):
                continue

            seen[index] = 1
            queue = deque([(x, y)])
            component: list[tuple[int, int]] = []
            touches_edge = False

            while queue:
                current_x, current_y = queue.popleft()
                component.append((current_x, current_y))
                if current_x in (0, width - 1) or current_y in (0, height - 1):
                    touches_edge = True

                for next_x, next_y in (
                    (current_x - 1, current_y),
                    (current_x + 1, current_y),
                    (current_x, current_y - 1),
                    (current_x, current_y + 1),
                ):
                    if not (0 <= next_x < width and 0 <= next_y < height):
                        continue
                    next_index = next_y * width + next_x
                    if seen[next_index] or not is_cavity(next_x, next_y):
                        continue
                    seen[next_index] = 1
                    queue.append((next_x, next_y))

            if not touches_edge and len(component) >= min_area:
                fill.extend(component)

    return fill


def mirrored_red_cavities(
    image: Image.Image,
    name: str,
    alpha_cutoff: int,
) -> list[tuple[int, int]]:
    """Recover open muscle cavities from the corresponding visible side.

    Some source muscle outlines have a small gap, so flood-fill correctly
    treats their interior as exterior transparency. The artwork is bilateral;
    only a transparent pixel whose counterpart is an opaque blood-red pixel is
    filled. This avoids filling the transparent space between limbs or outside
    the figure while removing the asymmetric black holes visible on the dark
    dashboard card.
    """
    center = MIRROR_CENTERS[name]
    pixels = image.load()
    width, height = image.size
    source = image.copy().load()
    fill: list[tuple[int, int]] = []

    def is_red(pixel: tuple[int, int, int, int]) -> bool:
        red, green, blue, alpha = pixel
        return (
            alpha >= alpha_cutoff
            and red >= 100
            and red > green * 1.8
            and red > blue * 1.8
        )

    for y in range(height):
        for x in range(width):
            if pixels[x, y][3] >= alpha_cutoff:
                continue
            mirror_x = (2 * center) - x
            if 0 <= mirror_x < width and is_red(source[mirror_x, y]):
                fill.append((x, y))
    return fill


def process(path: Path, name: str, alpha_cutoff: int, min_area: int) -> int:
    image = Image.open(path).convert("RGBA")
    enclosed = enclosed_cavities(image, alpha_cutoff, min_area)
    pixels = image.load()
    for x, y in enclosed:
        pixels[x, y] = DEFAULT_RED

    mirrored = mirrored_red_cavities(image, name, alpha_cutoff)
    for x, y in mirrored:
        pixels[x, y] = DEFAULT_RED

    image.save(path, format="PNG", optimize=True)
    print(
        f"{path}: filled {len(enclosed):,} enclosed and "
        f"{len(mirrored):,} mirrored muscle pixels"
    )
    return len(enclosed) + len(mirrored)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--asset-root",
        type=Path,
        default=Path(__file__).resolve().parents[1] / "Cadence/Cadence/Assets.xcassets",
        help="directory containing MuscleMapFront.imageset and MuscleMapBack.imageset",
    )
    parser.add_argument("--alpha-cutoff", type=int, default=DEFAULT_ALPHA_CUTOFF)
    parser.add_argument("--min-area", type=int, default=DEFAULT_MIN_AREA)
    args = parser.parse_args()

    if not 1 <= args.alpha_cutoff <= 254:
        parser.error("--alpha-cutoff must be between 1 and 254")
    if args.min_area < 1:
        parser.error("--min-area must be positive")

    total = 0
    for name in ("MuscleMapFront", "MuscleMapBack"):
        path = args.asset_root / f"{name}.imageset/{name}.png"
        if not path.is_file():
            parser.error(f"missing asset: {path}")
        total += process(path, name, args.alpha_cutoff, args.min_area)
    print(f"total: filled {total:,} enclosed pixels")


if __name__ == "__main__":
    main()
