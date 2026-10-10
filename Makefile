.PHONY: build run install clean generate

# Generate Xcode project using xcodegen
generate:
	xcodegen generate

# Build the app
build:
	xcodebuild -scheme TakarPakai -configuration Debug build

# Build release version
release:
	xcodebuild -scheme TakarPakai -configuration Release -derivedDataPath build CODE_SIGN_ALLOWED=NO clean build

# Run the app
run: build
	open "$$(xcodebuild -scheme TakarPakai -configuration Debug -showBuildSettings | grep -m 1 'BUILT_PRODUCTS_DIR' | awk '{print $$3}')/Takar Pakai.app"

# Install to Applications folder
install: build
	cp -R "$$(xcodebuild -scheme TakarPakai -configuration Debug -showBuildSettings | grep -m 1 'BUILT_PRODUCTS_DIR' | awk '{print $$3}')/Takar Pakai.app" /Applications/

# Clean build artifacts
clean:
	xcodebuild -scheme TakarPakai clean
	rm -rf ~/Library/Developer/Xcode/DerivedData/TakarPakai-*

# Open project in Xcode
xcode:
	open TakarPakai.xcodeproj
