.NOTPARALLEL:

.PHONY: resolve-dbpp build test test-core test-features guardrails check-watch-appicon check-xcodebuild-platform check-release-safety ci pre-commit pre-push

resolve-dbpp:
	swift package resolve --package-path CadenceCore

build: resolve-dbpp
	swift build --package-path CadenceCore

# The everyday gate: headless CadenceCore + CadenceFeatures unit tests.
# No simulator. This is what every phase must keep green.
test: resolve-dbpp
	bash scripts/ci-test.sh

test-core: resolve-dbpp
	bash scripts/ci-test.sh --filter CadenceCoreTests

test-features: resolve-dbpp
	bash scripts/ci-test.sh --filter CadenceFeaturesTests

guardrails:
	bash scripts/check-design-tokens.sh
	bash scripts/check-test-pyramid.sh
	bash scripts/check-no-network.sh
	bash scripts/check-citations-sync.sh
	bash scripts/check-engine-boundary.sh
	bash scripts/check-history-safety.sh
	bash scripts/check-accessibility-ratchet.sh
	bash scripts/check-cloudkit-schema.sh
	bash scripts/check-watch-appicon.sh
	bash scripts/check-watch-background-modes.sh
	bash scripts/check-xcodebuild-platform.sh
	bash scripts/check-release-safety.sh

check-release-safety:
	bash scripts/check-release-safety.sh

check-watch-appicon:
	bash scripts/check-watch-appicon.sh

check-xcodebuild-platform:
	bash scripts/check-xcodebuild-platform.sh

# CI-equivalent host gate without simulators.
ci: build test guardrails

# The installed commit hook is intentionally host-only and never boots a
# simulator. There is no simulator-based smoke gate in this repo (removed:
# UI/simulator tests reliably crash CI and aren't run locally either).
pre-commit: test

# Push gate: no tests. The commit gate already ran guards and unit tests;
# pushes stay fast.
pre-push:
	@echo "pre-push: no tests run on push"
