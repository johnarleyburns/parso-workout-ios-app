#!/usr/bin/env python3
"""Derive per-muscle alpha masks from the bundled anatomy artwork.

The source illustration is a raster export without semantic muscle IDs. This
keeps the artwork intact and segments its red muscle fill with a **geodesic
watershed**: every red pixel is flooded outward from the muscle callout anchors
at once, so each pixel belongs to the anchor that reaches it first through
connected muscle. Unlike a per-anchor nearest-component lookup, this cannot let
two muscles claim the same region (which left several groups identical and
mis-highlighted), and it splits a connected shape — e.g. an arm that is one red
region — at the midpoint between the biceps and forearm anchors.

The output is intentionally small, transparent PNGs consumed as SwiftUI
template images.
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
    "middle_back", "traps",
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


def muscle_pixels(image):
    width, height = image.size
    pixels = image.load()
    return {(x, y) for y in range(height) for x in range(width) if is_muscle(pixels[x, y])}


SEED_RADIUS = 30


def nearest_red(pixels, x, y, max_distance=260):
    best, best_distance = None, 10 ** 9
    for px, py in pixels:
        distance = abs(px - x) + abs(py - y)
        if distance < best_distance:
            best, best_distance = (px, py), distance
            if distance == 0:
                break
    if best is None or best_distance > max_distance:
        return None
    return best


def seed_blob(pixels, x, y):
    """A small disk of red pixels around the nearest red pixel to the anchor.

    A single edge pixel is not enough: a thin arm can be flooded by the muscle
    above it before the seed propagates, leaving the forearm nearly empty. A
    small blob anchors each region to its own part of the shape.
    """
    seed = nearest_red(pixels, x, y)
    if seed is None:
        return []
    sx, sy = seed
    return [p for p in pixels if abs(p[0] - sx) + abs(p[1] - sy) <= SEED_RADIUS]


def watershed(pixels, image, seeds):
    """Multi-source BFS over connected red pixels. Each pixel takes the label of
    the seed it is reached from first, which is the geodesic-nearest anchor."""
    width, height = image.size
    source = image.load()
    label = {}
    queue = deque()
    for group, points in seeds.items():
        for point in points:
            if point in pixels and point not in label:
                label[point] = group
                queue.append(point)
    while queue:
        x, y = queue.popleft()
        group = label[(x, y)]
        for nx, ny in ((x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)):
            if 0 <= nx < width and 0 <= ny < height and (nx, ny) not in label and (nx, ny) in pixels:
                label[(nx, ny)] = group
                queue.append((nx, ny))
    return label


def main():
    for panel, groups in CALLOUTS.items():
        source_name = f"MuscleMap{panel.title()}"
        image = Image.open(ASSETS / f"{source_name}.imageset/{source_name}.png").convert("RGBA")
        pixels = muscle_pixels(image)

        seeds = {}
        for group, anchor in groups.items():
            anchors = [anchor]
            if group in BILATERAL:
                anchors.append((1.0 - anchor[0], anchor[1]))
            points = set()
            for normalized_x, normalized_y in anchors:
                points.update(seed_blob(pixels, round(normalized_x * image.width),
                                        round(normalized_y * image.height)))
            seeds[group] = list(points)

        label = watershed(pixels, image, seeds)

        for group in groups:
            alpha = Image.new("L", image.size, 0)
            alpha_pixels = alpha.load()
            for (x, y), assigned in label.items():
                if assigned == group:
                    alpha_pixels[x, y] = 255
            name = f"MuscleMask-{panel}-{group}"
            output = ASSETS / f"{name}.imageset" / f"{name}.png"
            output.parent.mkdir(parents=True, exist_ok=True)
            rgba = Image.new("RGBA", image.size, (255, 255, 255, 0))
            rgba.putalpha(alpha)
            rgba.save(output, optimize=True)


if __name__ == "__main__":
    main()
