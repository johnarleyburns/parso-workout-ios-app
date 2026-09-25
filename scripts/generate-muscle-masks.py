#!/usr/bin/env python3
"""Derive per-muscle alpha masks from the bundled anatomy artwork.

The source illustration is a raster export without semantic muscle IDs. This
keeps the artwork intact and uses its dark internal separations as boundaries:
red muscle pixels are grouped from the existing MuscleMapLayout callout
anchors, with mirrored seeds for bilateral muscles. The output is intentionally
small, transparent PNGs consumed as SwiftUI template images.
"""

from collections import deque
from pathlib import Path

from PIL import Image


ROOT = Path(__file__).resolve().parents[1]
ASSETS = ROOT / "Cadence/Cadence/Assets.xcassets"

CALLOUTS = {
    "front": {
        "neck": (0.46, 0.17),
        "shoulders": (0.32, 0.23),
        "biceps": (0.29, 0.34),
        "hip_flexors": (0.42, 0.50),
        "abductors": (0.34, 0.58),
        "quadriceps": (0.41, 0.65),
        "tibialis": (0.43, 0.80),
        "chest": (0.58, 0.29),
        "abdominals": (0.58, 0.39),
        "forearms": (0.72, 0.46),
        "adductors": (0.58, 0.57),
        "calves": (0.60, 0.80),
    },
    "back": {
        "neck": (0.46, 0.17),
        "shoulders": (0.34, 0.24),
        "triceps": (0.30, 0.35),
        "lats": (0.40, 0.37),
        "abductors": (0.35, 0.52),
        "hamstrings": (0.42, 0.65),
        "traps": (0.56, 0.24),
        "rotator_cuff": (0.66, 0.29),
        "middle_back": (0.56, 0.34),
        "forearms": (0.70, 0.45),
        "lower_back": (0.56, 0.46),
        "glutes": (0.56, 0.51),
        "calves": (0.60, 0.81),
    },
}

# The illustration presents these structures on both sides of the body. The
# remaining groups are central or are deliberately represented by one shared
# torso shape in the supplied artwork.
BILATERAL = {
    "shoulders", "biceps", "hip_flexors", "abductors", "quadriceps",
    "tibialis", "chest", "abdominals", "forearms", "adductors", "calves",
    "triceps", "lats", "hamstrings", "rotator_cuff", "glutes",
}


def is_muscle(pixel):
    red, green, blue, alpha = pixel
    # The supplied illustration's muscle fill is red; this threshold excludes
    # skin, bone, transparent canvas, and the dark linework used as boundaries.
    return (
        alpha > 100
        and red > 120
        and red > green * 1.5
        and red > blue * 1.5
        and green < 120
        and blue < 120
        and red - green > 80
    )


def components(image):
    width, height = image.size
    seen = set()
    found = []
    for y in range(height):
        for x in range(width):
            if (x, y) in seen or not is_muscle(image.getpixel((x, y))):
                continue
            queue = deque([(x, y)])
            seen.add((x, y))
            pixels = []
            while queue:
                px, py = queue.popleft()
                pixels.append((px, py))
                for nx, ny in ((px + 1, py), (px - 1, py), (px, py + 1), (px, py - 1)):
                    if (
                        0 <= nx < width
                        and 0 <= ny < height
                        and (nx, ny) not in seen
                        and is_muscle(image.getpixel((nx, ny)))
                    ):
                        seen.add((nx, ny))
                        queue.append((nx, ny))
            if len(pixels) >= 100:
                found.append(pixels)
    return found


def nearest_component(all_components, x, y):
    candidates = []
    for pixels in all_components:
        distance, px, py = min((abs(px - x) + abs(py - y), px, py) for px, py in pixels)
        if distance <= 100:
            candidates.append((distance, len(pixels), pixels))
    if not candidates:
        raise RuntimeError(f"No anatomy region near ({x}, {y})")
    # Distance wins so a nearby named region is never replaced by a larger,
    # unrelated muscle. Tiny anti-alias fragments were removed above.
    return min(candidates, key=lambda item: (item[0], -item[1]))[2]


def make_mask(panel, group, anchor, image, all_components):
    width, height = image.size
    anchors = [anchor]
    if group in BILATERAL:
        anchors.append((1.0 - anchor[0], anchor[1]))

    pixels = set()
    for normalized_x, normalized_y in anchors:
        x = round(normalized_x * width)
        y = round(normalized_y * height)
        pixels.update(nearest_component(all_components, x, y))

    alpha = Image.new("L", image.size, 0)
    alpha_pixels = alpha.load()
    for x, y in pixels:
        alpha_pixels[x, y] = 255

    name = f"MuscleMask-{panel}-{group}"
    output = ASSETS / f"{name}.imageset" / f"{name}.png"
    output.parent.mkdir(parents=True, exist_ok=True)
    rgba = Image.new("RGBA", image.size, (255, 255, 255, 0))
    rgba.putalpha(alpha)
    rgba.save(output, optimize=True)


def main():
    for panel, groups in CALLOUTS.items():
        source_name = f"MuscleMap{panel.title()}"
        source = Image.open(ASSETS / f"{source_name}.imageset/{source_name}.png").convert("RGBA")
        all_components = components(source)
        for group, anchor in groups.items():
            make_mask(panel, group, anchor, source, all_components)


if __name__ == "__main__":
    main()
