#!/bin/bash
set -euo pipefail

# Tanuki Bell — build, sign, and package for release
# Usage: ./scripts/build-release.sh [version]
# Example: ./scripts/build-release.sh 1.0.0

VERSION="${1:-$(grep MARKETING_VERSION project.yml | head -1 | sed 's/.*: "\(.*\)"/\1/')}"
APP_NAME="Tanuki Bell"
SCHEME="TanukiBell"
BUILD_DIR="build/release"
APP_PATH="$BUILD_DIR/$APP_NAME.app"
DMG_PATH="build/TanukiBell-${VERSION}.dmg"

echo "==> Building $APP_NAME v$VERSION"

# Clean build directory
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

# Build release archive
xcodebuild \
    -project TanukiBell.xcodeproj \
    -scheme "$SCHEME" \
    -configuration Release \
    -derivedDataPath "$BUILD_DIR/DerivedData" \
    CONFIGURATION_BUILD_DIR="$(pwd)/$BUILD_DIR" \
    build

echo "==> Built $APP_PATH"

# Ad-hoc code sign (redundant with Xcode config, but explicit)
codesign --force --sign - --deep "$APP_PATH"
echo "==> Signed (ad-hoc)"

# Create DMG
if command -v create-dmg &>/dev/null; then
    create-dmg \
        --volname "$APP_NAME" \
        --window-size 600 400 \
        --icon "$APP_NAME.app" 150 200 \
        --app-drop-link 450 200 \
        --no-internet-enable \
        "$DMG_PATH" \
        "$APP_PATH"
    echo "==> Created $DMG_PATH"
else
    # Fallback: create a simple DMG with hdiutil
    echo "==> create-dmg not found, using hdiutil fallback"
    echo "    Install with: brew install create-dmg"

    STAGING="$BUILD_DIR/dmg-staging"
    mkdir -p "$STAGING"
    cp -R "$APP_PATH" "$STAGING/"
    ln -s /Applications "$STAGING/Applications"

    hdiutil create \
        -volname "$APP_NAME" \
        -srcfolder "$STAGING" \
        -ov \
        -format UDZO \
        "$DMG_PATH"

    rm -rf "$STAGING"
    echo "==> Created $DMG_PATH"
fi

echo ""
echo "Release artifacts:"
echo "  App: $APP_PATH"
echo "  DMG: $DMG_PATH"
echo ""
echo "Next steps:"
echo "  1. Generate Sparkle EdDSA keys if not done: ./scripts/generate-sparkle-keys.sh"
echo "  2. Generate appcast: sparkle/bin/generate_appcast build/"
echo "  3. Upload DMG + appcast.xml to GitHub Releases"
