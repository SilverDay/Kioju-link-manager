#!/bin/bash

# macOS App Launcher Script
# This script helps launch the Kioju Link Manager on macOS by removing the quarantine attribute

set -e

APP_NAME="kioju_link_manager_flutter.app"
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

echo "================================================"
echo "Kioju Link Manager - macOS Launcher"
echo "================================================"
echo ""

# Function to find the app
find_app() {
    # Check common locations
    local locations=(
        "/Applications/$APP_NAME"
        "$HOME/Applications/$APP_NAME"
        "$SCRIPT_DIR/build/macos/Build/Products/Release/$APP_NAME"
        "$SCRIPT_DIR/$APP_NAME"
    )
    
    for location in "${locations[@]}"; do
        if [ -d "$location" ]; then
            echo "$location"
            return 0
        fi
    done
    
    return 1
}

APP_PATH=$(find_app)

if [ -z "$APP_PATH" ]; then
    echo "❌ Error: Could not find $APP_NAME"
    echo ""
    echo "Please ensure the app is in one of these locations:"
    echo "  - /Applications/"
    echo "  - ~/Applications/"
    echo "  - $(pwd)/"
    echo "  - build/macos/Build/Products/Release/ (if building from source)"
    echo ""
    exit 1
fi

echo "✓ Found app at: $APP_PATH"
echo ""

# Check if app has quarantine attribute
if xattr -l "$APP_PATH" | grep -q "com.apple.quarantine"; then
    echo "⚠️  App has quarantine attribute (security warning will appear)"
    echo ""
    echo "Would you like to remove the quarantine attribute? This will allow the app to"
    echo "open without security warnings. Only do this if you trust the source of this app."
    echo ""
    read -t 30 -p "Remove quarantine attribute? (y/N): " -n 1 -r || { echo ""; echo "⚠️  No response received, skipping quarantine removal"; REPLY="n"; }
    echo ""
    
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        echo "Removing quarantine attribute..."
        xattr -cr "$APP_PATH"
        echo "✓ Quarantine attribute removed"
        echo ""
    fi
else
    echo "✓ App does not have quarantine attribute"
    echo ""
fi

# Check code signature
echo "Checking code signature..."
CODESIGN_ERROR=$(codesign --verify --deep --strict "$APP_PATH" 2>&1)
CODESIGN_EXIT_CODE=$?

if [ $CODESIGN_EXIT_CODE -eq 0 ]; then
    echo "✓ Code signature is valid"
    
    # Show signature details
    SIGNATURE_INFO=$(codesign -dv "$APP_PATH" 2>&1)
    if echo "$SIGNATURE_INFO" | grep -q "Developer ID Application"; then
        echo "✓ Signed with Developer ID (notarized app)"
    elif echo "$SIGNATURE_INFO" | grep -q "adhoc"; then
        echo "⚠️  App uses ad-hoc signature (not notarized)"
        echo "   You may need to approve in System Settings > Privacy & Security"
    fi
else
    echo "⚠️  Code signature verification failed or app is unsigned"
    if [ -n "$CODESIGN_ERROR" ]; then
        echo "   Error details: $CODESIGN_ERROR"
    fi
    echo "   You may need to approve in System Settings > Privacy & Security"
fi

echo ""
echo "Attempting to launch app..."
echo ""

# Try to open the app
OPEN_ERROR=$(open "$APP_PATH" 2>&1)
OPEN_EXIT_CODE=$?

if [ $OPEN_EXIT_CODE -eq 0 ]; then
    echo "✓ App launched successfully!"
    echo ""
    echo "If you see a security warning:"
    echo "1. Click 'Cancel' or 'OK' on the warning"
    echo "2. Open System Settings > Privacy & Security"
    echo "3. Click 'Open Anyway' next to the blocked app message"
    echo "4. Run this script again or open the app manually"
else
    echo "❌ Failed to launch app"
    if [ -n "$OPEN_ERROR" ]; then
        echo "   Error: $OPEN_ERROR"
    fi
    echo ""
    echo "Try these steps:"
    echo "1. Right-click the app in Finder and select 'Open'"
    echo "2. If that doesn't work, see MACOS_INSTALLATION.md for more solutions"
    exit 1
fi
