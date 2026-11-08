APP_NAME = idiot
SCHEME_NAME = idiot
PROJECT_DIR = .
BUNDLE_ID = com.umangsurana.idiot
SIMULATOR_NAME ?= iPhone 17 Pro
DEVICE_NAME ?= iPhone
DERIVED_DATA = $(PROJECT_DIR)/build
SWIFTFORMAT_VERSION = 0.55.5

XCODEBUILD = xcodebuild -project "$(PROJECT_DIR)/$(APP_NAME).xcodeproj" -scheme "$(SCHEME_NAME)"
MACOS_DEST = -destination "platform=macOS"
RELEASE_APP = $(DERIVED_DATA)/Build/Products/Release/$(APP_NAME).app
INSTALL_PATH = /Applications/Idiot.app

.PHONY: install install-release format build run build-ios run-ios build-device run-device clean all

install:
	@echo "Installing SwiftFormat $(SWIFTFORMAT_VERSION)..."
	@if ! command -v swiftformat &> /dev/null; then \
		brew install swiftformat || \
		mint install nicklockwood/SwiftFormat@$(SWIFTFORMAT_VERSION); \
	fi

format:
	@echo "Formatting Swift files..."
	swiftformat .

build: format
	@echo "Building $(APP_NAME) for macOS..."
	$(XCODEBUILD) $(MACOS_DEST) -derivedDataPath "$(DERIVED_DATA)" build

run: format
	@echo "Running $(APP_NAME) on macOS..."
	$(XCODEBUILD) $(MACOS_DEST) -derivedDataPath "$(DERIVED_DATA)" build
	open "$(DERIVED_DATA)/Build/Products/Debug/$(APP_NAME).app"

build-ios: format
	@echo "Building $(APP_NAME) for iOS Simulator ($(SIMULATOR_NAME))..."
	$(XCODEBUILD) \
		-destination "platform=iOS Simulator,name=$(SIMULATOR_NAME)" \
		-derivedDataPath "$(DERIVED_DATA)" build

run-ios: format
	@echo "Running $(APP_NAME) on iOS Simulator ($(SIMULATOR_NAME))..."
	$(XCODEBUILD) \
		-destination "platform=iOS Simulator,name=$(SIMULATOR_NAME)" \
		-derivedDataPath "$(DERIVED_DATA)" build
	open -a Simulator
	xcrun simctl boot "$(SIMULATOR_NAME)" 2>/dev/null || true
	xcrun simctl bootstatus "$(SIMULATOR_NAME)" -b
	xcrun simctl install "$(SIMULATOR_NAME)" "$(DERIVED_DATA)/Build/Products/Debug-iphonesimulator/$(APP_NAME).app"
	xcrun simctl launch "$(SIMULATOR_NAME)" $(BUNDLE_ID)

build-device: format
	@echo "Building $(APP_NAME) for physical iPhone..."
	$(XCODEBUILD) \
		-destination "generic/platform=iOS" -derivedDataPath "$(DERIVED_DATA)" \
		-allowProvisioningUpdates -allowProvisioningDeviceRegistration build

run-device: format
	@echo "Building and installing $(APP_NAME) on $(DEVICE_NAME)..."
	$(XCODEBUILD) \
		-destination "generic/platform=iOS" -derivedDataPath "$(DERIVED_DATA)" \
		-allowProvisioningUpdates -allowProvisioningDeviceRegistration build
	xcrun devicectl device install app --device "$(DEVICE_NAME)" \
		"$(DERIVED_DATA)/Build/Products/Debug-iphoneos/$(APP_NAME).app"
	xcrun devicectl device process launch --device "$(DEVICE_NAME)" $(BUNDLE_ID)

install-release: format
	@echo "Building signed $(APP_NAME) Release for macOS..."
	$(XCODEBUILD) -configuration Release $(MACOS_DEST) -derivedDataPath "$(DERIVED_DATA)" \
		-allowProvisioningUpdates -allowProvisioningDeviceRegistration build
	@codesign -d --entitlements :- "$(RELEASE_APP)" 2>/dev/null | grep -q "icloud-container-identifiers" || \
		{ echo "Error: the build has no iCloud entitlement."; exit 1; }
	@echo "Installing to $(INSTALL_PATH)..."
	-@pkill -x "$(APP_NAME)"
	rm -rf "$(INSTALL_PATH)"
	ditto "$(RELEASE_APP)" "$(INSTALL_PATH)"
	open "$(INSTALL_PATH)"

clean:
	@echo "Cleaning build artifacts..."
	rm -rf "$(DERIVED_DATA)"
	$(XCODEBUILD) clean

all: install format build
