.PHONY: build clean run install

build:
	./scripts/build-app.sh

run: build
	open build/Dictator.app

install: build
	mkdir -p "$(HOME)/Applications"
	ditto build/Dictator.app "$(HOME)/Applications/Dictator.app"
	@echo "Installed at $(HOME)/Applications/Dictator.app"

clean:
	swift package clean
	rm -rf build
