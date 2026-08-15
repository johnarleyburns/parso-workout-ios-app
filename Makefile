.PHONY: update-exercises build test test-core test-features guardrails smoke watch-smoke all-tests ci pre-commit pre-push

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

# iPhone smoke gate: build once, then run the app-target launch regression and
# the single normal UI smoke test on a pinned simulator. Manual App Store
# screenshot UI tests stay out of this plan.
SMOKE_SCHEME ?= Cadence
# Bind by name to the one simulator installed on disk (iPhone 16) so every run
# uses the same device and xcodebuild never resolves to — or downloads — another.
SMOKE_DEST ?= platform=iOS Simulator,name=iPhone 16
smoke:
	xcodebuild build-for-testing -project Cadence/Cadence.xcodeproj -scheme "$(SMOKE_SCHEME)" \
	  -testPlan Cadence -derivedDataPath .build/dd -destination '$(SMOKE_DEST)' -quiet
	xcodebuild test-without-building -project Cadence/Cadence.xcodeproj -scheme "$(SMOKE_SCHEME)" \
	  -testPlan Cadence -derivedDataPath .build/dd -destination '$(SMOKE_DEST)' \
	  -only-testing:CadenceTests/AppModelWCSessionDelegateTests/testActivationCallbackCanEnterFromWatchConnectivityQueue \
	  -only-testing:CadenceUITests/SmokeLaunchTests/testIPhoneStrengthWorkoutPlansLogsAndCompletes \
	  -parallel-testing-enabled NO -maximum-concurrent-test-simulator-destinations 1

# Watch smoke gate: build once, run the watch unit regressions, then exactly ONE
# UI test (start -> log -> complete strength) on the single named simulator.
# Local only: never in CI.
WATCH_SMOKE_DEST ?= platform=watchOS Simulator,name=Watch-Large,OS=26.5
watch-smoke:
	xcodebuild build-for-testing -project Cadence/Cadence.xcodeproj -scheme "Cadence Watch App Watch App" \
	  -derivedDataPath .build/dd-watch -destination '$(WATCH_SMOKE_DEST)' -quiet
	xcodebuild test-without-building -project Cadence/Cadence.xcodeproj -scheme "Cadence Watch App Watch App" \
	  -derivedDataPath .build/dd-watch -destination '$(WATCH_SMOKE_DEST)' \
	  -only-testing:"Cadence Watch App Watch AppTests" \
	  -parallel-testing-enabled NO -maximum-concurrent-test-simulator-destinations 1
	xcodebuild test-without-building -project Cadence/Cadence.xcodeproj -scheme "Cadence Watch App Watch App" \
	  -derivedDataPath .build/dd-watch -destination '$(WATCH_SMOKE_DEST)' \
	  -only-testing:"Cadence Watch App Watch AppUITests/WatchSmokeTests/testWatchStrengthWorkoutStartsLogsAndCompletes" \
	  -parallel-testing-enabled NO -maximum-concurrent-test-simulator-destinations 1

# Full regression suite (opt-in, not part of the commit gate): SwiftPM suite +
# iPhone and watch UI smoke.
all-tests: test smoke watch-smoke

# CI-equivalent host gate without simulators.
ci: build test guardrails

# Commit gate: guards + SwiftPM unit tests + both app-target smoke tests. The
# Watch launch path is a required regression gate because it shares the Swift 6
# app-entry actor boundary that can terminate before the first view renders.
pre-commit: guardrails test smoke watch-smoke

# Push gate: no tests. The commit gate already ran guards, unit tests, and both
# app-target smoke suites; pushes stay fast.
pre-push:
	@echo "pre-push: no tests run on push"
