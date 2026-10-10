.PHONY: build run install clean generate

# Generate Xcode project using xcodegen
generate:
	xcodegen generate

# Build the app
build:
	xcodebuild -scheme TokenMonitor -configuration Debug build

# Build release version
release:
	xcodebuild -scheme TokenMonitor -configuration Release -derivedDataPath build CODE_SIGN_ALLOWED=NO clean build

# Run the app
run: build
	open "$$(xcodebuild -scheme TokenMonitor -configuration Debug -showBuildSettings | grep -m 1 'BUILT_PRODUCTS_DIR' | awk '{print $$3}')/Token Monitor.app"

# Install to Applications folder
install: build
	cp -R "$$(xcodebuild -scheme TokenMonitor -configuration Debug -showBuildSettings | grep -m 1 'BUILT_PRODUCTS_DIR' | awk '{print $$3}')/Token Monitor.app" /Applications/

# Clean build artifacts
clean:
	xcodebuild -scheme TokenMonitor clean
	rm -rf ~/Library/Developer/Xcode/DerivedData/TokenMonitor-*

# Open project in Xcode
xcode:
	open TokenMonitor.xcodeproj
