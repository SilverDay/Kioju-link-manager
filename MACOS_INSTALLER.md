# macOS Installer Guide

## Overview
This guide explains how to create and install the Kioju Link Manager macOS DMG installer.

## Installation for End Users

### Option 1: Install from DMG (Recommended)

The DMG installer provides a standard macOS installation experience.

#### Installation Steps:

1. **Download the DMG file**
   - Download `Kioju Link Manager.dmg` from the releases page
   - Or build it yourself (see Building section below)

2. **Mount the DMG**
   - Double-click the `.dmg` file
   - A window will open showing the app icon and Applications folder

3. **Install the application**
   - Drag the "Kioju Link Manager" icon to the Applications folder
   - Wait for the copy to complete

4. **First launch - Handle Gatekeeper**
   - Go to Applications folder
   - Right-click (or Ctrl+click) on "Kioju Link Manager"
   - Select "Open" from the context menu
   - Click "Open" in the security dialog
   - The app will now launch

   **Alternative method:**
   ```bash
   # Remove the quarantine attribute
   xattr -cr "/Applications/Kioju Link Manager.app"
   ```

5. **Subsequent launches**
   - You can now open the app normally from Launchpad or Applications
   - No more security warnings

### Option 2: Run Without Installation (Portable)

You can run the app directly without installing:

1. Build or download the ZIP archive
2. Extract the `.app` bundle
3. Right-click → Open (first time only)
4. The app will run from any location

## Building the macOS Installer

### Prerequisites

**Required:**
- macOS 10.15 (Catalina) or later
- Xcode Command Line Tools
  ```bash
  xcode-select --install
  ```
- Flutter SDK 3.35.7 or later
  ```bash
  flutter --version
  ```

**Optional (for DMG creation on macOS):**
- Node.js (for flutter_distributor)
  ```bash
  brew install node
  ```

### Build Methods

#### Method 1: Using Flutter Distributor (Recommended - Creates DMG)

**Install flutter_distributor:**
```bash
flutter pub get
```

**Build the DMG installer:**
```bash
# Build only the macOS DMG
flutter_distributor package --platform macos --targets dmg

# Or build all release formats
flutter_distributor release --name production
```

**Output location:**
- DMG: `dist/<version>/Kioju_Link_Manager-<version>-macos.dmg`
- The DMG will include a nice drag-to-Applications window

#### Method 2: Manual Build (Creates .app bundle only)

**Build the macOS release:**
```bash
flutter build macos --release
```

**Create DMG manually (macOS only):**
```bash
# Install create-dmg if needed
brew install create-dmg

# Navigate to the build output
cd build/macos/Build/Products/Release

# Create the DMG
create-dmg \
  --volname "Kioju Link Manager" \
  --volicon "../../../../assets/kioju-icon.png" \
  --window-pos 200 120 \
  --window-size 600 400 \
  --icon-size 100 \
  --icon "Kioju Link Manager.app" 175 190 \
  --hide-extension "Kioju Link Manager.app" \
  --app-drop-link 425 185 \
  "Kioju-Link-Manager-2.0.0.dmg" \
  "Kioju Link Manager.app"
```

**Output location:**
- App bundle: `build/macos/Build/Products/Release/Kioju Link Manager.app`
- Manual DMG: `build/macos/Build/Products/Release/Kioju-Link-Manager-2.0.0.dmg`

#### Method 3: ZIP Archive (Cross-platform build)

**Build and package:**
```bash
# Build the app
flutter build macos --release

# Create ZIP (Windows can do this)
cd build/macos/Build/Products/Release
tar -czf "Kioju-Link-Manager-2.0.0-macos.tar.gz" "Kioju Link Manager.app"
```

Or using PowerShell on Windows:
```powershell
# Build for macOS from Windows (requires macOS for final packaging)
flutter build macos --release

# Note: You cannot create a proper DMG from Windows
# But you can prepare the .app bundle for later packaging
```

## Code Signing (Optional but Recommended)

### Without Code Signing (Current Default)

- App works but shows security warnings
- Users must right-click → Open on first launch
- Suitable for:
  - Personal use
  - Testing
  - Open-source distribution

### With Code Signing (Professional)

**Requirements:**
- Apple Developer Account ($99/year)
- Developer ID Application certificate

**Steps:**

1. **Get Apple Developer Account**
   - Sign up at https://developer.apple.com
   - Cost: $99/year

2. **Create Developer ID Certificate**
   - Open Xcode → Preferences → Accounts
   - Add your Apple ID
   - Manage Certificates → "+" → Developer ID Application

3. **Sign the app during build**
   ```bash
   # Build with code signing
   flutter build macos --release \
     --codesign="Developer ID Application: Your Name (TEAM_ID)"
   ```

4. **Notarize the app (required for macOS 10.15+)**
   ```bash
   # Create an archive
   ditto -c -k --keepParent "Kioju Link Manager.app" "Kioju Link Manager.zip"
   
   # Submit for notarization
   xcrun notarytool submit "Kioju Link Manager.zip" \
     --apple-id "your@email.com" \
     --password "app-specific-password" \
     --team-id "TEAM_ID" \
     --wait
   
   # Staple the notarization
   xcrun stapler staple "Kioju Link Manager.app"
   ```

### Benefits of Code Signing:
- ✅ No security warnings
- ✅ Users can double-click to install
- ✅ Professional appearance
- ✅ Required for Mac App Store
- ✅ Automatic updates possible

## Distribution Options

### 1. Direct Distribution (Current)
- Share the DMG or ZIP file
- Users install manually
- Free, but requires security override
- Good for open-source projects

### 2. Mac App Store
**Requirements:**
- Apple Developer Account ($99/year)
- App must pass review
- Must use App Store Connect

**Benefits:**
- Automatic code signing and notarization
- Built-in distribution platform
- Automatic updates
- No security warnings
- Trusted by users

**Process:**
1. Create App Store Connect listing
2. Build with App Store provisioning
3. Upload using Xcode or Transporter
4. Submit for review

### 3. Homebrew Cask (Advanced)
For wider distribution:
```ruby
# Create a Homebrew cask
cask "kioju-link-manager" do
  version "2.0.0"
  sha256 "checksum_here"

  url "https://github.com/silverday/Kioju-link-manager/releases/download/v#{version}/Kioju-Link-Manager-#{version}.dmg"
  name "Kioju Link Manager"
  desc "Cross-platform Flutter app to manage Kioju links and bookmarks"
  homepage "https://github.com/silverday/Kioju-link-manager"

  app "Kioju Link Manager.app"
end
```

Users install via:
```bash
brew install --cask kioju-link-manager
```

## Troubleshooting

### "App is damaged and can't be opened"
This happens due to Gatekeeper quarantine:

**Solution 1 - Remove quarantine:**
```bash
xattr -cr "/Applications/Kioju Link Manager.app"
```

**Solution 2 - Allow in System Preferences:**
1. Open System Preferences → Security & Privacy
2. Under "General" tab, click "Open Anyway"

**Solution 3 - Temporarily disable Gatekeeper (not recommended):**
```bash
sudo spctl --master-disable
# ... install app ...
sudo spctl --master-enable
```

### "App can't be opened because it is from an unidentified developer"
**Solution:**
- Right-click the app → Open
- Click "Open" in the dialog
- Or use the xattr command above

### Missing Dependencies
If the app fails to launch:
```bash
# Check for missing libraries
otool -L "/Applications/Kioju Link Manager.app/Contents/MacOS/kioju_link_manager"

# Most dependencies should be bundled
# If issues persist, rebuild with:
flutter clean
flutter pub get
flutter build macos --release
```

### App crashes on launch
**Check Console logs:**
1. Open Console.app
2. Filter for "kioju"
3. Launch the app
4. Check for error messages

**Common issues:**
- Permissions not set correctly
- Database initialization failed
- Missing keychain access

## Uninstallation

### Manual Uninstall:
```bash
# Remove the application
rm -rf "/Applications/Kioju Link Manager.app"

# Remove user data (optional)
rm -rf "~/Library/Application Support/com.silverday.kiojulinkmanager"

# Remove preferences (optional)
rm -rf "~/Library/Preferences/com.silverday.kiojulinkmanager.plist"

# Remove keychain items (optional)
# Open Keychain Access and search for "kioju" to remove saved credentials
```

### Automated uninstall script:
```bash
#!/bin/bash
echo "Uninstalling Kioju Link Manager..."
rm -rf "/Applications/Kioju Link Manager.app"
rm -rf ~/Library/Application\ Support/com.silverday.kiojulinkmanager
rm -rf ~/Library/Preferences/com.silverday.kiojulinkmanager.plist
echo "Uninstall complete!"
```

## Building on Different Platforms

### On macOS (Native)
- ✅ Can build .app bundle
- ✅ Can create DMG
- ✅ Can code sign
- ✅ Can notarize

### On Windows (Cross-compile)
- ✅ Can build .app bundle (theoretically)
- ❌ Cannot create DMG
- ❌ Cannot code sign
- ❌ Cannot notarize
- **Note:** Flutter's macOS build requires macOS

### On Linux (Cross-compile)
- ❌ Cannot build macOS apps
- **Recommendation:** Use macOS for macOS builds

## Recommended Workflow

### For Development:
1. Build on macOS: `flutter build macos --release`
2. Test the .app bundle directly
3. Use `xattr -cr` to bypass Gatekeeper locally

### For Distribution (Free):
1. Build on macOS
2. Create DMG using flutter_distributor
3. Upload to GitHub Releases
4. Document the security override steps

### For Distribution (Professional):
1. Get Apple Developer Account ($99/year)
2. Create Developer ID certificate
3. Sign and notarize the app
4. Create DMG
5. Distribute or publish to Mac App Store

## System Requirements

- **Operating System:** macOS 10.15 (Catalina) or later
- **Architecture:** Intel (x86_64) or Apple Silicon (arm64) via Rosetta
- **Disk Space:** ~50 MB
- **Internet:** Required for syncing with Kioju API

## Additional Resources

- [Apple Developer Program](https://developer.apple.com/programs/)
- [Notarization Guide](https://developer.apple.com/documentation/security/notarizing_macos_software_before_distribution)
- [flutter_distributor Documentation](https://github.com/leanflutter/flutter_distributor)
- [create-dmg Tool](https://github.com/create-dmg/create-dmg)

## Version Information

- **App Version:** 2.0.0+1
- **Build Date:** October 31, 2025
- **Supported Architectures:** x86_64 (Apple Silicon supported via Rosetta)
