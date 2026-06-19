.PHONY: update-exercises test build

update-exercises:
	@bash scripts/update-exercises.sh

test:
	cd CadenceCore && swift test

build:
	cd CadenceCore && swift build
