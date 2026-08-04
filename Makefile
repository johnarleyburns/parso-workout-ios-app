.PHONY: update-exercises build test test-core test-features guardrails smoke all-tests ci pre-commit pre-push watch-smoke

update-exercises:
	@bash scripts/update-exercises.sh

build:
	swift build --package-path CadenceCore

# The everyday gate: headless CadenceCore + CadenceFeatures unit tests.
# No simulator. This is what every phase must keep green.
test:
	swift test --package-path CadenceCore

test-core:
	swift test --package-path CadenceCore --filter CadenceCoreTests

test-features:
	swift test --package-path CadenceCore --filter CadenceFeaturesTests

guardrails:
	bash scripts/check-test-pyramid.sh
	bash scripts/check-no-network.sh

# UI smoke gate: build once, then run serially on a single simulator with no
# parallel clones and no retries — parallel testing + 148 cold launches is what
# pins the CPU. The smoke plan itself is culled to ~10 tests in Phase 5.
SMOKE_SCHEME ?= Cadence
# Bind by name to the one simulator installed on disk (iPhone 16) so every run
# uses the same device and xcodebuild never resolves to — or downloads — another.
SMOKE_DEST ?= platform=iOS Simulator,name=iPhone 16
smoke:
	xcodebuild build-for-testing -project Cadence/Cadence.xcodeproj -scheme "$(SMOKE_SCHEME)" \
	  -testPlan Cadence -derivedDataPath .build/dd -destination '$(SMOKE_DEST)' -quiet
	xcodebuild test-without-building -project Cadence/Cadence.xcodeproj -scheme "$(SMOKE_SCHEME)" \
	  -testPlan Cadence -derivedDataPath .build/dd -destination '$(SMOKE_DEST)' \
	  -parallel-testing-enabled NO -maximum-concurrent-test-simulator-destinations 1

# Full local gate used before push: unit suite + simulator UI smoke.
all-tests: test smoke

# CI-equivalent host gate without simulators.
ci: build test guardrails

# Commit gate: the full local gate (unit suite + simulator UI smoke) — every
# commit must leave the app field-testable, including the smoke strength loop.
pre-commit: all-tests

# Push gate: SwiftPM unit tests ONLY, no simulator. Pushes are frequent and the
# UI smoke already ran at commit; CI runs the SwiftPM suite on the push.
pre-push: test

# Watch smoke gate: build once, run exactly ONE simulator test (launch → start → stop)
# on the single named watch simulator. Local only — never in CI.
WATCH_SMOKE_DEST ?= platform=watchOS Simulator,name=Apple Watch Series 10 (46mm),OS=11.1
watch-smoke:
	xcodebuild build-for-testing -project Cadence/Cadence.xcodeproj -scheme "Cadence Watch App Watch App" \
	  -derivedDataPath .build/dd-watch -destination '$(WATCH_SMOKE_DEST)' -quiet
	xcodebuild test-without-building -project Cadence/Cadence.xcodeproj -scheme "Cadence Watch App Watch App" \
	  -derivedDataPath .build/dd-watch -destination '$(WATCH_SMOKE_DEST)' \
	  -parallel-testing-enabled NO -maximum-concurrent-test-simulator-destinations 1
