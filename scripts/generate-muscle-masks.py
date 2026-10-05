#!/usr/bin/env python3
"""Derive per-muscle alpha masks from the bundled anatomy artwork.

The source illustration (`MuscleMapFront`/`MuscleMapBack`, split from the
credited Wikimedia SVG) is a raster without semantic muscle IDs, but its
linework already separates the individual muscles: every muscle is a connected
region of red fill bounded by an outline. This script therefore:

1. labels the connected red regions of each panel (4-connectivity);
2. assigns each anatomical region to a tracked `MuscleGroup` through a seed
   point that lies inside it (`SEEDS` below; the left and right halves are
   seeded separately because the artwork draws a superficial layer on one side
   and a deeper layer on the other, so the two halves do not mirror);
3. splits the few regions the artwork draws as one shape but anatomy treats as
   two muscles (`SPLITS`, e.g. the trapezius into neck/upper traps/mid back);
4. excludes untracked anatomy (head, hands, feet) with `EXCLUDE` polygons;
5. floods every remaining body pixel (tiny unlabelled slivers, pale or
   transparent deep-layer linework, antialiasing) from the nearest assigned
   region, so a mask covers its whole muscle and never leaves a hole or gap; and
6. writes one `untracked` mask per panel covering every muscle pixel no group
   claims (head, hands, feet), which the app draws white so the map never shows
   red muscle that no workout can turn green.

Bone, tendon and skin (large light areas) are never part of a mask, and the
artwork's dark outline strokes are left out so the individual muscles remain
legible through the colour.

Run after changing the artwork or the assignments:

    python3 scripts/generate-muscle-masks.py

The groups each panel writes must stay in sync with
`MuscleMapLayout.maskGroups(for:)`; `MuscleMapMaskAssetTests` checks that every
listed mask exists, is non-empty, lies under its callout, and that no two masks
of one panel overlap.
"""

from collections import deque
from pathlib import Path

from PIL import Image, ImageFilter


ROOT = Path(__file__).resolve().parents[1]
ASSETS = ROOT / "Cadence/Cadence/Assets.xcassets"

# Seed points are in the 1024 x 1782 pixel space of each panel PNG. Each point
# selects the connected red region under it (or the nearest red pixel within a
# few pixels when it lands on an outline).
SEEDS = {
    "front": {
        "neck": [(474, 317), (503, 301), (490, 291), (479, 269), (593, 319)],
        "traps": [(435, 320)],
        "shoulders": [(338, 360), (691, 360), (356, 402), (681, 408), (262, 412)],
        "chest": [(422, 468), (607, 468)],
        "biceps": [(267, 587), (279, 622), (748, 493), (759, 579), (772, 627), (749, 621)],
        "forearms": [(208, 676), (264, 668), (219, 748), (271, 711), (239, 754),
                     (823, 674), (766, 669), (815, 703), (800, 739), (809, 754), (849, 760)],
        "triceps": [(712, 567)],
        "abdominals": [(385, 731), (644, 730), (333, 542),
                       (484, 593), (473, 645), (482, 696), (473, 764),
                       (543, 593), (556, 645), (545, 696), (556, 763),
                       (433, 815), (593, 810), (521, 875), (510, 724), (530, 566)],
        "hip_flexors": [(434, 934), (418, 836), (453, 885),
                        (594, 920), (572, 884), (593, 857)],
        "adductors": [(469, 928), (488, 973), (557, 926), (537, 880)],
        "abductors": [(364, 869), (666, 837), (679, 776), (663, 863)],
        "quadriceps": [(390, 1032), (409, 1167), (475, 1105),
                       (602, 1016), (554, 1102), (624, 1157)],
        "tibialis": [(423, 1360), (413, 1485), (597, 1338), (620, 1341), (622, 1465),
                     (605, 1475)],
        "calves": [(484, 1231), (478, 1349), (540, 1231), (551, 1352), (539, 1268)],
    },
    "back": {
        "neck": [(506, 236), (501, 259), (614, 241), (598, 266), (606, 290)],
        "traps": [(497, 375), (617, 378)],
        "shoulders": [(350, 484), (746, 455)],
        "rotator_cuff": [(395, 460), (448, 434), (455, 482), (431, 505),
                         (675, 496), (640, 505)],
        "lats": [(473, 629), (643, 652), (418, 527), (706, 525), (632, 533)],
        "triceps": [(334, 608), (381, 610), (362, 576), (395, 554),
                    (745, 590), (789, 602)],
        "forearms": [(312, 704), (333, 722), (349, 766), (273, 844),
                     (773, 752), (803, 772), (789, 720), (808, 704), (880, 921)],
        "abdominals": [(439, 753), (681, 753)],
        "glutes": [(487, 882), (637, 908), (541, 918), (476, 934), (485, 947),
                   (499, 929), (523, 932), (525, 943), (441, 980), (554, 935)],
        "hamstrings": [(448, 1016), (465, 1041), (478, 1075), (505, 1065), (529, 964),
                       (616, 980), (648, 1034), (594, 968), (682, 1103), (622, 1138),
                       (646, 1156), (482, 1091), (519, 1076), (458, 1145)],
        "adductors": [(543, 953), (580, 956)],
        "quadriceps": [(676, 1018)],
        "calves": [(603, 1302), (660, 1278), (597, 1444), (653, 1454), (463, 1286),
                   (528, 1299), (498, 1296), (518, 1395), (468, 1442), (526, 1444),
                   (479, 1237)],
    },
}

# (group, polygon, seed points of the regions the split applies to). Pixels of
# those regions inside the polygon are reassigned to `group`.
SPLITS = {
    "front": [
        # The right side draws the upper trapezius and the neck as one region.
        ("traps", [(577, 270), (730, 270), (730, 375), (567, 375), (569, 345), (577, 300)],
         [(593, 319)]),
        # The torso's lateral wall continues into the arm at the armpit; the
        # arm side of it is the medial head of triceps seen from the front.
        ("triceps", [(220, 430), (326, 452), (330, 480), (333, 545), (338, 760), (220, 760)],
         [(385, 731)]),
        ("triceps", [(804, 430), (712, 455), (703, 480), (700, 545), (688, 760), (804, 760)],
         [(644, 730)]),
        # Above the knee joint line the medial strip is vastus medialis.
        ("quadriceps", [(440, 1150), (580, 1150), (580, 1236), (440, 1236)],
         [(484, 1231), (540, 1231)]),
        # The lateral hip strip runs from the tensor fasciae latae (an abductor)
        # down the iliotibial band over vastus lateralis (a quadriceps).
        ("quadriceps", [(300, 905), (720, 905), (720, 1260), (300, 1260)],
         [(364, 869), (666, 837), (663, 863)]),
    ],
    "back": [
        # One trapezius shape per side: the part over the neck is the neck,
        # the upper fibres are traps, the middle/lower fibres are mid back.
        ("neck", [(470, 200), (660, 200), (660, 322), (470, 322)],
         [(497, 375), (617, 378)]),
        ("middle_back", [(360, 410), (560, 458), (760, 410), (760, 700), (360, 700)],
         [(497, 375), (617, 378)]),
        # Gluteus medius (abductor) above and lateral of gluteus maximus' edge.
        ("abductors", [(630, 760), (630, 775), (649, 789), (668, 820), (686, 870),
                       (700, 895), (750, 895), (750, 760)],
         [(637, 908)]),
        ("abductors", [(490, 760), (490, 775), (471, 789), (452, 820), (434, 870),
                       (420, 895), (370, 895), (370, 760)],
         [(487, 882)]),
        # Below the gluteal fold the same outline continues down the lateral
        # thigh over vastus lateralis.
        ("quadriceps", [(380, 995), (760, 995), (760, 1200), (380, 1200)],
         [(487, 882), (637, 908)]),
        # Erector spinae under the thoracolumbar fascia, medial to the lats.
        ("lower_back", [(522, 690), (598, 690), (612, 740), (618, 800), (600, 860),
                        (560, 895), (520, 860), (502, 800), (508, 740)],
         [(473, 629), (643, 652)]),
    ],
}

# Untracked anatomy. Every body pixel inside is left uncoloured.
EXCLUDE = {
    "front": [
        # Head and face, down to the jaw line.
        [(400, 0), (630, 0), (630, 252), (566, 262), (540, 284), (512, 297),
         (484, 284), (458, 262), (400, 252)],
        # Hands, beyond each wrist.
        [(0, 850), (60, 860), (120, 880), (250, 950), (250, 1200), (0, 1200)],
        [(1024, 850), (964, 860), (904, 880), (774, 950), (774, 1200), (1024, 1200)],
        # Feet, below the ankles.
        [(0, 1525), (1024, 1525), (1024, 1782), (0, 1782)],
    ],
    "back": [
        [(400, 0), (720, 0), (720, 219), (400, 219)],
        [(0, 840), (150, 862), (200, 883), (320, 931), (320, 1200), (0, 1200)],
        [(1024, 840), (970, 862), (920, 883), (800, 931), (800, 1200), (1024, 1200)],
        [(0, 1600), (1024, 1600), (1024, 1782), (0, 1782)],
    ],
}

NONE = "_none"
SPECK_AREA = 600    # enclosed specks of bone/linework smaller than this are filled
LIGHT_OPENING = 9   # light areas wider than this are bone, tendon or skin
BODY_CLOSING = 7    # bridges thin transparent linework inside the figure


def is_muscle(pixel):
    red, green, blue, alpha = pixel
    # The illustration's muscle fill is red; this excludes skin, bone,
    # transparent canvas, and the dark linework used as boundaries.
    return (
        alpha > 100
        and red > 120
        and red > green * 1.5
        and red > blue * 1.5
        and green < 120
        and blue < 120
        and red - green > 80
    )


def is_light(pixel):
    """Bone, tendon, skin and the pale linework of the deep-layer side."""
    red, green, blue, alpha = pixel
    return alpha > 128 and green > 140 and blue > 120


def body_region(image):
    """Pixels that belong to the figure's muscle, including its linework."""
    alpha = image.getchannel("A").point(lambda value: 255 if value > 100 else 0)
    closed = alpha.filter(ImageFilter.MaxFilter(BODY_CLOSING)).filter(
        ImageFilter.MinFilter(BODY_CLOSING))
    pixels = image.load()
    light = Image.new("L", image.size, 0)
    light_pixels = light.load()
    width, height = image.size
    for y in range(height):
        for x in range(width):
            red, green, blue, opacity = pixels[x, y]
            if is_light((red, green, blue, opacity)):
                light_pixels[x, y] = 255
    bone = light.filter(ImageFilter.MinFilter(LIGHT_OPENING)).filter(
        ImageFilter.MaxFilter(LIGHT_OPENING))
    closed_data, bone_data = closed.tobytes(), bone.tobytes()
    return bytearray(1 if closed_data[i] and not bone_data[i] else 0
                     for i in range(width * height))


def label_components(red, width, height):
    labels = [0] * (width * height)
    current = 0
    for start in range(width * height):
        if not red[start] or labels[start]:
            continue
        current += 1
        labels[start] = current
        queue = [start]
        while queue:
            index = queue.pop()
            x, y = index % width, index // width
            for neighbour, valid in ((index - 1, x > 0), (index + 1, x < width - 1),
                                     (index - width, y > 0), (index + width, y < height - 1)):
                if valid and red[neighbour] and not labels[neighbour]:
                    labels[neighbour] = current
                    queue.append(neighbour)
    return labels


def component_at(labels, red, width, height, point, radius=8):
    x0, y0 = point
    best, best_distance = 0, None
    for dy in range(-radius, radius + 1):
        for dx in range(-radius, radius + 1):
            x, y = x0 + dx, y0 + dy
            if 0 <= x < width and 0 <= y < height and red[y * width + x]:
                distance = dx * dx + dy * dy
                if best_distance is None or distance < best_distance:
                    best, best_distance = labels[y * width + x], distance
    if not best:
        raise SystemExit(f"seed {point} is not on the muscle artwork")
    return best


def polygon_mask(size, polygon):
    from PIL import ImageDraw
    mask = Image.new("L", size, 0)
    ImageDraw.Draw(mask).polygon(polygon, fill=255)
    return mask.tobytes()


def segment(panel):
    source_name = f"MuscleMap{panel.title()}"
    image = Image.open(ASSETS / f"{source_name}.imageset/{source_name}.png").convert("RGBA")
    width, height = image.size
    pixels = image.load()
    red = bytearray(1 if is_muscle(pixels[x, y]) else 0
                    for y in range(height) for x in range(width))
    body = body_region(image)
    outline = bytearray(
        1 if pixels[x, y][3] > 100 and not red[y * width + x] and not is_light(pixels[x, y]) else 0
        for y in range(height) for x in range(width))
    labels = label_components(red, width, height)

    component_group = {}
    for group, points in SEEDS[panel].items():
        for point in points:
            component = component_at(labels, red, width, height, point)
            previous = component_group.get(component)
            if previous and previous != group:
                raise SystemExit(f"{panel}: region at {point} seeded as {previous} and {group}")
            component_group[component] = group

    assigned = [None] * (width * height)
    for index in range(width * height):
        if red[index]:
            assigned[index] = component_group.get(labels[index])

    for group, polygon, points in SPLITS[panel]:
        inside = polygon_mask(image.size, polygon)
        components = {component_at(labels, red, width, height, p) for p in points}
        for index in range(width * height):
            if inside[index] and labels[index] in components:
                assigned[index] = group

    for polygon in EXCLUDE[panel]:
        inside = polygon_mask(image.size, polygon)
        for index in range(width * height):
            if inside[index] and body[index]:
                assigned[index] = NONE

    # Geodesic flood through the body from every assigned pixel, so outlines
    # and unseeded slivers join the muscle that surrounds them.
    queue = deque(i for i in range(width * height) if assigned[i] and body[i])
    while queue:
        index = queue.popleft()
        group = assigned[index]
        x, y = index % width, index // width
        for neighbour, valid in ((index - 1, x > 0), (index + 1, x < width - 1),
                                 (index - width, y > 0), (index + width, y < height - 1)):
            if valid and body[neighbour] and assigned[neighbour] is None:
                assigned[neighbour] = group
                queue.append(neighbour)

    def fill_specks(alpha):
        """Fill small uncoloured specks that one mask completely encloses."""
        seen = bytearray(width * height)
        for start in range(width * height):
            if alpha[start] or seen[start]:
                continue
            seen[start] = 1
            component, queue, open_edge = [start], [start], False
            while queue:
                index = queue.pop()
                x, y = index % width, index // width
                if x in (0, width - 1) or y in (0, height - 1):
                    open_edge = True
                for neighbour, valid in ((index - 1, x > 0), (index + 1, x < width - 1),
                                         (index - width, y > 0),
                                         (index + width, y < height - 1)):
                    if valid and not alpha[neighbour] and not seen[neighbour]:
                        seen[neighbour] = 1
                        component.append(neighbour)
                        queue.append(neighbour)
            if not open_edge and len(component) < SPECK_AREA:
                for index in component:
                    alpha[index] = 255

    groups = sorted({g for g in SEEDS[panel]} | {g for g, _, _ in SPLITS[panel]})
    covered = bytearray(width * height)
    for group in groups:
        alpha = bytearray(255 if body[i] and assigned[i] == group else 0
                          for i in range(width * height))
        fill_specks(alpha)
        # Keep the artwork's own outlines visible over the colour so the
        # individual muscles still read when every group is on target.
        alpha = bytes(0 if outline[i] else alpha[i] for i in range(width * height))
        for i in range(width * height):
            if alpha[i]:
                covered[i] = 1
        write_mask(panel, group, alpha, image.size)

    # Untracked anatomy (head, hands, feet and anything no group claims) is drawn
    # white, so the map never shows red muscle that no workout can turn green.
    untracked = bytearray(255 if (body[i] or red[i]) and not covered[i] and not outline[i] else 0
                          for i in range(width * height))
    write_mask(panel, "untracked", bytes(untracked), image.size)


def write_mask(panel, group, alpha, size):
    """Writes one alpha mask as a white RGBA PNG imageset."""
    mask = Image.frombytes("L", size, alpha)
    name = f"MuscleMask-{panel}-{group}"
    output = ASSETS / f"{name}.imageset" / f"{name}.png"
    output.parent.mkdir(parents=True, exist_ok=True)
    contents = output.parent / "Contents.json"
    if not contents.exists():
        contents.write_text(
            '{\n  "images" : [\n    {\n      "filename" : "%s.png",\n'
            '      "idiom" : "universal",\n      "scale" : "1x"\n    }\n  ],\n'
            '  "info" : {\n    "author" : "xcode",\n    "version" : 1\n  }\n}\n'
            % name)
    rgba = Image.new("RGBA", size, (255, 255, 255, 0))
    rgba.putalpha(mask)
    rgba.save(output, optimize=True)
    print(f"{name}: {sum(1 for value in alpha if value)} px")


def main():
    for panel in SEEDS:
        segment(panel)


if __name__ == "__main__":
    main()
