.PHONY: build clean run install

APP_NAME := Ramblr.app
BUILD_APP := build/$(APP_NAME)
INSTALL_APP := /Applications/$(APP_NAME)

build:
	./scripts/build-app.sh

run: build
	open "$(BUILD_APP)"

install: build
	ditto "$(BUILD_APP)" "$(INSTALL_APP)"
	@echo "Installed at $(INSTALL_APP)"
	@echo "Launch with: open $(INSTALL_APP)"

clean:
	swift package clean
	rm -rf build
