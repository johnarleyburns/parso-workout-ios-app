# Parso element icons — v1.0

Voxglass · Platterhead · Cladiron. One family, three metals.

| | Voxglass | Platterhead | Cladiron |
|---|---|---|---|
| Symbol | **V** · Vanadium · 23 | **Pt** · Platinum · 78 | **Fe** · Iron · 26 |
| Metal | Warm amber / honey | Platinum white, brass glint at the base | Iron green on graphite |
| Worst greyscale contrast | 5.47 : 1 | 6.91 : 1 | 4.90 : 1 |
| Ink radius (safe circle 380) | 330 px | 362 px | 353 px |

## The idea

I kept the periodic-element concept and made it do the whole job. Each icon is the element symbol and nothing
else — no box, no atomic number, no words. The three symbols are drawn as one small typeface: the same cap height,
stems, superellipse curves and corners. What changes between apps is only the letterform and the metal.

- **V** is wide and open, with a rounded crotch — the spine of an open book, the trough of a sound wave.
- **Pt** has a squircle bowl like a platter seen edge-on. The gradient finishes in a thin brass band: the warm glint on cool metal.
- **Fe** stands square. The F arms are long and level like a loaded bar; the e is the same squircle as the P bowl.

I dropped the atomic number. At 58 px it falls below 2 px, and the brief says the icon must not lean on it. It
lives on in the mono marks and marketing, where there is room. Two other directions (element tile, ingot) are
on the last page of `style-guide.pdf` with the reasons they lost.

## Layer recipe (identical on all three)

1. **Background** — the Icon Composer document fill: a two-stop linear gradient, top → bottom.
   `layers/background.svg` holds the same gradient as art, for docs and anything outside Icon Composer.
   I used the fill rather than an image layer because the system replaces the fill cleanly in Clear and Tinted.
2. **Glyph** — `layers/glyph.svg`, one outlined path with the metal gradient, Liquid Glass on.
3. **Accent** — not used, on any of the three. (`accent.svg` is therefore absent, as the brief allows.)

No shadows, blur, glass or highlights are baked into any art.

## Glyph metrics (px on the 1024 canvas)

| | |
|---|---|
| Cap height | 432.0 (cap top 288, baseline 720; box sits 8 px above centre) |
| x-height | 324.0 |
| Stem | 90.7 |
| Bar, caps / lowercase / e crossbar | 77.8 / 67.0 / 54.0 |
| Thinnest feature at 58 px | 3.06 px (rule ≥ 2) |
| Curves | superellipse, n = 3.0 |
| Corners | convex 10 px · concave 8 px · V crotch 24 px |

## Colours

Authored in Display P3. sRGB values are exact conversions of the P3 values, clipped to gamut — use them anywhere
P3 isn't supported. SVG layers carry the sRGB values; `icon.json` carries P3.

### Voxglass

| Use | Stop | Name | Display P3 | sRGB |
|---|---|---|---|---|
| Background · Default | 0.00 | `vox-bg-top` | `display-p3 0.1412 0.1020 0.0667` | `#261910` |
| Background · Default | 1.00 | `vox-bg-bottom` | `display-p3 0.0392 0.0431 0.0510` | `#0A0B0D` |
| Background · Dark | 0.00 | `vox-bg-top-dark` | `display-p3 0.0784 0.0588 0.0392` | `#150F09` |
| Background · Dark | 1.00 | `vox-bg-bottom-dark` | `display-p3 0.0118 0.0118 0.0157` | `#030304` |
| Glyph | 0.00 | `vox-honey` | `display-p3 0.9647 0.8157 0.5882` | `#FECE8D` |
| Glyph | 0.55 | `vox-amber` | `display-p3 0.8392 0.5765 0.3451` | `#E28F4B` |
| Glyph | 1.00 | `vox-umber` | `display-p3 0.7294 0.4784 0.2588` | `#C57634` |

### Platterhead

| Use | Stop | Name | Display P3 | sRGB |
|---|---|---|---|---|
| Background · Default | 0.00 | `pt-bg-top` | `display-p3 0.1176 0.1216 0.1373` | `#1E1F23` |
| Background · Default | 1.00 | `pt-bg-bottom` | `display-p3 0.0353 0.0353 0.0431` | `#09090B` |
| Background · Dark | 0.00 | `pt-bg-top-dark` | `display-p3 0.0667 0.0667 0.0784` | `#111114` |
| Background · Dark | 1.00 | `pt-bg-bottom-dark` | `display-p3 0.0118 0.0118 0.0157` | `#030304` |
| Glyph | 0.00 | `pt-white` | `display-p3 0.9725 0.9686 0.9529` | `#F8F7F3` |
| Glyph | 0.62 | `pt-platinum` | `display-p3 0.7922 0.8039 0.8157` | `#C9CDD0` |
| Glyph | 0.84 | `pt-steel` | `display-p3 0.6902 0.7020 0.7176` | `#AFB3B7` |
| Glyph | 1.00 | `pt-brass` | `display-p3 0.7529 0.5765 0.3451` | `#C8914D` |

### Cladiron

| Use | Stop | Name | Display P3 | sRGB |
|---|---|---|---|---|
| Background · Default | 0.00 | `fe-bg-top` | `display-p3 0.0941 0.1294 0.1137` | `#16211D` |
| Background · Default | 1.00 | `fe-bg-bottom` | `display-p3 0.0314 0.0431 0.0392` | `#070B0A` |
| Background · Dark | 0.00 | `fe-bg-top-dark` | `display-p3 0.0510 0.0745 0.0627` | `#0B1310` |
| Background · Dark | 1.00 | `fe-bg-bottom-dark` | `display-p3 0.0118 0.0157 0.0157` | `#030404` |
| Glyph | 0.00 | `fe-mint` | `display-p3 0.6118 0.8863 0.7216` | `#85E4B5` |
| Glyph | 0.55 | `fe-green` | `display-p3 0.3451 0.7137 0.5098` | `#20B97D` |
| Glyph | 1.00 | `fe-iron` | `display-p3 0.2431 0.5725 0.3922` | `#009460` |

## Fonts

None. Every glyph was constructed from geometric primitives (rectangles, polygons, superellipses) in
`source/glyphs.py`. No typeface was used as a starting point, so there is no font licence to track. All
delivered SVGs are outlines only — no live text, no embedded images.

## Icon Composer settings

### Voxglass — `voxglass/AppIcon.icon`

| Setting | Value |
|---|---|
| Fill (Default) | Linear gradient, top → bottom, `display-p3 0.1412 0.1020 0.0667` → `display-p3 0.0392 0.0431 0.0510` |
| Fill (Dark) | Linear gradient, `display-p3 0.0784 0.0588 0.0392` → `display-p3 0.0118 0.0118 0.0157` |
| Group "Glyph" | one layer, `glyph.svg`, scale 100 %, offset 0,0 |
| Liquid Glass | On · Specular on · Blur off · Translucency off |
| Shadow | Layer colour, 45 % |
| Clear Light / Clear Dark | System default (glyph goes monochrome glass). Check the glyph stays solid, not see-through. |
| Tinted Light / Tinted Dark | Glyph fill "Automatic". Worst-row greyscale contrast 5.47 : 1 |
| Platforms | Squares: shared (iOS, iPadOS, macOS) · Circles: watchOS |

### Platterhead — `platterhead/AppIcon.icon`

| Setting | Value |
|---|---|
| Fill (Default) | Linear gradient, top → bottom, `display-p3 0.1176 0.1216 0.1373` → `display-p3 0.0353 0.0353 0.0431` |
| Fill (Dark) | Linear gradient, `display-p3 0.0667 0.0667 0.0784` → `display-p3 0.0118 0.0118 0.0157` |
| Group "Glyph" | one layer, `glyph.svg`, scale 100 %, offset 0,0 |
| Liquid Glass | On · Specular on · Blur off · Translucency off |
| Shadow | Layer colour, 45 % |
| Clear Light / Clear Dark | System default (glyph goes monochrome glass). Check the glyph stays solid, not see-through. |
| Tinted Light / Tinted Dark | Glyph fill "Automatic". Worst-row greyscale contrast 6.91 : 1 |
| Platforms | Squares: shared (iOS, iPadOS) · Circles: watchOS |

### Cladiron — `cladiron/AppIcon.icon`

| Setting | Value |
|---|---|
| Fill (Default) | Linear gradient, top → bottom, `display-p3 0.0941 0.1294 0.1137` → `display-p3 0.0314 0.0431 0.0392` |
| Fill (Dark) | Linear gradient, `display-p3 0.0510 0.0745 0.0627` → `display-p3 0.0118 0.0157 0.0157` |
| Group "Glyph" | one layer, `glyph.svg`, scale 100 %, offset 0,0 |
| Liquid Glass | On · Specular on · Blur off · Translucency off |
| Shadow | Layer colour, 45 % |
| Clear Light / Clear Dark | System default (glyph goes monochrome glass). Check the glyph stays solid, not see-through. |
| Tinted Light / Tinted Dark | Glyph fill "Automatic". Worst-row greyscale contrast 4.90 : 1 |
| Platforms | Squares: shared (iOS, iPadOS) · Circles: watchOS |

## Source

`source/parso-icons.svg` is the master: the three glyphs are shared `<symbol>`s placed on three named artboards,
with gradients per app. It opens in Figma, Illustrator and Sketch.

The real single source of truth is the three scripts beside it. `glyphs.py` holds the construction and metrics,
`palette.py` holds every colour, and `build.py` + `sheets.py` regenerate every file in this zip. Change a colour or
a stem weight once and all three icons, the PNGs, both PDFs and this README update together. Rebuild with
`pip install shapely cairosvg pypdf pillow` then `python3 build.py && python3 sheets.py && python3 package.py`.

## Status against the acceptance checklist

Done and verified here:

- [x] Tree matches the brief file for file, except `accent.svg` (not used) and the source format (see below)
- [x] Glyph ≥ 4.5 : 1 in greyscale on every row of the glyph, Default and Dark palettes (figures above)
- [x] No words, app names or atomic masses in any icon
- [x] Told apart in greyscale — see page 1 of `family-sheet.pdf`
- [x] One grid, one letterform family, one layer recipe
- [x] App Store PNGs are 1024 × 1024, RGB, no alpha
- [x] Style guide lists P3 and sRGB for every colour used

Done in Icon Composer by the designer (2026-09-30):

- [x] Each `AppIcon.icon` opened in Icon Composer, all six appearances tuned, and re-saved.
- [x] Tinted PNGs and the 1088 × 1088 watchOS PNGs exported from Icon Composer.

Still open:

- [ ] 29 pt on a real iPhone and inside the Watch circle (round 3 device test)
- [ ] `parso-icons.fig`: delivered as `parso-icons.svg` plus the build scripts. Import the SVG into Figma if
      a `.fig` is wanted.
- [ ] Rights statement signed (below)

## Rights and licence statement

All three icons, their layers, the mono marks and the source files in this archive were created by the designer,
with input from Claude (an AI model made by Anthropic), working from the Parso App Icon Design Brief of
30 September 2026. No stock art, no fonts and no third-party imagery were used; every shape was constructed from
geometric primitives. All rights transfer to Parso Consulting on final payment.

Accepted for Parso Consulting: ______________________   Date: __________
