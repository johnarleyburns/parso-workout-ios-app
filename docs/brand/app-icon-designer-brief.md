# Cladiron app icon — designer handoff

> **Delivered 2026-09-30.** The commissioned icon (Parso family "Fe") is `Cadence/Cadence/AppIcon.icon`; sources and exact colours are in `design/icon/` and `plans/award-craft/2026-09-28/01-icon-and-launch.md`. This handoff is kept for history.

The D1 icon commission is intentionally manual. Do not replace the current
asset in this repository until the designer’s package has been reviewed.

Create a restrained, legible **Fe** monogram: the capital F and lowercase e
should read as one balanced mark inside Apple’s safe area. It must not resemble
the current placeholder E, run through the ring, contain a watermark, or rely
on tiny detail that disappears at 29–40 pt. Use a flat, high-contrast geometry
that works in both light and dark contexts; no text other than the Fe mark.

Deliver exactly:

- `Cladiron-Icon-Source.icon` — layered Icon Composer source with editable Fe,
  background, safe-area guides, and separate iPhone/Watch compositions.
- `Cladiron-iPhone-Light-1024.png`
- `Cladiron-iPhone-Dark-1024.png`
- `Cladiron-iPhone-Tinted-1024.png` — monochrome/tint-ready mark with no baked
  gradient or shadow.
- `Cladiron-iPhone-Clear-1024.png` — clear appearance artwork, with the alpha
  and material behavior documented in the source file.
- `Cladiron-Watch-Light-1024.png`
- `Cladiron-Watch-Dark-1024.png`
- `Cladiron-Watch-Tinted-1024.png`
- `Cladiron-Watch-Clear-1024.png`
- `icon-preview.pdf` showing 29 pt, 40 pt, 60 pt, 1024 px, light, dark,
  tinted, and clear previews on-device-style backgrounds.
- `icon-color-spec.json` containing sRGB/Display-P3 values, contrast checks,
  and the intended safe-area inset.

All PNGs must be exactly 1024×1024, sRGB, opaque unless the clear variant
explicitly requires alpha, and free of metadata/watermarks. Include a written
note confirming Apple’s Human Interface Guidelines and App Store icon assets
were checked at final size. The iPhone and Watch marks may share the same Fe
geometry, but their compositions must be validated separately.
