.PHONY: update-exercises test build smoke ci

update-exercises:
	@bash scripts/update-exercises.sh

# The everyday gate: headless CadenceCore + CadenceFeatures unit tests.
# Seconds, no simulator. This is what every phase must keep green.
test:
	cd CadenceCore && swift test

build:
	cd CadenceCore && swift build

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

# Full gate used by CI and before a release: unit suite + UI smoke.
ci: test smoke

# Watch smoke gate: build once, run exactly ONE simulator test (launch → start → stop)
# on the single named watch simulator. Local only — never in CI.
WATCH_SMOKE_DEST ?= platform=watchOS Simulator,name=Apple Watch Series 10 (46mm)
watch-smoke:
	xcodebuild build-for-testing -project Cadence/Cadence.xcodeproj -scheme "Cadence Watch App" \
	  -derivedDataPath .build/dd-watch -destination '$(WATCH_SMOKE_DEST)' -quiet
	xcodebuild test-without-building -project Cadence/Cadence.xcodeproj -scheme "Cadence Watch App" \
	  -derivedDataPath .build/dd-watch -destination '$(WATCH_SMOKE_DEST)' \
	  -parallel-testing-enabled NO -maximum-concurrent-test-simulator-destinations 1
