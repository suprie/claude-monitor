.PHONY: build run install clean generate

# Generate Xcode project using xcodegen
generate:
	xcodegen generate

# Build the app
build:
	xcodebuild -scheme ClaudeMonitor -configuration Debug build

# Build release version
release:
	xcodebuild -scheme ClaudeMonitor -configuration Release -derivedDataPath build CODE_SIGN_ALLOWED=NO clean build

# Run the app
run: build
	open "$$(xcodebuild -scheme ClaudeMonitor -configuration Debug -showBuildSettings | grep -m 1 'BUILT_PRODUCTS_DIR' | awk '{print $$3}')/Claude Monitor.app"

# Install to Applications folder
install: build
	cp -R "$$(xcodebuild -scheme ClaudeMonitor -configuration Debug -showBuildSettings | grep -m 1 'BUILT_PRODUCTS_DIR' | awk '{print $$3}')/Claude Monitor.app" /Applications/

# Clean build artifacts
clean:
	xcodebuild -scheme ClaudeMonitor clean
	rm -rf ~/Library/Developer/Xcode/DerivedData/ClaudeMonitor-*

# Open project in Xcode
xcode:
	open ClaudeMonitor.xcodeproj
