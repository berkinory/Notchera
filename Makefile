PROJECT := Notchera.xcodeproj
SCHEME := Notchera
DESTINATION := platform=macOS
DERIVED_DATA := .derived-data
SOURCE_PACKAGES := $(DERIVED_DATA)/SourcePackages
APP_PATH := $(DERIVED_DATA)/Build/Products/Debug/Notchera.app
XCODEBUILD_BASE := xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration Debug -destination '$(DESTINATION)' -derivedDataPath $(DERIVED_DATA) -clonedSourcePackagesDirPath $(SOURCE_PACKAGES) -disableAutomaticPackageResolution

.PHONY: open build run debug debug-run profile-build profile-run hud-cli format lint check

open:
	open $(PROJECT)

build:
	$(XCODEBUILD_BASE) build CODE_SIGNING_ALLOWED=NO

run: build
	open $(APP_PATH)

debug: build
	$(APP_PATH)/Contents/MacOS/Notchera

debug-run: debug

profile-build:
	$(XCODEBUILD_BASE) build

profile-run: profile-build
	open $(APP_PATH)

hud-cli:
	cd tools/notcherahud && swift build -c release

format:
	@command -v swiftformat >/dev/null 2>&1 || (echo "swiftformat yok. brew install swiftformat" && exit 1)
	swiftformat Notchera NotcheraXPCHelper

lint:
	@command -v swiftlint >/dev/null 2>&1 || (echo "swiftlint yok. brew install swiftlint" && exit 1)
	swiftlint lint --config .swiftlint.yml

check: format lint build
