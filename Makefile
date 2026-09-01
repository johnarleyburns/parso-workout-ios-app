.PHONY: build test test-core test-features guardrails smoke watch-smoke shutdown-sims all-tests ci pre-commit pre-push

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
	bash scripts/check-citations-sync.sh
	bash scripts/check-engine-boundary.sh

# iPhone smoke gate: build once, then run the app-target launch regression and
# the single normal UI smoke test on a pinned simulator. Manual App Store
# screenshot UI tests stay out of this plan.
SMOKE_SCHEME ?= Cadence
# Bind by name to a simulator DEDICATED to this repo, not the shared "iPhone 16".
# Other Xcode projects on this machine run their own UI tests against a device
# named "iPhone 16"; sharing it made both suites flaky ("Test crashed with signal
# term", 2026-08-18 and 2026-08-19) and made `shutdown-sims` kill the other
# project's run. Create it once with:
#   xcrun simctl create "Cadence-iPhone-16" \
#     com.apple.CoreSimulator.SimDeviceType.iPhone-16 \
#     com.apple.CoreSimulator.SimRuntime.iOS-26-5
# Override on the command line if you need the shared device: make smoke
# SMOKE_SIM_NAME='iPhone 16'. CI never uses this — it archives against
# generic/platform=iOS and does not run the UI smoke.
SMOKE_SIM_NAME ?= Cadence-iPhone-16
SMOKE_DEST ?= platform=iOS Simulator,name=$(SMOKE_SIM_NAME)
smoke:
	xcodebuild build-for-testing -project Cadence/Cadence.xcodeproj -scheme "$(SMOKE_SCHEME)" \
	  -testPlan Cadence -derivedDataPath .build/dd -destination '$(SMOKE_DEST)' -quiet
	@status=0; \
	  xcodebuild test-without-building -project Cadence/Cadence.xcodeproj -scheme "$(SMOKE_SCHEME)" \
	    -testPlan Cadence -derivedDataPath .build/dd -destination '$(SMOKE_DEST)' \
	    -only-testing:CadenceTests/AppModelWCSessionDelegateTests/testActivationCallbackCanEnterFromWatchConnectivityQueue \
	    -only-testing:CadenceUITests/SmokeLaunchTests/testIPhoneStrengthWorkoutPlansLogsAndCompletes \
	    -parallel-testing-enabled NO -maximum-concurrent-test-simulator-destinations 1 || status=$$?; \
	  $(MAKE) --no-print-directory shutdown-sims; \
	  exit $$status

# Watch smoke gate: build once, run the watch unit regressions, then exactly ONE
# UI test (start -> log -> complete strength) on the single named simulator.
# Local only: never in CI.
WATCH_SMOKE_DEST ?= platform=watchOS Simulator,name=$(WATCH_SIM_NAME),OS=26.5
watch-smoke:
	xcodebuild build-for-testing -project Cadence/Cadence.xcodeproj -scheme "Cadence Watch App Watch App" \
	  -derivedDataPath .build/dd-watch -destination '$(WATCH_SMOKE_DEST)' -quiet
	@status=0; \
	  xcodebuild test-without-building -project Cadence/Cadence.xcodeproj -scheme "Cadence Watch App Watch App" \
	    -derivedDataPath .build/dd-watch -destination '$(WATCH_SMOKE_DEST)' \
	    -only-testing:"Cadence Watch App Watch AppTests" \
	    -parallel-testing-enabled NO -maximum-concurrent-test-simulator-destinations 1 || status=$$?; \
	  if [ $$status -eq 0 ]; then \
	    xcodebuild test-without-building -project Cadence/Cadence.xcodeproj -scheme "Cadence Watch App Watch App" \
	      -derivedDataPath .build/dd-watch -destination '$(WATCH_SMOKE_DEST)' \
	      -only-testing:"Cadence Watch App Watch AppUITests/WatchSmokeTests/testWatchStrengthWorkoutStartsLogsAndCompletes" \
	      -parallel-testing-enabled NO -maximum-concurrent-test-simulator-destinations 1 || status=$$?; \
	  fi; \
	  $(MAKE) --no-print-directory shutdown-sims; \
	  exit $$status

# Every simulator this repo boots is shut down when a smoke gate finishes, pass
# or fail. A watchOS runtime left booted alongside the iPhone saturates the
# machine and makes the iPhone UI test time out with "Test crashed with signal
# term" and no crash report (seen 2026-08-18, load average 38-45).
# Only THIS repo's pinned devices, never `shutdown all`: this machine
# demonstrably runs other Xcode projects against the same simulators at the same
# time (a concurrent `xcodebuild test -scheme Voxglass` on iPhone 16 was what hung
# our runner on 2026-08-19), and a global shutdown would kill their run too.
# Simulator.app is quit only once nothing else is left booted.
WATCH_SIM_NAME ?= Watch-Large
shutdown-sims:
	@xcrun simctl shutdown "$(SMOKE_SIM_NAME)" >/dev/null 2>&1 || true
	@xcrun simctl shutdown "$(WATCH_SIM_NAME)" >/dev/null 2>&1 || true
	@if ! xcrun simctl list devices booted 2>/dev/null | grep -q "(Booted)"; then \
	  pkill -x Simulator >/dev/null 2>&1 || true; \
	  echo "simulators: shut down (Simulator.app closed)"; \
	else \
	  echo "simulators: shut down (Simulator.app left running — another project has a device booted)"; \
	fi

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
