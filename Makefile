PROJECT := Notchera.xcodeproj
SCHEME := Notchera
DESTINATION := platform=macOS
DERIVED_DATA := .derived-data
SOURCE_PACKAGES := $(DERIVED_DATA)/SourcePackages
APP_PATH := $(DERIVED_DATA)/Build/Products/Debug/Notchera.app
XCODEBUILD_BASE := xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration Debug -destination '$(DESTINATION)' -derivedDataPath $(DERIVED_DATA) -clonedSourcePackagesDirPath $(SOURCE_PACKAGES) -disableAutomaticPackageResolution

.PHONY: open build run debug debug-run clear profile-build profile-run hud-cli format lint check release-dmg

open:
	open $(PROJECT)

build:
	$(XCODEBUILD_BASE) build CODE_SIGNING_ALLOWED=NO

run: build
	open $(APP_PATH)

debug: build
	$(APP_PATH)/Contents/MacOS/Notchera

debug-run: debug

clear:
	-osascript -e 'tell application "Notchera" to quit' 2>/dev/null || true
	-sleep 1
	-pkill -x Notchera 2>/dev/null || true
	-pkill -x NotcheraXPCHelper 2>/dev/null || true
	-sleep 1
	-pkill -9 -x Notchera 2>/dev/null || true
	-pkill -9 -x NotcheraXPCHelper 2>/dev/null || true
	-rm -rf $(APP_PATH)
	-rm -rf $(DERIVED_DATA)
	-rm -rf ~/Library/Application\ Support/Notchera
	-rm -rf ~/Library/Application\ Support/com.notchera.app
	-rm -rf ~/Library/Containers/com.notchera.app/Data/Library/Application\ Support/Notchera
	-rm -rf ~/Library/Containers/com.notchera.app/Data/Library/Application\ Support/com.notchera.app
	-rm -f ~/Library/Preferences/com.notchera.app.plist
	-rm -f ~/Library/Containers/com.notchera.app/Data/Library/Preferences/com.notchera.app.plist
	-defaults delete com.notchera.app 2>/dev/null || true
	-killall cfprefsd 2>/dev/null || true
	-tccutil reset Accessibility com.notchera.app || true
	-tccutil reset Calendar com.notchera.app || true

profile-build:
	$(XCODEBUILD_BASE) build

profile-run: profile-build
	open $(APP_PATH)

hud-cli:
	cd cli/notcherahud && swift build -c release

format:
	@command -v swiftformat >/dev/null 2>&1 || (echo "swiftformat yok. brew install swiftformat" && exit 1)
	swiftformat Notchera NotcheraXPCHelper

lint:
	@command -v swiftlint >/dev/null 2>&1 || (echo "swiftlint yok. brew install swiftlint" && exit 1)
	swiftlint lint --config .swiftlint.yml

check: format lint build

release:
	python3 ./create_dmg.py
