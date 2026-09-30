# Cladiron icon brief

The icon is a quiet Fe monogram: one clean glyph, with no product name,
atomic number, mass, watermark, or decorative text. It uses a graphite-to-iron
green background and two foreground layers so it remains legible in Default,
Dark, Clear, and Tinted appearances and inside the watchOS circular mask.

The committed vector source is `cladiron-fe.svg`; it is the source of truth for
the current PNG export. A designer should review the mark at 1024, 180, 120,
87, 60, and 40 px, plus the watchOS mask. The silhouette must survive
monochrome/tinted rendering with at least 4.5:1 glyph contrast.

The current implementation uses the same source-derived export for iOS and
Watch. An Icon Composer `.icon` file can replace the asset-catalog export when
final commissioned layers are available.
