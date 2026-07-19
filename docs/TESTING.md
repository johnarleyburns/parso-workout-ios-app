# Testing

This repo uses two different test/build paths:

- Swift package logic is tested with SwiftPM.
- iOS and watchOS app targets are built or smoke-tested with Xcode.

## Package Tests

Run the core package test suite with SwiftPM:

```sh
swift test --package-path CadenceCore
```

That command runs both package test targets defined in
`CadenceCore/Package.swift`:

- `CadenceCoreTests`
- `CadenceFeaturesTests`

Focused variants:

```sh
swift test --package-path CadenceCore --filter CadenceCoreTests
swift test --package-path CadenceCore --filter CadenceFeaturesTests
swift test --package-path CadenceCore --filter WatchSyncTests
swift test --package-path CadenceCore --filter WatchCardioModelsTests
swift test --package-path CadenceCore --filter CoachScientificValidationTests
```

`make test` is a convenience wrapper for the same package suite. `make test-core`
and `make test-features` run the package test targets independently.

## Why Not Xcode Product Schemes

Do not use these commands in plans or CI:

```sh
xcodebuild test -project Cadence/Cadence.xcodeproj -scheme CadenceCore
xcodebuild test -project Cadence/Cadence.xcodeproj -scheme CadenceFeatures
```

Xcode lists `CadenceCore` and `CadenceFeatures` because they are local Swift
package products used by the app targets. Those product schemes are not
configured with Xcode `TestAction` entries, so `xcodebuild test` exits with:

```text
xcodebuild: error: Scheme CadenceCore is not currently configured for the test action.
xcodebuild: error: Scheme CadenceFeatures is not currently configured for the test action.
```

The app scheme's Xcode test action is for app and UI tests. The package tests
are intentionally headless and simulator-free, so SwiftPM is the correct runner.
This is also what GitHub Actions runs in `.github/workflows/ios.yml`.

## App And Watch Checks

Use Xcode for app/watch targets and simulator smoke tests:

```sh
xcodebuild -project Cadence/Cadence.xcodeproj -scheme Cadence \
  -destination 'platform=iOS Simulator,name=iPhone 16' build

xcodebuild build -project Cadence/Cadence.xcodeproj \
  -scheme 'Cadence Watch App Watch App' \
  -destination 'generic/platform=watchOS' \
  CODE_SIGNING_ALLOWED=NO
```

Local smoke-test wrappers:

```sh
make smoke
make watch-smoke
```

## Git Hooks

Versioned hooks live in `scripts/git-hooks`. Install them once per clone:

```sh
bash scripts/install-git-hooks.sh
```

Installed hooks:

- `pre-commit`: runs `make pre-commit`, which is the SwiftPM unit suite.
- `pre-push`: runs `make pre-push`, which is the SwiftPM unit suite plus the iOS simulator smoke test.

The pre-push hook intentionally includes simulator smoke coverage, so it expects
the pinned simulator from `Makefile`'s `SMOKE_DEST` to be available locally. For
exceptional cases, Git's standard `--no-verify` flag bypasses hooks.

## Standard Gate

For implementation plans and host-only verification, use:

```sh
swift test --package-path CadenceCore
bash scripts/check-test-pyramid.sh
bash scripts/check-no-network.sh
xcodebuild build -project Cadence/Cadence.xcodeproj \
  -scheme 'Cadence Watch App Watch App' \
  -destination 'generic/platform=watchOS' \
  CODE_SIGNING_ALLOWED=NO
```

For full local pre-push verification, use:

```sh
make all-tests
```
