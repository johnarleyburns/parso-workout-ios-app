# Phase 3 — Bundle exercise imagery (make NFR-3 true)

**Branch:** `phase-3-bundled-images`
**Depends on:** nothing.
**Decision:** D3.

---

## Problem

Two problems, one root cause.

```
CadenceCore/Sources/CadenceCore/ImportedExerciseLibrary.swift:135
    https://raw.githubusercontent.com/yuhonas/free-exercise-db/main/exercises/...

Cadence/Cadence/Features/Train/ExerciseDetailView.swift:99
    AsyncImage(url: ...)
```

Exercise photos are fetched from GitHub **at runtime**. Therefore:

1. **A basement gym with no signal shows no images.** The place the app is used is
   the place it stops working.
2. **GitHub sees a request every single time a user views an exercise** — in an app
   whose entire pitch is *"we never phone home,"* and whose **NFR-3** explicitly
   claims a *no-network core*.

The second one is the serious one. It is not a privacy-label violation (nothing is
collected by *you*), but it means the headline claim is **aspirational rather than
true**, and it is exactly the detail a hostile Hacker News commenter finds on
launch day — on the very post where "you can read the source and verify we don't
track you" is the pitch.

## Sizing — measured, not guessed

```
$ curl -sI .../Barbell_Bench_Press_-_Medium_Grip/0.jpg
content-length: 72816
```

~72 KB × 2 images × 873 exercises ≈ **1,746 images ≈ 127 MB raw.** Too large to
bundle as-is. Downscale.

---

## Design

### 1. New `scripts/build-exercise-images.sh`

A one-shot pipeline. Run once; **commit the output**. Not run at build time, not
run in CI.

- Source: free-exercise-db, **pinned to commit `b0eed06`** — the same commit
  `free-exercise-db.json` is pinned to. Do not let these drift.
- For each exercise id, fetch `exercises/<id>/0.jpg` and `<id>/1.jpg`.
- Downscale and re-encode with `sips` (already on macOS — no new dependency, and
  this repo targets zero proprietary deps per NFR-6):
  ```sh
  sips -s format heic -s formatOptions 70 \
       --resampleHeightWidthMax 400 "$in" --out "$out"
  ```
- Write to `CadenceCore/Sources/CadenceCore/Resources/ExerciseImages/<id>/0.heic`
  and `1.heic`.
- Expected total: **~21–35 MB.**
- **Print the final `du -sh`** so the size is a recorded fact, not a hope. Put the
  real number in the commit body.
- Idempotent and re-runnable.

### 2. `CadenceCore/Package.swift`

Add `.copy("Resources/ExerciseImages")` to the `CadenceCore` target's `resources`
array, alongside the existing `free-exercise-db.json`.

### 3. New `CadenceCore/Sources/CadenceCore/ExerciseImageCatalog.swift`

```swift
/// Bundled exercise photography. Resolves entirely from `Bundle.module` — there
/// is no network path, by design (NFR-3), and `scripts/check-no-network.sh`
/// fails CI if one is ever reintroduced.
public enum ExerciseImageCatalog {
    /// Local file URLs for an exercise's bundled images, in display order.
    /// Empty when the exercise has no bundled photography.
    public static func imageURLs(forImageName name: String) -> [URL]

    public static func hasImages(forImageName name: String) -> Bool
}
```

### 4. `ImportedExerciseLibrary.swift:135`

Delete the `raw.githubusercontent.com` URL construction **entirely**. `imageName`
stays as the lookup key.

### 5. `ExerciseDetailView.swift:99`

Replace `AsyncImage` with a synchronous load from the bundled file URL
(`UIImage(contentsOfFile:)`), plus a **placeholder** for exercises with no bundled
image. No `AsyncImage` anywhere in the app.

### 6. New `scripts/check-no-network.sh` — the guardrail

This is what turns a one-time fix into a permanent property. Wire it into CI next
to `check-test-pyramid.sh`.

Fail the build if any of `URLSession`, `URLRequest`, `dataTask`, `AsyncImage`, or
`.data(from:` appears under `CadenceCore/Sources/` or `Cadence/Cadence/`.

> **Important — do not grep for the string `http`.** `Citation.swift` legitimately
> contains ~53 paper URLs. Those are *displayed*, and opened in Safari on tap —
> they are never fetched by the app. **Ban the fetching APIs, not the URLs.** Keep
> an explicit allowlist file if a legitimate exception ever arises; there should be
> none today.

---

## Tests — new `CadenceCoreTests/ExerciseImageCatalogTests.swift`

- For **every** exercise in `ExerciseLibrary.starter` with a non-nil `imageName`,
  `hasImages` returns `true`. **This is the test that catches a half-run pipeline** —
  the most likely failure mode of this phase.
- Every URL returned by `imageURLs` exists on disk (`FileManager.fileExists`) and
  resolves under `Bundle.module`.
- No returned URL has an `http`/`https` scheme — assert `url.isFileURL`.
- An unknown `imageName` returns `[]` and does not crash.
- The bundled image count matches the number of exercises with imagery — guards
  against a truncated pipeline run.

---

## Acceptance

- Airplane mode + fresh install → exercise photos still render.
- `scripts/check-no-network.sh` green, and wired into CI.
- The repo grows by the measured amount (~21–35 MB); **record the real number in
  the commit body.**
- NFR-3 is now a true statement about the code.

## Open question — surface it, do not silently decide

**If the measured HEIC output exceeds ~50 MB, stop and report rather than
committing.** Fallbacks, in order of preference:

1. Ship a single image per exercise instead of two (halves the size).
2. Bundle only the 124 curated exercises plus the 20 `popularNames`, and ship the
   long tail imageless.

## Commit

```
feat: bundle exercise imagery; NFR-3 no-network core is now enforced, not aspirational
```
