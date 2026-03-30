#!/bin/bash
set -euo pipefail

# Tanuki Bell — build, sign, package, and optionally publish a release
#
# Usage:
#   ./scripts/build-release.sh <version>            # build only
#   ./scripts/build-release.sh <version> --publish   # build + GitHub Release
#
# Examples:
#   ./scripts/build-release.sh 1.0.0
#   ./scripts/build-release.sh 1.0.0 --publish

if [ -z "${1:-}" ]; then
    echo "Usage: $0 <version> [--publish]"
    echo "  version: semver like 1.0.0"
    echo "  --publish: create GitHub Release and upload DMG"
    exit 1
fi

VERSION="$1"
PUBLISH="${2:-}"
APP_NAME="Tanuki Bell"
SCHEME="TanukiBell"
BUILD_DIR="build/release"
APP_PATH="$BUILD_DIR/$APP_NAME.app"
DMG_PATH="build/TanukiBell-${VERSION}.dmg"
TAG="v${VERSION}"

# Sparkle tools (resolved via SPM into Xcode DerivedData)
SPARKLE_BIN=$(find ~/Library/Developer/Xcode/DerivedData -path "*/Sparkle*/bin/generate_appcast" -type f 2>/dev/null | head -1)
SIGN_UPDATE_BIN=$(find ~/Library/Developer/Xcode/DerivedData -path "*/Sparkle*/bin/sign_update" -type f 2>/dev/null | head -1)

echo "==> Building $APP_NAME v$VERSION"

# Clean build directory
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

# Regenerate Xcode project (ensures consistency)
if command -v xcodegen &>/dev/null; then
    xcodegen generate
fi

# Build release
xcodebuild \
    -project TanukiBell.xcodeproj \
    -scheme "$SCHEME" \
    -configuration Release \
    -derivedDataPath "$BUILD_DIR/DerivedData" \
    CONFIGURATION_BUILD_DIR="$(pwd)/$BUILD_DIR" \
    build

echo "==> Built $APP_PATH"

# Ad-hoc code sign
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
else
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
fi

echo "==> Created $DMG_PATH"

# Generate / update appcast.xml
if [ -n "$SPARKLE_BIN" ]; then
    echo "==> Generating appcast.xml"
    APPCAST_DIR="build/appcast"
    mkdir -p "$APPCAST_DIR"
    cp "$DMG_PATH" "$APPCAST_DIR/"

    # generate_appcast signs each DMG and writes appcast.xml into the same dir
    "$SPARKLE_BIN" "$APPCAST_DIR" \
        --link "https://github.com/danielkuhlwein/tanuki-bell/releases" \
        --download-url-prefix "https://github.com/danielkuhlwein/tanuki-bell/releases/download/${TAG}/"

    cp "$APPCAST_DIR/appcast.xml" appcast.xml
    echo "==> appcast.xml updated"
else
    echo "Warning: generate_appcast not found — skipping appcast.xml generation."
    echo "         Build the project in Xcode first so SPM resolves Sparkle."
fi

# Publish to GitHub Releases
if [ "$PUBLISH" = "--publish" ]; then
    if ! command -v gh &>/dev/null; then
        echo "Error: gh CLI not installed. Install with: brew install gh"
        exit 1
    fi

    echo "==> Creating GitHub Release $TAG"

    NOTES="## Tanuki Bell v${VERSION}

### Installation
1. Download \`TanukiBell-${VERSION}.dmg\` below
2. Open the DMG and drag **Tanuki Bell** to Applications
3. On first launch, macOS will block the app since it is not notarised. To allow it:
   - **Double-click** the app (you will see a blocked dialogue — click **Done**)
   - Open **System Settings → Privacy & Security**
   - Scroll down to find the blocked message and click **Open Anyway**
   - Authenticate with your password or Touch ID
   - This is a **one-time** step — all subsequent launches work normally

### Setup
1. Create a GitLab **legacy** Personal Access Token with \`read_api\` scope
2. Click the bell in your menu bar → **Settings...**
3. Paste your token and click **Test Connection**
4. Click **Save & Start Polling**
5. Enable notifications when prompted (or in System Settings → Notifications → Tanuki Bell)"

    gh release create "$TAG" \
        "$DMG_PATH" \
        --title "Tanuki Bell v${VERSION}" \
        --notes "$NOTES"

    echo "==> Published: $(gh release view "$TAG" --json url -q .url)"

    # Commit and push updated appcast.xml so Sparkle can find it
    if [ -f appcast.xml ]; then
        echo "==> Committing appcast.xml"
        git add appcast.xml
        git commit -m "chore: update appcast.xml for v${VERSION}"
        git push
        echo "==> appcast.xml pushed to main"
    fi
else
    echo ""
    echo "Release artifacts:"
    echo "  App: $APP_PATH"
    echo "  DMG: $DMG_PATH"
    echo ""
    echo "To publish to GitHub:"
    echo "  ./scripts/build-release.sh $VERSION --publish"
fi
