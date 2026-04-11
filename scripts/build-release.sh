#!/bin/bash
set -euo pipefail

# Tanuki Bell — build, sign, notarise, package, and optionally publish a release
#
# Usage:
#   ./scripts/build-release.sh <version>            # build only
#   ./scripts/build-release.sh <version> --publish   # build + GitHub Release
#
# Prerequisites:
#   - Xcode with "Developer ID Application" certificate installed
#   - DEVELOPMENT_TEAM env var set to your Apple Team ID
#   - Notarytool credentials stored in keychain (one-time):
#       xcrun notarytool store-credentials "tanuki-bell" \
#           --apple-id "your@email.com" \
#           --team-id "YOUR_TEAM_ID" \
#           --password "app-specific-password"
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
NOTARYTOOL_PROFILE="${NOTARYTOOL_PROFILE:-tanuki-bell}"
DEVELOPMENT_TEAM="WG7BK7C4BG"
SIGN_IDENTITY="Developer ID Application"

# Verify the signing identity exists
if ! security find-identity -v -p codesigning | grep -q "$SIGN_IDENTITY"; then
    echo "Error: No '$SIGN_IDENTITY' certificate found."
    echo "  Install it from your Apple Developer account (Certificates, Identifiers & Profiles)."
    exit 1
fi

# Sparkle tools (resolved via SPM into Xcode DerivedData)
SPARKLE_BIN=$(find ~/Library/Developer/Xcode/DerivedData -path "*/Sparkle*/bin/generate_appcast" -type f 2>/dev/null | head -1)
SIGN_UPDATE_BIN=$(find ~/Library/Developer/Xcode/DerivedData -path "*/Sparkle*/bin/sign_update" -type f 2>/dev/null | head -1)

echo "==> Building $APP_NAME v$VERSION"
echo "    Team: $DEVELOPMENT_TEAM"

# Clean build directory
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

# Regenerate Xcode project (ensures consistency)
if command -v xcodegen &>/dev/null; then
    xcodegen generate
fi

# Build release (xcodebuild handles signing with hardened runtime)
xcodebuild \
    -project TanukiBell.xcodeproj \
    -scheme "$SCHEME" \
    -configuration Release \
    -derivedDataPath "$BUILD_DIR/DerivedData" \
    CONFIGURATION_BUILD_DIR="$(pwd)/$BUILD_DIR" \
    DEVELOPMENT_TEAM="$DEVELOPMENT_TEAM" \
    CODE_SIGN_IDENTITY="$SIGN_IDENTITY" \
    build

echo "==> Built $APP_PATH"

# Re-sign all embedded binaries with Developer ID + timestamp + hardened runtime.
# xcodebuild signs the main binary but SPM-built dependencies (Sparkle) may not
# inherit the correct signing identity or timestamp.
echo "==> Signing embedded frameworks and helpers"

# Find and sign every Mach-O binary inside Frameworks (innermost first via -depth)
find "$APP_PATH/Contents/Frameworks" -depth \( -name "*.xpc" -o -name "*.app" -o -name "*.framework" \) -type d | while read -r bundle; do
    echo "    Signing $(basename "$bundle")"
    codesign --force --sign "$SIGN_IDENTITY" --timestamp --options runtime "$bundle"
done

# Also sign any standalone Mach-O executables not inside sub-bundles (e.g. Sparkle's Autoupdate)
FRAMEWORKS_DIR="$APP_PATH/Contents/Frameworks"
find "$FRAMEWORKS_DIR" -type f | while read -r bin; do
    # Get path relative to Frameworks dir; skip files inside .app or .xpc sub-bundles
    rel_path="${bin#"$FRAMEWORKS_DIR"/}"
    if echo "$rel_path" | grep -qE '\.(app|xpc)/'; then
        continue
    fi
    if file "$bin" | grep -q "Mach-O"; then
        echo "    Signing $(basename "$bin")"
        codesign --force --sign "$SIGN_IDENTITY" --timestamp --options runtime "$bin"
    fi
done

# Re-sign frameworks after signing their contents
find "$APP_PATH/Contents/Frameworks" -name "*.framework" -type d -maxdepth 1 | while read -r fw; do
    echo "    Re-signing $(basename "$fw")"
    codesign --force --sign "$SIGN_IDENTITY" --timestamp --options runtime "$fw"
done

# Sign the main app bundle (outermost — must be last)
echo "    Signing $APP_NAME.app"
codesign --force --sign "$SIGN_IDENTITY" --timestamp --options runtime \
    --entitlements TanukiBell/TanukiBell.entitlements "$APP_PATH"

# Verify code signature
echo "==> Verifying code signature"
codesign --verify --deep --strict "$APP_PATH"
codesign -d --verbose=2 "$APP_PATH" 2>&1 | grep -E "Authority|TeamIdentifier"
echo "==> Signature valid"

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

# Sign the DMG
codesign --force --sign "$SIGN_IDENTITY" --timestamp "$DMG_PATH"
echo "==> Signed DMG"

# Notarise
echo "==> Submitting for notarisation (this may take a few minutes)..."
NOTARIZE_OUTPUT=$(xcrun notarytool submit "$DMG_PATH" \
    --keychain-profile "$NOTARYTOOL_PROFILE" \
    --wait 2>&1) || true
echo "$NOTARIZE_OUTPUT"

if echo "$NOTARIZE_OUTPUT" | grep -q "status: Accepted"; then
    echo "==> Notarisation accepted"
else
    echo "Error: Notarisation failed. Check the log with:"
    SUBMISSION_ID=$(echo "$NOTARIZE_OUTPUT" | grep "id:" | head -1 | awk '{print $2}')
    echo "  xcrun notarytool log $SUBMISSION_ID --keychain-profile $NOTARYTOOL_PROFILE"
    exit 1
fi

# Staple the notarisation ticket to the DMG
xcrun stapler staple "$DMG_PATH"
echo "==> Stapled notarisation ticket"

# Verify notarisation
echo "==> Verifying notarisation"
spctl --assess --type open --context context:primary-signature -v "$DMG_PATH"
echo "==> Notarisation verified"

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
3. Launch from Applications — that's it!

### Setup
1. Create a GitLab **Personal Access Token** with \`read_api\` scope
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
