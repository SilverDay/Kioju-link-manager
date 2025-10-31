#!/bin/bash

# Build script for creating release packages for all platforms
# This script should be run on macOS to build all installers

set -e  # Exit on error

VERSION=$(grep "version:" pubspec.yaml | sed 's/version: //' | tr -d ' ')
echo "Building Kioju Link Manager version $VERSION"

# Create dist directory
mkdir -p dist

echo ""
echo "================================================"
echo "Building macOS DMG Installer"
echo "================================================"
if [[ "$OSTYPE" == "darwin"* ]]; then
    echo "Building macOS app bundle..."
    flutter build macos --release
    
    echo "Creating DMG installer..."
    flutter_distributor package --platform macos --targets dmg
    
    echo "✅ macOS DMG created: dist/$VERSION/Kioju_Link_Manager-$VERSION-macos.dmg"
else
    echo "⚠️  Skipping macOS build (requires macOS)"
fi

echo ""
echo "================================================"
echo "Building macOS ZIP Archive"
echo "================================================"
if [[ "$OSTYPE" == "darwin"* ]]; then
    flutter_distributor package --platform macos --targets zip
    echo "✅ macOS ZIP created: dist/$VERSION/Kioju_Link_Manager-$VERSION-macos.zip"
else
    echo "⚠️  Skipping macOS ZIP (requires macOS)"
fi

echo ""
echo "================================================"
echo "Building Windows MSIX Installer"
echo "================================================"
if [[ "$OSTYPE" == "msys" ]] || [[ "$OSTYPE" == "win32" ]]; then
    echo "Building Windows app..."
    flutter build windows --release
    
    echo "Creating MSIX installer..."
    flutter pub run msix:create
    
    # Copy to dist folder
    cp build/windows/x64/runner/Release/kioju_link_manager.msix "dist/kioju_link_manager-$VERSION-windows.msix"
    echo "✅ Windows MSIX created: dist/kioju_link_manager-$VERSION-windows.msix"
else
    echo "⚠️  Skipping Windows build (requires Windows)"
fi

echo ""
echo "================================================"
echo "Building Linux AppImage"
echo "================================================"
if [[ "$OSTYPE" == "linux-gnu"* ]]; then
    echo "Building Linux app..."
    flutter build linux --release
    
    echo "Creating AppImage..."
    flutter_distributor package --platform linux --targets appimage
    
    echo "✅ Linux AppImage created: dist/$VERSION/Kioju_Link_Manager-$VERSION-linux.AppImage"
else
    echo "⚠️  Skipping Linux build (requires Linux)"
fi

echo ""
echo "================================================"
echo "Build Summary"
echo "================================================"
echo "Version: $VERSION"
echo ""
echo "Created packages:"
ls -lh dist/ 2>/dev/null || ls dist/
echo ""
echo "✅ Build complete!"
echo ""
echo "Next steps:"
echo "1. Test each installer on target platforms"
echo "2. Create a GitHub release for version $VERSION"
echo "3. Upload the installers to the release"
echo "4. Update release notes with changelog"
