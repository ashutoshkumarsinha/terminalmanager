.PHONY: help build build-debug build-release package package-debug package-release \
	run bootstrap dmg notarize test clean

CONFIG ?= debug
APP := Terminal Manager.app
SCRIPTS := scripts

help:
	@echo "Terminal Manager — make targets"
	@echo ""
	@echo "  make build            Build debug binary (default)"
	@echo "  make build-release    Build release binary"
	@echo "  make package          Assemble $(APP) (debug)"
	@echo "  make package-release  Assemble $(APP) (release)"
	@echo "  make run              Bootstrap config, package, and open app"
	@echo "  make bootstrap        Create ~/.terminalmanager from example config"
	@echo "  make dmg              Build release app and create dist/*.dmg"
	@echo "  make notarize         Sign and notarize DMG (Apple Developer credentials)"
	@echo "  make test             Run Swift tests"
	@echo "  make clean            Remove build artifacts and app bundle"

build build-debug:
	swift build

build-release:
	swift build -c release

package package-debug: build-debug
	bash $(SCRIPTS)/package-app.sh debug

package-release: build-release
	bash $(SCRIPTS)/package-app.sh release

run:
	bash $(SCRIPTS)/run-app.sh $(CONFIG)

bootstrap:
	bash $(SCRIPTS)/bootstrap-config.sh

dmg:
	bash $(SCRIPTS)/create-dmg.sh

notarize:
	bash $(SCRIPTS)/notarize-dmg.sh

test:
	swift test

clean:
	rm -rf .build "$(APP)" dist
