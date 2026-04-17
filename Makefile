PROJECT := Notchera.xcodeproj
SCHEME := Notchera
DESTINATION := platform=macOS
DERIVED_DATA := .derived-data
APP_PATH := $(DERIVED_DATA)/Build/Products/Debug/Notchera.app

.PHONY: open build run format lint check

open:
	open $(PROJECT)

build:
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration Debug -destination '$(DESTINATION)' -derivedDataPath $(DERIVED_DATA) build CODE_SIGNING_ALLOWED=NO

run: build
	open $(APP_PATH)

format:
	@command -v swiftformat >/dev/null 2>&1 || (echo "swiftformat yok. brew install swiftformat" && exit 1)
	swiftformat Notchera NotcheraXPCHelper

lint:
	@command -v swiftlint >/dev/null 2>&1 || (echo "swiftlint yok. brew install swiftlint" && exit 1)
	swiftlint lint --config .swiftlint.yml

check: format lint build
