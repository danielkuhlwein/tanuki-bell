#!/bin/bash
set -euo pipefail

# Generate Sparkle EdDSA key pair for update signing.
# The private key is stored in your Keychain (managed by Sparkle).
# The public key goes in Info.plist as SUPublicEDKey.
#
# This only needs to be run ONCE. The private key persists in Keychain.

SPARKLE_BIN=""

# Find generate_keys in SPM build artifacts
DERIVED_DATA="build/release/DerivedData"
if [ -d "$DERIVED_DATA" ]; then
    SPARKLE_BIN=$(find "$DERIVED_DATA" -name "generate_keys" -type f 2>/dev/null | head -1)
fi

# Fallback: check SourcePackages
if [ -z "$SPARKLE_BIN" ]; then
    SPARKLE_BIN=$(find ~/Library/Developer/Xcode/DerivedData -path "*/Sparkle*/generate_keys" -type f 2>/dev/null | head -1)
fi

if [ -z "$SPARKLE_BIN" ]; then
    echo "Error: Could not find Sparkle's generate_keys tool."
    echo "Build the project first, then run this script."
    exit 1
fi

echo "Using: $SPARKLE_BIN"
echo ""
"$SPARKLE_BIN"
echo ""
echo "Copy the public key above into Info.plist under SUPublicEDKey."
echo "The private key is stored in your login Keychain."
